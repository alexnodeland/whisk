// RulesTextTests.swift
// docs/acceptance/rules-editing.feature — the comment-preserving document
// model: parse/print round-trips, and merges that keep hand-written comments.

import Foundation
import XCTest

@testable import WhiskCore

final class RulesTextTests: XCTestCase {

    // MARK: Helpers

    private func roundTrip(_ text: String) -> String {
        RulesText.print(RulesText.parse(text)!)
    }

    private func decodeSet(_ data: Data) -> RuleSet {
        try! RuleParser.parse(data).get()
    }

    private let commented = """
        // My cleanup rules — synced via dotfiles.
        {
          version: 1,
          /* defaults tuned after the zip incident */
          defaults: { cooldownSeconds: 60 },
          targets: [
            {
              path: "~/Downloads",
              rules: [
                // Screenshots pile up fast.
                { id: "shots", match: { name: { glob: "*.png" } }, actions: [ { trash: {} } ] },
                { id: "keep", enabled: false,
                  // inner note about why this is disabled
                  match: { extension: ["dmg"] }, actions: [ { trash: {} } ] },
              ],
            },
          ],
        }
        // trailing thought
        """

    // MARK: Parse + print

    func testRoundTripKeepsCommentsAndStructure() {
        let printed = roundTrip(commented)
        XCTAssertTrue(printed.contains("// My cleanup rules — synced via dotfiles."))
        XCTAssertTrue(printed.contains("/* defaults tuned after the zip incident */"))
        XCTAssertTrue(printed.contains("// Screenshots pile up fast."))
        XCTAssertTrue(printed.contains("// inner note about why this is disabled"))
        XCTAssertTrue(printed.contains("// trailing thought"))
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        XCTAssertNoThrow(try decoder.decode(RuleSet.self, from: Data(printed.utf8)))
    }

    func testPrintingIsStable() {
        let once = roundTrip(commented)
        XCTAssertEqual(roundTrip(once), once)
    }

    func testParsesEmptyContainersAndBareScalars() {
        let printed = roundTrip("{ a: {}, b: [], c: true, d: null, e: 1.5 }")
        XCTAssertTrue(printed.contains("a: {}"))
        XCTAssertTrue(printed.contains("b: []"))
        XCTAssertTrue(printed.contains("c: true"))
        XCTAssertTrue(printed.contains("e: 1.5"))
    }

    func testParsesQuotedKeysSingleQuotesAndEscapes() {
        let printed = roundTrip(#"{ "quoted key": "a \"b\" c", other: 'single' }"#)
        XCTAssertTrue(printed.contains(#""quoted key": "a \"b\" c""#))
        XCTAssertTrue(printed.contains("other: 'single'"))
    }

    func testCommentsBetweenKeyColonAndValueAttachToTheMember() {
        let printed = roundTrip("{ a /*k*/ : // v\n 1 }")
        XCTAssertTrue(printed.contains("/*k*/"))
        XCTAssertTrue(printed.contains("// v"))
    }

    func testCommentAfterCommaAttachesForward() {
        let printed = roundTrip("[ 1, // note\n 2 ]")
        let noteLine = printed.range(of: "// note")
        let two = printed.range(of: "2,")
        XCTAssertNotNil(noteLine)
        XCTAssertNotNil(two)
        XCTAssertTrue(noteLine!.lowerBound < two!.lowerBound)
    }

    func testCommentsBeforeAClosingBracketSurvive() {
        let printed = roundTrip("{ a: [ 1, // last\n ], // end of a\n }")
        XCTAssertTrue(printed.contains("// last"))
        XCTAssertTrue(printed.contains("// end of a"))
    }

    func testMalformedTextParsesToNil() {
        XCTAssertNil(RulesText.parse(""))
        XCTAssertNil(RulesText.parse("{ a: 1"))
        XCTAssertNil(RulesText.parse("[ 1"))
        XCTAssertNil(RulesText.parse("{ a: }"))
        XCTAssertNil(RulesText.parse("{ a 1 }"))
        XCTAssertNil(RulesText.parse("{ a: 1 ]"))
        XCTAssertNil(RulesText.parse("[ 1 }"))
        XCTAssertNil(RulesText.parse("{ a: 1 } trailing"))
        XCTAssertNil(RulesText.parse("\"unterminated"))
        XCTAssertNil(RulesText.parse("\"bad escape \\"))
        XCTAssertNil(RulesText.parse("/* never closed"))
        XCTAssertNil(RulesText.parse("{ /* never closed"))
        XCTAssertNil(RulesText.parse("{ a: /* no"))
        XCTAssertNil(RulesText.parse("{ a: 1, /* no"))
        XCTAssertNil(RulesText.parse("[ /* no"))
        XCTAssertNil(RulesText.parse("[ 1, /* no"))
        XCTAssertNil(RulesText.parse("{ ,: 1 }"))
        XCTAssertNil(RulesText.parse("{} /* unterminated after root"))
        XCTAssertNil(RulesText.parse("[ , ]"))
        XCTAssertNil(RulesText.parse("{"))
        XCTAssertNil(RulesText.parse("["))
        XCTAssertNil(RulesText.parse("{ "))
        XCTAssertNil(RulesText.parse("[ "))
        XCTAssertNil(RulesText.parse("{ a: 1 /* no"))
        XCTAssertNil(RulesText.parse("[ 1 /* no"))
    }

    // MARK: Merge

    private func makeSet(_ mutate: (inout RuleSet) -> Void = { _ in }) -> RuleSet {
        var set = decodeSet(Data(commented.utf8))
        mutate(&set)
        return set
    }

    func testUnchangedSaveKeepsEveryComment() {
        let out = String(decoding: RulesText.encode(makeSet(), preserving: commented), as: UTF8.self)
        XCTAssertTrue(out.contains("// My cleanup rules — synced via dotfiles."))
        XCTAssertTrue(out.contains("// Screenshots pile up fast."))
        XCTAssertTrue(out.contains("// inner note about why this is disabled"))
        XCTAssertTrue(out.contains("/* defaults tuned after the zip incident */"))
        XCTAssertTrue(out.contains("// trailing thought"))
        XCTAssertEqual(decodeSet(Data(out.utf8)), makeSet())
    }

    func testEditingOneRuleKeepsItsLeadingCommentAndTheOthersEntirely() {
        let edited = makeSet { $0.targets[0].rules[0].enabled = false }
        let out = String(decoding: RulesText.encode(edited, preserving: commented), as: UTF8.self)
        XCTAssertTrue(out.contains("// Screenshots pile up fast."), "leading comment of the edited rule survives")
        XCTAssertTrue(out.contains("// inner note about why this is disabled"), "untouched rule keeps inner comments")
        XCTAssertEqual(decodeSet(Data(out.utf8)), edited)
    }

    func testDeletingARuleRemovesItAndKeepsTheRest() {
        let edited = makeSet { $0.targets[0].rules.removeFirst() }
        let out = String(decoding: RulesText.encode(edited, preserving: commented), as: UTF8.self)
        XCTAssertFalse(out.contains("\"shots\""))
        XCTAssertTrue(out.contains("// inner note about why this is disabled"))
        XCTAssertEqual(decodeSet(Data(out.utf8)), edited)
    }

    func testAddingARuleAndReorderingKeepsCommentsWithTheirRules() {
        let edited = makeSet { set in
            set.targets[0].rules.reverse()
            set.targets[0].rules.append(Rule(id: "new", match: .all([.kind(.file)]), actions: [.trash]))
        }
        let out = String(decoding: RulesText.encode(edited, preserving: commented), as: UTF8.self)
        let shots = out.range(of: "// Screenshots pile up fast.")
        let keepNote = out.range(of: "// inner note about why this is disabled")
        XCTAssertNotNil(shots)
        XCTAssertNotNil(keepNote)
        XCTAssertTrue(keepNote!.lowerBound < shots!.lowerBound, "comments moved with their reordered rules")
        XCTAssertEqual(decodeSet(Data(out.utf8)), edited)
    }

    func testChangingATargetPathRegeneratesItButKeepsOtherTargets() {
        let twoTargets = """
            {
              version: 1,
              targets: [
                // downloads target
                { path: "~/Downloads", rules: [ { id: "a", match: { kind: "file" }, actions: [ { trash: {} } ] } ] },
                { path: "~/Desktop", rules: [] },
              ],
            }
            """
        let edited: RuleSet = {
            var set = decodeSet(Data(twoTargets.utf8))
            set.targets[1].path = "~/Documents"
            return set
        }()
        let out = String(decoding: RulesText.encode(edited, preserving: twoTargets), as: UTF8.self)
        XCTAssertTrue(out.contains("// downloads target"))
        XCTAssertTrue(out.contains("~/Documents"))
        XCTAssertEqual(decodeSet(Data(out.utf8)), edited)
    }

    func testMalformedOriginalFallsBackToStrictEncoding() {
        let set = makeSet()
        XCTAssertEqual(RulesText.encode(set, preserving: "{ not valid"), RuleParser.encode(set))
        XCTAssertEqual(RulesText.encode(set, preserving: "[1]"), RuleParser.encode(set), "non-object root")
    }

    func testOriginalWithoutTargetsGainsThem() {
        let out = String(decoding: RulesText.encode(makeSet(), preserving: "// hi\n{ version: 1 }"), as: UTF8.self)
        XCTAssertTrue(out.contains("// hi"))
        // The original's (absent) defaults stay absent — merge only rewrites targets.
        XCTAssertEqual(decodeSet(Data(out.utf8)).targets, makeSet().targets)
    }

    func testTargetThatIsNotAnObjectIsRegenerated() {
        let odd = "{ version: 1, targets: [ 42 ] }"
        let set = RuleSet(version: 1, targets: [Target(path: "~/Downloads", rules: [])])
        let out = String(decoding: RulesText.encode(set, preserving: odd), as: UTF8.self)
        XCTAssertEqual(decodeSet(Data(out.utf8)), set)
    }

    func testOriginalTargetWithoutAPathMemberIsRegenerated() {
        let odd = "{ version: 1, targets: [ { rules: [] } ] }"
        let set = RuleSet(version: 1, targets: [Target(path: "~/Downloads", rules: [])])
        let out = String(decoding: RulesText.encode(set, preserving: odd), as: UTF8.self)
        XCTAssertEqual(decodeSet(Data(out.utf8)).targets, set.targets)
    }

    func testOriginalTargetWithoutARulesMemberGainsOne() {
        let odd = #"{ version: 1, targets: [ /* keep me */ { path: "~/Downloads" } ] }"#
        let set = RuleSet(
            version: 1,
            targets: [Target(path: "~/Downloads", rules: [Rule(id: "a", match: .all([.kind(.file)]), actions: [.trash])])])
        let out = String(decoding: RulesText.encode(set, preserving: odd), as: UTF8.self)
        XCTAssertTrue(out.contains("/* keep me */"))
        XCTAssertEqual(decodeSet(Data(out.utf8)).targets, set.targets)
    }

    func testOriginalRuleThatIsNotAnObjectIsRegenerated() {
        let odd = #"{ version: 1, targets: [ { path: "~/Downloads", rules: [ 7 ] } ] }"#
        let set = RuleSet(
            version: 1,
            targets: [Target(path: "~/Downloads", rules: [Rule(id: "a", match: .all([.kind(.file)]), actions: [.trash])])])
        let out = String(decoding: RulesText.encode(set, preserving: odd), as: UTF8.self)
        XCTAssertEqual(decodeSet(Data(out.utf8)).targets, set.targets)
    }

    func testQuotedKeysInTheOriginalAreStillRecognized() {
        let quoted = """
            { "version": 1, "targets": [ { "path": "~/Downloads", "rules": [
              // note stays
              { "id": "a", "match": { "kind": "file" }, "actions": [ { "trash": {} } ] },
            ] } ] }
            """
        let set = decodeSet(Data(quoted.utf8))
        let out = String(decoding: RulesText.encode(set, preserving: quoted), as: UTF8.self)
        XCTAssertTrue(out.contains("// note stays"))
        XCTAssertEqual(decodeSet(Data(out.utf8)), set)
    }
}
