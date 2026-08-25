// WhiskRoute.swift
// Parses the whisk:// URL scheme: sweep now, pause/resume, and dry-run — the
// same verbs the menu offers, scriptable (and driven by the smoke test).
// In coverage. Imports only Foundation.

import Foundation

/// A parsed whisk:// command.
enum WhiskRoute: Equatable {
    /// Sweep every target now.
    case sweep
    /// Pause sweeps for `minutes`, or indefinitely when nil.
    case pause(minutes: Int?)
    /// Resume sweeps.
    case resume
    /// Turn dry-run mode on or off.
    case dryRun(Bool)

    /// Parse `url`, or nil for anything unrecognized.
    static func parse(_ url: URL) -> WhiskRoute? {
        guard url.scheme?.lowercased() == "whisk" else { return nil }
        let query = queryValues(of: url)
        switch url.host?.lowercased() {
        case "sweep":
            return .sweep
        case "pause":
            guard let raw = query["minutes"] else { return .pause(minutes: nil) }
            guard let minutes = Int(raw), minutes > 0 else { return nil }
            return .pause(minutes: minutes)
        case "resume":
            return .resume
        case "dry-run":
            switch query["enabled"] ?? "true" {
            case "true": return .dryRun(true)
            case "false": return .dryRun(false)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// The query string as a dictionary (first value wins; no percent decoding —
    /// the scheme's values are plain tokens).
    private static func queryValues(of url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for pair in (url.query ?? "").split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            if parts.count == 2 && out[key] == nil {
                out[key] = String(parts[1])
            }
        }
        return out
    }
}
