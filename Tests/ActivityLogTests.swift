// ActivityLogTests.swift
// Maps to: docs/acceptance/activity-log.feature.

import XCTest

@testable import WhiskCore

final class ActivityLogTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func action(_ op: PlannedAction.Operation) -> PlannedAction {
        PlannedAction(ruleID: "r", ruleName: "Rule", notify: true, op: op)
    }

    func testEntryForOutcomes() {
        let move = action(.move(src: "/d/a.txt", destDir: "/e", onConflict: .rename))
        let ok = ActivityLog.entry(for: ExecutedAction(action: move, outcome: .success(dst: "/e/a.txt")), target: "/d", now: base)
        XCTAssertEqual(ok.action, "move")
        XCTAssertEqual(ok.src, "/d/a.txt")
        XCTAssertEqual(ok.dst, "/e/a.txt")
        XCTAssertEqual(ok.outcome, "ok")
        XCTAssertFalse(ok.dryRun)

        let failed = ActivityLog.entry(for: ExecutedAction(action: move, outcome: .failure("boom")), target: "/d", now: base)
        XCTAssertEqual(failed.outcome, "error")
        XCTAssertEqual(failed.detail, "boom")

        let skipped = ActivityLog.entry(for: ExecutedAction(action: move, outcome: .skipped), target: "/d", now: base)
        XCTAssertEqual(skipped.outcome, "skipped")

        let preview = ActivityLog.entry(for: ExecutedAction(action: move, outcome: .preview), target: "/d", now: base)
        XCTAssertEqual(preview.outcome, "preview")
        XCTAssertTrue(preview.dryRun)
    }

    func testVerbsAndSources() {
        XCTAssertEqual(ActivityLog.verb(for: .move(src: "/a", destDir: "/b", onConflict: .skip)), "move")
        XCTAssertEqual(ActivityLog.verb(for: .copy(src: "/a", destDir: "/b", onConflict: .skip)), "copy")
        XCTAssertEqual(ActivityLog.verb(for: .rename(src: "/a", proposedName: "b")), "rename")
        XCTAssertEqual(ActivityLog.verb(for: .trash(src: "/a")), "trash")
        XCTAssertEqual(ActivityLog.verb(for: .run(spec: RunSpec(command: "/x"), file: "/a")), "run")
        XCTAssertEqual(ActivityLog.source(of: .copy(src: "/a", destDir: "/b", onConflict: .skip)), "/a")
        XCTAssertEqual(ActivityLog.source(of: .rename(src: "/a", proposedName: "b")), "/a")
        XCTAssertEqual(ActivityLog.source(of: .run(spec: RunSpec(command: "/x"), file: "/f")), "/f")
    }

    func testLineRoundTrip() {
        let entry = ActivityEntry(
            ts: base, ruleID: "r", target: "/d", action: "move", src: "/d/a.txt",
            dst: "/e/a.txt", outcome: "ok", dryRun: false, detail: nil)
        let line = ActivityLog.encodeLine(entry)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertEqual(ActivityLog.decodeLine(line), entry)
    }

    func testDecodeToleratesGarbage() {
        XCTAssertNil(ActivityLog.decodeLine("not json"))
    }

    func testPruneByAgeAndCount() {
        let old = ActivityEntry(
            ts: base.addingTimeInterval(-31 * 86400), ruleID: "r", target: "/d", action: "move",
            src: "/a", dst: nil, outcome: "ok", dryRun: false, detail: nil)
        var entries = [old]
        for index in 0..<(ActivityLog.maxEntries + 5) {
            entries.append(
                ActivityEntry(
                    ts: base.addingTimeInterval(TimeInterval(index)), ruleID: "r", target: "/d",
                    action: "move", src: "/a\(index)", dst: nil, outcome: "ok", dryRun: false, detail: nil))
        }
        let pruned = ActivityLog.prune(entries, now: base)
        XCTAssertEqual(pruned.count, ActivityLog.maxEntries)
        XCTAssertFalse(pruned.contains(old))
        XCTAssertEqual(pruned.last?.src, "/a\(ActivityLog.maxEntries + 4)")
    }
}
