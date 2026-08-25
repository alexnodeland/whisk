// SweepCoordinator.swift
// Owns intent: when to sweep, how plans become effects through the ports, and
// what state the menu shows. Everything here is deterministic given the ports'
// answers; tests drive it entirely with fakes.
// In coverage. Imports only Foundation.

import Foundation

/// Per-target status for the menu.
struct TargetStatus: Equatable {
    /// The expanded target directory.
    var path: String
    /// When it last swept, if ever.
    var lastSweep: Date?
    /// Actions performed (or previewed) in the last sweep.
    var lastActionCount: Int
    /// True when the directory could not be read (TCC denial or missing).
    var denied: Bool
}

/// The orchestrator between the pure planner and the I/O shims.
final class SweepCoordinator {

    /// The seed rules file written on first launch: a safe, dry-run-free
    /// starting point that only tidies obvious Downloads clutter.
    static let seedRules = """
        // Whisk rules — https://github.com/alexnodeland/whisk
        //
        // This file is the source of truth. Whisk reloads it whenever it changes.
        // JSON5: comments and trailing commas are fine (the in-app editor writes
        // strict JSON and drops comments — it warns first).
        {
          version: 1,
          targets: [
            {
              path: "~/Downloads",
              rules: [
                {
                  id: "trash-old-installers",
                  name: "Trash installers after a week",
                  enabled: false,   // flip to true when ready
                  match: { all: [
                    { kind: "file" },
                    { extension: ["dmg", "pkg"] },
                    { age: { basis: "added", olderThan: "7d" } },
                  ]},
                  actions: [ { trash: {} } ],
                },
              ],
            },
          ],
        }
        """

    private let enumerator: DirectoryEnumerating
    private let files: FileActing
    private let runner: CommandRunning
    private let notifier: Notifying
    private let scheduler: Scheduler
    private let clock: Clock
    private let activity: ActivityPersisting
    private let rulesFile: RulesFileAccessing
    private let watcher: TargetWatching
    private let settings: AppSettings
    private let home: String
    private let timeZone: TimeZone

    /// The last successfully parsed rules.
    private(set) var ruleSet: RuleSet?
    /// The current rules-file diagnostic, if any.
    private(set) var lastError: RuleParseError?
    /// Loop-protection state.
    private(set) var guardState = LoopGuardState()
    /// Shell commands waiting for the user.
    private(set) var pendingApprovals: [PendingApproval] = []
    /// Newest-last cache of recent activity for the menu.
    private(set) var recentActivity: [ActivityEntry] = []
    /// Per-target sweep status, keyed by expanded path.
    private(set) var targetStatuses: [String: TargetStatus] = [:]

    /// Fired after any observable state change (the view model re-reads).
    var onStateChange: (() -> Void)?

    private var rejectedApprovalKeys = Set<String>()
    private var debounces: [String: Cancellable] = [:]
    private var ageTimer: Cancellable?
    private var rescanTimer: Cancellable?
    private var factsCache: [String: [FileFacts]] = [:]

    /// Wire the coordinator to its ports.
    init(
        enumerator: DirectoryEnumerating,
        files: FileActing,
        runner: CommandRunning,
        notifier: Notifying,
        scheduler: Scheduler,
        clock: Clock,
        activity: ActivityPersisting,
        rulesFile: RulesFileAccessing,
        watcher: TargetWatching,
        settings: AppSettings,
        home: String,
        timeZone: TimeZone
    ) {
        self.enumerator = enumerator
        self.files = files
        self.runner = runner
        self.notifier = notifier
        self.scheduler = scheduler
        self.clock = clock
        self.activity = activity
        self.rulesFile = rulesFile
        self.watcher = watcher
        self.settings = settings
        self.home = home
        self.timeZone = timeZone
    }

    // MARK: Lifecycle

    /// Launch wiring: seed the rules file if missing, load rules, restore the
    /// activity log, start the watcher and the rescan cadence, and sweep.
    func start() {
        if rulesFile.read() == nil {
            rulesFile.write(Data(Self.seedRules.utf8))
        }
        restoreActivity()
        watcher.onTargetEvent = { [weak self] target, path in self?.targetEvent(target: target, path: path) }
        watcher.onRulesFileEvent = { [weak self] in self?.reloadRules() }
        rescanTimer = scheduler.every(seconds: SweepScheduler.rescanInterval) { [weak self] in self?.sweepAll() }
        reloadRules()
    }

    /// Re-read and re-parse the rules file. On failure the previous rules stay
    /// active and the diagnostic is surfaced.
    func reloadRules() {
        guard let data = rulesFile.read() else {
            lastError = RuleParseError(message: "rules file missing at \(rulesFile.path)")
            changed()
            return
        }
        switch RuleParser.parse(data) {
        case .success(let set):
            ruleSet = set
            lastError = nil
            watcher.setTargets(expandedTargetPaths(of: set))
            sweepAll()
        case .failure(let problem):
            lastError = problem
            post(NotificationPlanner.rulesErrorNotice(message: problem.message))
            changed()
        }
    }

    // MARK: Events

    /// Which watched root contains `path` (the event-routing decision the
    /// FSEvents shim delegates here).
    static func targetRoot(forEventPath path: String, roots: [String]) -> String? {
        roots.first { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// A filesystem event inside a watched target.
    func targetEvent(target: String, path: String) {
        if guardState.shouldIgnoreEvent(at: path, now: clock.now()) { return }
        debounces[target]?.cancel()
        debounces[target] = scheduler.schedule(after: SweepScheduler.eventDebounce) { [weak self] in
            self?.debounces[target] = nil
            self?.sweep(expandedTarget: target)
        }
    }

    /// Handle a whisk:// command.
    func handle(route: WhiskRoute) {
        switch route {
        case .sweep:
            sweepAll()
        case .pause(let minutes):
            pause(until: minutes.map { clock.now().addingTimeInterval(TimeInterval($0) * 60) })
        case .resume:
            resume()
        case .dryRun(let enabled):
            setDryRun(enabled)
        }
    }

    // MARK: User intent

    /// Sweep every target now (also the "Run Now" menu action; ignores pause).
    func sweepAll() {
        for path in expandedTargetPaths(of: ruleSet) {
            sweep(expandedTarget: path, evenWhilePaused: false)
        }
    }

    /// "Run Now": sweep everything even while paused.
    func runNow() {
        for path in expandedTargetPaths(of: ruleSet) {
            sweep(expandedTarget: path, evenWhilePaused: true)
        }
    }

    /// Pause sweeps until `date` (nil = indefinitely).
    func pause(until date: Date?) {
        settings.pause(until: date)
        changed()
    }

    /// Resume sweeping, and catch up immediately.
    func resume() {
        settings.resume()
        sweepAll()
    }

    /// Toggle dry-run (preview) mode.
    func setDryRun(_ enabled: Bool) {
        settings.dryRun = enabled
        changed()
    }

    /// Whether sweeps are paused right now.
    var isPaused: Bool { settings.isPaused(now: clock.now()) }

    /// Whether dry-run mode is on.
    var isDryRun: Bool { settings.dryRun }

    /// Approve a held shell command and re-sweep so it runs.
    func approve(key: String) {
        settings.approvals = settings.approvals.approving(key)
        pendingApprovals.removeAll { $0.key == key }
        sweepAll()
    }

    /// Reject a held shell command for this session.
    func reject(key: String) {
        rejectedApprovalKeys.insert(key)
        pendingApprovals.removeAll { $0.key == key }
        changed()
    }

    /// The approved shell commands, for the Settings approvals list.
    var approvedCommandKeys: [String] {
        settings.approvals.approved.sorted()
    }

    /// Withdraw a previously granted approval; the command is held again the
    /// next time a rule reaches it.
    func revokeApproval(key: String) {
        settings.approvals = settings.approvals.revoking(key)
        changed()
    }

    /// Re-enable a rule paused by the runaway budget.
    func unpauseRule(id: String) {
        settings.autoPausedRules = settings.autoPausedRules.subtracting([id])
        sweepAll()
    }

    /// Rules paused by the runaway budget.
    var autoPausedRules: Set<String> { settings.autoPausedRules }

    // MARK: Sweeping

    /// Sweep one target directory (already `~`-expanded).
    func sweep(expandedTarget: String, evenWhilePaused: Bool = false) {
        let now = clock.now()
        guard evenWhilePaused || !settings.isPaused(now: now) else { return }
        guard let set = ruleSet, let target = target(in: set, expandedPath: expandedTarget) else { return }
        guard let facts = enumerator.facts(inDirectory: expandedTarget) else {
            targetStatuses[expandedTarget] = TargetStatus(path: expandedTarget, lastSweep: now, lastActionCount: 0, denied: true)
            changed()
            return
        }
        factsCache[expandedTarget] = facts

        let context = SweepContext(
            now: now, home: home, timeZone: timeZone, defaults: set.defaults,
            approvals: settings.approvals, pausedRules: settings.autoPausedRules)
        let plan = SweepPlanner.plan(target: target, facts: facts, guardState: guardState, context: context)
        guardState = plan.guardState

        for ruleID in plan.autoPausedRules {
            settings.autoPausedRules = settings.autoPausedRules.union([ruleID])
            // The planner only pauses rules from this very set, so the lookup cannot miss.
            post(NotificationPlanner.autoPausedNotice(ruleName: set.rule(withID: ruleID)!.displayName))
        }
        registerPending(plan.pendingApprovals)

        let dryRun = settings.dryRun
        let executed = plan.actions.compactMap { execute($0, targetDir: expandedTarget, dryRun: dryRun) }
        record(executed, target: expandedTarget, now: now)
        for notice in NotificationPlanner.notices(for: executed, dryRun: dryRun) {
            post(notice)
        }

        guardState.prune(now: now, cooldown: set.defaults.cooldownSeconds)
        targetStatuses[expandedTarget] = TargetStatus(
            path: expandedTarget, lastSweep: now, lastActionCount: executed.count, denied: false)
        rescheduleAgeWake(set: set, now: now)
        changed()
    }

    // MARK: Execution

    /// Perform one planned action through the ports (or preview it). Returns
    /// nil for a launched run: its outcome is recorded when it finishes.
    private func execute(_ action: PlannedAction, targetDir: String, dryRun: Bool) -> ExecutedAction? {
        if dryRun { return ExecutedAction(action: action, outcome: .preview) }
        switch action.op {
        case .move(let src, let destDir, let policy):
            return ExecutedAction(action: action, outcome: transfer(src: src, destDir: destDir, policy: policy, move: true))
        case .copy(let src, let destDir, let policy):
            return ExecutedAction(action: action, outcome: transfer(src: src, destDir: destDir, policy: policy, move: false))
        case .rename(let src, let proposedName):
            return ExecutedAction(action: action, outcome: rename(src: src, proposedName: proposedName))
        case .trash(let src):
            return ExecutedAction(action: action, outcome: outcome(of: files.trash(src)))
        case .run(let spec, let file):
            launch(spec, on: file, action: action, targetDir: targetDir)
            return nil
        }
    }

    /// Move or copy `src` into `destDir` under `policy`.
    private func transfer(src: String, destDir: String, policy: ConflictPolicy, move: Bool) -> ExecutedAction.Outcome {
        if case .failure(let error) = files.ensureDirectory(destDir) {
            return .failure(error.message)
        }
        let existing = enumerator.names(inDirectory: destDir) ?? []
        let proposed = (src as NSString).lastPathComponent
        switch PatternRenderer.resolveConflict(proposed: proposed, existing: existing, policy: policy) {
        case .skip:
            return .skipped
        case .replace(let name):
            if case .failure(let error) = files.remove(destDir + "/" + name) {
                return .failure(error.message)
            }
            return finishTransfer(src: src, dst: destDir + "/" + name, move: move)
        case .use(let name):
            return finishTransfer(src: src, dst: destDir + "/" + name, move: move)
        }
    }

    /// The actual move/copy call plus self-write bookkeeping.
    private func finishTransfer(src: String, dst: String, move: Bool) -> ExecutedAction.Outcome {
        let result = move ? files.move(src, to: dst) : files.copy(src, to: dst)
        if case .success(let path) = result {
            guardState.noteWrite(path, now: clock.now())
        }
        return outcome(of: result)
    }

    /// Rename `src` inside its own directory, uniquifying on conflict.
    private func rename(src: String, proposedName: String) -> ExecutedAction.Outcome {
        let dir = (src as NSString).deletingLastPathComponent
        let current = (src as NSString).lastPathComponent
        let taken = Set((enumerator.names(inDirectory: dir) ?? []).filter { $0 != current }.map { $0.lowercased() })
        let name = taken.contains(proposedName.lowercased()) ? PatternRenderer.uniqueName(proposedName, taken: taken) : proposedName
        return finishTransfer(src: src, dst: dir + "/" + name, move: true)
    }

    /// Launch an approved shell command with a sanitized environment; its
    /// outcome is logged (and failures notified) when it finishes.
    private func launch(_ spec: RunSpec, on file: String, action: PlannedAction, targetDir: String) {
        let environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home,
            "WHISK_FILE": file,
            "WHISK_RULE_ID": action.ruleID,
        ]
        runner.run(
            command: spec.command, arguments: spec.args + [file], directory: targetDir,
            environment: environment, timeout: spec.timeoutSeconds
        ) { [weak self] exitCode, output in
            let outcome: ExecutedAction.Outcome
            if exitCode == 0 {
                outcome = .success(dst: nil)
            } else {
                let reason = exitCode.map { "exit \($0)" } ?? "failed to launch or timed out"
                outcome = .failure("\(reason): \(output)")
            }
            self?.finishRun(ExecutedAction(action: action, outcome: outcome), targetDir: targetDir)
        }
    }

    /// Record and notify a finished shell command.
    private func finishRun(_ finished: ExecutedAction, targetDir: String) {
        record([finished], target: targetDir, now: clock.now())
        for notice in NotificationPlanner.notices(for: [finished], dryRun: false) {
            post(notice)
        }
        changed()
    }

    /// Map a port result into an outcome.
    private func outcome(of result: Result<String, FileOpError>) -> ExecutedAction.Outcome {
        switch result {
        case .success(let path): return .success(dst: path)
        case .failure(let error): return .failure(error.message)
        }
    }

    // MARK: Bookkeeping

    /// Append `executed` to the activity log and the in-memory cache.
    private func record(_ executed: [ExecutedAction], target: String, now: Date) {
        for item in executed {
            let entry = ActivityLog.entry(for: item, target: target, now: now)
            recentActivity.append(entry)
            activity.append(line: ActivityLog.encodeLine(entry))
        }
        recentActivity = ActivityLog.prune(recentActivity, now: now)
    }

    /// Load, prune, and rewrite the activity log at launch.
    private func restoreActivity() {
        let entries = activity.readLines().compactMap(ActivityLog.decodeLine)
        recentActivity = ActivityLog.prune(entries, now: clock.now())
        if recentActivity.count != entries.count {
            activity.rewrite(lines: recentActivity.map(ActivityLog.encodeLine))
        }
    }

    /// Merge newly held approvals, skipping already-known and rejected keys.
    private func registerPending(_ pending: [PendingApproval]) {
        for item in pending {
            guard !rejectedApprovalKeys.contains(item.key) else { continue }
            guard !pendingApprovals.contains(where: { $0.key == item.key }) else { continue }
            pendingApprovals.append(item)
            post(NotificationPlanner.pendingApprovalNotice(displayCommand: ApprovedCommands.display(key: item.key)))
        }
    }

    /// Arm the next age-based wake-up from the cached snapshots.
    private func rescheduleAgeWake(set: RuleSet, now: Date) {
        ageTimer?.cancel()
        ageTimer = nil
        let snapshots = set.targets.compactMap { target -> (Target, [FileFacts])? in
            let path = PatternRenderer.expandPath(target.path, home: home)
            return factsCache[path].map { (target, $0) }
        }
        guard let delay = SweepScheduler.nextWakeDelay(snapshots: snapshots, now: now) else { return }
        ageTimer = scheduler.schedule(after: delay) { [weak self] in self?.sweepAll() }
    }

    /// The expanded paths of every target in `set`.
    private func expandedTargetPaths(of set: RuleSet?) -> [String] {
        (set?.targets ?? []).map { PatternRenderer.expandPath($0.path, home: home) }
    }

    /// The target whose expanded path is `expandedPath`.
    private func target(in set: RuleSet, expandedPath: String) -> Target? {
        set.targets.first { PatternRenderer.expandPath($0.path, home: home) == expandedPath }
    }

    /// Post a notice if notifications are on.
    private func post(_ notice: Notice) {
        guard settings.notificationsEnabled else { return }
        notifier.post(title: notice.title, body: notice.body)
    }

    /// Signal the view model.
    private func changed() {
        onStateChange?()
    }
}
