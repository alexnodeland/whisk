// RulesFileStore.swift
// Reads and writes ~/.config/whisk/rules.json behind the RulesFileAccessing
// port. Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// The real rules file.
final class RulesFileStore: RulesFileAccessing {

    let path: String

    init(path: String) {
        self.path = path
    }

    /// The default location, honoring a WHISK_RULES_FILE override (used by the
    /// integration tests and the --sweep-once mode).
    static func defaultPath(home: String) -> String {
        ProcessInfo.processInfo.environment["WHISK_RULES_FILE"] ?? home + "/.config/whisk/rules.json"
    }

    func read() -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    func write(_ data: Data) {
        let parent = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }
}
