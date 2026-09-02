import Foundation

/// Light tidy-up so the pasted text reads like you typed it.
enum TextCleaner {
    private static let fillers = try! NSRegularExpression(
        pattern: #"(?i)(?<![\w'])(?:u+m+|u+h+|er+m*|hm+|mm+|ah+)(?![\w'])[,.]?\s*"#
    )

    static func clean(_ raw: String, removeFillers: Bool) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if removeFillers {
            text = fillers.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
            )
            text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = text.first else { return "" }
        text = first.uppercased() + text.dropFirst()

        // Trailing space so you can keep dictating in the same sentence.
        return text + " "
    }
}
