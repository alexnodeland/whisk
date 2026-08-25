// SweepPlannerTests.swift
// Maps to: docs/acceptance/planning.feature and loop-guard.feature.

import XCTest

@testable import WhiskCore

final class SweepPlannerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 2_000_000)
    private let home = "/Users/x"

    private func context(
        defaults: RuleDefaults = RuleDefaults(),
        approvals: ApprovedCommands = ApprovedCommands(),
        paused: Set<String> = []
    ) -> SweepContext {
        SweepContext(
            now: base, home: home, timeZone: TimeZone(identifier: "UTC")!,
            defaults: defaults, approvals: approvals, pausedRules: paused)
    }

    private func rule(
        id: String = "r",
        enabled: Bool = true,
        match: Condition = .kind(.file),
        actions: [Action]
    ) -> Rule {
        Rule(id: id, enabled: enabled, match: match, actions: actions)
    }

    private func plan(
        rules: [Rule],
        facts: [FileFacts],
        guardState: LoopGuardState = LoopGuardState(),
        context: SweepContext? = nil
    ) -> SweepPlan {
        SweepPlanner.plan(
            target: Target(path: "~/Downloads", rules: rules), facts: facts,
            guardState: guardState, context: context ?? self.context())
    }

    // MARK: Basics

    func testMoveWithTildeExpansionAndConsumption() {
        let move = rule(actions: [.move(MoveSpec(to: "~/Archive"))])
        let second = rule(id: "second", actions: [.trash])
        let result = plan(rules: [move, second], facts: [Fixtures.file("/Users/x/Downloads/a.txt")])
        XCTAssertEqual(result.actions.count, 1)
        XCTAssertEqual(
            result.actions[0].op,
            .move(src: "/Users/x/Downloads/a.txt", destDir: "/Users/x/Archive", onConflict: .rename))
        XCTAssertTrue(result.autoPausedRules.isEmpty)
    }

    func testRelativeDestinationResolvesAgainstTarget() {
        let move = rule(actions: [.move(MoveSpec(to: "Sorted/{ext}"))])
        let result = plan(rules: [move], facts: [Fixtures.file("/Users/x/Downloads/a.PNG")])
        XCTAssertEqual(
            result.actions[0].op,
            .move(src: "/Users/x/Downloads/a.PNG", destDir: "/Users/x/Downloads/Sorted/png", onConflict: .rename))
    }

    func testCopyDoesNotConsume() {
        let copy = rule(actions: [.copy(MoveSpec(to: "~/Backup"))])
        let trash = rule(id: "t", actions: [.trash])
        let result = plan(rules: [copy, trash], facts: [Fixtures.file("/Users/x/Downloads/a.txt")])
        XCTAssertEqual(result.actions.count, 2)
        XCTAssertEqual(result.actions[1].op, .trash(src: "/Users/x/Downloads/a.txt"))
    }

    func testRenameThreadsPathThroughChain() {
        let chain = rule(actions: [
            .rename(RenameSpec(to: "{name}-done.{ext}")),
            .copy(MoveSpec(to: "~/Backup")),
            .move(MoveSpec(to: "~/Archive")),
        ])
        let result = plan(rules: [chain], facts: [Fixtures.file("/Users/x/Downloads/a.txt")])
        XCTAssertEqual(
            result.actions.map(\.op),
            [
                .rename(src: "/Users/x/Downloads/a.txt", proposedName: "a-done.txt"),
                .copy(src: "/Users/x/Downloads/a-done.txt", destDir: "/Users/x/Backup", onConflict: .rename),
                .move(src: "/Users/x/Downloads/a-done.txt", destDir: "/Users/x/Archive", onConflict: .rename),
            ])
    }

    func testRunGating() {
        let spec = RunSpec(command: "/opt/unpack")
        let key = ApprovedCommands.key(for: spec)
        let run = rule(actions: [.run(spec)])
        let facts = [Fixtures.file("/Users/x/Downloads/a.zip")]

        let held = plan(rules: [run], facts: facts)
        XCTAssertTrue(held.actions.isEmpty)
        XCTAssertEqual(held.pendingApprovals, [PendingApproval(key: key, ruleID: "r", file: "/Users/x/Downloads/a.zip")])
        // A held command must not start the cooldown — approval acts immediately.
        XCTAssertFalse(held.guardState.cooldownActive(path: "/Users/x/Downloads/a.zip", ruleID: "r", now: base, cooldown: 30))

        let approved = plan(rules: [run], facts: facts, context: context(approvals: ApprovedCommands().approving(key)))
        XCTAssertEqual(approved.actions.map(\.op), [.run(spec: spec, file: "/Users/x/Downloads/a.zip")])
        XCTAssertTrue(approved.pendingApprovals.isEmpty)
    }

    // MARK: Skips

    func testDisabledPausedAndUnmatchedRulesPlanNothing() {
        let disabled = rule(id: "off", enabled: false, actions: [.trash])
        let paused = rule(id: "paused", actions: [.trash])
        let unmatched = rule(id: "nomatch", match: .extensions(["zip"]), actions: [.trash])
        let result = plan(
            rules: [disabled, paused, unmatched],
            facts: [Fixtures.file("/Users/x/Downloads/a.txt")],
            context: context(paused: ["paused"]))
        XCTAssertTrue(result.actions.isEmpty)
    }

    func testCooldownSkips() {
        var state = LoopGuardState()
        state.noteAction(path: "/Users/x/Downloads/a.txt", ruleID: "r", now: base.addingTimeInterval(-5))
        let result = plan(rules: [rule(actions: [.trash])], facts: [Fixtures.file("/Users/x/Downloads/a.txt")], guardState: state)
        XCTAssertTrue(result.actions.isEmpty)
    }

    func testGuardStateRecordsPlannedFiles() {
        let result = plan(rules: [rule(actions: [.trash])], facts: [Fixtures.file("/Users/x/Downloads/a.txt")])
        XCTAssertTrue(
            result.guardState.cooldownActive(path: "/Users/x/Downloads/a.txt", ruleID: "r", now: base, cooldown: 30))
    }

    // MARK: Budgets

    func testRuleBudgetAutoPauses() {
        let defaults = RuleDefaults(cooldownSeconds: 30, maxActionsPerRule: 2, maxActionsPerSweep: 500)
        let facts = (0..<4).map { Fixtures.file("/Users/x/Downloads/f\($0).txt") }
        let result = plan(rules: [rule(actions: [.trash])], facts: facts, context: context(defaults: defaults))
        XCTAssertEqual(result.actions.count, 2)
        XCTAssertEqual(result.autoPausedRules, ["r"])
        XCTAssertFalse(result.truncatedByBudget)
    }

    func testSweepBudgetTruncates() {
        let defaults = RuleDefaults(cooldownSeconds: 30, maxActionsPerRule: 100, maxActionsPerSweep: 3)
        let facts = (0..<5).map { Fixtures.file("/Users/x/Downloads/f\($0).txt") }
        let result = plan(rules: [rule(actions: [.trash])], facts: facts, context: context(defaults: defaults))
        XCTAssertEqual(result.actions.count, 3)
        XCTAssertTrue(result.truncatedByBudget)
        XCTAssertTrue(result.autoPausedRules.isEmpty)
    }

    // MARK: Refusals

    func testMoveIntoOwnDirectoryIsRefused() {
        let move = rule(actions: [.move(MoveSpec(to: "~/Downloads"))])
        let result = plan(rules: [move], facts: [Fixtures.file("/Users/x/Downloads/a.txt")])
        XCTAssertTrue(result.actions.isEmpty)
    }

    func testMoveDirectoryIntoItselfIsRefused() {
        let intoSelf = rule(match: .kind(.directory), actions: [.move(MoveSpec(to: "~/Downloads/sub/inner"))])
        let ontoSelf = rule(id: "onto", match: .kind(.directory), actions: [.move(MoveSpec(to: "~/Downloads/sub"))])
        let facts = [Fixtures.file("/Users/x/Downloads/sub", isDirectory: true)]
        XCTAssertTrue(plan(rules: [intoSelf], facts: facts).actions.isEmpty)
        XCTAssertTrue(plan(rules: [ontoSelf], facts: facts).actions.isEmpty)
    }

    func testUnrenderableTemplatesAreRefused() {
        // Constructed directly — the parser would reject these, but the planner
        // must stay safe if handed them anyway.
        let badMove = rule(actions: [.move(MoveSpec(to: "{bogus}"))])
        let badRename = rule(id: "r2", actions: [.rename(RenameSpec(to: "{bogus}"))])
        let slashRename = rule(id: "r3", actions: [.rename(RenameSpec(to: "a/b"))])
        let emptyRename = rule(id: "r4", actions: [.rename(RenameSpec(to: "{ext}"))])
        let sameRename = rule(id: "r5", actions: [.rename(RenameSpec(to: "{name}.{ext}"))])
        let facts = [Fixtures.file("/Users/x/Downloads/a.txt")]
        XCTAssertTrue(plan(rules: [badMove], facts: facts).actions.isEmpty)
        XCTAssertTrue(plan(rules: [badRename], facts: facts).actions.isEmpty)
        XCTAssertTrue(plan(rules: [slashRename], facts: facts).actions.isEmpty)
        XCTAssertTrue(plan(rules: [sameRename], facts: facts).actions.isEmpty)
        // "{ext}" renders to "txt", which is a legal (if odd) rename.
        XCTAssertEqual(plan(rules: [emptyRename], facts: facts).actions.count, 1)
    }

    func testEmptyRenderedRenameIsRefused() {
        let empty = rule(actions: [.rename(RenameSpec(to: "{ext}"))])
        let facts = [Fixtures.file("/Users/x/Downloads/README")]
        XCTAssertTrue(plan(rules: [empty], facts: facts).actions.isEmpty)
    }
}
