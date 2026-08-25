// ConditionEvaluatorTests.swift
// Maps to: docs/acceptance/matching.feature.

import XCTest

@testable import WhiskCore

final class ConditionEvaluatorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 2_000_000)

    private func matches(_ condition: Condition, _ facts: FileFacts, now: Date? = nil) -> Bool {
        ConditionEvaluator.matches(condition, facts: facts, now: now ?? base)
    }

    func testNameGlobAndRegex() {
        let facts = Fixtures.file("/d/shot.png")
        XCTAssertTrue(matches(.name(.glob("*.png")), facts))
        XCTAssertFalse(matches(.name(.glob("*.jpg")), facts))
        XCTAssertTrue(matches(.name(.regex("^shot\\..*$")), facts))
        XCTAssertFalse(matches(.name(.regex("^other")), facts))
    }

    func testExtensions() {
        let facts = Fixtures.file("/d/App.DMG")
        XCTAssertTrue(matches(.extensions(["dmg", "pkg"]), facts))
        XCTAssertTrue(matches(.extensions(["DMG"]), facts))
        XCTAssertFalse(matches(.extensions(["zip"]), facts))
    }

    func testKind() {
        XCTAssertTrue(matches(.kind(.file), Fixtures.file("/d/a.txt")))
        XCTAssertFalse(matches(.kind(.directory), Fixtures.file("/d/a.txt")))
        XCTAssertTrue(matches(.kind(.directory), Fixtures.file("/d/sub", isDirectory: true)))
    }

    func testSizeBounds() {
        let facts = Fixtures.file("/d/a.bin", size: 1000)
        XCTAssertTrue(matches(.size(SizeCondition(overBytes: 999, underBytes: nil)), facts))
        XCTAssertFalse(matches(.size(SizeCondition(overBytes: 1000, underBytes: nil)), facts))
        XCTAssertTrue(matches(.size(SizeCondition(overBytes: nil, underBytes: 1001)), facts))
        XCTAssertFalse(matches(.size(SizeCondition(overBytes: nil, underBytes: 1000)), facts))
        XCTAssertTrue(matches(.size(SizeCondition(overBytes: 500, underBytes: 1500)), facts))
    }

    func testAgeBounds() {
        let facts = Fixtures.file(
            "/d/a.txt",
            created: base.addingTimeInterval(-100),
            modified: base.addingTimeInterval(-50),
            added: base.addingTimeInterval(-10))
        XCTAssertTrue(matches(.age(AgeCondition(basis: .created, olderThanSeconds: 99, newerThanSeconds: nil)), facts))
        XCTAssertFalse(matches(.age(AgeCondition(basis: .created, olderThanSeconds: 100, newerThanSeconds: nil)), facts))
        XCTAssertTrue(matches(.age(AgeCondition(basis: .added, olderThanSeconds: nil, newerThanSeconds: 10)), facts))
        XCTAssertFalse(matches(.age(AgeCondition(basis: .added, olderThanSeconds: nil, newerThanSeconds: 9)), facts))
        XCTAssertTrue(matches(.age(AgeCondition(basis: .modified, olderThanSeconds: 20, newerThanSeconds: 60)), facts))
    }

    func testCombinators() {
        let facts = Fixtures.file("/d/a.png", size: 1000)
        let isPNG = Condition.extensions(["png"])
        let isBig = Condition.size(SizeCondition(overBytes: 1_000_000, underBytes: nil))
        XCTAssertTrue(matches(.all([isPNG]), facts))
        XCTAssertFalse(matches(.all([isPNG, isBig]), facts))
        XCTAssertTrue(matches(.any([isBig, isPNG]), facts))
        XCTAssertFalse(matches(.any([isBig]), facts))
        XCTAssertTrue(matches(.not(isBig), facts))
        XCTAssertFalse(matches(.not(isPNG), facts))
        XCTAssertTrue(matches(.all([]), facts))
        XCTAssertFalse(matches(.any([]), facts))
    }
}
