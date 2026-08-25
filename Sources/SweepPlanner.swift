// SweepPlanner.swift
// The heart of Whisk (ADR 0005): given a metadata snapshot of one target, its
// rules, and the guard state, produce the list of actions to perform — plus
// held shell approvals and any rules to auto-pause. Deterministic; all effects
// happen elsewhere. In coverage. Imports only Foundation.

import Foundation

/// One effect the executor should perform.
struct PlannedAction: Equatable {
    /// The rule that planned this.
    var ruleID: String
    /// The rule's display name (for notifications and the activity log).
    var ruleName: String
    /// Whether this rule notifies.
    var notify: Bool
    /// What to do.
    var op: Operation

    /// The concrete filesystem or process effect.
    enum Operation: Equatable {
        /// Move `src` into `destDir`, resolving name conflicts by `onConflict`.
        case move(src: String, destDir: String, onConflict: ConflictPolicy)
        /// Copy `src` into `destDir`, resolving name conflicts by `onConflict`.
        case copy(src: String, destDir: String, onConflict: ConflictPolicy)
        /// Rename `src` to `proposedName` inside its directory (uniquified on conflict).
        case rename(src: String, proposedName: String)
        /// Send `src` to the Trash.
        case trash(src: String)
        /// Run the approved command on `file`.
        case run(spec: RunSpec, file: String)
    }
}

/// A shell command held for first-run approval.
struct PendingApproval: Equatable {
    /// The approval key (see `ApprovedCommands.key(for:)`).
    var key: String
    /// The rule that wanted to run it.
    var ruleID: String
    /// The file it would have run on.
    var file: String
}

/// Everything one sweep decided.
struct SweepPlan: Equatable {
    /// The effects to perform, in order.
    var actions: [PlannedAction] = []
    /// Shell commands held for approval.
    var pendingApprovals: [PendingApproval] = []
    /// Rules that exceeded their per-sweep budget and must be paused.
    var autoPausedRules: [String] = []
    /// The guard state after recording this sweep's decisions.
    var guardState: LoopGuardState
    /// True when the whole-sweep budget stopped planning early.
    var truncatedByBudget = false
}

/// The inputs a sweep needs beyond the target itself.
struct SweepContext {
    /// The current instant.
    var now: Date
    /// The user's home directory (for `~` expansion).
    var home: String
    /// Time zone for `{date.*}` tokens.
    var timeZone: TimeZone
    /// File-wide tunables.
    var defaults: RuleDefaults
    /// Approved shell commands.
    var approvals: ApprovedCommands
    /// Rules currently paused (manually or automatically).
    var pausedRules: Set<String>
}

/// Pure sweep planning.
enum SweepPlanner {

    /// Plan one sweep of `target` over the snapshot `facts`.
    static func plan(
        target: Target,
        facts: [FileFacts],
        guardState: LoopGuardState,
        context: SweepContext
    ) -> SweepPlan {
        var plan = SweepPlan(guardState: guardState)
        var consumed = Set<String>()
        var sweepCount = 0
        let targetDir = PatternRenderer.expandPath(target.path, home: context.home)

        for rule in target.rules where rule.enabled && !context.pausedRules.contains(rule.id) {
            var ruleCount = 0
            for file in facts where !consumed.contains(file.path) {
                if plan.guardState.cooldownActive(
                    path: file.path, ruleID: rule.id, now: context.now, cooldown: context.defaults.cooldownSeconds)
                {
                    continue
                }
                guard ConditionEvaluator.matches(rule.match, facts: file, now: context.now) else { continue }
                if sweepCount >= context.defaults.maxActionsPerSweep {
                    plan.truncatedByBudget = true
                    return plan
                }
                if ruleCount >= context.defaults.maxActionsPerRule {
                    plan.autoPausedRules.append(rule.id)
                    break
                }
                let step = planActions(of: rule, on: file, targetDir: targetDir, context: context)
                if step.actions.isEmpty && step.pending.isEmpty { continue }
                plan.actions += step.actions
                plan.pendingApprovals += step.pending
                // A pending-only step took no action: no cooldown, no budget —
                // approval must be able to act immediately, and re-sweeps dedup
                // held keys anyway.
                if !step.actions.isEmpty {
                    plan.guardState.noteAction(path: file.path, ruleID: rule.id, now: context.now)
                    ruleCount += 1
                    sweepCount += 1
                }
                if step.consumes { consumed.insert(file.path) }
            }
        }
        return plan
    }

    /// The outcome of planning one rule's action chain on one file.
    private struct ChainStep {
        var actions: [PlannedAction] = []
        var pending: [PendingApproval] = []
        var consumes = false
    }

    /// Plan `rule`'s ordered actions on `file`, threading the file's projected
    /// path through the chain. Move and trash end the chain (the parser rejects
    /// actions after them).
    private static func planActions(of rule: Rule, on file: FileFacts, targetDir: String, context: SweepContext) -> ChainStep {
        var step = ChainStep()
        var current = file
        for action in rule.actions {
            switch action {
            case .move(let spec), .copy(let spec):
                guard let destDir = destination(spec, for: current, targetDir: targetDir, context: context) else { return ChainStep() }
                if case .move = action {
                    step.actions.append(planned(rule, .move(src: current.path, destDir: destDir, onConflict: spec.onConflict)))
                    step.consumes = true
                } else {
                    step.actions.append(planned(rule, .copy(src: current.path, destDir: destDir, onConflict: spec.onConflict)))
                }
            case .rename(let spec):
                guard let newName = PatternRenderer.render(template: spec.to, facts: current, timeZone: context.timeZone),
                    !newName.isEmpty, !newName.contains("/"), newName != current.name
                else { return ChainStep() }
                step.actions.append(planned(rule, .rename(src: current.path, proposedName: newName)))
                let dir = (current.path as NSString).deletingLastPathComponent
                current.path = dir + "/" + newName
                current.name = newName
            case .trash:
                step.actions.append(planned(rule, .trash(src: current.path)))
                step.consumes = true
            case .run(let spec):
                switch context.approvals.gate(spec) {
                case .approved:
                    step.actions.append(planned(rule, .run(spec: spec, file: current.path)))
                case .pending(let key):
                    step.pending.append(PendingApproval(key: key, ruleID: rule.id, file: current.path))
                }
            }
        }
        return step
    }

    /// Render and resolve a move/copy destination directory, or nil when the
    /// action must be refused: unrenderable template, moving into the source's
    /// own directory, or into the source itself (the plan-time cycle check).
    private static func destination(_ spec: MoveSpec, for file: FileFacts, targetDir: String, context: SweepContext) -> String? {
        guard let rendered = PatternRenderer.render(template: spec.to, facts: file, timeZone: context.timeZone) else { return nil }
        let expanded = PatternRenderer.expandPath(rendered, home: context.home)
        let absolute = expanded.hasPrefix("/") ? expanded : targetDir + "/" + expanded
        let normalized = (absolute as NSString).standardizingPath
        let sourceDir = (file.path as NSString).deletingLastPathComponent
        if normalized == sourceDir { return nil }
        if normalized == file.path || normalized.hasPrefix(file.path + "/") { return nil }
        return normalized
    }

    /// Wrap an operation with the rule's identity.
    private static func planned(_ rule: Rule, _ op: PlannedAction.Operation) -> PlannedAction {
        PlannedAction(ruleID: rule.id, ruleName: rule.displayName, notify: rule.notify, op: op)
    }
}
