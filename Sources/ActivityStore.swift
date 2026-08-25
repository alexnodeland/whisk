// ActivityStore.swift
// The JSONL activity log file behind the ActivityPersisting port. Retention
// decisions live in ActivityLog.prune (covered); this only appends and rewrites.
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// The real activity log at <data dir>/activity.jsonl.
final class ActivityStore: ActivityPersisting {

    private let file: URL

    init(directory: String) {
        file = URL(fileURLWithPath: directory + "/activity.jsonl")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    func append(line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    func readLines() -> [String] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    func rewrite(lines: [String]) {
        let text = lines.map { $0 + "\n" }.joined()
        try? Data(text.utf8).write(to: file, options: [.atomic])
    }
}
