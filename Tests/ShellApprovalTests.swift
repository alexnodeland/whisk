// ShellApprovalTests.swift
// Maps to: docs/acceptance/shell-safety.feature.

import XCTest

@testable import WhiskCore

final class ShellApprovalTests: XCTestCase {

    private let spec = RunSpec(command: "/opt/bin/unpack", args: ["-v"])

    func testKeyIsVerbatimCommandPlusArgs() {
        XCTAssertEqual(ApprovedCommands.key(for: spec), "/opt/bin/unpack\u{1F}-v")
        XCTAssertEqual(ApprovedCommands.display(key: ApprovedCommands.key(for: spec)), "/opt/bin/unpack -v")
    }

    func testGate() {
        let empty = ApprovedCommands()
        XCTAssertEqual(empty.gate(spec), .pending(key: ApprovedCommands.key(for: spec)))
        let approved = empty.approving(ApprovedCommands.key(for: spec))
        XCTAssertEqual(approved.gate(spec), .approved)
        let changed = RunSpec(command: "/opt/bin/unpack", args: ["-x"])
        XCTAssertEqual(approved.gate(changed), .pending(key: ApprovedCommands.key(for: changed)))
    }

    func testPersistenceRoundTrip() {
        let approved = ApprovedCommands().approving("a").approving("b")
        let decoded = ApprovedCommands.decode(from: approved.encoded())
        XCTAssertEqual(decoded, approved)
    }

    func testDecodeToleratesNilAndGarbage() {
        XCTAssertEqual(ApprovedCommands.decode(from: nil), ApprovedCommands())
        XCTAssertEqual(ApprovedCommands.decode(from: "not json"), ApprovedCommands())
    }
}
