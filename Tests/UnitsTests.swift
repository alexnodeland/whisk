// UnitsTests.swift
// Maps to: docs/acceptance/rules-parsing.feature (duration/size literals).

import XCTest

@testable import WhiskCore

final class UnitsTests: XCTestCase {

    func testDurationUnits() {
        XCTAssertEqual(Units.duration("30s"), 30)
        XCTAssertEqual(Units.duration("5m"), 300)
        XCTAssertEqual(Units.duration("12h"), 43200)
        XCTAssertEqual(Units.duration("7d"), 604800)
        XCTAssertEqual(Units.duration("2w"), 1_209_600)
        XCTAssertEqual(Units.duration(" 3d "), 259200)
    }

    func testDurationRejectsGarbage() {
        XCTAssertNil(Units.duration(""))
        XCTAssertNil(Units.duration("7"))
        XCTAssertNil(Units.duration("d"))
        XCTAssertNil(Units.duration("0d"))
        XCTAssertNil(Units.duration("-3d"))
        XCTAssertNil(Units.duration("3.5d"))
        XCTAssertNil(Units.duration("7y"))
    }

    func testSizeUnits() {
        XCTAssertEqual(Units.size("500B"), 500)
        XCTAssertEqual(Units.size("100KB"), 102_400)
        XCTAssertEqual(Units.size("25MB"), 26_214_400)
        XCTAssertEqual(Units.size("2GB"), 2_147_483_648)
        XCTAssertEqual(Units.size("100kb"), 102_400)
        XCTAssertEqual(Units.size(" 1KB "), 1024)
    }

    func testSizeRejectsGarbage() {
        XCTAssertNil(Units.size(""))
        XCTAssertNil(Units.size("100"))
        XCTAssertNil(Units.size("KB"))
        XCTAssertNil(Units.size("0KB"))
        XCTAssertNil(Units.size("100TB"))
        XCTAssertNil(Units.size("99999999999GB"))
    }

    func testFormatDurationPicksLargestEvenUnit() {
        XCTAssertEqual(Units.formatDuration(604800), "1w")
        XCTAssertEqual(Units.formatDuration(86400 * 3), "3d")
        XCTAssertEqual(Units.formatDuration(7200), "2h")
        XCTAssertEqual(Units.formatDuration(300), "5m")
        XCTAssertEqual(Units.formatDuration(90), "90s")
        XCTAssertEqual(Units.formatDuration(0), "0s")
    }

    func testFormatSizePicksLargestEvenUnit() {
        XCTAssertEqual(Units.formatSize(2_147_483_648), "2GB")
        XCTAssertEqual(Units.formatSize(26_214_400), "25MB")
        XCTAssertEqual(Units.formatSize(102_400), "100KB")
        XCTAssertEqual(Units.formatSize(500), "500B")
        XCTAssertEqual(Units.formatSize(1025), "1025B")
    }

    func testRoundTripThroughFormat() {
        XCTAssertEqual(Units.duration(Units.formatDuration(604800)), 604800)
        XCTAssertEqual(Units.size(Units.formatSize(102_400)), 102_400)
    }
}
