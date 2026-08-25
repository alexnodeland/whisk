// MenuContentView.swift
// The menu bar popover: status, controls, pending approvals, recent activity.
// Exempt from coverage and audit (presentation only).

import SwiftUI

/// A deliberately high-contrast button: primary-colored label on a subtle
/// bezel drawn by us, not the system. The MenuBarExtra window never becomes
/// key, and system bezels render their "inactive" look there — washed-out
/// labels that are genuinely hard to read. Owning the bezel sidesteps that.
struct WhiskButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.22 : (prominent ? 0.12 : 0.07)),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(prominent ? 0.35 : 0.18))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The popover shown from the menu bar item.
struct MenuContentView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            controls
            if model.availableUpdate != nil || model.updateStatus != nil {
                Divider()
                updateRow
            }
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
                Image(nsImage: MenuIcon.regular)
                Text("Whisk")
                    .font(.headline)
                Spacer()
                if model.paused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.25), in: Capsule())
                }
                if model.dryRun {
                    Text("Dry run")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.indigo.opacity(0.3), in: Capsule())
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
                    .buttonStyle(WhiskButtonStyle())
                Spacer()
                if model.paused {
                    Button("Resume") { model.resume() }
                        .buttonStyle(WhiskButtonStyle())
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

    private var updateRow: some View {
        HStack(spacing: 6) {
            if let status = model.updateStatus {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.caption)
            } else if let update = model.availableUpdate {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                Text("Whisk \(update.version) is available")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Install") { model.installUpdate() }
                    .buttonStyle(WhiskButtonStyle(prominent: true))
            }
        }
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
                            .buttonStyle(WhiskButtonStyle(prominent: true))
                        Button("Reject") { model.reject(key: item.key) }
                            .buttonStyle(WhiskButtonStyle())
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
                        .buttonStyle(WhiskButtonStyle())
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
                Button("Show All…") { openWindow(id: "activity") }
                    .buttonStyle(WhiskButtonStyle())
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
        HStack {
            Button("Edit Rules…") { openWindow(id: "editor") }
                .buttonStyle(WhiskButtonStyle())
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(WhiskButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(WhiskButtonStyle())
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
        case "preview": return .indigo
        default: return .secondary
        }
    }
}
