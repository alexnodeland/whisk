// Units.swift
// Parsing for the human-readable duration ("7d") and size ("100MB") strings
// used in the rules file. In coverage. Imports only Foundation.

import Foundation

/// Parsers for the unit-suffixed strings the rules schema uses.
enum Units {

    /// Seconds per duration unit suffix.
    private static let durationSeconds: [Character: TimeInterval] = [
        "s": 1,
        "m": 60,
        "h": 3600,
        "d": 86400,
        "w": 604800,
    ]

    /// Bytes per size unit suffix (binary multiples).
    private static let sizeBytes: [String: UInt64] = [
        "B": 1,
        "KB": 1024,
        "MB": 1024 * 1024,
        "GB": 1024 * 1024 * 1024,
    ]

    /// Parse a duration like "30s", "5m", "12h", "7d", "2w" into seconds.
    /// Returns nil for anything else.
    static func duration(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let unit = trimmed.last, let scale = durationSeconds[unit] else { return nil }
        guard let value = UInt(trimmed.dropLast()), value > 0 else { return nil }
        return TimeInterval(value) * scale
    }

    /// Render seconds back to the canonical unit-suffixed form ("7d", "90s"),
    /// choosing the largest unit that divides evenly.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let whole = UInt(seconds)
        for (unit, scale) in [("w", UInt(604800)), ("d", 86400), ("h", 3600), ("m", 60)] where whole >= scale && whole % scale == 0 {
            return "\(whole / scale)\(unit)"
        }
        return "\(whole)s"
    }

    /// Render bytes back to the canonical unit-suffixed form ("100KB", "512B"),
    /// choosing the largest unit that divides evenly.
    static func formatSize(_ bytes: UInt64) -> String {
        for (unit, scale) in [("GB", UInt64(1024 * 1024 * 1024)), ("MB", 1024 * 1024), ("KB", 1024)]
        where bytes >= scale && bytes % scale == 0 {
            return "\(bytes / scale)\(unit)"
        }
        return "\(bytes)B"
    }

    /// Parse a size like "500B", "100KB", "25MB", "2GB" into bytes.
    /// Returns nil for anything else.
    static func size(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = trimmed.prefix(while: \.isNumber)
        guard let value = UInt64(digits), value > 0 else { return nil }
        let suffix = String(trimmed.dropFirst(digits.count))
        guard let scale = sizeBytes[suffix] else { return nil }
        let (result, overflow) = value.multipliedReportingOverflow(by: scale)
        return overflow ? nil : result
    }
}
