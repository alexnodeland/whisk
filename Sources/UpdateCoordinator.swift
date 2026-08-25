// UpdateCoordinator.swift
// Owns update intent: when to check, what to do with a found release, and how
// a download becomes an install — all through ports, so every branch is
// exercised with fakes. The network and the bundle swap live in shims.
// In coverage. Imports only Foundation.

import Foundation

/// Orchestrates update checks and installs (ADR 0012).
final class UpdateCoordinator {

    /// Seconds after launch before the first background check — late enough to
    /// stay clear of launch work, early enough to matter.
    static let initialCheckDelay: TimeInterval = 15

    /// How often the timer re-evaluates whether a check is due; the daily
    /// cadence itself is UpdatePlanner.checkInterval.
    static let tickInterval: TimeInterval = 3600

    private let fetcher: UpdateFetching
    private let installer: UpdateInstalling
    private let notifier: Notifying
    private let scheduler: Scheduler
    private let clock: Clock
    private let settings: AppSettings
    private let currentVersion: String

    /// A newer published build, when one is known.
    private(set) var availableUpdate: ReleaseInfo?
    /// Human-readable progress ("Checking…", "Downloading…"), nil when idle.
    private(set) var updateStatus: String?
    /// Fires after any state change, for the view model to mirror.
    var onStateChange: (() -> Void)?

    private var timers: [Cancellable] = []

    /// Wire the ports; nothing runs until `start()`.
    init(
        fetcher: UpdateFetching,
        installer: UpdateInstalling,
        notifier: Notifying,
        scheduler: Scheduler,
        clock: Clock,
        settings: AppSettings,
        currentVersion: String
    ) {
        self.fetcher = fetcher
        self.installer = installer
        self.notifier = notifier
        self.scheduler = scheduler
        self.clock = clock
        self.settings = settings
        self.currentVersion = currentVersion
    }

    /// Arm the initial and recurring background checks.
    func start() {
        timers.append(scheduler.schedule(after: Self.initialCheckDelay) { self.tick() })
        timers.append(scheduler.every(seconds: Self.tickInterval) { self.tick() })
    }

    /// Run a background check when one is due.
    func tick() {
        guard
            UpdatePlanner.shouldCheck(
                now: clock.now(), lastCheck: settings.lastUpdateCheck, autoCheck: settings.autoCheckUpdates)
        else { return }
        check()
    }

    /// Check the latest release now, regardless of cadence (menu "Check Now").
    func check() {
        updateStatus = "Checking…"
        onStateChange?()
        fetcher.fetch(url: UpdatePlanner.latestReleaseURL) { data in
            self.settings.lastUpdateCheck = self.clock.now()
            self.updateStatus = nil
            guard let data, let release = UpdatePlanner.parseLatest(data) else {
                // Offline or a malformed payload: keep whatever we knew.
                self.onStateChange?()
                return
            }
            self.handle(release: release)
        }
    }

    /// Fold a fetched release into state and act on the configured policy.
    private func handle(release: ReleaseInfo) {
        guard UpdatePlanner.isNewer(release.version, than: currentVersion) else {
            availableUpdate = nil
            onStateChange?()
            return
        }
        availableUpdate = release
        onStateChange?()
        if settings.autoInstallUpdates {
            installAvailable()
            return
        }
        if settings.lastNotifiedUpdateVersion != release.version {
            settings.lastNotifiedUpdateVersion = release.version
            post(title: "Whisk \(release.version) is available", body: "Open the Whisk menu to install it.")
        }
    }

    /// Download and install the known update; on success the app relaunches.
    func installAvailable() {
        guard let release = availableUpdate else { return }
        updateStatus = "Downloading \(release.version)…"
        onStateChange?()
        fetcher.download(url: release.zipURL) { zipPath in
            guard let zipPath else {
                self.updateStatus = nil
                self.onStateChange?()
                self.post(title: "Whisk update failed", body: "Could not download \(release.version). Will retry later.")
                return
            }
            self.updateStatus = "Installing \(release.version)…"
            self.onStateChange?()
            self.installer.install(zipPath: zipPath) { error in
                // Reached only on failure — success exits the process.
                self.updateStatus = nil
                self.onStateChange?()
                self.post(title: "Whisk update failed", body: error ?? "Unknown installer error.")
            }
        }
    }

    /// Notifications honor the global switch; the menu still shows the update.
    private func post(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        notifier.post(title: title, body: body)
    }
}
