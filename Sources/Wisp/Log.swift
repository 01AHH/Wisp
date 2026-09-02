import Foundation
import os

/// Timestamped lines to ~/Library/Logs/Wisp.log (and the unified log).
enum Log {
    private static let logger = Logger(subsystem: "com.arthurhinton.wisp", category: "wisp")
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Wisp.log")
    private static let queue = DispatchQueue(label: "wisp.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
