// GlobMatcher.swift
// Translates the rules file's glob patterns into anchored regular expressions.
// Supports `*`, `?`, `[abc]` character classes, and `{a,b}` alternation.
// In coverage. Imports only Foundation.

import Foundation

/// Glob-to-regex translation and matching for file names.
enum GlobMatcher {

    /// Regex metacharacters that must be escaped when copied literally.
    private static let regexSpecials = Set("\\^$.|+()[]{}?*")

    /// Translate `glob` into an anchored regex pattern, or nil if the glob is
    /// malformed (unterminated class or alternation, nested alternation).
    static func regexPattern(fromGlob glob: String) -> String? {
        var out = "^"
        let chars = Array(glob)
        var index = 0
        var braceDepth = 0
        while index < chars.count {
            let c = chars[index]
            switch c {
            case "*":
                out += "[^/]*"
            case "?":
                out += "[^/]"
            case "[":
                guard let close = chars[(index + 1)...].firstIndex(of: "]") else { return nil }
                let body = String(chars[(index + 1)..<close])
                guard !body.isEmpty else { return nil }
                out += "[" + body.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                index = close
            case "{":
                guard braceDepth == 0 else { return nil }
                braceDepth += 1
                out += "(?:"
            case ",":
                out += braceDepth > 0 ? "|" : ","
            case "}":
                guard braceDepth == 1 else { return nil }
                braceDepth -= 1
                out += ")"
            default:
                if regexSpecials.contains(c) {
                    out += "\\" + String(c)
                } else {
                    out += String(c)
                }
            }
            index += 1
        }
        guard braceDepth == 0 else { return nil }
        return out + "$"
    }

    /// Whether `name` matches `glob`, case-insensitively. Malformed globs match nothing.
    static func matches(glob: String, name: String) -> Bool {
        guard let pattern = regexPattern(fromGlob: glob) else { return false }
        return matches(regex: pattern, name: name)
    }

    /// Whether `name` matches the regex `pattern` in full, case-insensitively.
    /// Invalid patterns match nothing.
    static func matches(regex pattern: String, name: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return regex.firstMatch(in: name, options: [.anchored], range: range).map { $0.range == range } ?? false
    }

    /// Whether `pattern` compiles as a regular expression.
    static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
