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
}
