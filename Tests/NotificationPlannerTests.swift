// NotificationPlannerTests.swift
// Maps to: docs/acceptance/notifications.feature.

import XCTest

@testable import WhiskCore

final class NotificationPlannerTests: XCTestCase {

    private func executed(
        _ op: PlannedAction.Operation,
        ruleID: String = "r",
        notify: Bool = true,
        outcome: ExecutedAction.Outcome = .success(dst: nil)
    ) -> ExecutedAction {
        ExecutedAction(action: PlannedAction(ruleID: ruleID, ruleName: ruleID.uppercased(), notify: notify, op: op), outcome: outcome)
    }

    func testBatchesPerRuleInOrder() {
        let items = [
            executed(.move(src: "/d/a.txt", destDir: "/e", onConflict: .rename), ruleID: "one"),
            executed(.trash(src: "/d/b.txt"), ruleID: "two"),
            executed(.move(src: "/d/c.txt", destDir: "/e", onConflict: .rename), ruleID: "one"),
        ]
        let notices = NotificationPlanner.notices(for: items, dryRun: false)
        XCTAssertEqual(notices.count, 2)
        XCTAssertEqual(notices[0].title, "Whisk — ONE")
        XCTAssertEqual(notices[0].body, "a.txt → e/\nc.txt → e/")
        XCTAssertEqual(notices[1].title, "Whisk — TWO")
        XCTAssertEqual(notices[1].body, "trashed b.txt")
    }

    func testElidesBeyondMaxDetailLines() {
        let items = (0..<6).map { executed(.trash(src: "/d/f\($0).txt")) }
        let notices = NotificationPlanner.notices(for: items, dryRun: false)
        XCTAssertEqual(notices.count, 1)
        XCTAssertTrue(notices[0].body.hasSuffix("…and 2 more"))
    }

    func testHonorsNotifyFlagAndSkipped() {
        let items = [
            executed(.trash(src: "/d/a.txt"), notify: false),
            executed(.trash(src: "/d/b.txt"), outcome: .skipped),
        ]
        XCTAssertTrue(NotificationPlanner.notices(for: items, dryRun: false).isEmpty)
    }

    func testFailuresAlwaysCollect() {
        let items = [
            executed(.trash(src: "/d/a.txt"), notify: false, outcome: .failure("nope")),
            executed(.move(src: "/d/b.txt", destDir: "/e", onConflict: .rename), outcome: .failure("denied")),
        ]
        let notices = NotificationPlanner.notices(for: items, dryRun: false)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Whisk — 2 errors")
        XCTAssertTrue(notices[0].body.contains("trashed a.txt: nope"))
    }

    func testSingularErrorTitle() {
        let items = [executed(.trash(src: "/d/a.txt"), outcome: .failure("nope"))]
        XCTAssertEqual(NotificationPlanner.notices(for: items, dryRun: false)[0].title, "Whisk — 1 error")
    }

    func testPreviewPrefix() {
        let items = [executed(.trash(src: "/d/a.txt"), outcome: .preview)]
        XCTAssertEqual(NotificationPlanner.notices(for: items, dryRun: true)[0].title, "Whisk preview — R")
    }

    func testDescribeCoversEveryOperation() {
        XCTAssertEqual(NotificationPlanner.describe(.copy(src: "/d/a.txt", destDir: "/e", onConflict: .skip)), "copied a.txt → e/")
        XCTAssertEqual(NotificationPlanner.describe(.rename(src: "/d/a.txt", proposedName: "b.txt")), "a.txt → b.txt")
        XCTAssertEqual(
            NotificationPlanner.describe(.run(spec: RunSpec(command: "/opt/unpack"), file: "/d/a.zip")),
            "ran unpack on a.zip")
    }

    func testStandaloneNotices() {
        XCTAssertTrue(NotificationPlanner.autoPausedNotice(ruleName: "X").body.contains("\"X\""))
        XCTAssertTrue(NotificationPlanner.pendingApprovalNotice(displayCommand: "/x -v").body.contains("/x -v"))
        XCTAssertTrue(NotificationPlanner.rulesErrorNotice(message: "bad").body.contains("bad"))
    }
}
