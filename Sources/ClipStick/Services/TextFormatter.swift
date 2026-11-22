import Foundation

/// Local, offline pretty-printing for JSON and SQL clips.
enum TextFormatter {
    /// Pretty-printed JSON, or nil when `text` isn't JSON (or is already formatted).
    static func prettyJSON(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let f = t.first, f == "{" || f == "[", let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: out, encoding: .utf8), s != t else { return nil }
        return s
    }

    private static let sqlStart = try! NSRegularExpression(pattern: #"^\s*(?i:select|insert|update|delete|with|create|alter)\b"#)

    static func looksLikeSQL(_ text: String) -> Bool {
        sqlStart.firstMatch(in: text, range: NSRange(location: 0, length: min(text.utf16.count, 40))) != nil && !text.contains("\n")
    }

    /// Minimal SQL formatter: clause keywords start new lines.
    static func prettySQL(_ text: String) -> String? {
        guard looksLikeSQL(text) else { return nil }
        let clauses = ["LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "FULL JOIN", "JOIN", "FROM", "WHERE", "GROUP BY",
                       "ORDER BY", "HAVING", "LIMIT", "UNION", "VALUES", "SET", "ON"]
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for c in clauses {
            let pattern = #"\s+(?i:"# + c.replacingOccurrences(of: " ", with: #"\s+"#) + #")\b"#
            s = s.replacingOccurrences(of: pattern, with: "\n" + c, options: .regularExpression)
        }
        return s
    }

    static func format(_ text: String) -> String? { prettyJSON(text) ?? prettySQL(text) }
}
