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
