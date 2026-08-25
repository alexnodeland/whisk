// WhiskRouteTests.swift
// Maps to: docs/acceptance/url-scheme.feature.

import XCTest

@testable import WhiskCore

final class WhiskRouteTests: XCTestCase {

    private func route(_ string: String) -> WhiskRoute? {
        WhiskRoute.parse(URL(string: string)!)
    }

    func testSweep() {
        XCTAssertEqual(route("whisk://sweep"), .sweep)
        XCTAssertEqual(route("WHISK://SWEEP"), .sweep)
    }

    func testPause() {
        XCTAssertEqual(route("whisk://pause"), .pause(minutes: nil))
        XCTAssertEqual(route("whisk://pause?minutes=60"), .pause(minutes: 60))
        XCTAssertNil(route("whisk://pause?minutes=0"))
        XCTAssertNil(route("whisk://pause?minutes=abc"))
    }

    func testResume() {
        XCTAssertEqual(route("whisk://resume"), .resume)
    }

    func testDryRun() {
        XCTAssertEqual(route("whisk://dry-run"), .dryRun(true))
        XCTAssertEqual(route("whisk://dry-run?enabled=true"), .dryRun(true))
        XCTAssertEqual(route("whisk://dry-run?enabled=false"), .dryRun(false))
        XCTAssertNil(route("whisk://dry-run?enabled=maybe"))
    }

    func testQueryEdgeCases() {
        XCTAssertEqual(route("whisk://pause?minutes=30&minutes=60"), .pause(minutes: 30))
        XCTAssertEqual(route("whisk://pause?minutes"), .pause(minutes: nil))
        XCTAssertEqual(route("whisk://sweep?x=1&y=2"), .sweep)
    }

    func testRejectsForeignAndUnknown() {
        XCTAssertNil(route("http://sweep"))
        XCTAssertNil(route("whisk://unknown"))
        XCTAssertNil(route("whisk://"))
    }
}
