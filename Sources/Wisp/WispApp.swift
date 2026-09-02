import AppKit

@main
enum WispMain {
    static func main() {
        if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
            SelfTest.run(outputPath: CommandLine.arguments.dropFirst(i + 1).first ?? "/tmp/wisp-selftest.txt")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pressedAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let model = AppModel.shared

        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            // Render each page to PNG and quit. No permissions, no audio.
            let dir = CommandLine.arguments.dropFirst(i + 1).first ?? "/tmp"
            Transcriber.shared.onStateChange = { model.state = $0 }
            Transcriber.shared.debugSetState(.ready)
            model.accessibilityGranted = true
            model.refreshDevices()
            MainWindowController.shared.show()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                for section in Section.allCases {
                    model.section = section
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    MainWindowController.shared.snapshot(to: "\(dir)/\(section.rawValue).png")
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    MainWindowController.shared.snapshot(to: "\(dir)/\(section.rawValue)-2.png")
                }
                Transcriber.shared.debugSetState(.listening)
                model.section = .home
                for i in 0..<24 { model.push(level: Float(0.2 + 0.6 * abs(sin(Double(i) * 0.7)))) }
                try? await Task.sleep(nanoseconds: 800_000_000)
                MainWindowController.shared.snapshot(to: "\(dir)/home-listening.png")
                exit(0)
            }
            return
        }

        Transcriber.shared.onStateChange = { state in
            model.state = state
            if state != .listening { model.clearLevels() }
        }
        Transcriber.shared.onLevel = { level in
            Overlay.shared.push(level: level)
            model.push(level: level)
        }
        Task { await Transcriber.shared.prepare(); model.refreshPermissions() }

        AudioDevices.onChange = { model.refreshDevices() }
        AudioDevices.startWatching()

        HoldKeyMonitor.shared.onPress = { [weak self] in self?.keyDown() }
        HoldKeyMonitor.shared.onRelease = { [weak self] in self?.keyUp() }
        HoldKeyMonitor.shared.onCancel = { [weak self] in self?.keyCancelled() }
        model.watchAccessibility()
        if !model.accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        MainWindowController.shared.show()
    }

    /// Closing the window leaves dictation running; the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }

    // MARK: dictation

    private func keyDown() {
        let transcriber = Transcriber.shared
        switch transcriber.state {
        case .ready:
            pressedAt = Date()
            Overlay.shared.show(.listening)
            transcriber.startListening()
        case .preparing(let why), .failed(let why):
            Overlay.shared.flash(why)
        case .listening, .transcribing:
            break
        }
    }

    private func keyUp() {
        guard let pressedAt, Transcriber.shared.state == .listening else { return }
        self.pressedAt = nil

        // A quick tap is almost always accidental.
        if Date().timeIntervalSince(pressedAt) < 0.25 {
            Overlay.shared.hide()
            Task { await Transcriber.shared.cancel() }
            return
        }

        Overlay.shared.show(.transcribing)
        Task {
            do {
                let raw = try await Transcriber.shared.stopAndTranscribe()
                let text = TextCleaner.clean(raw, removeFillers: Settings.removeFillers)
                if text.isEmpty {
                    Overlay.shared.flash("Didn't catch that")
                } else {
                    Settings.lastTranscript = text
                    Scratchpad.shared.remember(text)
                    Overlay.shared.hide()
                    TextInserter.insert(text)
                }
            } catch {
                Overlay.shared.flash(error.localizedDescription)
            }
        }
    }

    private func keyCancelled() {
        guard pressedAt != nil, Transcriber.shared.state == .listening else { return }
        pressedAt = nil
        Overlay.shared.hide()
        Task { await Transcriber.shared.cancel() }
    }

    // MARK: menu bar (the real one, at the top of the screen)

    @objc private func showMainWindow() { MainWindowController.shared.show() }

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Wisp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Wisp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        let show = window.addItem(withTitle: "Wisp", action: #selector(showMainWindow), keyEquivalent: "1")
        show.target = self
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}

/// `Wisp --selftest <file>`: record 4 s from the mic, transcribe, write the outcome to <file>.
enum SelfTest {
    static func run(outputPath: String) {
        var lines: [String] = []
        func out(_ s: String) { lines.append(s); try? lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8) }
        Task { @MainActor in
            let t = Transcriber.shared
            t.onStateChange = { out("state: \(String(describing: $0))") }
            await t.prepare()
            t.startListening()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            do {
                let text = try await t.stopAndTranscribe()
                out("TRANSCRIPT: [\(text)]")
            } catch { out("ERROR: \(error)") }
            out("done")
            exit(0)
        }
        RunLoop.main.run()
    }
}
