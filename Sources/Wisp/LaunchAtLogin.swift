import Foundation
import ServiceManagement

/// Registers Wisp as a login item via SMAppService (macOS 13+).
/// Only works when running from a real .app bundle — `swift run` has no bundle to register.
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message on failure, nil on success.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        guard isAvailable else { return "Build Wisp.app first — this can't be set when running from the command line." }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.note("Launch at login \(enabled ? "enabled" : "disabled")")
            return nil
        } catch {
            Log.note("Launch at login failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
