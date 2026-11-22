import Foundation

/// Finds secrets (API keys, tokens, emails, phone numbers…) in plain text. Pure and synchronous.
enum SecretDetector {
    private static let patterns: [NSRegularExpression] = [
        #"sk-ant-[A-Za-z0-9_\-]{10,}"#,
        #"sk-[A-Za-z0-9_\-]{20,}"#,
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"AIza[0-9A-Za-z_\-]{30,}"#,
        #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,
        #"(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#,
        #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,        // JWT
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,                       // email
        #"(?:\+\d{1,3}[ \-]?)?(?:\(\d{2,4}\)[ \-]?)?\d{3,5}[ \-]\d{3,5}(?:[ \-]\d{2,5})?"#, // phone
        #"(?i)(?:password|passwd|pwd|secret|token|api[_\-]?key)\s*[:=]\s*\S{4,}"#,  // key=value
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Ranges of every secret found in `text`, merged when overlapping.
    static func ranges(in text: String) -> [Range<String.Index>] {
        let ns = text as NSString
        var found: [NSRange] = []
        for re in patterns {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) { found.append(m.range) }
        }
        found.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for r in found {
            if let last = merged.last, r.location <= last.location + last.length {
                merged[merged.count - 1] = NSUnionRange(last, r)
            } else { merged.append(r) }
        }
        return merged.compactMap { Range($0, in: text) }
    }

    static func containsSecret(_ text: String) -> Bool { !ranges(in: text).isEmpty }
}
