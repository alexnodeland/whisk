// MenuContentView.swift
// The menu bar popover: status, controls, pending approvals, recent activity.
// Exempt from coverage and audit (presentation only).

import SwiftUI

/// The popover shown from the menu bar item.
struct MenuContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            controls
            if let error = model.rulesError {
                Divider()
                errorBadge(error)
            }
            if !model.pending.isEmpty {
                Divider()
                approvals
            }
            if !model.autoPaused.isEmpty {
                Divider()
                pausedRules
            }
            Divider()
            recentActivity
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Whisk")
                    .font(.headline)
                Spacer()
                if model.paused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                if model.dryRun {
                    Text("Dry run")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                }
            }
            ForEach(model.statuses, id: \.path) { status in
                HStack(spacing: 6) {
                    Image(systemName: status.denied ? "exclamationmark.triangle.fill" : "folder")
                        .foregroundStyle(status.denied ? .orange : .secondary)
                        .font(.caption)
                    Text(abbreviate(status.path))
                        .font(.caption)
                    Spacer()
                    if status.denied {
                        Text("No access")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let last = status.lastSweep {
                        Text("\(status.lastActionCount) · \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Run Now") { model.runNow() }
                Spacer()
                if model.paused {
                    Button("Resume") { model.resume() }
                } else {
                    Menu("Pause") {
                        Button("For 1 hour") { model.pauseOneHour() }
                        Button("Until resumed") { model.pauseIndefinitely() }
                    }
                    .fixedSize()
                }
            }
            Toggle("Dry-run mode (preview only)", isOn: dryRunBinding)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    private var dryRunBinding: Binding<Bool> {
        Binding(get: { model.dryRun }, set: { model.setDryRun($0) })
    }

    private func errorBadge(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .lineLimit(3)
        } icon: {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private var approvals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pending approval")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.pending, id: \.key) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ApprovedCommands.display(key: item.key))
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    HStack {
                        Button("Approve") { model.approve(key: item.key) }
                            .controlSize(.small)
                        Button("Reject") { model.reject(key: item.key) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var pausedRules: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Auto-paused rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.autoPaused, id: \.self) { ruleID in
                HStack {
                    Text(ruleID)
                        .font(.caption)
                    Spacer()
                    Button("Re-enable") { model.unpauseRule(id: ruleID) }
                        .controlSize(.small)
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show all…") { openWindow(id: "activity") }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            if model.recent.isEmpty {
                Text("Nothing yet — Whisk sweeps when files change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.recent.enumerated()), id: \.offset) { _, entry in
                ActivityRow(entry: entry)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Open Rules File") { model.openRulesFile() }
                Button("Edit Rules…") { openWindow(id: "editor") }
            }
            .controlSize(.small)
            Toggle("Notifications", isOn: $model.notificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Launch at login", isOn: $model.launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
            HStack {
                Spacer()
                Button("Quit Whisk") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// One compact activity line.
struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 12)
            Text((entry.src as NSString).lastPathComponent)
                .font(.caption)
                .lineLimit(1)
            if let dst = entry.dst {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text((dst as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(entry.ts.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var symbol: String {
        switch entry.action {
        case "move": return "arrow.turn.down.right"
        case "copy": return "doc.on.doc"
        case "rename": return "pencil"
        case "trash": return "trash"
        case "run": return "terminal"
        default: return "questionmark"
        }
    }

    private var color: Color {
        switch entry.outcome {
        case "ok": return .green
        case "error": return .red
        case "preview": return .blue
        default: return .secondary
        }
    }
}
