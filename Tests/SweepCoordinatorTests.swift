// SweepCoordinatorTests.swift
// Maps to: docs/acceptance/planning.feature, rules-reload.feature,
// pause-and-dry-run.feature, shell-safety.feature, loop-guard.feature,
// activity-log.feature, url-scheme.feature.

import XCTest

@testable import WhiskCore

final class SweepCoordinatorTests: XCTestCase {

    /// A coordinator wired entirely to fakes, with helpers for common setups.
    private final class Harness {
        let enumerator = FakeEnumerator()
        let files = FakeFileActor()
        let runner = FakeRunner()
        let notifier = FakeNotifier()
        let scheduler = FakeScheduler()
        let clock = FakeClock()
        let activity = FakeActivityStore()
        let rulesFile = FakeRulesFile()
        let watcher = FakeWatcher()
        let kv = FakeKVStore()
        var coordinator: SweepCoordinator?

        init() {
            coordinator = SweepCoordinator(
                enumerator: enumerator, files: files, runner: runner, notifier: notifier,
                scheduler: scheduler, clock: clock, activity: activity, rulesFile: rulesFile,
                watcher: watcher, settings: AppSettings(store: kv), home: "/U",
                timeZone: TimeZone(identifier: "UTC")!)
        }

        var settings: AppSettings { AppSettings(store: kv) }

        func setRules(_ json: String) {
            rulesFile.contents = Data(json.utf8)
        }

        func start() {
            coordinator?.start()
        }
    }

    private let trashRules = """
        {version: 1, targets: [{path: "~/d", rules: [
          {id: "t", match: {kind: "file"}, actions: [{trash: {}}]},
        ]}]}
        """

    // MARK: Lifecycle

    func testFirstLaunchSeedsRulesFile() {
        let h = Harness()
        h.start()
        XCTAssertEqual(h.rulesFile.writes.count, 1)
        XCTAssertNil(h.coordinator?.lastError)
        XCTAssertEqual(h.watcher.targetSets.last, ["/U/Downloads"])
        XCTAssertTrue(h.scheduler.scheduled.contains { $0.repeating && $0.seconds == SweepScheduler.rescanInterval })
    }

    func testExistingRulesFileIsNotReseeded() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        XCTAssertTrue(h.rulesFile.writes.isEmpty)
        XCTAssertEqual(h.watcher.targetSets.last, ["/U/d"])
    }

    func testParseFailureKeepsPreviousRulesAndNotifies() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.setRules("{nope")
        h.coordinator?.reloadRules()
        XCTAssertNotNil(h.coordinator?.lastError)
        XCTAssertEqual(h.coordinator?.ruleSet?.targets.first?.path, "~/d")
        XCTAssertTrue(h.notifier.posted.contains { $0.title.contains("rules file error") })
    }

    func testMissingRulesFileAfterStartSurfacesError() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.rulesFile.contents = nil
        h.coordinator?.reloadRules()
        XCTAssertTrue(h.coordinator?.lastError?.message.contains("missing") ?? false)
    }

    func testRulesFileEventReloads() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.setRules("{version: 1, targets: [{path: \"~/e\", rules: []}]}")
        h.watcher.onRulesFileEvent?()
        XCTAssertEqual(h.watcher.targetSets.last, ["/U/e"])
    }

    // MARK: Sweeping and execution

    func testSweepTrashesMatchingFilesAndLogs() {
        let h = Harness()
        h.setRules(trashRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.start()
        XCTAssertEqual(h.files.log, ["trash /U/d/a.txt -> /trash/a.txt"])
        XCTAssertEqual(h.coordinator?.recentActivity.last?.outcome, "ok")
        XCTAssertEqual(h.activity.lines.count, 1)
        XCTAssertEqual(h.coordinator?.targetStatuses["/U/d"]?.lastActionCount, 1)
        XCTAssertTrue(h.notifier.posted.contains { $0.body.contains("trashed a.txt") })
    }

    func testTrashFailureIsLoggedAndNotified() {
        let h = Harness()
        h.setRules(trashRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.files.failing = ["/U/d/a.txt"]
        h.start()
        XCTAssertEqual(h.coordinator?.recentActivity.last?.outcome, "error")
        XCTAssertTrue(h.notifier.posted.contains { $0.title.contains("error") })
    }

    private let moveRules = """
        {version: 1, targets: [{path: "~/d", rules: [
          {id: "m", match: {extension: ["png"]}, actions: [{move: {to: "~/pics"}}]},
        ]}]}
        """

    func testMoveCreatesDestinationAndRecordsSelfWrite() {
        let h = Harness()
        h.setRules(moveRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        h.start()
        XCTAssertEqual(h.files.log, ["mkdir /U/pics -> /U/pics", "move /U/d/a.png -> /U/pics/a.png"])
        XCTAssertTrue(h.coordinator!.guardState.shouldIgnoreEvent(at: "/U/pics/a.png", now: h.clock.now()))
    }

    func testMoveConflictPolicies() {
        let h = Harness()
        h.setRules(moveRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        h.enumerator.tree["/U/pics"] = [Fixtures.file("/U/pics/a.png")]
        h.start()
        XCTAssertTrue(h.files.log.contains("move /U/d/a.png -> /U/pics/a 2.png"))

        let skip = Harness()
        skip.setRules(moveRules.replacingOccurrences(of: "{to: \"~/pics\"}", with: "{to: \"~/pics\", onConflict: \"skip\"}"))
        skip.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        skip.enumerator.tree["/U/pics"] = [Fixtures.file("/U/pics/a.png")]
        skip.start()
        XCTAssertEqual(skip.coordinator?.recentActivity.last?.outcome, "skipped")

        let replace = Harness()
        replace.setRules(moveRules.replacingOccurrences(of: "{to: \"~/pics\"}", with: "{to: \"~/pics\", onConflict: \"replace\"}"))
        replace.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        replace.enumerator.tree["/U/pics"] = [Fixtures.file("/U/pics/a.png")]
        replace.start()
        XCTAssertTrue(replace.files.log.contains("remove /U/pics/a.png -> /U/pics/a.png"))
        XCTAssertTrue(replace.files.log.contains("move /U/d/a.png -> /U/pics/a.png"))
    }

    func testMoveFailureBranches() {
        let mkdirFail = Harness()
        mkdirFail.setRules(moveRules)
        mkdirFail.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        mkdirFail.files.failing = ["/U/pics"]
        mkdirFail.start()
        XCTAssertEqual(mkdirFail.coordinator?.recentActivity.last?.detail, "mkdir failed")

        let removeFail = Harness()
        removeFail.setRules(moveRules.replacingOccurrences(of: "{to: \"~/pics\"}", with: "{to: \"~/pics\", onConflict: \"replace\"}"))
        removeFail.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        removeFail.enumerator.tree["/U/pics"] = [Fixtures.file("/U/pics/a.png")]
        removeFail.files.failing = ["/U/pics/a.png"]
        removeFail.start()
        XCTAssertEqual(removeFail.coordinator?.recentActivity.last?.detail, "remove failed")
    }

    func testRenameUniquifiesAgainstSiblings() {
        let rules = """
            {version: 1, targets: [{path: "~/d", rules: [
              {id: "rn", match: {extension: ["png"]}, actions: [{rename: {to: "shot.{ext}"}}]},
            ]}]}
            """
        let h = Harness()
        h.setRules(rules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/IMG.png"), Fixtures.file("/U/d/shot.png")]
        h.start()
        XCTAssertTrue(h.files.log.contains("move /U/d/IMG.png -> /U/d/shot 2.png"))
        XCTAssertTrue(h.files.log.contains { $0.hasPrefix("move /U/d/shot.png") } == false)
    }

    func testDeniedTargetShowsBadge() {
        let h = Harness()
        h.setRules(trashRules)
        h.enumerator.denied = ["/U/d"]
        h.start()
        XCTAssertEqual(h.coordinator?.targetStatuses["/U/d"]?.denied, true)
    }

    func testSweepOfUnknownTargetIsIgnored() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.coordinator?.sweep(expandedTarget: "/nope")
        XCTAssertNil(h.coordinator?.targetStatuses["/nope"])
    }

    // MARK: Pause, dry-run, routes

    func testPauseBlocksSweepsAndRunNowOverrides() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.coordinator?.pause(until: nil)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.coordinator?.sweepAll()
        XCTAssertTrue(h.files.log.isEmpty)
        XCTAssertTrue(h.coordinator?.isPaused ?? false)
        h.coordinator?.runNow()
        XCTAssertFalse(h.files.log.isEmpty)
        h.coordinator?.resume()
        XCTAssertFalse(h.coordinator?.isPaused ?? true)
    }

    func testDryRunPreviewsWithoutTouching() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.coordinator?.setDryRun(true)
        XCTAssertTrue(h.coordinator?.isDryRun ?? false)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.coordinator?.sweepAll()
        XCTAssertTrue(h.files.log.isEmpty)
        XCTAssertEqual(h.coordinator?.recentActivity.last?.outcome, "preview")
        XCTAssertTrue(h.notifier.posted.contains { $0.title.contains("preview") })
    }

    func testRoutes() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.coordinator?.handle(route: .pause(minutes: 60))
        XCTAssertTrue(h.coordinator?.isPaused ?? false)
        h.clock.advance(3601)
        XCTAssertFalse(h.coordinator?.isPaused ?? true)
        h.coordinator?.handle(route: .pause(minutes: nil))
        XCTAssertTrue(h.coordinator?.isPaused ?? false)
        h.coordinator?.handle(route: .resume)
        XCTAssertFalse(h.coordinator?.isPaused ?? true)
        h.coordinator?.handle(route: .dryRun(true))
        XCTAssertTrue(h.coordinator?.isDryRun ?? false)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.coordinator?.handle(route: .sweep)
        XCTAssertEqual(h.coordinator?.recentActivity.last?.outcome, "preview")
    }

    // MARK: Debounce and self-write events

    func testTargetEventDebouncesAndSweeps() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.watcher.onTargetEvent?("/U/d", "/U/d/a.txt")
        h.watcher.onTargetEvent?("/U/d", "/U/d/a.txt")
        XCTAssertTrue(h.files.log.isEmpty)
        h.scheduler.fireAllOneShots()
        XCTAssertEqual(h.files.log.count, 1)
    }

    func testSelfWriteEventsAreDropped() {
        let h = Harness()
        h.setRules(moveRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        h.start()
        let before = h.scheduler.scheduled.count
        h.watcher.onTargetEvent?("/U/pics", "/U/pics/a.png")
        XCTAssertEqual(h.scheduler.scheduled.count, before)
    }

    // MARK: Shell runs

    private let runRules = """
        {version: 1, targets: [{path: "~/d", rules: [
          {id: "sh", match: {extension: ["zip"]}, actions: [{run: {command: "/opt/unpack", args: ["-v"]}}]},
        ]}]}
        """

    func testRunIsHeldForApprovalThenRunsAfterApprove() {
        let h = Harness()
        h.setRules(runRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.zip")]
        h.start()
        XCTAssertTrue(h.runner.requests.isEmpty)
        XCTAssertEqual(h.coordinator?.pendingApprovals.count, 1)
        XCTAssertTrue(h.notifier.posted.contains { $0.title.contains("needs approval") })

        // Re-sweeping while held must not duplicate or re-notify.
        h.clock.advance(60)
        h.coordinator?.sweepAll()
        XCTAssertEqual(h.coordinator?.pendingApprovals.count, 1)

        let key = h.coordinator!.pendingApprovals[0].key
        h.clock.advance(60)
        h.coordinator?.approve(key: key)
        XCTAssertEqual(h.runner.requests.count, 1)
        let request = h.runner.requests[0]
        XCTAssertEqual(request.command, "/opt/unpack")
        XCTAssertEqual(request.arguments, ["-v", "/U/d/a.zip"])
        XCTAssertEqual(request.directory, "/U/d")
        XCTAssertEqual(request.environment["WHISK_FILE"], "/U/d/a.zip")
        XCTAssertEqual(request.environment["WHISK_RULE_ID"], "sh")
        XCTAssertEqual(request.environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(request.environment["HOME"], "/U")
        XCTAssertEqual(request.timeout, 30)

        request.completion(0, "done")
        XCTAssertEqual(h.coordinator?.recentActivity.last?.action, "run")
        XCTAssertEqual(h.coordinator?.recentActivity.last?.outcome, "ok")
        XCTAssertTrue(h.notifier.posted.contains { $0.body.contains("ran unpack") })
    }

    func testRunFailureAndLaunchFailureAreRecorded() {
        let h = Harness()
        h.setRules(runRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.zip")]
        h.start()
        h.coordinator?.approve(key: h.coordinator!.pendingApprovals[0].key)
        h.runner.requests[0].completion(1, "boom")
        XCTAssertTrue(h.coordinator!.recentActivity.last!.detail!.contains("exit 1: boom"))

        h.clock.advance(60)
        h.coordinator?.sweepAll()
        h.runner.requests[1].completion(nil, "")
        XCTAssertTrue(h.coordinator!.recentActivity.last!.detail!.contains("failed to launch or timed out"))
    }

    func testRejectSilencesForSession() {
        let h = Harness()
        h.setRules(runRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.zip")]
        h.start()
        let key = h.coordinator!.pendingApprovals[0].key
        h.coordinator?.reject(key: key)
        XCTAssertTrue(h.coordinator!.pendingApprovals.isEmpty)
        h.clock.advance(60)
        h.coordinator?.sweepAll()
        XCTAssertTrue(h.coordinator!.pendingApprovals.isEmpty)
    }

    // MARK: Budgets and auto-pause

    func testRunawayRuleAutoPausesPersistsAndUnpauses() {
        let rules = """
            {version: 1, defaults: {maxActionsPerRule: 2},
             targets: [{path: "~/d", rules: [{id: "t", match: {kind: "file"}, actions: [{trash: {}}]}]}]}
            """
        let h = Harness()
        h.setRules(rules)
        h.enumerator.tree["/U/d"] = (0..<5).map { Fixtures.file("/U/d/f\($0).txt") }
        h.start()
        XCTAssertEqual(h.coordinator?.autoPausedRules, ["t"])
        XCTAssertTrue(h.notifier.posted.contains { $0.title.contains("paused a rule") })
        XCTAssertEqual(h.files.log.count, 2)

        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/f9.txt")]
        h.clock.advance(60)
        h.coordinator?.unpauseRule(id: "t")
        XCTAssertEqual(h.coordinator?.autoPausedRules, [])
        XCTAssertEqual(h.files.log.count, 3)
    }

    // MARK: Activity restore

    func testRestorePrunesOversizedLog() {
        let h = Harness()
        h.setRules(trashRules)
        let stale = ActivityEntry(
            ts: h.clock.now().addingTimeInterval(-40 * 86400), ruleID: "r", target: "/U/d",
            action: "move", src: "/a", dst: nil, outcome: "ok", dryRun: false, detail: nil)
        let fresh = ActivityEntry(
            ts: h.clock.now().addingTimeInterval(-60), ruleID: "r", target: "/U/d",
            action: "move", src: "/b", dst: nil, outcome: "ok", dryRun: false, detail: nil)
        h.activity.lines = [ActivityLog.encodeLine(stale), ActivityLog.encodeLine(fresh), "garbage"]
        h.start()
        XCTAssertEqual(h.coordinator?.recentActivity.map(\.src), ["/b"])
        XCTAssertEqual(h.activity.rewrites, 1)
    }

    func testRestoreWithNothingToPruneDoesNotRewrite() {
        let h = Harness()
        h.setRules(trashRules)
        let fresh = ActivityEntry(
            ts: h.clock.now().addingTimeInterval(-60), ruleID: "r", target: "/U/d",
            action: "move", src: "/b", dst: nil, outcome: "ok", dryRun: false, detail: nil)
        h.activity.lines = [ActivityLog.encodeLine(fresh)]
        h.start()
        XCTAssertEqual(h.activity.rewrites, 0)
    }

    // MARK: Age wake-ups and state-change hook

    func testAgeWakeSchedulesAndReschedules() {
        let rules = """
            {version: 1, targets: [{path: "~/d", rules: [
              {id: "old", match: {age: {olderThan: "1h"}}, actions: [{trash: {}}]},
            ]}]}
            """
        let h = Harness()
        h.setRules(rules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt", added: h.clock.now().addingTimeInterval(-1800))]
        h.start()
        let wake = h.scheduler.scheduled.last { !$0.repeating }
        XCTAssertEqual(wake?.seconds, 1800)
        h.clock.advance(1801)
        h.scheduler.fireAllOneShots()
        XCTAssertEqual(h.files.log.count, 1)
    }

    func testNotificationsGlobalToggle() {
        let h = Harness()
        h.setRules(trashRules)
        h.settings.notificationsEnabled = false
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.start()
        XCTAssertTrue(h.notifier.posted.isEmpty)
    }

    func testOnStateChangeFires() {
        let h = Harness()
        h.setRules(trashRules)
        var fired = 0
        h.coordinator?.onStateChange = { fired += 1 }
        h.start()
        XCTAssertGreaterThan(fired, 0)
    }

    func testRescanTimerSweeps() {
        let h = Harness()
        h.setRules(trashRules)
        h.start()
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.txt")]
        h.scheduler.fireRepeating()
        XCTAssertEqual(h.files.log.count, 1)
    }

    func testCopyExecutesAndUnreadableDestinationListingIsTolerated() {
        let rules = """
            {version: 1, targets: [{path: "~/d", rules: [
              {id: "c", match: {extension: ["png"]}, actions: [{copy: {to: "~/backup"}}]},
            ]}]}
            """
        let h = Harness()
        h.setRules(rules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.png")]
        h.enumerator.namesDenied = ["/U/backup"]
        h.start()
        XCTAssertTrue(h.files.log.contains("copy /U/d/a.png -> /U/backup/a.png"))
    }

    func testRenameWithUnreadableSiblingListingStillRenames() {
        let rules = """
            {version: 1, targets: [{path: "~/d", rules: [
              {id: "rn", match: {extension: ["png"]}, actions: [{rename: {to: "shot.{ext}"}}]},
            ]}]}
            """
        let h = Harness()
        h.setRules(rules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/IMG.png")]
        h.enumerator.namesDenied = ["/U/d"]
        h.start()
        XCTAssertTrue(h.files.log.contains("move /U/d/IMG.png -> /U/d/shot.png"))
    }

    func testRunNowBeforeStartDoesNothing() {
        let h = Harness()
        h.coordinator?.runNow()
        XCTAssertTrue(h.files.log.isEmpty)
    }

    // MARK: Released-coordinator callbacks are inert

    func testCallbacksAfterReleaseDoNothing() {
        let h = Harness()
        h.setRules(runRules)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/a.zip")]
        h.start()
        h.coordinator?.approve(key: h.coordinator!.pendingApprovals[0].key)
        h.enumerator.tree["/U/d"] = [Fixtures.file("/U/d/b.txt")]
        h.watcher.onTargetEvent?("/U/d", "/U/d/b.txt")
        let completion = h.runner.requests[0].completion
        h.coordinator = nil
        h.watcher.onRulesFileEvent?()
        h.scheduler.fireAllOneShots()
        completion(0, "late")
        XCTAssertFalse(h.files.log.contains { $0.contains("b.txt") })
    }
}
