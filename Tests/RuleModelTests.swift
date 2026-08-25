// RuleModelTests.swift
// Maps to: docs/acceptance/rules-parsing.feature (schema coding).

import XCTest

@testable import WhiskCore

final class RuleModelTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(type, from: Data(json.utf8))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value)
    }

    // MARK: Conditions

    func testNamePattern() throws {
        XCTAssertEqual(try decode(NamePattern.self, #"{"glob": "*.png"}"#), .glob("*.png"))
        XCTAssertEqual(try decode(NamePattern.self, #"{"regex": "^a$"}"#), .regex("^a$"))
        XCTAssertThrowsError(try decode(NamePattern.self, "{}"))
        try roundTrip(NamePattern.glob("*.png"))
        try roundTrip(NamePattern.regex("^a$"))
    }

    func testSizeCondition() throws {
        XCTAssertEqual(try decode(SizeCondition.self, #"{"over": "1KB"}"#).overBytes, 1024)
        XCTAssertEqual(try decode(SizeCondition.self, #"{"under": "1KB"}"#).underBytes, 1024)
        XCTAssertThrowsError(try decode(SizeCondition.self, #"{"over": "huge"}"#))
        XCTAssertThrowsError(try decode(SizeCondition.self, #"{"under": "tiny"}"#))
        XCTAssertThrowsError(try decode(SizeCondition.self, "{}"))
        try roundTrip(SizeCondition(overBytes: 1024, underBytes: 2048))
        try roundTrip(SizeCondition(overBytes: nil, underBytes: 500))
    }

    func testAgeCondition() throws {
        let age = try decode(AgeCondition.self, #"{"basis": "modified", "olderThan": "7d"}"#)
        XCTAssertEqual(age.basis, .modified)
        XCTAssertEqual(age.olderThanSeconds, 604800)
        XCTAssertEqual(try decode(AgeCondition.self, #"{"newerThan": "1h"}"#).basis, .added)
        XCTAssertThrowsError(try decode(AgeCondition.self, #"{"olderThan": "ages"}"#))
        XCTAssertThrowsError(try decode(AgeCondition.self, #"{"newerThan": "ages"}"#))
        XCTAssertThrowsError(try decode(AgeCondition.self, #"{"basis": "added"}"#))
        try roundTrip(AgeCondition(basis: .created, olderThanSeconds: 3600, newerThanSeconds: 60))
        try roundTrip(AgeCondition(basis: .added, olderThanSeconds: nil, newerThanSeconds: 60))
    }

    func testConditionVariants() throws {
        XCTAssertEqual(try decode(Condition.self, #"{"kind": "file"}"#), .kind(.file))
        XCTAssertEqual(try decode(Condition.self, #"{"extension": ["png"]}"#), .extensions(["png"]))
        XCTAssertEqual(try decode(Condition.self, #"{"name": {"glob": "*"}}"#), .name(.glob("*")))
        XCTAssertEqual(
            try decode(Condition.self, #"{"all": [{"kind": "file"}]}"#), .all([.kind(.file)]))
        XCTAssertEqual(
            try decode(Condition.self, #"{"any": [{"kind": "directory"}]}"#), .any([.kind(.directory)]))
        XCTAssertEqual(try decode(Condition.self, #"{"not": {"kind": "file"}}"#), .not(.kind(.file)))
        XCTAssertEqual(
            try decode(Condition.self, #"{"size": {"over": "1KB"}}"#), .size(SizeCondition(overBytes: 1024, underBytes: nil)))
        XCTAssertEqual(
            try decode(Condition.self, #"{"age": {"olderThan": "1h"}}"#),
            .age(AgeCondition(basis: .added, olderThanSeconds: 3600, newerThanSeconds: nil)))
        XCTAssertThrowsError(try decode(Condition.self, "{}"))
        XCTAssertThrowsError(try decode(Condition.self, #"{"kind": "file", "extension": ["png"]}"#))
    }

    func testConditionRoundTrip() throws {
        let tree = Condition.all([
            .any([.name(.glob("*.png")), .name(.regex("^x"))]),
            .not(.kind(.directory)),
            .extensions(["png"]),
            .size(SizeCondition(overBytes: 1, underBytes: nil)),
            .age(AgeCondition(basis: .added, olderThanSeconds: 60, newerThanSeconds: nil)),
        ])
        try roundTrip(tree)
    }

    // MARK: Actions

    func testActionVariants() throws {
        XCTAssertEqual(
            try decode(Action.self, #"{"move": {"to": "~/x"}}"#), .move(MoveSpec(to: "~/x", onConflict: .rename)))
        XCTAssertEqual(
            try decode(Action.self, #"{"move": {"to": "~/x", "onConflict": "skip"}}"#),
            .move(MoveSpec(to: "~/x", onConflict: .skip)))
        XCTAssertEqual(
            try decode(Action.self, #"{"copy": {"to": "~/x"}}"#), .copy(MoveSpec(to: "~/x", onConflict: .rename)))
        XCTAssertEqual(try decode(Action.self, #"{"rename": {"to": "{name}.bak"}}"#), .rename(RenameSpec(to: "{name}.bak")))
        XCTAssertEqual(try decode(Action.self, #"{"trash": {}}"#), .trash)
        let run = try decode(Action.self, #"{"run": {"command": "/x"}}"#)
        XCTAssertEqual(run, .run(RunSpec(command: "/x", args: [], timeoutSeconds: 30)))
        let fullRun = try decode(Action.self, #"{"run": {"command": "/x", "args": ["-v"], "timeoutSeconds": 5}}"#)
        XCTAssertEqual(fullRun, .run(RunSpec(command: "/x", args: ["-v"], timeoutSeconds: 5)))
        XCTAssertThrowsError(try decode(Action.self, "{}"))
        XCTAssertThrowsError(try decode(Action.self, #"{"move": {"to": "x"}, "trash": {}}"#))
    }

    func testActionRoundTrip() throws {
        try roundTrip(Action.move(MoveSpec(to: "~/x", onConflict: .replace)))
        try roundTrip(Action.copy(MoveSpec(to: "~/x", onConflict: .skip)))
        try roundTrip(Action.rename(RenameSpec(to: "{name}")))
        try roundTrip(Action.trash)
        try roundTrip(Action.run(RunSpec(command: "/x", args: ["-v"], timeoutSeconds: 10)))
    }

    // MARK: Rules, targets, defaults, set

    func testRuleDefaultsAndDisplayName() throws {
        let rule = try decode(Rule.self, #"{"id": "r", "match": {"kind": "file"}, "actions": [{"trash": {}}]}"#)
        XCTAssertTrue(rule.enabled)
        XCTAssertTrue(rule.notify)
        XCTAssertNil(rule.name)
        XCTAssertEqual(rule.displayName, "r")
        let named = try decode(
            Rule.self,
            #"{"id": "r", "name": "Nice", "enabled": false, "notify": false, "match": {"kind": "file"}, "actions": [{"trash": {}}]}"#)
        XCTAssertEqual(named.displayName, "Nice")
        XCTAssertFalse(named.enabled)
        XCTAssertFalse(named.notify)
        try roundTrip(named)
        try roundTrip(rule)
    }

    func testRuleDefaultsType() throws {
        let empty = try decode(RuleDefaults.self, "{}")
        XCTAssertEqual(empty, RuleDefaults())
        let partial = try decode(RuleDefaults.self, #"{"cooldownSeconds": 5}"#)
        XCTAssertEqual(partial.cooldownSeconds, 5)
        XCTAssertEqual(partial.maxActionsPerRule, RuleDefaults().maxActionsPerRule)
        try roundTrip(RuleDefaults(cooldownSeconds: 1, maxActionsPerRule: 2, maxActionsPerSweep: 3))
    }

    func testRuleSetDefaultsAndLookup() throws {
        let json =
            #"{"version": 1, "targets": [{"path": "~/d", "rules": [{"id": "r", "match": {"kind": "file"}, "actions": [{"trash": {}}]}]}]}"#
        let set = try decode(RuleSet.self, json)
        XCTAssertEqual(set.defaults, RuleDefaults())
        XCTAssertEqual(set.allRules.map(\.id), ["r"])
        XCTAssertEqual(set.rule(withID: "r")?.id, "r")
        XCTAssertNil(set.rule(withID: "missing"))
        try roundTrip(set)
    }
}
