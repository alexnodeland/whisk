// ShellApproval.swift
// First-run approval for shell commands (ADR 0007): a run action executes only
// after its exact (command, args template) pair has been approved once. New or
// changed commands are held, surfaced in the menu, and notified.
// In coverage. Imports only Foundation.

import Foundation

/// The persisted set of approved (command, args) pairs, and the gate decision.
struct ApprovedCommands: Equatable, Codable {

    /// The approved keys (see `key(for:)`).
    var approved: Set<String> = []

    /// What the executor should do with a run action.
    enum Gate: Equatable {
        /// The exact command has been approved before; run it.
        case approved
        /// Hold the action and ask the user.
        case pending(key: String)
    }

    /// The verbatim identity of a run spec: the executable plus its argument
    /// template, joined with a separator no argument can contain.
    static func key(for spec: RunSpec) -> String {
        ([spec.command] + spec.args).joined(separator: "\u{1F}")
    }

    /// A human-readable rendering of a key for menus and notifications.
    static func display(key: String) -> String {
        key.split(separator: "\u{1F}", omittingEmptySubsequences: false).joined(separator: " ")
    }

    /// Gate `spec` against the approved set.
    func gate(_ spec: RunSpec) -> Gate {
        let key = Self.key(for: spec)
        return approved.contains(key) ? .approved : .pending(key: key)
    }

    /// A copy with `key` approved.
    func approving(_ key: String) -> ApprovedCommands {
        var copy = self
        copy.approved.insert(key)
        return copy
    }

    /// Decode from the persisted JSON blob; nil or garbage yields the empty set.
    static func decode(from string: String?) -> ApprovedCommands {
        guard let string, let decoded = try? JSONDecoder().decode(ApprovedCommands.self, from: Data(string.utf8))
        else { return ApprovedCommands() }
        return decoded
    }

    /// Encode for persistence. ApprovedCommands always encodes, so this cannot fail.
    func encoded() -> String {
        String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }
}
