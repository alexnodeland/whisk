// RuleParserTests.swift
// Maps to: docs/acceptance/rules-parsing.feature.

import XCTest

@testable import WhiskCore

final class RuleParserTests: XCTestCase {

    private func parse(_ json: String) -> Result<RuleSet, RuleParseError> {
        RuleParser.parse(Data(json.utf8))
    }

    private func failureMessage(_ json: String) -> String {
        guard case .failure(let problem) = parse(json) else {
            XCTFail("expected failure for \(json)")
            return ""
        }
        return problem.message
    }

    private func wrap(rule: String) -> String {
        #"{version: 1, targets: [{path: "~/d", rules: [\#(rule)]}]}"#
    }

    // MARK: Happy path

    func testParsesJSON5WithCommentsAndTrailingCommas() throws {
        let json = """
            // comment
            {
              version: 1,
              targets: [
                { path: "~/Downloads", rules: [
                  { id: "r", match: { kind: "file" }, actions: [ { trash: {} }, ], },
                ]},
              ],
            }
            """
        guard case .success(let set) = parse(json) else { return XCTFail("expected success") }
        XCTAssertEqual(set.targets.first?.path, "~/Downloads")
    }

    func testValidPatternsPassValidation() {
        let json = wrap(
            rule: #"{id: "r", match: {any: [{name: {glob: "*.png"}}, {name: {regex: "^x$"}}]}, actions: [{trash: {}}]}"#)
        guard case .success = parse(json) else { return XCTFail("valid glob/regex must parse") }
    }

    func testSeedRulesParse() {
        guard case .success = parse(SweepCoordinator.seedRules) else { return XCTFail("seed must parse") }
    }

    func testEncodeRoundTripsThroughParse() throws {
        guard case .success(let set) = parse(SweepCoordinator.seedRules) else { return XCTFail("seed must parse") }
        guard case .success(let again) = RuleParser.parse(RuleParser.encode(set)) else { return XCTFail("re-parse failed") }
        XCTAssertEqual(again, set)
    }

    // MARK: Decode failures

    func testSyntaxError() {
        XCTAssertFalse(failureMessage("{version: 1,").isEmpty)
    }

    func testDescribeCoversEveryShape() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "boom")
        XCTAssertEqual(RuleParser.describe(DecodingError.dataCorrupted(context)), "boom")
        XCTAssertTrue(failureMessage(#"{version: 1}"#).contains("missing key \"targets\""))
        XCTAssertTrue(failureMessage(#"{version: "x", targets: []}"#).contains("wrong type"))
        XCTAssertTrue(failureMessage(#"{version: null, targets: []}"#).contains("missing value"))
        XCTAssertTrue(failureMessage(#"[1, 2]"#).contains("top level") || !failureMessage(#"[1, 2]"#).isEmpty)
        struct Custom: Error {}
        XCTAssertFalse(RuleParser.describe(Custom()).isEmpty)
    }

    func testPathStringRendersIndexesAndKeys() {
        let message = failureMessage(
            #"{version: 1, targets: [{path: "~/d", rules: [{id: "r", match: {kind: "file"}}]}]}"#)
        XCTAssertTrue(message.contains("targets[0].rules[0]"), message)
    }

    // MARK: Validation failures

    func testVersionAndTargets() {
        XCTAssertTrue(failureMessage(#"{version: 2, targets: [{path: "x", rules: []}]}"#).contains("unsupported version"))
        XCTAssertTrue(failureMessage(#"{version: 1, targets: []}"#).contains("no targets"))
    }

    func testDefaultsMustBePositive() {
        XCTAssertTrue(
            failureMessage(#"{version: 1, defaults: {maxActionsPerRule: 0}, targets: [{path: "x", rules: []}]}"#)
                .contains("positive"))
    }

    func testTargetPaths() {
        XCTAssertTrue(failureMessage(#"{version: 1, targets: [{path: "", rules: []}]}"#).contains("empty path"))
        XCTAssertTrue(
            failureMessage(#"{version: 1, targets: [{path: "x", rules: []}, {path: "x", rules: []}]}"#)
                .contains("duplicate target"))
    }

    func testRuleIDs() {
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "", match: {kind: "file"}, actions: [{trash: {}}]}"#))
                .contains("empty id"))
        let one = #"{id: "r", match: {kind: "file"}, actions: [{trash: {}}]}"#
        let dup = #"{version: 1, targets: [{path: "x", rules: [\#(one), \#(one)]}]}"#
        XCTAssertTrue(failureMessage(dup).contains("duplicate rule id"))
    }

    func testConditionValidation() {
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {all: []}, actions: [{trash: {}}]}"#))
                .contains("empty all/any"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {any: []}, actions: [{trash: {}}]}"#))
                .contains("empty all/any"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {all: [{name: {glob: "a["}}]}, actions: [{trash: {}}]}"#))
                .contains("malformed glob"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {any: [{name: {glob: "a["}}]}, actions: [{trash: {}}]}"#))
                .contains("malformed glob"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {not: {name: {regex: "(["}}}, actions: [{trash: {}}]}"#))
                .contains("invalid regex"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {extension: []}, actions: [{trash: {}}]}"#))
                .contains("empty extension"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {extension: ["png", ""]}, actions: [{trash: {}}]}"#))
                .contains("empty extension"))
    }

    func testActionValidation() {
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: []}"#))
                .contains("no actions"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{move: {to: ""}}]}"#))
                .contains("empty destination"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{copy: {to: "{bogus}"}}]}"#))
                .contains("unknown token"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{rename: {to: "{bogus}"}}]}"#))
                .contains("unknown token"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{run: {command: "relative"}}]}"#))
                .contains("absolute path"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{run: {command: "/x", timeoutSeconds: 0}}]}"#))
                .contains("timeout"))
        XCTAssertTrue(
            failureMessage(wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{run: {command: "/x", timeoutSeconds: 301}}]}"#))
                .contains("timeout"))
    }

    func testActionsAfterMoveOrTrashAreRejected() {
        XCTAssertTrue(
            failureMessage(
                wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{trash: {}}, {run: {command: "/x"}}]}"#)
            )
            .contains("unreachable"))
        XCTAssertTrue(
            failureMessage(
                wrap(rule: #"{id: "r", match: {kind: "file"}, actions: [{move: {to: "~/x"}}, {trash: {}}]}"#)
            )
            .contains("unreachable"))
        let chained = wrap(
            rule: #"{id: "r", match: {kind: "file"}, actions: [{rename: {to: "{name}.bak"}}, {copy: {to: "~/x"}}, {move: {to: "~/y"}}]}"#)
        guard case .success = parse(chained) else { return XCTFail("rename → copy → move must be valid") }
    }
}
