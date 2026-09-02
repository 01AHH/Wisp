import AppKit
import CoreGraphics

/// Watches a single modifier key system-wide and reports press / release.
/// Uses a CGEventTap, so it needs the Accessibility permission.
final class HoldKeyMonitor {
    static let shared = HoldKeyMonitor()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Fired when another key is typed while the hold key is down
    /// (e.g. fn+Delete) — that's a shortcut, not dictation.
    var onCancel: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false
    private var interrupted = false

    private init() {}

    var isRunning: Bool { tap != nil }

    /// Starts listening. Returns false if the tap could not be created
    /// (almost always: Accessibility permission not granted yet).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HoldKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
        isDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall; just switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            if isDown && !interrupted {
                interrupted = true
                DispatchQueue.main.async { [self] in onCancel?() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        let key = Settings.holdKey
        guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let nowDown = event.flags.contains(key.flag)
        if nowDown != isDown {
            isDown = nowDown
            let wasInterrupted = interrupted
            interrupted = false
            DispatchQueue.main.async { [self] in
                if nowDown { onPress?() } else if !wasInterrupted { onRelease?() }
            }
        }

        // Swallow the fn key so the system doesn't open the emoji picker /
        // start Apple's own dictation on top of ours.
        if key == .fn { return nil }
        return Unmanaged.passUnretained(event)
    }
}
