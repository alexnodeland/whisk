// AppSettingsTests.swift
// Maps to: docs/acceptance/pause-and-dry-run.feature (persistence decisions).

import XCTest

@testable import WhiskCore

final class AppSettingsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func make() -> (AppSettings, FakeKVStore) {
        let store = FakeKVStore()
        return (AppSettings(store: store), store)
    }

    func testPauseUntilDate() {
        let (settings, _) = make()
        XCTAssertFalse(settings.isPaused(now: base))
        settings.pause(until: base.addingTimeInterval(60))
        XCTAssertTrue(settings.isPaused(now: base.addingTimeInterval(59)))
        XCTAssertFalse(settings.isPaused(now: base.addingTimeInterval(61)))
        settings.resume()
        XCTAssertFalse(settings.isPaused(now: base))
    }

    func testPauseForever() {
        let (settings, _) = make()
        settings.pause(until: nil)
        XCTAssertTrue(settings.isPaused(now: base.addingTimeInterval(1_000_000)))
    }

    func testGarbagePauseValueMeansNotPaused() {
        let (settings, store) = make()
        store.values["pausedUntil"] = "garbage"
        XCTAssertFalse(settings.isPaused(now: base))
    }

    func testDryRun() {
        let (settings, store) = make()
        XCTAssertFalse(settings.dryRun)
        settings.dryRun = true
        XCTAssertTrue(settings.dryRun)
        settings.dryRun = false
        XCTAssertFalse(settings.dryRun)
        XCTAssertNil(store.values["dryRun"])
    }

    func testNotificationsDefaultOn() {
        let (settings, store) = make()
        XCTAssertTrue(settings.notificationsEnabled)
        settings.notificationsEnabled = false
        XCTAssertFalse(settings.notificationsEnabled)
        settings.notificationsEnabled = true
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertNil(store.values["notificationsDisabled"])
    }

    func testAutoPausedRules() {
        let (settings, store) = make()
        XCTAssertEqual(settings.autoPausedRules, [])
        settings.autoPausedRules = ["b", "a"]
        XCTAssertEqual(settings.autoPausedRules, ["a", "b"])
        settings.autoPausedRules = []
        XCTAssertNil(store.values["autoPausedRules"])
        store.values["autoPausedRules"] = ""
        XCTAssertEqual(settings.autoPausedRules, [])
    }

    func testApprovalsRoundTrip() {
        let (settings, _) = make()
        XCTAssertEqual(settings.approvals, ApprovedCommands())
        settings.approvals = ApprovedCommands().approving("k")
        XCTAssertEqual(settings.approvals, ApprovedCommands().approving("k"))
    }

    func testSparklesMenuIconDefaultsOffAndRoundTrips() {
        let (settings, store) = make()
        XCTAssertFalse(settings.sparklesMenuIcon)
        settings.sparklesMenuIcon = true
        XCTAssertTrue(settings.sparklesMenuIcon)
        settings.sparklesMenuIcon = false
        XCTAssertFalse(settings.sparklesMenuIcon)
        XCTAssertNil(store.values["menuIconSparkles"])
    }

    func testRecentActivityCountDefaultsClampsAndRejectsGarbage() {
        let (settings, store) = make()
        XCTAssertEqual(settings.recentActivityCount, 10)
        settings.recentActivityCount = 15
        XCTAssertEqual(settings.recentActivityCount, 15)
        settings.recentActivityCount = 500
        XCTAssertEqual(settings.recentActivityCount, 50)
        settings.recentActivityCount = 0
        XCTAssertEqual(settings.recentActivityCount, 1)
        store.values["recentActivityCount"] = "999"
        XCTAssertEqual(settings.recentActivityCount, 50)
        store.values["recentActivityCount"] = "garbage"
        XCTAssertEqual(settings.recentActivityCount, 10)
    }

    func testLaunchAtLoginDesiredDefaultsOffAndRoundTrips() {
        let (settings, store) = make()
        XCTAssertFalse(settings.launchAtLoginDesired)
        settings.launchAtLoginDesired = true
        XCTAssertTrue(settings.launchAtLoginDesired)
        settings.launchAtLoginDesired = false
        XCTAssertFalse(settings.launchAtLoginDesired)
        XCTAssertNil(store.values["launchAtLogin"])
    }

    func testAutoCheckUpdatesDefaultsOnAndRoundTrips() {
        let (settings, store) = make()
        XCTAssertTrue(settings.autoCheckUpdates)
        settings.autoCheckUpdates = false
        XCTAssertFalse(settings.autoCheckUpdates)
        settings.autoCheckUpdates = true
        XCTAssertTrue(settings.autoCheckUpdates)
        XCTAssertNil(store.values["updatesAutoCheckDisabled"])
    }

    func testAutoInstallUpdatesDefaultsOffAndRoundTrips() {
        let (settings, store) = make()
        XCTAssertFalse(settings.autoInstallUpdates)
        settings.autoInstallUpdates = true
        XCTAssertTrue(settings.autoInstallUpdates)
        settings.autoInstallUpdates = false
        XCTAssertFalse(settings.autoInstallUpdates)
        XCTAssertNil(store.values["updatesAutoInstall"])
    }

    func testLastUpdateCheckRoundTripsAndRejectsGarbage() {
        let (settings, store) = make()
        XCTAssertNil(settings.lastUpdateCheck)
        let instant = Date(timeIntervalSince1970: 1_234_567)
        settings.lastUpdateCheck = instant
        XCTAssertEqual(settings.lastUpdateCheck, instant)
        settings.lastUpdateCheck = nil
        XCTAssertNil(store.values["updatesLastCheck"])
        store.values["updatesLastCheck"] = "not-a-number"
        XCTAssertNil(settings.lastUpdateCheck)
    }

    func testLastNotifiedUpdateVersionRoundTrips() {
        let (settings, _) = make()
        XCTAssertNil(settings.lastNotifiedUpdateVersion)
        settings.lastNotifiedUpdateVersion = "0.2.0"
        XCTAssertEqual(settings.lastNotifiedUpdateVersion, "0.2.0")
    }
}
