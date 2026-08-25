// GlobMatcherTests.swift
// Maps to: docs/acceptance/matching.feature (name globs and regexes).

import XCTest

@testable import WhiskCore

final class GlobMatcherTests: XCTestCase {

    func testLiteralAndStar() {
        XCTAssertTrue(GlobMatcher.matches(glob: "*.png", name: "shot.png"))
        XCTAssertTrue(GlobMatcher.matches(glob: "*.png", name: "SHOT.PNG"))
        XCTAssertFalse(GlobMatcher.matches(glob: "*.png", name: "shot.jpeg"))
        XCTAssertTrue(GlobMatcher.matches(glob: "report*", name: "report-final.pdf"))
        XCTAssertFalse(GlobMatcher.matches(glob: "*.png", name: "dir/shot.png"))
    }

    func testQuestionMark() {
        XCTAssertTrue(GlobMatcher.matches(glob: "file?.txt", name: "file1.txt"))
        XCTAssertFalse(GlobMatcher.matches(glob: "file?.txt", name: "file12.txt"))
    }

    func testCharacterClass() {
        XCTAssertTrue(GlobMatcher.matches(glob: "file[0-9].txt", name: "file7.txt"))
        XCTAssertFalse(GlobMatcher.matches(glob: "file[0-9].txt", name: "fileA.txt"))
    }

    func testAlternation() {
        XCTAssertTrue(GlobMatcher.matches(glob: "*.{png,jpg}", name: "a.jpg"))
        XCTAssertTrue(GlobMatcher.matches(glob: "*.{png,jpg}", name: "a.png"))
        XCTAssertFalse(GlobMatcher.matches(glob: "*.{png,jpg}", name: "a.gif"))
    }

    func testCommaOutsideBracesIsLiteral() {
        XCTAssertTrue(GlobMatcher.matches(glob: "a,b.txt", name: "a,b.txt"))
    }

    func testRegexSpecialsAreEscaped() {
        XCTAssertTrue(GlobMatcher.matches(glob: "a+b(1).txt", name: "a+b(1).txt"))
        XCTAssertFalse(GlobMatcher.matches(glob: "a+b.txt", name: "aab.txt"))
    }

    func testMalformedGlobs() {
        XCTAssertNil(GlobMatcher.regexPattern(fromGlob: "file[.txt"))
        XCTAssertNil(GlobMatcher.regexPattern(fromGlob: "file[].txt"))
        XCTAssertNil(GlobMatcher.regexPattern(fromGlob: "{a,{b,c}}"))
        XCTAssertNil(GlobMatcher.regexPattern(fromGlob: "{a,b"))
        XCTAssertNil(GlobMatcher.regexPattern(fromGlob: "a}b"))
        XCTAssertFalse(GlobMatcher.matches(glob: "file[.txt", name: "file1.txt"))
    }

    func testClassBodyBackslashIsEscaped() {
        XCTAssertNotNil(GlobMatcher.regexPattern(fromGlob: "file[\\]x.txt"))
    }

    func testRegexMatching() {
        XCTAssertTrue(GlobMatcher.matches(regex: "^Screenshot [0-9]{4}.*\\.png$", name: "Screenshot 2026-01-01.png"))
        XCTAssertFalse(GlobMatcher.matches(regex: "^Screenshot", name: "shot.png"))
        XCTAssertFalse(GlobMatcher.matches(regex: "Screenshot", name: "My Screenshot Collection"))
        XCTAssertFalse(GlobMatcher.matches(regex: "([", name: "anything"))
    }

    func testIsValidRegex() {
        XCTAssertTrue(GlobMatcher.isValidRegex("^a+$"))
        XCTAssertFalse(GlobMatcher.isValidRegex("(["))
    }
}
