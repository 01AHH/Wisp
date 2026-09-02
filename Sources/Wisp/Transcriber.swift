import AVFoundation
import CoreMedia
import Speech

enum TranscriberError: LocalizedError {
    case noMicrophone, noModel, notReady, timeout
    var errorDescription: String? {
        switch self {
        case .noMicrophone: return "Microphone access is off"
        case .noModel: return "Speech model unavailable"
        case .notReady: return "Still getting ready"
        case .timeout: return "Transcription timed out"
        }
    }
}

/// Records from the default microphone and turns it into text with Apple's
/// on-device SpeechAnalyzer (macOS 26). Nothing leaves the Mac.
@MainActor
final class Transcriber {
    static let shared = Transcriber()

    enum State: Equatable {
        case preparing(String), ready, listening, transcribing, failed(String)
    }

    private(set) var state: State = .preparing("Getting ready…") {
        didSet { Log.note("state → \(String(describing: self.state))"); onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?
    /// Microphone level 0…1, delivered on the main thread while listening.
    var onLevel: ((Float) -> Void)?

    private var locale = Locale(identifier: "en_US")

    // One pre-warmed session so dictation starts the instant the key goes down.
    private final class TextBox { var text = ""; var finished = false }
    private struct Session {
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat
        let input: AsyncStream<AnalyzerInput>.Continuation
        let box: TextBox
        let results: Task<Void, Error>
    }
    private var session: Session?
    private var warmUpTask: Task<Void, Never>?
    private var startTask: Task<Void, Error>?
    private var peak: Float = 0
    /// Loudest level heard during the most recent recording (0…1).
    var lastPeak: Float { peak }
    private var capture: AVCaptureSession?
    private var captureDelegate: CaptureDelegate?
    private let captureQueue = DispatchQueue(label: "wisp.capture")

    private init() {}

    /// Debug only: fake a state for UI snapshots.
    func debugSetState(_ new: State) { state = new }

    // MARK: setup

    func prepare() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .failed(TranscriberError.noMicrophone.localizedDescription)
            return
        }
        do {
            locale = await Self.pickLocale()
            Log.note("locale \(self.locale.identifier)")
            let probe = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                          reportingOptions: [], attributeOptions: [])
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                state = .preparing("Downloading speech model…")
                try await request.downloadAndInstall()
            }
            await warmUp()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func pickLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if let exact = supported.first(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) {
            return exact
        }
        if let sameLanguage = supported.first(where: {
            $0.language.languageCode == current.language.languageCode
        }) {
            return sameLanguage
        }
        return supported.first(where: { $0.identifier(.bcp47) == "en-US" }) ?? Locale(identifier: "en_US")
    }

    /// Builds the next analyzer session ahead of time.
    private func warmUp() async {
        if session != nil { return }
        if let warmUpTask { return await warmUpTask.value }
        let task = Task<Void, Never> { [self] in
            do { session = try await makeSession() } catch {
                state = .failed(error.localizedDescription)
            }
        }
        warmUpTask = task
        await task.value
        warmUpTask = nil
    }

    private func makeSession() async throws -> Session {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.noModel
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let box = TextBox()
        let results = Task<Void, Error> {
            defer { box.finished = true }
            for try await result in transcriber.results {
                Log.note("result final=\(result.isFinal) \"\(String(result.text.characters))\"")
                if result.isFinal { box.text += String(result.text.characters) }
            }
            Log.note("results stream ended")
        }
        try await analyzer.start(inputSequence: stream)
        Log.note("session warmed, format \(format)")
        return Session(transcriber: transcriber, analyzer: analyzer, format: format,
                       input: continuation, box: box, results: results)
    }

    // MARK: recording

    func startListening() {
        guard state == .ready else { return }
        state = .listening
        peak = 0
        Log.note("startListening")
        startTask = Task { [self] in
            await warmUp()
            guard let session else { throw TranscriberError.notReady }
            try startCapture(feeding: session)
        }
    }

    /// Opens the chosen microphone with AVCaptureSession and streams its audio
    /// into the analyzer. (AVAudioEngine was tried first: its input-only graph
    /// never runs on macOS 26 and it can't record from a mic that isn't also the
    /// output device. AVCaptureSession just works, per device.)
    private func startCapture(feeding session: Session) throws {
        stopCapture()
        guard let device = AudioDevices.captureDevice() else { throw TranscriberError.noMicrophone }
        let cap = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard cap.canAddInput(input) else { throw TranscriberError.noMicrophone }
        cap.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let target = session.format
        let continuation = session.input
        let onLevel = self.onLevel
        var buffers = 0
        var converter: AVAudioConverter?

        var calls = 0
        let delegate = CaptureDelegate { sampleBuffer in
            calls += 1
            guard let pcm = Self.pcmBuffer(from: sampleBuffer) else {
                if calls == 1 { Log.note("couldn't read sample buffer") }
                return
            }
            var out = pcm
            if pcm.format != target {
                if converter == nil || converter!.inputFormat != pcm.format {
                    converter = AVAudioConverter(from: pcm.format, to: target)
                }
                guard let converter, let converted = Self.convert(pcm, with: converter, to: target) else { return }
                out = converted
            }
            guard out.frameLength > 0 else { return }
            let level = Self.level(of: out)
            DispatchQueue.main.async { self.peak = max(self.peak, level); onLevel?(level) }
            buffers += 1
            if buffers == 1 { Log.note("audio flowing (\(pcm.format.sampleRate) Hz from device)") }
            continuation.yield(AnalyzerInput(buffer: out))
        }
        output.setSampleBufferDelegate(delegate, queue: captureQueue)
        guard cap.canAddOutput(output) else { throw TranscriberError.noMicrophone }
        cap.addOutput(output)

        capture = cap
        captureDelegate = delegate
        Log.note("mic \(device.localizedName)")
        NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: cap, queue: .main) { note in
            Log.note("capture runtime error: \(String(describing: note.userInfo?[AVCaptureSessionErrorKey]))")
        }
        captureQueue.async { cap.startRunning(); Log.note("capture running=\(cap.isRunning)") }
    }

    private func stopCapture() {
        if let capture {
            captureQueue.async { capture.stopRunning() }
        }
        capture = nil
        captureDelegate = nil
    }

    /// Stops recording and returns everything that was said.
    func stopAndTranscribe() async throws -> String {
        state = .transcribing
        defer { Task { await self.warmUp(); if case .transcribing = self.state { self.state = .ready } } }

        try await startTask?.value
        stopCapture()
        guard let session else { throw TranscriberError.notReady }
        self.session = nil

        session.input.finish()
        Log.note("input finished, finalizing…")
        let finalizeDone = TextBox()
        let finalize = Task {
            defer { finalizeDone.finished = true }
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
        }
        let finished = await waitUntil(seconds: 15) { finalizeDone.finished }
        if !finished {
            Log.note("finalize timed out — cancelling analyzer")
            finalize.cancel()
            await session.analyzer.cancelAndFinishNow()
        }
        // Results normally all land before finalize returns; give stragglers a moment.
        _ = await waitUntil(seconds: 1) { session.box.finished }
        session.results.cancel()
        let text = session.box.text
        Log.note("transcript (peak level \(peak)): \"\(text)\"")
        if !finished && text.isEmpty { throw TranscriberError.timeout }
        return text
    }

    /// Throws away the current recording (accidental tap).
    func cancel() async {
        try? await startTask?.value
        stopCapture()
        if let session {
            self.session = nil
            session.input.finish()
            session.results.cancel()
            await session.analyzer.cancelAndFinishNow()
        }
        await warmUp()
        if state == .listening { state = .ready }
    }

    // MARK: helpers

    private final class CaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        let handler: (CMSampleBuffer) -> Void
        init(handler: @escaping (CMSampleBuffer) -> Void) { self.handler = handler }
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            handler(sampleBuffer)
        }
    }

    nonisolated private static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sample) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    nonisolated private static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var handedOver = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if handedOver { status.pointee = .noDataNow; return nil }
            handedOver = true
            status.pointee = .haveData
            return input
        }
        if let error { Log.note("convert failed: \(error)"); return nil }
        return out
    }

    /// 0…1 loudness, works for Int16 or Float32 buffers.
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        if let data = buffer.int16ChannelData?[0] {
            for i in 0..<n { let v = Float(data[i]) / 32768; sum += v * v }
        } else if let data = buffer.floatChannelData?[0] {
            for i in 0..<n { sum += data[i] * data[i] }
        } else { return 0 }
        return min(1, (sum / Float(n)).squareRoot() * 6)
    }
}

/// Polls `condition` until true or `seconds` elapse. (Awaiting a Task's value
/// can't be interrupted by cancellation, so we never block on one.)
@MainActor
private func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        if Date() >= deadline { return false }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
    return true
}
