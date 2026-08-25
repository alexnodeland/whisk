// SweepScheduler.swift
// Time-based sweep policy (ADR 0004): FSEvents cannot fire when a file simply
// gets older, so this computes the earliest future instant any olderThan
// condition could newly become true, clamped to a sane window. A safety-net
// rescan runs regardless. In coverage. Imports only Foundation.

import Foundation

/// When to sweep next, absent any filesystem event.
enum SweepScheduler {

    /// The safety-net full-rescan cadence, seconds.
    static let rescanInterval: TimeInterval = 1800

    /// FSEvent debounce before a triggered sweep, seconds.
    static let eventDebounce: TimeInterval = 2

    /// The earliest an age wake-up may fire, seconds from now.
    static let minWakeDelay: TimeInterval = 30

    /// The latest an age wake-up may fire, seconds from now (the rescan covers beyond).
    static let maxWakeDelay: TimeInterval = 3600

    /// The delay until the next age-based wake-up for `snapshots`, or nil when
    /// no future olderThan condition exists. Clamped to
    /// [`minWakeDelay`, `maxWakeDelay`].
    static func nextWakeDelay(snapshots: [(target: Target, facts: [FileFacts])], now: Date) -> TimeInterval? {
        var earliest: Date?
        for (target, facts) in snapshots {
            for rule in target.rules where rule.enabled {
                for bound in olderThanBounds(in: rule.match) {
                    for file in facts {
                        let fires = file.date(for: bound.basis).addingTimeInterval(bound.olderThan)
                        if fires > now && (earliest == nil || fires < earliest!) {
                            earliest = fires
                        }
                    }
                }
            }
        }
        guard let instant = earliest else { return nil }
        return min(max(instant.timeIntervalSince(now), minWakeDelay), maxWakeDelay)
    }

    /// Every (basis, olderThan) bound anywhere in `condition`. Bounds under
    /// `not`/`any` still only cause an extra sweep, never a missed one, so the
    /// walk is deliberately structure-blind.
    private static func olderThanBounds(in condition: Condition) -> [(basis: AgeBasis, olderThan: TimeInterval)] {
        switch condition {
        case .all(let inner), .any(let inner):
            return inner.flatMap(olderThanBounds(in:))
        case .not(let inner):
            return olderThanBounds(in: inner)
        case .age(let bound):
            return bound.olderThanSeconds.map { [(bound.basis, $0)] } ?? []
        case .name, .extensions, .kind, .size:
            return []
        }
    }
}
