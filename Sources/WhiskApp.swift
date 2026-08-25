// WhiskApp.swift
// The composition root. ALL launch wiring lives in
// applicationDidFinishLaunching — MenuBarExtra content is lazy, so nothing may
// depend on the popover having been opened. Exempt from coverage and audit.

import AppKit
import SwiftUI
import UserNotifications

/// A notifier that swallows everything (used by --sweep-once so a headless run
/// never triggers the notification-permission prompt).
private final class NullNotifier: Notifying {
    func post(title: String, body: String) {}
}

/// Builds the object graph and owns the coordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let model = AppViewModel()
    private var coordinator: SweepCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["WHISK_HOME"] ?? NSHomeDirectory()
        let dataDir = environment["WHISK_DATA_DIR"] ?? home + "/Library/Application Support/Whisk"
        let sweepOnce = CommandLine.arguments.contains("--sweep-once")

        let rulesFile = RulesFileStore(path: RulesFileStore.defaultPath(home: home))
        let settings = AppSettings(store: DefaultsStore())
        let watcher = FSEventsWatcher(rulesFilePath: rulesFile.path)
        let coordinator = SweepCoordinator(
            enumerator: MetadataReader(),
            files: FileOps(),
            runner: CommandRunner(),
            notifier: sweepOnce ? NullNotifier() : Notifier(),
            scheduler: SystemScheduler(),
            clock: SystemClock(),
            activity: ActivityStore(directory: dataDir),
            rulesFile: rulesFile,
            watcher: watcher,
            settings: settings,
            home: home,
            timeZone: TimeZone.current)
        self.coordinator = coordinator
        model.bind(coordinator: coordinator, rulesFile: rulesFile, settings: settings)

        if sweepOnce {
            coordinator.start()
            // Give already-launched shell actions a moment to land, then exit.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            exit(0)
        }

        coordinator.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak coordinator] _ in
            coordinator?.sweepAll()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let route = WhiskRoute.parse(url) {
                coordinator?.handle(route: route)
            }
        }
    }
}

/// The app: a menu bar item plus the activity and editor windows.
@main
struct WhiskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(delegate.model)
        } label: {
            Image(systemName: delegate.model.menuSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Whisk Activity", id: "activity") {
            ActivityListView()
                .environmentObject(delegate.model)
        }
        .windowResizability(.contentSize)

        Window("Whisk Rules", id: "editor") {
            RuleEditorView()
                .environmentObject(delegate.model)
        }
    }
}
