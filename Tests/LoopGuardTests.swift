// LoopGuardTests.swift
// Maps to: docs/acceptance/loop-guard.feature.

import XCTest

@testable import WhiskCore

final class LoopGuardTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testSelfWriteWindow() {
        var state = LoopGuardState()
        state.noteWrite("/d/a.txt", now: base)
        XCTAssertTrue(state.shouldIgnoreEvent(at: "/d/a.txt", now: base.addingTimeInterval(5)))
        XCTAssertFalse(state.shouldIgnoreEvent(at: "/d/a.txt", now: base.addingTimeInterval(11)))
        XCTAssertFalse(state.shouldIgnoreEvent(at: "/d/other.txt", now: base))
    }

    func testCooldown() {
        var state = LoopGuardState()
        XCTAssertFalse(state.cooldownActive(path: "/d/a.txt", ruleID: "r", now: base, cooldown: 30))
        state.noteAction(path: "/d/a.txt", ruleID: "r", now: base)
        XCTAssertTrue(state.cooldownActive(path: "/d/a.txt", ruleID: "r", now: base.addingTimeInterval(29), cooldown: 30))
        XCTAssertFalse(state.cooldownActive(path: "/d/a.txt", ruleID: "r", now: base.addingTimeInterval(31), cooldown: 30))
        XCTAssertFalse(state.cooldownActive(path: "/d/a.txt", ruleID: "other", now: base, cooldown: 30))
    }

    func testPruneDropsStaleEntries() {
        var state = LoopGuardState()
        state.noteWrite("/d/old.txt", now: base)
        state.noteWrite("/d/new.txt", now: base.addingTimeInterval(100))
        state.noteAction(path: "/d/old.txt", ruleID: "r", now: base)
        state.noteAction(path: "/d/new.txt", ruleID: "r", now: base.addingTimeInterval(100))
        state.prune(now: base.addingTimeInterval(105), cooldown: 30)
        XCTAssertEqual(state.recentWrites.keys.sorted(), ["/d/new.txt"])
        XCTAssertEqual(Array(state.lastActed.keys), [LoopGuardState.ActionKey(path: "/d/new.txt", ruleID: "r")])
    }

    func testPruneHorizonUsesLargerOfCooldownAndWindow() {
        var state = LoopGuardState()
        state.noteAction(path: "/d/a.txt", ruleID: "r", now: base)
        state.prune(now: base.addingTimeInterval(60), cooldown: 120)
        XCTAssertEqual(state.lastActed.count, 1)
        state.prune(now: base.addingTimeInterval(121), cooldown: 120)
        XCTAssertTrue(state.lastActed.isEmpty)
    }
}
