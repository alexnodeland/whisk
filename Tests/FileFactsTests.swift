// FileFactsTests.swift
// Maps to: docs/acceptance/matching.feature (metadata snapshot semantics).

import XCTest

@testable import WhiskCore

final class FileFactsTests: XCTestCase {

    func testExtensionIsLowercasedAndDotless() {
        XCTAssertEqual(Fixtures.file("/d/Photo.JPG").ext, "jpg")
        XCTAssertEqual(Fixtures.file("/d/archive.tar.gz").ext, "gz")
        XCTAssertEqual(Fixtures.file("/d/README").ext, "")
    }

    func testStemDropsExtension() {
        XCTAssertEqual(Fixtures.file("/d/Photo.JPG").stem, "Photo")
        XCTAssertEqual(Fixtures.file("/d/README").stem, "README")
    }

    func testFromResourceDefaults() {
        let bare = FileFacts.fromResource(
            path: "/d/a", name: "a", isDirectory: nil, size: nil, created: nil, modified: nil, added: nil)
        XCTAssertFalse(bare.isDirectory)
        XCTAssertEqual(bare.size, 0)
        XCTAssertEqual(bare.created, .distantPast)
        XCTAssertEqual(bare.modified, .distantPast)
        XCTAssertEqual(bare.added, .distantPast)

        let created = Date(timeIntervalSince1970: 5)
        let partial = FileFacts.fromResource(
            path: "/d/a", name: "a", isDirectory: true, size: -3, created: created, modified: nil, added: nil)
        XCTAssertTrue(partial.isDirectory)
        XCTAssertEqual(partial.size, 0)
        XCTAssertEqual(partial.modified, created)
        XCTAssertEqual(partial.added, created)

        let full = FileFacts.fromResource(
            path: "/d/a", name: "a", isDirectory: false, size: 9,
            created: created, modified: Date(timeIntervalSince1970: 6), added: Date(timeIntervalSince1970: 7))
        XCTAssertEqual(full.size, 9)
        XCTAssertEqual(full.modified, Date(timeIntervalSince1970: 6))
        XCTAssertEqual(full.added, Date(timeIntervalSince1970: 7))
    }

    func testDateForBasis() {
        let created = Date(timeIntervalSince1970: 1)
        let modified = Date(timeIntervalSince1970: 2)
        let added = Date(timeIntervalSince1970: 3)
        let facts = Fixtures.file("/d/a.txt", created: created, modified: modified, added: added)
        XCTAssertEqual(facts.date(for: .created), created)
        XCTAssertEqual(facts.date(for: .modified), modified)
        XCTAssertEqual(facts.date(for: .added), added)
    }
}
