// AppSettings.swift
// Typed access to persisted app state behind the KeyValueStore port: pause
// state, dry-run mode, notification master switch, auto-paused rules, and the
// shell approval set. All decisions live here, not in the shim.
// In coverage. Imports only Foundation.

import Foundation

/// Persisted settings and small state, decided here and stored via the port.
struct AppSettings {

    /// Sentinel for an indefinite pause.
    private static let forever = "forever"

    private let store: KeyValueStore

    /// Wrap `store`.
    init(store: KeyValueStore) {
        self.store = store
    }

    // MARK: Pause

    /// Whether sweeps are paused at `now`.
    func isPaused(now: Date) -> Bool {
        guard let raw = store.string(forKey: "pausedUntil") else { return false }
        if raw == Self.forever { return true }
        guard let until = TimeInterval(raw) else { return false }
        return now < Date(timeIntervalSince1970: until)
    }

    /// Pause until `date`, or indefinitely when nil.
    func pause(until date: Date?) {
        store.set(date.map { String($0.timeIntervalSince1970) } ?? Self.forever, forKey: "pausedUntil")
    }

    /// Clear any pause.
    func resume() {
        store.set(nil, forKey: "pausedUntil")
    }

    // MARK: Toggles

    /// Dry-run (preview) mode; nothing is touched while on.
    var dryRun: Bool {
        get { store.string(forKey: "dryRun") == "1" }
        nonmutating set { store.set(newValue ? "1" : nil, forKey: "dryRun") }
    }

    /// Master switch for notifications (default on).
    var notificationsEnabled: Bool {
        get { store.string(forKey: "notificationsDisabled") != "1" }
        nonmutating set { store.set(newValue ? nil : "1", forKey: "notificationsDisabled") }
    }

    // MARK: Updates

    /// Background update checks (default on).
    var autoCheckUpdates: Bool {
        get { store.string(forKey: "updatesAutoCheckDisabled") != "1" }
        nonmutating set { store.set(newValue ? nil : "1", forKey: "updatesAutoCheckDisabled") }
    }

    /// Install found updates without asking (default off — ADR 0012).
    var autoInstallUpdates: Bool {
        get { store.string(forKey: "updatesAutoInstall") == "1" }
        nonmutating set { store.set(newValue ? "1" : nil, forKey: "updatesAutoInstall") }
    }

    /// When the last background update check ran.
    var lastUpdateCheck: Date? {
        get {
            guard let raw = store.string(forKey: "updatesLastCheck"), let epoch = TimeInterval(raw) else { return nil }
            return Date(timeIntervalSince1970: epoch)
        }
        nonmutating set {
            store.set(newValue.map { String($0.timeIntervalSince1970) }, forKey: "updatesLastCheck")
        }
    }

    /// The last version an "update available" notification was posted for, so a
    /// version notifies once rather than on every check.
    var lastNotifiedUpdateVersion: String? {
        get { store.string(forKey: "updatesLastNotified") }
        nonmutating set { store.set(newValue, forKey: "updatesLastNotified") }
    }

    // MARK: Auto-paused rules

    /// Rules paused by the runaway budget, persisted across launches.
    var autoPausedRules: Set<String> {
        get {
            guard let raw = store.string(forKey: "autoPausedRules"), !raw.isEmpty else { return [] }
            return Set(raw.components(separatedBy: "\u{1F}"))
        }
        nonmutating set {
            store.set(newValue.isEmpty ? nil : newValue.sorted().joined(separator: "\u{1F}"), forKey: "autoPausedRules")
        }
    }

    // MARK: Shell approvals

    /// The approved shell command set.
    var approvals: ApprovedCommands {
        get { ApprovedCommands.decode(from: store.string(forKey: "approvedCommands")) }
        nonmutating set { store.set(newValue.encoded(), forKey: "approvedCommands") }
    }
}
