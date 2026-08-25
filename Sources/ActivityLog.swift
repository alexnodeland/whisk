// ActivityLog.swift
// The "what happened" model: executed-action outcomes, their JSONL codec, and
// the retention policy for the activity log file.
// In coverage. Imports only Foundation.

import Foundation

/// A planned action paired with what actually happened to it.
struct ExecutedAction: Equatable {
    /// The action the planner produced.
    var action: PlannedAction
    /// The result of performing (or previewing) it.
    var outcome: Outcome

    /// How an action ended.
    enum Outcome: Equatable {
        /// Performed; `dst` is the resulting path where one exists.
        case success(dst: String?)
        /// Failed with a message.
        case failure(String)
        /// Skipped by the conflict policy.
        case skipped
        /// Dry-run mode: nothing was touched.
        case preview
    }
}

/// One line of the activity log.
struct ActivityEntry: Codable, Equatable {
    /// When it happened.
    var ts: Date
    /// The rule that acted.
    var ruleID: String
    /// The target directory swept.
    var target: String
    /// The verb: move/copy/rename/trash/run.
    var action: String
    /// The source path.
    var src: String
    /// The resulting path, when one exists.
    var dst: String?
    /// ok / error / skipped / preview.
    var outcome: String
    /// True when produced by dry-run mode.
    var dryRun: Bool
    /// Failure message or captured command output.
    var detail: String?
}

/// Codec and retention for the JSONL activity log.
enum ActivityLog {

    /// Keep at most this many entries.
    static let maxEntries = 1000

    /// Keep entries at most this old, seconds (30 days).
    static let maxAge: TimeInterval = 30 * 86400

    /// Map an executed action into a log entry.
    static func entry(for executed: ExecutedAction, target: String, now: Date) -> ActivityEntry {
        var entry = ActivityEntry(
            ts: now, ruleID: executed.action.ruleID, target: target,
            action: verb(for: executed.action.op), src: source(of: executed.action.op),
            dst: nil, outcome: "ok", dryRun: false, detail: nil)
        switch executed.outcome {
        case .success(let dst):
            entry.dst = dst
        case .failure(let message):
            entry.outcome = "error"
            entry.detail = message
        case .skipped:
            entry.outcome = "skipped"
        case .preview:
            entry.outcome = "preview"
            entry.dryRun = true
        }
        return entry
    }

    /// One JSON line for `entry` (stable key order). ActivityEntry always
    /// encodes, so this cannot fail.
    static func encodeLine(_ entry: ActivityEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(entry)
        return String(decoding: data, as: UTF8.self)
    }

    /// Decode one log line, or nil for garbage (tolerated, never fatal).
    static func decodeLine(_ line: String) -> ActivityEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ActivityEntry.self, from: Data(line.utf8))
    }

    /// Apply retention: newest `maxEntries`, none older than `maxAge`.
    static func prune(_ entries: [ActivityEntry], now: Date) -> [ActivityEntry] {
        let horizon = now.addingTimeInterval(-maxAge)
        let fresh = entries.filter { $0.ts > horizon }
        return Array(fresh.suffix(maxEntries))
    }

    /// The log verb for an operation.
    static func verb(for op: PlannedAction.Operation) -> String {
        switch op {
        case .move: return "move"
        case .copy: return "copy"
        case .rename: return "rename"
        case .trash: return "trash"
        case .run: return "run"
        }
    }

    /// The source path of an operation.
    static func source(of op: PlannedAction.Operation) -> String {
        switch op {
        case .move(let src, _, _), .copy(let src, _, _), .rename(let src, _), .trash(let src):
            return src
        case .run(_, let file):
            return file
        }
    }
}
