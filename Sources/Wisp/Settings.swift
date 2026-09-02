import AppKit
import CoreGraphics

/// Which modifier key you hold to dictate.
enum HoldKey: String, CaseIterable {
    case fn, rightOption, rightCommand, rightControl

    var title: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        }
    }

    var shortName: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .rightControl: return "right ⌃"
        }
    }

    /// Virtual key code reported in the flagsChanged event.
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }

    /// Flag that is set while the key is down.
    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        }
    }
}

/// Tiny UserDefaults wrapper — everything Wisp remembers.
enum Settings {
    private static let d = UserDefaults.standard

    static var holdKey: HoldKey {
        get { HoldKey(rawValue: d.string(forKey: "holdKey") ?? "") ?? .fn }
        set { d.set(newValue.rawValue, forKey: "holdKey") }
    }

    static var removeFillers: Bool {
        get { d.object(forKey: "removeFillers") as? Bool ?? true }
        set { d.set(newValue, forKey: "removeFillers") }
    }

    /// CoreAudio UID of the chosen input device; empty = follow the system default.
    static var microphoneUID: String {
        get { d.string(forKey: "microphoneUID") ?? "" }
        set { d.set(newValue, forKey: "microphoneUID") }
    }

    static var scratchpadText: String {
        get { d.string(forKey: "scratchpadText") ?? "" }
        set { d.set(newValue, forKey: "scratchpadText") }
    }

    static var history: [Dictation] {
        get {
            if let data = d.data(forKey: "history"),
               let items = try? JSONDecoder().decode([Dictation].self, from: data) { return items }
            // One-off migration from the old plain-string list.
            let old = d.stringArray(forKey: "recentTranscripts") ?? []
            return old.map { Dictation(text: $0, date: Date()) }
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "history") }
    }

    static var lastTranscript: String {
        get { d.string(forKey: "lastTranscript") ?? "" }
        set { d.set(newValue, forKey: "lastTranscript") }
    }
}

/// One finished dictation.
struct Dictation: Codable, Identifiable, Equatable {
    var id = UUID()
    let text: String
    let date: Date

    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}
