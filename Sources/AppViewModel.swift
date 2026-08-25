// AppViewModel.swift
// Mirrors SweepCoordinator state into @Published properties and forwards user
// intent. Holds NO decisions — if you are writing an `if` here, the decision
// belongs in the coordinator or a policy type. Exempt from coverage and audit.

import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// The SwiftUI bridge to the coordinator.
@MainActor
final class AppViewModel: ObservableObject {

    @Published private(set) var statuses: [TargetStatus] = []
    @Published private(set) var recent: [ActivityEntry] = []
    @Published private(set) var pending: [PendingApproval] = []
    @Published private(set) var autoPaused: [String] = []
    @Published private(set) var rulesError: String?
    @Published private(set) var paused = false
    @Published private(set) var dryRun = false
    @Published var ruleSet: RuleSet?
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var updateStatus: String?

    private(set) var rulesPath = ""

    private var coordinator: SweepCoordinator?
    private var updates: UpdateCoordinator?
    private var rulesFile: RulesFileAccessing?
    private var settings: AppSettings?

    /// The menu bar icon; pause swaps it so the state reads at a glance.
    var menuIcon: NSImage {
        paused ? MenuIcon.paused : MenuIcon.regular
    }

    func bind(coordinator: SweepCoordinator, rulesFile: RulesFileAccessing, settings: AppSettings) {
        self.coordinator = coordinator
        self.rulesFile = rulesFile
        self.settings = settings
        rulesPath = rulesFile.path
        coordinator.onStateChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Re-read everything the menu shows.
    func refresh() {
        guard let coordinator else { return }
        statuses = coordinator.targetStatuses.values.sorted { $0.path < $1.path }
        recent = coordinator.recentActivity.suffix(10).reversed()
        pending = coordinator.pendingApprovals
        autoPaused = coordinator.autoPausedRules.sorted()
        rulesError = coordinator.lastError?.message
        paused = coordinator.isPaused
        dryRun = coordinator.isDryRun
        ruleSet = coordinator.ruleSet
    }

    /// Mirror the update coordinator the same way.
    func bindUpdates(_ updates: UpdateCoordinator) {
        self.updates = updates
        updates.onStateChange = { [weak self] in
            Task { @MainActor in self?.refreshUpdates() }
        }
        refreshUpdates()
    }

    private func refreshUpdates() {
        availableUpdate = updates?.availableUpdate
        updateStatus = updates?.updateStatus
    }

    /// The full activity list for the activity window.
    var fullActivity: [ActivityEntry] {
        (coordinator?.recentActivity ?? []).reversed()
    }

    // MARK: Intent

    func runNow() { coordinator?.runNow() }

    func pauseIndefinitely() { coordinator?.pause(until: nil) }

    func pauseOneHour() { coordinator?.pause(until: Date().addingTimeInterval(3600)) }

    func resume() { coordinator?.resume() }

    func setDryRun(_ enabled: Bool) { coordinator?.setDryRun(enabled) }

    func approve(key: String) { coordinator?.approve(key: key) }

    func reject(key: String) { coordinator?.reject(key: key) }

    func unpauseRule(id: String) { coordinator?.unpauseRule(id: id) }

    func openRulesFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: rulesPath))
    }

    /// The editor writes strict JSON back to the rules file; the vnode watch
    /// hot-reloads it.
    func saveRules(_ set: RuleSet) {
        rulesFile?.write(RuleParser.encode(set))
    }

    /// Whether the raw rules file contains comments the strict-JSON save would drop.
    var rulesFileHasComments: Bool {
        let raw = String(decoding: rulesFile?.read() ?? Data(), as: UTF8.self)
        return raw.contains("//") || raw.contains("/*")
    }

    func checkForUpdates() { updates?.check() }

    func installUpdate() { updates?.installAvailable() }

    var autoCheckUpdates: Bool {
        get { settings?.autoCheckUpdates ?? true }
        set {
            settings?.autoCheckUpdates = newValue
            objectWillChange.send()
        }
    }

    var autoInstallUpdates: Bool {
        get { settings?.autoInstallUpdates ?? false }
        set {
            settings?.autoInstallUpdates = newValue
            objectWillChange.send()
        }
    }

    var notificationsEnabled: Bool {
        get { settings?.notificationsEnabled ?? true }
        set {
            settings?.notificationsEnabled = newValue
            objectWillChange.send()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? (newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
            objectWillChange.send()
        }
    }
}
