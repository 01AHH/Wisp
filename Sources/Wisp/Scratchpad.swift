import AppKit
import SwiftUI

/// The notepad in the main window. Dictate into it, edit freely, then
/// "pull through" — it brings back the app you came from and pastes the text
/// there. Also keeps your recent dictations for re-use.
@MainActor
final class Scratchpad {
    static let shared = Scratchpad()

    final class Model: ObservableObject {
        @Published var text: String = Settings.scratchpadText { didSet { Settings.scratchpadText = text } }
        @Published var history: [Dictation] = Settings.history { didSet { Settings.history = history } }
        @Published var targetName: String = ""
    }

    let model = Model()
    /// The app that was in front before Wisp — where "pull through" pastes.
    private var target: NSRunningApplication?

    private init() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            setTarget(front)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.setTarget(app) }
        }
    }

    /// Called after every successful dictation.
    func remember(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.history.insert(Dictation(text: clean, date: Date()), at: 0)
        if model.history.count > 500 { model.history.removeLast(model.history.count - 500) }
    }

    func append(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        model.text = model.text.isEmpty
            ? clean
            : model.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + clean
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text, forType: .string)
    }

    func pullThrough() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let target else { return }
        NSApp.hide(nil)
        target.activate()
        // Wait for focus to land back in the other app before pasting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            TextInserter.insert(text)
        }
    }

    private func setTarget(_ app: NSRunningApplication) {
        target = app
        model.targetName = app.localizedName ?? "previous app"
    }
}

