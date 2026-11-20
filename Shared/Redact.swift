import Foundation

/// Strips sensitive values before they are shown in previews or logs.
/// Matches the relay-side redaction (last4 for card/account numbers, [redacted] for keys).
public enum Redact {
    private static let patterns: [(regex: String, replacement: String)] = [
        // Card numbers: 13-19 digits (possibly space/dash separated)
        (#"(\d[\s\-]?){12,18}\d"#, "[card …]"),
        // Secret/key/password/token values after = or :
        (#"(?i)(secret|key|password|token|apikey|api_key)\s*[=:]\s*\S+"#, "$1=[redacted]"),
        // Email addresses
        (#"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#, "[email]"),
    ]

    public static func clean(_ s: String) -> String {
        var out = s
        for (pattern, rep) in patterns {
            if let re = try? NSRegularExpression(pattern: pattern) {
                let r = NSRange(out.startIndex..., in: out)
                out = re.stringByReplacingMatches(in: out, range: r, withTemplate: rep)
            }
        }
        return out
    }
}
