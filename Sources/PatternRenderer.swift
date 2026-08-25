// PatternRenderer.swift
// Renders the `{name}` / `{ext}` / `{date.*:FMT}` tokens in destination and
// rename templates, expands `~`, and decides conflict outcomes.
// In coverage. Imports only Foundation.

import Foundation

/// Template rendering and name-conflict resolution for destinations and renames.
enum PatternRenderer {

    /// What the executor should do about a proposed destination name.
    enum ConflictOutcome: Equatable {
        /// Use this name; nothing is in the way.
        case use(String)
        /// Remove the existing entry of this name first, then use it.
        case replace(String)
        /// Leave the file where it is.
        case skip
    }

    /// Expand a leading `~` to `home`.
    static func expandPath(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// Render `template` for `facts`, or nil if it contains an unknown or
    /// malformed token. Dates format with a fixed POSIX locale in `timeZone`.
    static func render(template: String, facts: FileFacts, timeZone: TimeZone) -> String? {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let afterOpen = rest[rest.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "}") else { return nil }
            guard let rendered = renderToken(String(afterOpen[..<close]), facts: facts, timeZone: timeZone) else { return nil }
            out += rendered
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        return out + rest
    }

    /// Whether `template`'s tokens are all well-formed. Uses fixed placeholder
    /// facts, so validity does not depend on any particular file.
    static func isValidTemplate(_ template: String) -> Bool {
        let probe = FileFacts(
            path: "/probe/file.txt", name: "file.txt", isDirectory: false, size: 0,
            created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0),
            added: Date(timeIntervalSince1970: 0))
        return render(template: template, facts: probe, timeZone: TimeZone(identifier: "UTC")!) != nil
    }

    /// Decide what to do when `proposed` may collide with `existing` names
    /// (compared case-insensitively, as on APFS default volumes).
    static func resolveConflict(proposed: String, existing: [String], policy: ConflictPolicy) -> ConflictOutcome {
        let taken = Set(existing.map { $0.lowercased() })
        if !taken.contains(proposed.lowercased()) { return .use(proposed) }
        switch policy {
        case .skip: return .skip
        case .replace: return .replace(proposed)
        case .rename: return .use(uniqueName(proposed, taken: taken))
        }
    }

    /// Finder-style uniquing: insert " 2", " 3", … before the extension until
    /// the name is free.
    static func uniqueName(_ proposed: String, taken: Set<String>) -> String {
        let stem = (proposed as NSString).deletingPathExtension
        let ext = (proposed as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var counter = 2
        var candidate = "\(stem) \(counter)\(suffix)"
        while taken.contains(candidate.lowercased()) {
            counter += 1
            candidate = "\(stem) \(counter)\(suffix)"
        }
        return candidate
    }

    /// Render one token body (the text between `{` and `}`), or nil if unknown.
    private static func renderToken(_ token: String, facts: FileFacts, timeZone: TimeZone) -> String? {
        switch token {
        case "name": return facts.stem
        case "ext": return facts.ext
        default: return renderDateToken(token, facts: facts, timeZone: timeZone)
        }
    }

    /// Render a `date.<basis>:<FMT>` token, or nil if malformed.
    private static func renderDateToken(_ token: String, facts: FileFacts, timeZone: TimeZone) -> String? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let head = String(token[..<colon])
        let format = String(token[token.index(after: colon)...])
        guard head.hasPrefix("date."), !format.isEmpty else { return nil }
        guard let basis = AgeBasis(rawValue: String(head.dropFirst("date.".count))) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: facts.date(for: basis))
    }
}
