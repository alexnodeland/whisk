// ConditionEvaluator.swift
// Decides whether a file's metadata snapshot satisfies a rule's predicate.
// Deterministic given (facts, now). In coverage. Imports only Foundation.

import Foundation

/// Pure predicate evaluation over `FileFacts`.
enum ConditionEvaluator {

    /// Whether `facts` satisfies `condition` at instant `now`.
    static func matches(_ condition: Condition, facts: FileFacts, now: Date) -> Bool {
        switch condition {
        case .all(let conditions):
            return conditions.allSatisfy { matches($0, facts: facts, now: now) }
        case .any(let conditions):
            return conditions.contains { matches($0, facts: facts, now: now) }
        case .not(let inner):
            return !matches(inner, facts: facts, now: now)
        case .name(.glob(let pattern)):
            return GlobMatcher.matches(glob: pattern, name: facts.name)
        case .name(.regex(let pattern)):
            return GlobMatcher.matches(regex: pattern, name: facts.name)
        case .extensions(let extensions):
            return extensions.contains { $0.lowercased() == facts.ext }
        case .kind(let kind):
            return (kind == .directory) == facts.isDirectory
        case .size(let bounds):
            return matchesSize(bounds, facts: facts)
        case .age(let bounds):
            return matchesAge(bounds, facts: facts, now: now)
        }
    }

    /// Whether `facts.size` sits inside `bounds`.
    private static func matchesSize(_ bounds: SizeCondition, facts: FileFacts) -> Bool {
        if let over = bounds.overBytes, facts.size <= over { return false }
        if let under = bounds.underBytes, facts.size >= under { return false }
        return true
    }

    /// Whether the basis date's distance from `now` sits inside `bounds`.
    private static func matchesAge(_ bounds: AgeCondition, facts: FileFacts, now: Date) -> Bool {
        let age = now.timeIntervalSince(facts.date(for: bounds.basis))
        if let older = bounds.olderThanSeconds, age <= older { return false }
        if let newer = bounds.newerThanSeconds, age > newer { return false }
        return true
    }
}
