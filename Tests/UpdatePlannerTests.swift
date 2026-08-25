// UpdatePlannerTests.swift
// docs/acceptance/updates.feature — parsing, version ordering, and cadence.

import Foundation
import XCTest

@testable import WhiskCore

final class UpdatePlannerTests: XCTestCase {

    // MARK: Parsing

    private func payload(tag: String, assets: [[String: String]]) -> Data {
        let object: [String: Any] = ["tag_name": tag, "assets": assets]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testParsesTagAndUniversalAsset() {
        let data = payload(
            tag: "v0.2.0",
            assets: [
                ["name": "Whisk-v0.2.0.zip", "browser_download_url": "https://example.test/versioned.zip"],
                ["name": "Whisk-universal.zip", "browser_download_url": "https://example.test/universal.zip"],
            ])
        XCTAssertEqual(
            UpdatePlanner.parseLatest(data),
            ReleaseInfo(version: "0.2.0", zipURL: "https://example.test/universal.zip"))
    }

    func testParsesTagWithoutLeadingV() {
        let data = payload(
            tag: "0.3.1",
            assets: [
                ["name": "Whisk-universal.zip", "browser_download_url": "https://example.test/u.zip"]
            ])
        XCTAssertEqual(UpdatePlanner.parseLatest(data)?.version, "0.3.1")
    }

    func testMalformedPayloadParsesToNil() {
        XCTAssertNil(UpdatePlanner.parseLatest(Data("not json".utf8)))
    }

    func testPayloadWithoutUniversalAssetParsesToNil() {
        let data = payload(
            tag: "v0.2.0",
            assets: [
                ["name": "Whisk-v0.2.0.zip", "browser_download_url": "https://example.test/versioned.zip"]
            ])
        XCTAssertNil(UpdatePlanner.parseLatest(data))
    }

    // MARK: Version ordering

    func testNewerPatchMinorAndMajor() {
        XCTAssertTrue(UpdatePlanner.isNewer("0.1.2", than: "0.1.1"))
        XCTAssertTrue(UpdatePlanner.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(UpdatePlanner.isNewer("1.0.0", than: "0.9.9"))
    }

    func testOlderAndEqualAreNotNewer() {
        XCTAssertFalse(UpdatePlanner.isNewer("0.1.0", than: "0.1.1"))
        XCTAssertFalse(UpdatePlanner.isNewer("0.1.1", than: "0.1.1"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertTrue(UpdatePlanner.isNewer("0.1.1", than: "0.1"))
        XCTAssertFalse(UpdatePlanner.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(UpdatePlanner.isNewer("0.1", than: "0.1.1"))
    }

    func testMalformedComponentsCountAsZeroSoTheyNeverWin() {
        XCTAssertFalse(UpdatePlanner.isNewer("garbage", than: "0.0.1"))
        XCTAssertTrue(UpdatePlanner.isNewer("0.0.1", than: "garbage"))
    }

    // MARK: Cadence

    func testNoCheckWhenAutoCheckIsOff() {
        XCTAssertFalse(UpdatePlanner.shouldCheck(now: Date(), lastCheck: nil, autoCheck: false))
    }

    func testFirstCheckIsAlwaysDue() {
        XCTAssertTrue(UpdatePlanner.shouldCheck(now: Date(), lastCheck: nil, autoCheck: true))
    }

    func testRecentCheckIsNotDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-UpdatePlanner.checkInterval + 60)
        XCTAssertFalse(UpdatePlanner.shouldCheck(now: now, lastCheck: recent, autoCheck: true))
    }

    func testStaleCheckIsDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = now.addingTimeInterval(-UpdatePlanner.checkInterval)
        XCTAssertTrue(UpdatePlanner.shouldCheck(now: now, lastCheck: stale, autoCheck: true))
    }
}
