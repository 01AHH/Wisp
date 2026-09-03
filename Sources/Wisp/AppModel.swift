import AppKit
import AVFoundation
import Combine

/// Everything the main window shows and edits.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var section: Section? = .home
    @Published var state: Transcriber.State = .preparing("Getting ready…")
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var levels: [Float] = Array(repeating: 0, count: 24)

    @Published var holdKey: HoldKey = Settings.holdKey { didSet { Settings.holdKey = holdKey } }
    @Published var removeFillers = Settings.removeFillers { didSet { Settings.removeFillers = removeFillers } }
    @Published var microphoneUID = Settings.microphoneUID { didSet { Settings.microphoneUID = microphoneUID } }

    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var launchAtLoginError: String?

    @Published var devices: [AudioDevices.Device] = []
    @Published var defaultMicName = ""
    @Published var micTestResult: String?
    @Published var testingMic = false

    private var permissionTimer: Timer?

    private init() {
        refreshDevices()
    }

    var activeMicName: String { AudioDevices.selected()?.name ?? "no microphone" }

    var statusTitle: String {
        if !accessibilityGranted { return "Waiting for Accessibility access" }
        switch state {
        case .ready: return "Ready — hold \(holdKey.shortName) and speak"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .preparing(let why), .failed(let why): return why
        }
    }

    func refreshDevices() {
        devices = AudioDevices.inputs()
        defaultMicName = AudioDevices.systemDefault()?.name ?? "none"
        objectWillChange.send()
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Called from the Settings toggle. Reverts the switch if registration fails.
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = LaunchAtLogin.set(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Polls until Accessibility is granted, then starts the hotkey.
    func watchAccessibility() {
        refreshPermissions()
        if accessibilityGranted { HoldKeyMonitor.shared.start(); return }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPermissions()
                if self.accessibilityGranted {
                    self.permissionTimer?.invalidate()
                    HoldKeyMonitor.shared.start()
                }
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
        watchAccessibility()
    }

    func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func clearLevels() {
        levels = Array(repeating: 0, count: levels.count)
    }

    /// Records for three seconds and reports what came through.
    func testMicrophone() {
        let transcriber = Transcriber.shared
        guard transcriber.state == .ready, !testingMic else { return }
        testingMic = true
        micTestResult = "Listening for 3 seconds — say something…"
        transcriber.startListening()
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            do {
                let text = try await transcriber.stopAndTranscribe().trimmingCharacters(in: .whitespaces)
                let peak = transcriber.lastPeak
                if peak < 0.005 {
                    micTestResult = "No sound reached Wisp from “\(activeMicName)”. If that's the built-in mic, it's disabled while the lid is closed — pick another device above."
                } else if text.isEmpty {
                    micTestResult = "Audio is coming through (peak \(Int(peak * 100))%) but nothing was recognised. Try a full sentence."
                } else {
                    micTestResult = "Heard: “\(text)”  (peak \(Int(peak * 100))%)"
                }
            } catch {
                micTestResult = "Test failed: \(error.localizedDescription)"
            }
            clearLevels()
            testingMic = false
        }
    }
}
