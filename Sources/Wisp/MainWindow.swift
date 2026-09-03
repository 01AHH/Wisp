import AppKit
import SwiftUI

// MARK: - Window

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Renders the window's content to a PNG (used by `--snapshot`).
    func snapshot(to path: String) {
        guard let window, let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        // Layer render: what the compositor actually has, not a re-draw.
        if let layer = view.layer {
            // AppKit layers are flipped relative to CG.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            layer.render(in: ctx)
        }
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Wisp"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 520)
        window.setFrameAutosaveName("WispMain")
        if !window.setFrameUsingName("WispMain") { window.center() }
        window.contentView = NSHostingView(
            rootView: MainView(app: AppModel.shared, pad: Scratchpad.shared.model)
        )
        self.window = window
        return window
    }
}

extension Color {
    static let wisp = Color(red: 0.56, green: 0.38, blue: 0.97)
    static let wispDeep = Color(red: 0.34, green: 0.18, blue: 0.74)
}

// MARK: - Shell

enum Section: String, CaseIterable, Identifiable {
    case home, scratchpad, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .scratchpad: return "Scratchpad"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .scratchpad: return "square.and.pencil"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var pad: Scratchpad.Model

    var body: some View {
        NavigationSplitView {
            List(selection: $app.section) {
                ForEach(Section.allCases) { s in
                    Label(s.title, systemImage: s.icon).tag(s)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarStatus(app: app) }
        } detail: {
            Group {
                switch app.section ?? .home {
                case .home: HomeView(app: app, pad: pad)
                case .scratchpad: ScratchpadView(model: pad, app: app)
                case .history: HistoryView(pad: pad)
                case .settings: SettingsView(app: app)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

private struct SidebarStatus: View {
    @ObservedObject var app: AppModel

    private var color: Color {
        if !app.accessibilityGranted { return .orange }
        switch app.state {
        case .ready: return .green
        case .listening: return .red
        case .transcribing: return .wisp
        case .preparing: return .orange
        case .failed: return .red
        }
    }
    private var text: String {
        if !app.accessibilityGranted { return "Needs permission" }
        switch app.state {
        case .ready: return "Ready · \(app.holdKey.shortName)"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .preparing: return "Getting ready"
        case .failed: return "Not working"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 4)
            Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared bits

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

private struct Waveform: View {
    let levels: [Float]
    var color: Color = .red
    var height: CGFloat = 44
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 4 + CGFloat(levels[i]) * (height - 4))
                    .animation(.easeOut(duration: 0.08), value: levels[i])
            }
        }
        .frame(height: height)
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

// MARK: - Home

private struct HomeView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var pad: Scratchpad.Model

    private var listening: Bool { app.state == .listening }
    private var todayWords: Int {
        pad.history.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words }
    }
    private var totalWords: Int { pad.history.reduce(0) { $0 + $1.words } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(title: "Wisp", subtitle: "Voice to text, anywhere on your Mac.")

                if !app.accessibilityGranted {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility access needed").font(.headline)
                            Text("It's how Wisp sees the hold key and pastes into other apps.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant Access…") { app.requestAccessibility() }
                            .buttonStyle(.borderedProminent).tint(.orange)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
                }

                Card(padding: 0) {
                    VStack(spacing: 18) {
                        MicOrb(listening: listening, level: app.levels.last ?? 0, ready: app.state == .ready && app.accessibilityGranted)
                            .padding(.top, 8)
                        VStack(spacing: 6) {
                            Text(app.statusTitle)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        if listening {
                            Waveform(levels: app.levels)
                        } else {
                            HStack(spacing: 8) {
                                Text("Hold")
                                KeyCap(text: app.holdKey.shortName)
                                Text("anywhere to dictate · release to paste")
                            }
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(height: 44)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 24)
                }

                HStack(spacing: 14) {
                    StatCard(value: "\(todayWords)", label: "Words today", icon: "sun.max.fill", tint: .orange)
                    StatCard(value: "\(totalWords)", label: "Words total", icon: "text.word.spacing", tint: .wisp)
                    StatCard(value: "\(pad.history.count)", label: "Dictations", icon: "waveform", tint: .pink)
                    StatCard(value: app.activeMicName, label: "Microphone", icon: "mic.fill", tint: .teal, small: true)
                }
            }
            .padding(28)
        }
    }

    private var subtitle: String {
        switch app.state {
        case .ready: return "Your words land wherever the cursor is — Mail, Slack, a browser, anything."
        case .listening: return "Speak naturally. Let go of the key when you're done."
        case .transcribing: return "Turning speech into text on this Mac — nothing leaves it."
        case .preparing: return "Apple's speech model is loading. This only takes a moment the first time."
        case .failed: return "Check the microphone and permissions in Settings."
        }
    }
}

private struct MicOrb: View {
    let listening: Bool
    let level: Float
    let ready: Bool

    var body: some View {
        ZStack {
            if listening {
                Circle()
                    .stroke(Color.red.opacity(0.25), lineWidth: 3)
                    .frame(width: 124 + CGFloat(level) * 70, height: 124 + CGFloat(level) * 70)
                    .animation(.easeOut(duration: 0.1), value: level)
            }
            Circle()
                .fill(LinearGradient(
                    colors: listening ? [.red, .orange] : (ready ? [.wisp, .wispDeep] : [Color.gray.opacity(0.6), Color.gray]),
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 112, height: 112)
                .shadow(color: (listening ? Color.red : Color.wisp).opacity(ready || listening ? 0.45 : 0), radius: 26, y: 10)
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .frame(width: 200, height: 200)
        .animation(.spring(duration: 0.35), value: listening)
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var small = false

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.14)))
                Text(value)
                    .font(.system(size: small ? 15 : 26, weight: .bold, design: .rounded))
                    .lineLimit(small ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 32, alignment: .bottomLeading)
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Scratchpad

struct ScratchpadView: View {
    @ObservedObject var model: Scratchpad.Model
    @ObservedObject var app: AppModel

    private var words: Int { model.text.split { $0.isWhitespace || $0.isNewline }.count }
    private var isEmpty: Bool { model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Scratchpad", subtitle: "Dictate here, tidy it up, then send it to the app you came from.")
                Text(words == 1 ? "1 word" : "\(words) words")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Card(padding: 0) {
                TextEditor(text: $model.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            HStack(spacing: 6) {
                                Text("Hold")
                                KeyCap(text: app.holdKey.shortName)
                                Text("and talk — words land here while this window is in front.")
                            }
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .padding(.leading, 19).padding(.top, 14)
                            .allowsHitTesting(false)
                        }
                    }
            }

            HStack(spacing: 10) {
                Menu {
                    if model.history.isEmpty { Text("No dictations yet") }
                    ForEach(model.history.prefix(15)) { item in
                        Button(item.text.count > 60 ? String(item.text.prefix(60)) + "…" : item.text) {
                            Scratchpad.shared.append(item.text)
                        }
                    }
                } label: {
                    Label("Insert Recent", systemImage: "clock.arrow.circlepath")
                }
                .fixedSize()
                Spacer()
                Button("Clear") { model.text = "" }.disabled(model.text.isEmpty)
                Button {
                    Scratchpad.shared.copyAll()
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(isEmpty)
                Button {
                    Scratchpad.shared.pullThrough()
                } label: {
                    Label(model.targetName.isEmpty ? "Pull Through" : "Pull Through to \(model.targetName)",
                          systemImage: "arrow.turn.up.right")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.wisp)
                .disabled(isEmpty || model.targetName.isEmpty)
                .help("⌘↩ — paste this into the app you came from")
            }
            .controlSize(.large)
        }
        .padding(28)
    }
}

// MARK: - History

private struct HistoryView: View {
    @ObservedObject var pad: Scratchpad.Model
    @State private var query = ""

    private var items: [Dictation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? pad.history : pad.history.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                PageHeader(title: "History", subtitle: "Everything you've dictated, newest first.")
                if !pad.history.isEmpty {
                    Button("Clear All", role: .destructive) { pad.history.removeAll() }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search dictations", text: $query).textFieldStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

            if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(pad.history.isEmpty ? "Nothing yet — your dictations will show up here." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in HistoryRow(item: item, pad: pad) }
                    }
                }
            }
        }
        .padding(28)
    }
}

private struct HistoryRow: View {
    let item: Dictation
    @ObservedObject var pad: Scratchpad.Model
    @State private var hovering = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.text).font(.system(size: 14)).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    Text(Self.relative.localizedString(for: item.date, relativeTo: Date()))
                    Text("·")
                    Text(item.words == 1 ? "1 word" : "\(item.words) words")
                    Spacer()
                    if hovering {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.text, forType: .string)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button {
                            Scratchpad.shared.append(item.text)
                        } label: { Label("To Scratchpad", systemImage: "square.and.pencil") }
                        Button(role: .destructive) {
                            pad.history.removeAll { $0.id == item.id }
                        } label: { Image(systemName: "trash") }
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .controlSize(.small)
                .frame(height: 22)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Settings", subtitle: "Everything runs on this Mac. No account, no cloud.")
                .padding(.horizontal, 28).padding(.top, 28)
            Form {
                SwiftUI.Section("Dictation") {
                    Picker("Hold key", selection: $app.holdKey) {
                        ForEach(HoldKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Remove filler words (um, uh, erm)", isOn: $app.removeFillers)
                }

                SwiftUI.Section("General") {
                    Toggle("Open Wisp at login", isOn: Binding(
                        get: { app.launchAtLogin },
                        set: { app.setLaunchAtLogin($0) }
                    ))
                    .disabled(!LaunchAtLogin.isAvailable)
                    if let err = app.launchAtLoginError {
                        Text(err).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !LaunchAtLogin.isAvailable {
                        Text("Available when running the installed Wisp.app.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                SwiftUI.Section("Microphone") {
                    Picker("Record from", selection: $app.microphoneUID) {
                        Text("System Default (\(app.defaultMicName))").tag("")
                        ForEach(app.devices, id: \.uid) { Text($0.name).tag($0.uid) }
                        if !app.microphoneUID.isEmpty, !app.devices.contains(where: { $0.uid == app.microphoneUID }) {
                            Text("Not connected — using default").tag(app.microphoneUID)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Button(app.testingMic ? "Listening…" : "Test Microphone") { app.testMicrophone() }
                            .disabled(app.testingMic || app.state != .ready)
                        if app.testingMic {
                            Waveform(levels: app.levels, color: .wisp, height: 22)
                        } else if let result = app.micTestResult {
                            Text(result).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }

                SwiftUI.Section("Permissions") {
                    PermissionRow(name: "Accessibility", granted: app.accessibilityGranted,
                                  hint: "Needed to see the hold key and paste into other apps.") {
                        app.requestAccessibility()
                    }
                    PermissionRow(name: "Microphone", granted: app.microphoneGranted,
                                  hint: "Needed to hear you.") {
                        app.openSettings("Privacy_Microphone")
                    }
                }

                SwiftUI.Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    LabeledContent("Speech engine", value: "Apple on-device (macOS 26)")
                    Button("Reveal Log in Finder") {
                        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Wisp.log")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
            app.refreshDevices()
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let hint: String
    let grant: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(granted ? "Granted" : hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: grant) }
        }
    }
}
