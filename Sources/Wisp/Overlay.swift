import AppKit
import SwiftUI

/// The little pill at the bottom of the screen while you talk.
@MainActor
final class Overlay {
    static let shared = Overlay()

    enum Mode: Equatable { case listening, transcribing, message(String) }

    private final class Model: ObservableObject {
        @Published var mode: Mode = .listening
        @Published var levels: [Float] = Array(repeating: 0, count: 18)
        /// False until the first mic buffer arrives (AirPods take a second or two).
        @Published var hasAudio = false
        /// True when we've been listening a while and heard nothing at all.
        @Published var stalled = false
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var stallTimer: Timer?

    private init() {}

    func show(_ mode: Mode) {
        hideTimer?.invalidate()
        model.mode = mode
        stallTimer?.invalidate()
        model.stalled = false
        if mode == .listening {
            model.levels = Array(repeating: 0, count: model.levels.count)
            model.hasAudio = false
            stallTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.model.hasAudio else { return }
                    self.model.stalled = true
                }
            }
        }
        let panel = panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func flash(_ text: String, for seconds: Double = 1.6) {
        show(.message(text))
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        stallTimer?.invalidate()
        panel?.orderOut(nil)
    }

    func push(level: Float) {
        if !model.hasAudio { model.hasAudio = true }
        model.levels.removeFirst()
        model.levels.append(level)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28))
    }

    // MARK: SwiftUI

    private struct PillView: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack(spacing: 10) {
                switch model.mode {
                case .listening where model.stalled:
                    Image(systemName: "mic.slash").foregroundStyle(.orange)
                    Text("No sound from \(AudioDevices.selected()?.name ?? "mic")")
                case .listening where !model.hasAudio:
                    Image(systemName: "mic").foregroundStyle(.secondary)
                    Text("Connecting mic…").foregroundStyle(.secondary)
                case .listening:
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    HStack(alignment: .center, spacing: 2.5) {
                        ForEach(model.levels.indices, id: \.self) { i in
                            Capsule()
                                .fill(.white)
                                .frame(width: 3, height: 4 + CGFloat(model.levels[i]) * 22)
                                .animation(.easeOut(duration: 0.08), value: model.levels[i])
                        }
                    }
                    .frame(height: 26)
                case .transcribing:
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Transcribing…")
                case .message(let text):
                    Image(systemName: "info.circle")
                    Text(text)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.black.opacity(0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .frame(width: 300, height: 48)
        }
    }
}
