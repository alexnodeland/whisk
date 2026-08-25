// CoverageManifestTests.swift
// The pin that makes the 100% gate mean something (ADR 0005).
//
// The gate only sees files compiled into libWhiskCore.dylib, and that set comes
// from `logic-manifest.txt`. Two ways it could quietly lie:
//
//   1. A file is dropped from the manifest — the denominator shrinks and the gate
//      still reports a green 100%. (coverage-gate.py's required-files pin catches
//      this too; this test catches it before the report is even produced.)
//   2. A NEW logic file is added and nobody touches the manifest — it is never
//      compiled into the dylib, never measured, and nothing complains.
//
// Case 2 is the one no other check catches, so this test enumerates every file in
// `Sources/` and asserts it is EXACTLY partitioned into "in the manifest" and
// "declared excluded, with a reason". Adding a file to Sources/ without deciding
// which side of the coverage boundary it sits on now fails the suite.

import Foundation
import XCTest

@testable import WhiskCore

final class CoverageManifestTests: XCTestCase {

    /// The files deliberately outside the coverage boundary, each with the reason
    /// it cannot be a pure logic file. Keep the reasons honest — a shim that grows
    /// a real branch belongs on the other side of this line (see ADR 0005).
    private static let declaredExclusions: [String: String] = [
        "WhiskApp.swift": "@main composition root; SwiftUI App + AppKit delegate",
        "AppViewModel.swift": "@MainActor SwiftUI bridge",
        "MenuContentView.swift": "SwiftUI view body",
        "RuleEditorView.swift": "SwiftUI view body",
        "ActivityListView.swift": "SwiftUI view body",
        "FSEventsWatcher.swift": "FSEventStream + DispatchSource vnode watch",
        "MetadataReader.swift": "FileManager attribute reads",
        "FileOps.swift": "FileManager move/copy/trash",
        "CommandRunner.swift": "spawns Process",
        "Notifier.swift": "UNUserNotificationCenter",
        "RulesFileStore.swift": "FileManager reads/writes of the rules file",
        "ActivityStore.swift": "FileHandle append to the JSONL log",
        "SystemScheduler.swift": "DispatchSourceTimer + wake notification",
        "SystemServices.swift": "Date(), UserDefaults, FileManager home",
    ]

    /// The in-coverage manifest, as this test believes it to be. `test.sh` passes
    /// the real `logic-manifest.txt` contents through the environment; the two must
    /// agree, so editing the manifest without editing this list fails here.
    private static let expectedManifest: Set<String> = [
        "Sources/Ports.swift",
        "Sources/Units.swift",
        "Sources/GlobMatcher.swift",
        "Sources/FileFacts.swift",
        "Sources/RuleModel.swift",
        "Sources/RuleParser.swift",
        "Sources/ConditionEvaluator.swift",
        "Sources/PatternRenderer.swift",
        "Sources/LoopGuard.swift",
        "Sources/ShellApproval.swift",
        "Sources/SweepPlanner.swift",
        "Sources/SweepScheduler.swift",
        "Sources/NotificationPlanner.swift",
        "Sources/ActivityLog.swift",
        "Sources/AppSettings.swift",
        "Sources/WhiskRoute.swift",
        "Sources/SweepCoordinator.swift",
    ]

    private func environmentValue(_ key: String) throws -> String {
        let value = ProcessInfo.processInfo.environment[key] ?? ""
        try XCTSkipIf(value.isEmpty, "\(key) is unset — run the suite via ./test.sh, which exports it.")
        return value
    }

    /// The manifest `test.sh` actually compiled matches the list pinned here.
    func testManifestMatchesWhatTestScriptCompiled() throws {
        let raw = try environmentValue("WHISK_LOGIC_MANIFEST")
        let compiled = Set(raw.split(separator: ":").map(String.init))

        XCTAssertEqual(
            compiled,
            Self.expectedManifest,
            """
            logic-manifest.txt and CoverageManifestTests.expectedManifest disagree.
            Only in the manifest: \(compiled.subtracting(Self.expectedManifest).sorted())
            Only in the test:     \(Self.expectedManifest.subtracting(compiled).sorted())
            """
        )
    }

    /// Every file in `Sources/` is either in coverage or explicitly excluded — no
    /// file may sit in neither set and go silently unmeasured.
    func testEverySourceFileIsClassified() throws {
        let projectDir = try environmentValue("WHISK_PROJECT_DIR")
        let sources = URL(fileURLWithPath: projectDir).appendingPathComponent("Sources")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }

        XCTAssertFalse(names.isEmpty, "no Swift files found in \(sources.path)")

        let inCoverage = Set(Self.expectedManifest.map { ($0 as NSString).lastPathComponent })
        let excluded = Set(Self.declaredExclusions.keys)

        let unclassified = Set(names).subtracting(inCoverage).subtracting(excluded)
        XCTAssertTrue(
            unclassified.isEmpty,
            """
            \(unclassified.sorted()) is in Sources/ but is neither in logic-manifest.txt nor
            in declaredExclusions. Decide which side of the coverage boundary it sits on
            (see the rule at the top of logic-manifest.txt) and record it.
            """
        )
    }

    /// The two classifications are mutually exclusive.
    func testClassificationsDoNotOverlap() {
        let inCoverage = Set(Self.expectedManifest.map { ($0 as NSString).lastPathComponent })
        let overlap = inCoverage.intersection(Self.declaredExclusions.keys)
        XCTAssertTrue(overlap.isEmpty, "\(overlap.sorted()) is both in coverage and declared excluded")
    }

    /// Every exclusion carries a stated reason — the exclusion list is an argument,
    /// not a list of names.
    func testEveryExclusionHasAReason() {
        for (file, reason) in Self.declaredExclusions {
            XCTAssertFalse(reason.isEmpty, "\(file) is excluded without a reason")
        }
    }
}
