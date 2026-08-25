// LoopGuard.swift
// The runaway-rule protection state machine (ADR 0006): a self-write ledger
// (events for paths Whisk just wrote are dropped), per-(file, rule) cooldowns,
// and pruning. Budgets are enforced by the planner using this state.
// In coverage. Imports only Foundation.

import Foundation

/// Pure state for loop protection. Shims only feed it instants and paths.
struct LoopGuardState: Equatable {

    /// How long an FSEvent for a self-written path is ignored, seconds.
    static let selfWriteWindow: TimeInterval = 10

    /// Paths Whisk itself wrote recently, by write instant.
    private(set) var recentWrites: [String: Date] = [:]

    /// Last instant each (file path, rule id) pair was acted on.
    private(set) var lastActed: [ActionKey: Date] = [:]

    /// A (file path, rule id) cooldown key.
    struct ActionKey: Hashable {
        var path: String
        var ruleID: String
    }

    /// Record that Whisk wrote `path` at `now`.
    mutating func noteWrite(_ path: String, now: Date) {
        recentWrites[path] = now
    }

    /// Record that `ruleID` acted on `path` at `now`.
    mutating func noteAction(path: String, ruleID: String, now: Date) {
        lastActed[ActionKey(path: path, ruleID: ruleID)] = now
    }

    /// Whether an FSEvent at `path` should be dropped because Whisk itself
    /// wrote it within the self-write window.
    func shouldIgnoreEvent(at path: String, now: Date) -> Bool {
        guard let written = recentWrites[path] else { return false }
        return now.timeIntervalSince(written) < Self.selfWriteWindow
    }

    /// Whether `ruleID` is still cooling down for `path`.
    func cooldownActive(path: String, ruleID: String, now: Date, cooldown: TimeInterval) -> Bool {
        guard let acted = lastActed[ActionKey(path: path, ruleID: ruleID)] else { return false }
        return now.timeIntervalSince(acted) < cooldown
    }

    /// Drop entries too old to matter (bounded memory over long sessions).
    mutating func prune(now: Date, cooldown: TimeInterval) {
        let writeHorizon = now.addingTimeInterval(-Self.selfWriteWindow)
        recentWrites = recentWrites.filter { $0.value > writeHorizon }
        let actionHorizon = now.addingTimeInterval(-max(cooldown, Self.selfWriteWindow))
        lastActed = lastActed.filter { $0.value > actionHorizon }
    }
}
