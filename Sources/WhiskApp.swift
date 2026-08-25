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

/// The menu bar icon: the brand whisk, drawn as a template image so it follows
/// the menu bar's light/dark appearance. Paused dims the whisk and adds pause
/// bars so the state still reads at a glance.
enum MenuIcon {
    static let regular = draw(paused: false)
    static let paused = draw(paused: true)

    private static func draw(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.withAlphaComponent(paused ? 0.35 : 1).setStroke()

            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 9, y: 2))
            handle.line(to: NSPoint(x: 9, y: 7.5))
            handle.lineWidth = 2.4
            handle.lineCapStyle = .round
            handle.stroke()

            let wires = NSBezierPath()
            for spread in [-4.6, -2.2, 0.0, 2.2, 4.6] {
                wires.move(to: NSPoint(x: 9, y: 7.5))
                wires.curve(
                    to: NSPoint(x: 9, y: 15.8),
                    controlPoint1: NSPoint(x: 9 + spread, y: 9.5),
                    controlPoint2: NSPoint(x: 9 + spread, y: 14.2))
            }
            wires.lineWidth = 1.3
            wires.lineCapStyle = .round
            wires.stroke()

            if paused {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 12.4, y: 10.5, width: 1.9, height: 6), xRadius: 0.9, yRadius: 0.9).fill()
                NSBezierPath(roundedRect: NSRect(x: 15.4, y: 10.5, width: 1.9, height: 6), xRadius: 0.9, yRadius: 0.9).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Builds the object graph and owns the coordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let model = AppViewModel()
    private var coordinator: SweepCoordinator?
    private var updates: UpdateCoordinator?

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

        let updates = UpdateCoordinator(
            fetcher: UpdateFetcher(),
            installer: UpdateInstaller(),
            notifier: Notifier(),
            scheduler: SystemScheduler(),
            clock: SystemClock(),
            settings: settings,
            currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        self.updates = updates
        model.bindUpdates(updates)
        updates.start()

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
            Image(nsImage: delegate.model.menuIcon)
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
