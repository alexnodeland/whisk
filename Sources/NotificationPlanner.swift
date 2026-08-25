// NotificationPlanner.swift
// Decides which user notifications a sweep produces: per-rule batched summaries
// for successes, one collected error notice, and standalone notices for
// auto-paused rules, pending approvals, and rules-file errors.
// In coverage. Imports only Foundation.

import Foundation

/// A notification to post.
struct Notice: Equatable {
    /// The notification title.
    var title: String
    /// The notification body.
    var body: String
}

/// Pure notification planning.
enum NotificationPlanner {

    /// How many detail lines a batched notice shows before eliding.
    static let maxDetailLines = 4

    /// The notices for one sweep's executed actions. Successes (and previews)
    /// batch per rule, honoring each rule's notify flag; failures always
    /// collect into one notice regardless of the flag.
    static func notices(for executed: [ExecutedAction], dryRun: Bool) -> [Notice] {
        var out: [Notice] = []
        var order: [String] = []
        var groups: [String: [ExecutedAction]] = [:]
        var failures: [String] = []

        for item in executed {
            switch item.outcome {
            case .success, .preview:
                guard item.action.notify else { continue }
                if groups[item.action.ruleID] == nil { order.append(item.action.ruleID) }
                groups[item.action.ruleID, default: []].append(item)
            case .failure(let message):
                failures.append("\(describe(item.action.op)): \(message)")
            case .skipped:
                continue
            }
        }

        for ruleID in order {
            let items = groups[ruleID]!
            let prefix = dryRun ? "Whisk preview — " : "Whisk — "
            var lines = items.prefix(maxDetailLines).map { describe($0.action.op) }
            if items.count > maxDetailLines {
                lines.append("…and \(items.count - maxDetailLines) more")
            }
            out.append(Notice(title: prefix + items[0].action.ruleName, body: lines.joined(separator: "\n")))
        }

        if !failures.isEmpty {
            let shown = failures.prefix(maxDetailLines).joined(separator: "\n")
            out.append(Notice(title: "Whisk — \(failures.count) error\(failures.count == 1 ? "" : "s")", body: shown))
        }
        return out
    }

    /// The notice for a rule paused by its action budget.
    static func autoPausedNotice(ruleName: String) -> Notice {
        Notice(
            title: "Whisk paused a rule",
            body: "\"\(ruleName)\" hit its per-sweep action budget and looks like a runaway. It is paused until you re-enable it.")
    }

    /// The notice for a shell command held for approval.
    static func pendingApprovalNotice(displayCommand: String) -> Notice {
        Notice(
            title: "Whisk — command needs approval",
            body: "A rule wants to run: \(displayCommand)\nApprove it from the Whisk menu.")
    }

    /// The notice for a rules-file parse failure.
    static func rulesErrorNotice(message: String) -> Notice {
        Notice(title: "Whisk — rules file error", body: "\(message)\nThe previous rules stay active.")
    }

    /// One human line for an operation.
    static func describe(_ op: PlannedAction.Operation) -> String {
        switch op {
        case .move(let src, let destDir, _):
            return "\(name(src)) → \(name(destDir))/"
        case .copy(let src, let destDir, _):
            return "copied \(name(src)) → \(name(destDir))/"
        case .rename(let src, let proposedName):
            return "\(name(src)) → \(proposedName)"
        case .trash(let src):
            return "trashed \(name(src))"
        case .run(let spec, let file):
            return "ran \(name(spec.command)) on \(name(file))"
        }
    }

    /// The last path component of `path`.
    private static func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
