// ActivityListView.swift
// The full activity window. Exempt from coverage and audit (presentation only).

import SwiftUI

/// Every retained activity entry, newest first.
struct ActivityListView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Table(rows) {
            TableColumn("Time") { row in
                Text(row.entry.ts.formatted(date: .abbreviated, time: .standard))
                    .monospacedDigit()
            }
            .width(150)
            TableColumn("Rule") { row in
                Text(row.entry.ruleID)
            }
            .width(120)
            TableColumn("Action") { row in
                Text(row.entry.action)
            }
            .width(60)
            TableColumn("File") { row in
                Text((row.entry.src as NSString).lastPathComponent)
            }
            TableColumn("Result") { row in
                Text(row.entry.dst.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? row.entry.outcome)
                    .foregroundStyle(row.entry.outcome == "error" ? .red : .secondary)
                    .help(row.entry.detail ?? "")
            }
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private var rows: [Row] {
        model.fullActivity.enumerated().map { Row(id: $0.offset, entry: $0.element) }
    }

    private struct Row: Identifiable {
        let id: Int
        let entry: ActivityEntry
    }
}
