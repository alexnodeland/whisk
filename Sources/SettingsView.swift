// SettingsView.swift
// The Settings window (⌘,): General, Appearance, Setup, About. Everything that
// is configuration rather than a moment-to-moment control lives here, so the
// menu bar popover can stay an at-a-glance surface.
// Exempt from coverage and audit (presentation only).

import SwiftUI

/// The tabbed Settings window.
struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SetupSettingsTab()
                .tabItem { Label("Setup", systemImage: "folder.badge.gearshape") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
        .environmentObject(model)
    }
}

/// Launch, notifications, and the update policy.
private struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch Whisk at login", isOn: $model.launchAtLogin)
                Toggle("Show notifications", isOn: $model.notificationsEnabled)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $model.autoCheckUpdates)
                Toggle("Install updates automatically", isOn: $model.autoInstallUpdates)
                    .disabled(!model.autoCheckUpdates)
                LabeledContent {
                    Button(model.availableUpdate == nil ? "Check Now" : "Install \(model.availableUpdate!.version)") {
                        if model.availableUpdate == nil {
                            model.checkForUpdates()
                        } else {
                            model.installUpdate()
                        }
                    }
                } label: {
                    if let status = model.updateStatus {
                        Text(status)
                    } else if let update = model.availableUpdate {
                        Text("Whisk \(update.version) is available")
                    } else {
                        Text("You're on \(model.appVersion)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The menu bar icon and how much the popover shows.
private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Form {
            Section("Menu bar icon") {
                Picker("Icon", selection: $model.sparklesMenuIcon) {
                    Label {
                        Text("Whisk")
                    } icon: {
                        Image(nsImage: MenuIcon.regular)
                    }
                    .tag(false)
                    Label {
                        Text("Sparkles")
                    } icon: {
                        Image(nsImage: MenuIcon.sparkles)
                    }
                    .tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text("The icon dims and shows pause bars while Whisk is paused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Menu") {
                Stepper(value: $model.recentActivityCount, in: 1...50) {
                    LabeledContent("Recent actions shown", value: "\(model.recentActivityCount)")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The rules file, targets, and where everything lives on disk.
private struct SetupSettingsTab: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Rules") {
                LabeledContent("Rules file") {
                    Text((model.rulesPath as NSString).abbreviatingWithTildeInPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Edit Rules…") { openWindow(id: "editor") }
                    Button("Open in Editor App") { model.openRulesFile() }
                }
                Text("The file is the source of truth — JSON5 with comments, hot-reloaded on every save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Watched folders") {
                if model.statuses.isEmpty {
                    Text("No targets configured yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.statuses, id: \.path) { status in
                    LabeledContent {
                        if status.denied {
                            Label("No access", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        } else {
                            Label("Watching", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    } label: {
                        Text((status.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption.monospaced())
                    }
                }
                Text(
                    "macOS asks for access to each folder the first time a rule targets it. "
                        + "Grant it in System Settings › Privacy if a folder shows \"No access\"."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Activity") {
                Button("Open Activity Log Window") { openWindow(id: "activity") }
            }
            Section("Scripting") {
                LabeledContent("Sweep now", value: "whisk://sweep")
                LabeledContent("Pause an hour", value: "whisk://pause?minutes=60")
                LabeledContent("Resume", value: "whisk://resume")
                LabeledContent("Toggle preview", value: "whisk://dry-run")
            }
            .font(.caption.monospaced())
        }
        .formStyle(.grouped)
    }
}

/// Version, links, license.
private struct AboutSettingsTab: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Whisk")
                .font(.title2.weight(.semibold))
            Text("Version \(model.appVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Keep your folders clean, automatically.")
                .font(.callout)
            HStack(spacing: 16) {
                Link("Website", destination: URL(string: "https://alexnodeland.github.io/whisk/")!)
                Link("GitHub", destination: URL(string: "https://github.com/alexnodeland/whisk")!)
                Link(
                    "Rules Reference", destination: URL(string: "https://github.com/alexnodeland/whisk/blob/main/docs/rfcs/0001-whisk.md")!)
            }
            .font(.callout)
            Text("MIT © Alex Nodeland")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
