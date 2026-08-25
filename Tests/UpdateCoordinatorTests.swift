// UpdateCoordinatorTests.swift
// docs/acceptance/updates.feature — check orchestration, notify-once, and the
// auto-install path, all through fakes.

import Foundation
import XCTest

@testable import WhiskCore

final class UpdateCoordinatorTests: XCTestCase {

    private final class Harness {
        let fetcher = FakeUpdateFetcher()
        let installer = FakeUpdateInstaller()
        let notifier = FakeNotifier()
        let scheduler = FakeScheduler()
        let clock = FakeClock()
        let store = FakeKVStore()
        let coordinator: UpdateCoordinator
        var stateChanges = 0

        init(currentVersion: String = "0.1.1") {
            let settings = AppSettings(store: store)
            coordinator = UpdateCoordinator(
                fetcher: fetcher, installer: installer, notifier: notifier,
                scheduler: scheduler, clock: clock, settings: settings, currentVersion: currentVersion)
            coordinator.onStateChange = { self.stateChanges += 1 }
        }

        var settings: AppSettings { AppSettings(store: store) }

        func stubLatest(version: String, url: String = "https://example.test/Whisk-universal.zip") {
            let object: [String: Any] = [
                "tag_name": "v\(version)",
                "assets": [["name": "Whisk-universal.zip", "browser_download_url": url]],
            ]
            fetcher.fetchResponse = try! JSONSerialization.data(withJSONObject: object)
        }
    }

    // MARK: Cadence

    func testStartArmsInitialAndRecurringChecks() {
        let harness = Harness()
        harness.coordinator.start()
        XCTAssertEqual(harness.scheduler.scheduled.map(\.repeating), [false, true])
        XCTAssertEqual(harness.scheduler.scheduled.first?.seconds, UpdateCoordinator.initialCheckDelay)
    }

    func testTickChecksWhenDueAndRecordsTheCheckInstant() {
        let harness = Harness()
        harness.stubLatest(version: "0.1.1")
        harness.coordinator.start()
        harness.scheduler.fireAllOneShots()
        XCTAssertEqual(harness.fetcher.fetchedURLs, [UpdatePlanner.latestReleaseURL])
        XCTAssertEqual(harness.settings.lastUpdateCheck, harness.clock.now())
    }

    func testTickSkipsWhenRecentlyChecked() {
        let harness = Harness()
        harness.settings.lastUpdateCheck = harness.clock.now()
        harness.coordinator.tick()
        XCTAssertTrue(harness.fetcher.fetchedURLs.isEmpty)
    }

    func testTickSkipsWhenAutoCheckIsOff() {
        let harness = Harness()
        harness.settings.autoCheckUpdates = false
        harness.coordinator.tick()
        XCTAssertTrue(harness.fetcher.fetchedURLs.isEmpty)
    }

    func testRepeatingTickChecksAgainOnceStale() {
        let harness = Harness()
        harness.stubLatest(version: "0.1.1")
        harness.coordinator.start()
        harness.scheduler.fireAllOneShots()
        harness.clock.advance(UpdatePlanner.checkInterval + 1)
        harness.scheduler.fireRepeating()
        XCTAssertEqual(harness.fetcher.fetchedURLs.count, 2)
    }

    // MARK: Check outcomes

    func testUpToDateClearsAvailableUpdate() {
        let harness = Harness()
        harness.stubLatest(version: "0.1.1")
        harness.coordinator.check()
        XCTAssertNil(harness.coordinator.availableUpdate)
        XCTAssertNil(harness.coordinator.updateStatus)
        XCTAssertTrue(harness.notifier.posted.isEmpty)
    }

    func testFetchFailureKeepsStateAndStillRecordsCheck() {
        let harness = Harness()
        harness.fetcher.fetchResponse = nil
        harness.coordinator.check()
        XCTAssertNil(harness.coordinator.availableUpdate)
        XCTAssertEqual(harness.settings.lastUpdateCheck, harness.clock.now())
    }

    func testNewerVersionSurfacesAndNotifiesOnce() {
        let harness = Harness()
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        XCTAssertEqual(harness.coordinator.availableUpdate?.version, "0.2.0")
        XCTAssertEqual(harness.notifier.posted.count, 1)
        XCTAssertTrue(harness.notifier.posted[0].title.contains("0.2.0"))

        harness.coordinator.check()
        XCTAssertEqual(harness.notifier.posted.count, 1, "the same version must not notify twice")
    }

    func testUpdateNoticeHonorsTheNotificationsSwitch() {
        let harness = Harness()
        harness.settings.notificationsEnabled = false
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        XCTAssertEqual(harness.coordinator.availableUpdate?.version, "0.2.0", "the menu still shows it")
        XCTAssertTrue(harness.notifier.posted.isEmpty)
    }

    // MARK: Install

    func testAutoInstallDownloadsAndInstalls() {
        let harness = Harness()
        harness.settings.autoInstallUpdates = true
        harness.stubLatest(version: "0.2.0", url: "https://example.test/u.zip")
        harness.fetcher.downloadResponse = "/tmp/u.zip"
        harness.installer.callsCompletion = false  // success exits the process
        harness.coordinator.check()
        XCTAssertEqual(harness.fetcher.downloadedURLs, ["https://example.test/u.zip"])
        XCTAssertEqual(harness.installer.installedZips, ["/tmp/u.zip"])
        XCTAssertTrue(harness.notifier.posted.isEmpty, "auto-install replaces the notify path")
    }

    func testManualCheckReportsButNeverAutoInstalls() {
        let harness = Harness()
        harness.settings.autoInstallUpdates = true
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check(manual: true)
        XCTAssertEqual(harness.coordinator.availableUpdate?.version, "0.2.0")
        XCTAssertTrue(harness.fetcher.downloadedURLs.isEmpty, "a button click must not install by itself")
        XCTAssertTrue(harness.installer.installedZips.isEmpty)
        XCTAssertEqual(harness.notifier.posted.count, 1, "the availability notice still fires once")
    }

    func testManualInstallWithNoKnownUpdateDoesNothing() {
        let harness = Harness()
        harness.coordinator.installAvailable()
        XCTAssertTrue(harness.fetcher.downloadedURLs.isEmpty)
    }

    func testDownloadFailureNotifiesAndClearsStatus() {
        let harness = Harness()
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        harness.fetcher.downloadResponse = nil
        harness.coordinator.installAvailable()
        XCTAssertNil(harness.coordinator.updateStatus)
        XCTAssertTrue(harness.notifier.posted.last?.title.contains("failed") ?? false)
    }

    func testInstallerFailureNotifiesWithItsMessage() {
        let harness = Harness()
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        harness.fetcher.downloadResponse = "/tmp/u.zip"
        harness.installer.failure = "ditto exploded"
        harness.coordinator.installAvailable()
        XCTAssertEqual(harness.notifier.posted.last?.body, "ditto exploded")
    }

    func testInstallerFailureWithoutMessageUsesTheFallback() {
        let harness = Harness()
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        harness.fetcher.downloadResponse = "/tmp/u.zip"
        harness.installer.failure = nil
        harness.coordinator.installAvailable()
        XCTAssertEqual(harness.notifier.posted.last?.body, "Unknown installer error.")
    }

    func testStatusProgressesThroughDownloadAndInstall() {
        let harness = Harness()
        harness.stubLatest(version: "0.2.0")
        harness.coordinator.check()
        harness.fetcher.downloadResponse = "/tmp/u.zip"
        harness.installer.callsCompletion = false
        harness.coordinator.installAvailable()
        XCTAssertEqual(harness.coordinator.updateStatus, "Installing 0.2.0…")
        XCTAssertGreaterThan(harness.stateChanges, 0)
    }
}
