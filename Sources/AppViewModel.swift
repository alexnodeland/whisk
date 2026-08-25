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
    @Published private(set) var approvedCommands: [String] = []
    @Published private(set) var autoPaused: [String] = []
    @Published private(set) var rulesError: String?
    @Published private(set) var paused = false
    @Published private(set) var dryRun = false
    @Published var ruleSet: RuleSet?
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var updateStatus: String?

    private(set) var rulesPath = ""
    private(set) var activityLogPath = ""

    private var coordinator: SweepCoordinator?
    private var updates: UpdateCoordinator?
    private var rulesFile: RulesFileAccessing?
    private var settings: AppSettings?

    /// The menu bar icon; pause swaps it so the state reads at a glance.
    var menuIcon: NSImage {
        if sparklesMenuIcon {
            return paused ? MenuIcon.sparklesPaused : MenuIcon.sparkles
        }
        return paused ? MenuIcon.paused : MenuIcon.regular
    }

    func bind(
        coordinator: SweepCoordinator, rulesFile: RulesFileAccessing, settings: AppSettings, activityLogPath: String
    ) {
        self.coordinator = coordinator
        self.rulesFile = rulesFile
        self.settings = settings
        self.activityLogPath = activityLogPath
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
        recent = coordinator.recentActivity.suffix(settings?.recentActivityCount ?? 10).reversed()
        pending = coordinator.pendingApprovals
        approvedCommands = coordinator.approvedCommandKeys
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

    func revokeApproval(key: String) { coordinator?.revokeApproval(key: key) }

    func unpauseRule(id: String) { coordinator?.unpauseRule(id: id) }

    func openRulesFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: rulesPath))
    }

    /// Show the activity log file in Finder.
    func revealActivityLog() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: activityLogPath)])
    }

    /// Show an acted-on file where it is now — its destination when the
    /// action moved it (moves, renames, the Trash), else where it was.
    func reveal(entry: ActivityEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.dst ?? entry.src)])
    }

    /// The editor saves through the comment-preserving merge (ADR 0003): an
    /// untouched rule keeps its text verbatim, an edited rule keeps its
    /// leading comments. The vnode watch hot-reloads the result.
    func saveRules(_ set: RuleSet) {
        let original = String(decoding: rulesFile?.read() ?? Data(), as: UTF8.self)
        rulesFile?.write(RulesText.encode(set, preserving: original))
    }

    func checkForUpdates() { updates?.check(manual: true) }

    /// The cadence-guarded background check (safe to call often).
    func tickUpdates() { updates?.tick() }

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

    var sparklesMenuIcon: Bool {
        get { settings?.sparklesMenuIcon ?? false }
        set {
            settings?.sparklesMenuIcon = newValue
            objectWillChange.send()
        }
    }

    var recentActivityCount: Int {
        get { settings?.recentActivityCount ?? 10 }
        set {
            settings?.recentActivityCount = newValue
            refresh()
            objectWillChange.send()
        }
    }

    /// The running version, for the About tab.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
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
            settings?.launchAtLoginDesired = newValue
            try? (newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
            objectWillChange.send()
        }
    }
}
