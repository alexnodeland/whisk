// PatternRendererTests.swift
// Maps to: docs/acceptance/patterns.feature.

import XCTest

@testable import WhiskCore

final class PatternRendererTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    // 2001-09-09 01:46:40 UTC
    private let facts = Fixtures.file(
        "/d/Photo.JPG",
        created: Date(timeIntervalSince1970: 1_000_000_000),
        modified: Date(timeIntervalSince1970: 1_000_086_400),
        added: Date(timeIntervalSince1970: 1_000_172_800))

    func testExpandPath() {
        XCTAssertEqual(PatternRenderer.expandPath("~", home: "/Users/x"), "/Users/x")
        XCTAssertEqual(PatternRenderer.expandPath("~/Downloads", home: "/Users/x"), "/Users/x/Downloads")
        XCTAssertEqual(PatternRenderer.expandPath("/abs/path", home: "/Users/x"), "/abs/path")
        XCTAssertEqual(PatternRenderer.expandPath("relative", home: "/Users/x"), "relative")
    }

    func testNameAndExtTokens() {
        XCTAssertEqual(PatternRenderer.render(template: "{name}-copy.{ext}", facts: facts, timeZone: utc), "Photo-copy.jpg")
        XCTAssertEqual(PatternRenderer.render(template: "plain", facts: facts, timeZone: utc), "plain")
        XCTAssertEqual(PatternRenderer.render(template: "", facts: facts, timeZone: utc), "")
    }

    func testDateTokens() {
        XCTAssertEqual(PatternRenderer.render(template: "{date.created:yyyy-MM}", facts: facts, timeZone: utc), "2001-09")
        XCTAssertEqual(PatternRenderer.render(template: "{date.modified:dd}", facts: facts, timeZone: utc), "10")
        XCTAssertEqual(PatternRenderer.render(template: "{date.added:dd}", facts: facts, timeZone: utc), "11")
    }

    func testMalformedTemplates() {
        XCTAssertNil(PatternRenderer.render(template: "{unknown}", facts: facts, timeZone: utc))
        XCTAssertNil(PatternRenderer.render(template: "{name", facts: facts, timeZone: utc))
        XCTAssertNil(PatternRenderer.render(template: "{date.created}", facts: facts, timeZone: utc))
        XCTAssertNil(PatternRenderer.render(template: "{date.created:}", facts: facts, timeZone: utc))
        XCTAssertNil(PatternRenderer.render(template: "{date.deleted:yyyy}", facts: facts, timeZone: utc))
        XCTAssertNil(PatternRenderer.render(template: "{created:yyyy}", facts: facts, timeZone: utc))
    }

    func testIsValidTemplate() {
        XCTAssertTrue(PatternRenderer.isValidTemplate("{name}.{ext}"))
        XCTAssertTrue(PatternRenderer.isValidTemplate("Archive/{date.added:yyyy}"))
        XCTAssertFalse(PatternRenderer.isValidTemplate("{bogus}"))
    }

    func testResolveConflictNoCollision() {
        XCTAssertEqual(
            PatternRenderer.resolveConflict(proposed: "a.txt", existing: ["b.txt"], policy: .rename),
            .use("a.txt"))
    }

    func testResolveConflictPolicies() {
        let existing = ["A.TXT", "other.txt"]
        XCTAssertEqual(PatternRenderer.resolveConflict(proposed: "a.txt", existing: existing, policy: .skip), .skip)
        XCTAssertEqual(PatternRenderer.resolveConflict(proposed: "a.txt", existing: existing, policy: .replace), .replace("a.txt"))
        XCTAssertEqual(PatternRenderer.resolveConflict(proposed: "a.txt", existing: existing, policy: .rename), .use("a 2.txt"))
    }

    func testUniqueNameCountsPastCollisions() {
        let taken: Set<String> = ["a.txt", "a 2.txt", "a 3.txt"]
        XCTAssertEqual(PatternRenderer.uniqueName("a.txt", taken: taken), "a 4.txt")
        XCTAssertEqual(PatternRenderer.uniqueName("noext", taken: ["noext"]), "noext 2")
    }
}
