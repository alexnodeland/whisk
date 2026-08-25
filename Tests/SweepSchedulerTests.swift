// SweepSchedulerTests.swift
// Maps to: docs/acceptance/scheduling.feature.

import XCTest

@testable import WhiskCore

final class SweepSchedulerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func rule(_ condition: Condition, enabled: Bool = true) -> Rule {
        Rule(id: "r", enabled: enabled, match: condition, actions: [.trash])
    }

    private func target(_ rules: [Rule]) -> Target {
        Target(path: "/d", rules: rules)
    }

    func testNoAgeConditionsMeansNoWake() {
        let snapshot = [(target: target([rule(.extensions(["png"]))]), facts: [Fixtures.file("/d/a.png")])]
        XCTAssertNil(SweepScheduler.nextWakeDelay(snapshots: snapshot, now: base))
    }

    func testPicksEarliestFutureFire() {
        let condition = Condition.age(AgeCondition(basis: .added, olderThanSeconds: 600, newerThanSeconds: nil))
        let facts = [
            Fixtures.file("/d/soon.txt", added: base.addingTimeInterval(-500)),
            Fixtures.file("/d/later.txt", added: base.addingTimeInterval(-100)),
            Fixtures.file("/d/past.txt", added: base.addingTimeInterval(-700)),
        ]
        let delay = SweepScheduler.nextWakeDelay(snapshots: [(target([rule(condition)]), facts)], now: base)
        XCTAssertEqual(delay, 100)
    }

    func testClampsToMinAndMax() {
        let condition = Condition.age(AgeCondition(basis: .added, olderThanSeconds: 600, newerThanSeconds: nil))
        let nearly = [Fixtures.file("/d/a.txt", added: base.addingTimeInterval(-599))]
        XCTAssertEqual(
            SweepScheduler.nextWakeDelay(snapshots: [(target([rule(condition)]), nearly)], now: base), SweepScheduler.minWakeDelay)
        let distant = [Fixtures.file("/d/b.txt", added: base.addingTimeInterval(7200 - 600))]
        XCTAssertEqual(
            SweepScheduler.nextWakeDelay(snapshots: [(target([rule(condition)]), distant)], now: base), SweepScheduler.maxWakeDelay)
    }

    func testOnlyPastFilesMeansNoWake() {
        let condition = Condition.age(AgeCondition(basis: .added, olderThanSeconds: 600, newerThanSeconds: nil))
        let facts = [Fixtures.file("/d/past.txt", added: base.addingTimeInterval(-700))]
        XCTAssertNil(SweepScheduler.nextWakeDelay(snapshots: [(target([rule(condition)]), facts)], now: base))
    }

    func testDisabledRulesAndNewerThanAreIgnored() {
        let age = Condition.age(AgeCondition(basis: .added, olderThanSeconds: 600, newerThanSeconds: nil))
        let newer = Condition.age(AgeCondition(basis: .added, olderThanSeconds: nil, newerThanSeconds: 600))
        let facts = [Fixtures.file("/d/a.txt", added: base.addingTimeInterval(-100))]
        XCTAssertNil(SweepScheduler.nextWakeDelay(snapshots: [(target([rule(age, enabled: false)]), facts)], now: base))
        XCTAssertNil(SweepScheduler.nextWakeDelay(snapshots: [(target([rule(newer)]), facts)], now: base))
    }

    func testBoundsAreFoundInsideCombinators() {
        let nested = Condition.any([
            .not(.age(AgeCondition(basis: .modified, olderThanSeconds: 600, newerThanSeconds: nil))),
            .all([.kind(.file), .age(AgeCondition(basis: .created, olderThanSeconds: 300, newerThanSeconds: nil))]),
        ])
        let facts = [
            Fixtures.file(
                "/d/a.txt",
                created: base.addingTimeInterval(-100),
                modified: base.addingTimeInterval(-100),
                added: base)
        ]
        let delay = SweepScheduler.nextWakeDelay(snapshots: [(target([rule(nested)]), facts)], now: base)
        XCTAssertEqual(delay, 200)
    }
}
