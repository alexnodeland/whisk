// RuleModel.swift
// The value types of the rules schema and their JSON coding. Conditions and
// actions are single-key objects ({ "age": {...} }, { "move": {...} }); sizes
// and durations are unit-suffixed strings ("100MB", "7d").
// In coverage. Imports only Foundation.

import Foundation

/// Which timestamp an age condition measures from.
enum AgeBasis: String, Codable {
    case created
    case modified
    case added
}

/// Whether a kind condition matches files or directories.
enum FileKind: String, Codable {
    case file
    case directory
}

/// What to do when a move/copy destination name already exists.
enum ConflictPolicy: String, Codable {
    case rename
    case skip
    case replace
}

/// A name condition: glob or regular expression.
enum NamePattern: Equatable {
    case glob(String)
    case regex(String)
}

/// A size bound; at least one side is set.
struct SizeCondition: Equatable {
    /// Match entries strictly larger than this many bytes.
    var overBytes: UInt64?
    /// Match entries strictly smaller than this many bytes.
    var underBytes: UInt64?
}

/// An age bound relative to now; at least one side is set.
struct AgeCondition: Equatable {
    /// Which timestamp to measure from.
    var basis: AgeBasis
    /// Match entries whose basis date is more than this many seconds ago.
    var olderThanSeconds: TimeInterval?
    /// Match entries whose basis date is at most this many seconds ago.
    var newerThanSeconds: TimeInterval?
}

/// A rule's matching predicate. `all`/`any`/`not` nest arbitrarily.
indirect enum Condition: Equatable {
    case all([Condition])
    case any([Condition])
    case not(Condition)
    case name(NamePattern)
    case extensions([String])
    case kind(FileKind)
    case size(SizeCondition)
    case age(AgeCondition)
}

/// Destination spec for move and copy.
struct MoveSpec: Equatable {
    /// Destination directory; may contain `~`, `{name}`, `{ext}`, and
    /// `{date.*:FMT}` tokens.
    var to: String
    /// Conflict policy when the destination name exists (default: rename).
    var onConflict: ConflictPolicy = .rename
}

/// New-name spec for rename.
struct RenameSpec: Equatable {
    /// New file name template; same tokens as `MoveSpec.to`.
    var to: String
}

/// Shell command spec for the run action.
struct RunSpec: Equatable {
    /// Absolute path of the executable to run.
    var command: String
    /// Arguments; the matched file's path is appended as the final argument.
    var args: [String] = []
    /// Seconds before the process is killed (default 30, hard cap 300).
    var timeoutSeconds: TimeInterval = 30
}

/// One step a rule performs on a matched file.
enum Action: Equatable {
    case move(MoveSpec)
    case copy(MoveSpec)
    case rename(RenameSpec)
    case trash
    case run(RunSpec)
}

/// One rule: a predicate plus an ordered action list.
struct Rule: Equatable {
    /// Stable identifier, unique across the whole rules file.
    var id: String
    /// Optional human-readable name (falls back to `id` in UI).
    var name: String?
    /// Disabled rules are parsed but never planned.
    var enabled: Bool = true
    /// Whether actions taken by this rule post a notification.
    var notify: Bool = true
    /// The predicate.
    var match: Condition
    /// The ordered actions; never empty after validation.
    var actions: [Action]

    /// The name to show in UI and notifications.
    var displayName: String { name ?? id }
}

/// A watched directory and its ordered rules.
struct Target: Equatable {
    /// The directory path; may start with `~`.
    var path: String
    /// The rules applied to entries of this directory, in order.
    var rules: [Rule]
}

/// File-wide tunables with safe defaults.
struct RuleDefaults: Equatable {
    /// Per-(file, rule) re-trigger guard, seconds.
    var cooldownSeconds: TimeInterval = 30
    /// Per-rule action budget per sweep; exceeding auto-pauses the rule.
    var maxActionsPerRule: Int = 100
    /// Whole-sweep action budget; exceeding stops the sweep.
    var maxActionsPerSweep: Int = 500
}

/// The parsed rules file.
struct RuleSet: Equatable {
    /// Schema version; must be 1.
    var version: Int
    /// File-wide tunables.
    var defaults: RuleDefaults = RuleDefaults()
    /// The watched directories.
    var targets: [Target]

    /// Every rule across every target, in file order.
    var allRules: [Rule] { targets.flatMap(\.rules) }

    /// The rule with `id`, if any.
    func rule(withID id: String) -> Rule? {
        allRules.first { $0.id == id }
    }
}

// MARK: - Codable

extension NamePattern: Codable {
    private enum Key: String, CodingKey {
        case glob
        case regex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let glob = try container.decodeIfPresent(String.self, forKey: .glob) {
            self = .glob(glob)
        } else if let regex = try container.decodeIfPresent(String.self, forKey: .regex) {
            self = .regex(regex)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "name needs a \"glob\" or \"regex\" key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .glob(let pattern): try container.encode(pattern, forKey: .glob)
        case .regex(let pattern): try container.encode(pattern, forKey: .regex)
        }
    }
}

extension SizeCondition: Codable {
    private enum Key: String, CodingKey {
        case over
        case under
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        overBytes = try container.decodeIfPresent(String.self, forKey: .over).map { text in
            guard let bytes = Units.size(text) else {
                throw DecodingError.dataCorruptedError(forKey: .over, in: container, debugDescription: "invalid size \"\(text)\"")
            }
            return bytes
        }
        underBytes = try container.decodeIfPresent(String.self, forKey: .under).map { text in
            guard let bytes = Units.size(text) else {
                throw DecodingError.dataCorruptedError(forKey: .under, in: container, debugDescription: "invalid size \"\(text)\"")
            }
            return bytes
        }
        if overBytes == nil && underBytes == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "size needs an \"over\" or \"under\" key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(overBytes.map(Units.formatSize), forKey: .over)
        try container.encodeIfPresent(underBytes.map(Units.formatSize), forKey: .under)
    }
}

extension AgeCondition: Codable {
    private enum Key: String, CodingKey {
        case basis
        case olderThan
        case newerThan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        basis = try container.decodeIfPresent(AgeBasis.self, forKey: .basis) ?? .added
        olderThanSeconds = try container.decodeIfPresent(String.self, forKey: .olderThan).map { text in
            guard let seconds = Units.duration(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .olderThan, in: container, debugDescription: "invalid duration \"\(text)\"")
            }
            return seconds
        }
        newerThanSeconds = try container.decodeIfPresent(String.self, forKey: .newerThan).map { text in
            guard let seconds = Units.duration(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .newerThan, in: container, debugDescription: "invalid duration \"\(text)\"")
            }
            return seconds
        }
        if olderThanSeconds == nil && newerThanSeconds == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "age needs an \"olderThan\" or \"newerThan\" key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(basis, forKey: .basis)
        try container.encodeIfPresent(olderThanSeconds.map(Units.formatDuration), forKey: .olderThan)
        try container.encodeIfPresent(newerThanSeconds.map(Units.formatDuration), forKey: .newerThan)
    }
}

extension Condition: Codable {
    private enum Key: String, CodingKey {
        case all
        case any
        case not
        case name
        case extensions = "extension"
        case kind
        case size
        case age
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "a condition must be exactly one of all/any/not/name/extension/kind/size/age"))
        }
        switch key {
        case .all: self = .all(try container.decode([Condition].self, forKey: .all))
        case .any: self = .any(try container.decode([Condition].self, forKey: .any))
        case .not: self = .not(try container.decode(Condition.self, forKey: .not))
        case .name: self = .name(try container.decode(NamePattern.self, forKey: .name))
        case .extensions: self = .extensions(try container.decode([String].self, forKey: .extensions))
        case .kind: self = .kind(try container.decode(FileKind.self, forKey: .kind))
        case .size: self = .size(try container.decode(SizeCondition.self, forKey: .size))
        case .age: self = .age(try container.decode(AgeCondition.self, forKey: .age))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .all(let conditions): try container.encode(conditions, forKey: .all)
        case .any(let conditions): try container.encode(conditions, forKey: .any)
        case .not(let condition): try container.encode(condition, forKey: .not)
        case .name(let pattern): try container.encode(pattern, forKey: .name)
        case .extensions(let exts): try container.encode(exts, forKey: .extensions)
        case .kind(let kind): try container.encode(kind, forKey: .kind)
        case .size(let size): try container.encode(size, forKey: .size)
        case .age(let age): try container.encode(age, forKey: .age)
        }
    }
}

extension MoveSpec: Codable {
    private enum Key: String, CodingKey {
        case to
        case onConflict
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        to = try container.decode(String.self, forKey: .to)
        onConflict = try container.decodeIfPresent(ConflictPolicy.self, forKey: .onConflict) ?? .rename
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(to, forKey: .to)
        try container.encode(onConflict, forKey: .onConflict)
    }
}

extension RenameSpec: Codable {}

extension RunSpec: Codable {
    private enum Key: String, CodingKey {
        case command
        case args
        case timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds) ?? 30
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
    }
}

extension Action: Codable {
    private enum Key: String, CodingKey {
        case move
        case copy
        case rename
        case trash
        case run
    }

    /// The empty `{}` payload of a trash action.
    private struct Empty: Codable {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "an action must be exactly one of move/copy/rename/trash/run"))
        }
        switch key {
        case .move: self = .move(try container.decode(MoveSpec.self, forKey: .move))
        case .copy: self = .copy(try container.decode(MoveSpec.self, forKey: .copy))
        case .rename: self = .rename(try container.decode(RenameSpec.self, forKey: .rename))
        case .trash:
            _ = try container.decode(Empty.self, forKey: .trash)
            self = .trash
        case .run: self = .run(try container.decode(RunSpec.self, forKey: .run))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .move(let spec): try container.encode(spec, forKey: .move)
        case .copy(let spec): try container.encode(spec, forKey: .copy)
        case .rename(let spec): try container.encode(spec, forKey: .rename)
        case .trash: try container.encode(Empty(), forKey: .trash)
        case .run(let spec): try container.encode(spec, forKey: .run)
        }
    }
}

extension Rule: Codable {
    private enum Key: String, CodingKey {
        case id
        case name
        case enabled
        case notify
        case match
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        notify = try container.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        match = try container.decode(Condition.self, forKey: .match)
        actions = try container.decode([Action].self, forKey: .actions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(notify, forKey: .notify)
        try container.encode(match, forKey: .match)
        try container.encode(actions, forKey: .actions)
    }
}

extension Target: Codable {}

extension RuleDefaults: Codable {
    private enum Key: String, CodingKey {
        case cooldownSeconds
        case maxActionsPerRule
        case maxActionsPerSweep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let fallback = RuleDefaults()
        cooldownSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? fallback.cooldownSeconds
        maxActionsPerRule = try container.decodeIfPresent(Int.self, forKey: .maxActionsPerRule) ?? fallback.maxActionsPerRule
        maxActionsPerSweep = try container.decodeIfPresent(Int.self, forKey: .maxActionsPerSweep) ?? fallback.maxActionsPerSweep
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try container.encode(maxActionsPerRule, forKey: .maxActionsPerRule)
        try container.encode(maxActionsPerSweep, forKey: .maxActionsPerSweep)
    }
}

extension RuleSet: Codable {
    private enum Key: String, CodingKey {
        case version
        case defaults
        case targets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        version = try container.decode(Int.self, forKey: .version)
        defaults = try container.decodeIfPresent(RuleDefaults.self, forKey: .defaults) ?? RuleDefaults()
        targets = try container.decode([Target].self, forKey: .targets)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(version, forKey: .version)
        try container.encode(defaults, forKey: .defaults)
        try container.encode(targets, forKey: .targets)
    }
}
