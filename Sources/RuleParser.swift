// RuleParser.swift
// Decodes and validates the rules file (JSON5-relaxed JSON, ADR 0003). A parse
// failure never crashes or wipes state: callers keep the last-good RuleSet and
// surface the diagnostic. In coverage. Imports only Foundation.

import Foundation

/// A human-readable rules-file diagnostic.
struct RuleParseError: Error, Equatable {
    /// What went wrong, phrased for the menu-bar error badge.
    var message: String
}

/// Rules-file decoding, validation, and canonical re-encoding.
enum RuleParser {

    /// The schema version this build understands.
    static let supportedVersion = 1

    /// The hard cap on a run action's timeout, seconds.
    static let maxRunTimeout: TimeInterval = 300

    /// Decode and validate `data`. Returns the parsed set or a diagnostic.
    static func parse(_ data: Data) -> Result<RuleSet, RuleParseError> {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let set: RuleSet
        do {
            set = try decoder.decode(RuleSet.self, from: data)
        } catch {
            return .failure(RuleParseError(message: describe(error)))
        }
        if let problem = validate(set) { return .failure(problem) }
        return .success(set)
    }

    /// Re-encode `set` as strict, pretty-printed, key-sorted JSON — what the GUI
    /// editor writes back (hand-written comments do not survive; the editor warns).
    static func encode(_ set: RuleSet) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try! encoder.encode(set)
    }

    /// Semantic validation beyond what decoding enforces, or nil when valid.
    static func validate(_ set: RuleSet) -> RuleParseError? {
        if set.version != supportedVersion {
            return RuleParseError(message: "unsupported version \(set.version) (this build understands \(supportedVersion))")
        }
        if set.targets.isEmpty {
            return RuleParseError(message: "no targets defined")
        }
        if set.defaults.cooldownSeconds < 0 || set.defaults.maxActionsPerRule < 1 || set.defaults.maxActionsPerSweep < 1 {
            return RuleParseError(message: "defaults must be positive")
        }
        var seenPaths = Set<String>()
        var seenIDs = Set<String>()
        for target in set.targets {
            if target.path.isEmpty { return RuleParseError(message: "a target has an empty path") }
            if !seenPaths.insert(target.path).inserted {
                return RuleParseError(message: "duplicate target path \"\(target.path)\"")
            }
            for rule in target.rules {
                if let problem = validate(rule, seenIDs: &seenIDs) { return problem }
            }
        }
        return nil
    }

    /// Validate one rule, tracking id uniqueness across the whole file.
    private static func validate(_ rule: Rule, seenIDs: inout Set<String>) -> RuleParseError? {
        if rule.id.isEmpty { return RuleParseError(message: "a rule has an empty id") }
        if !seenIDs.insert(rule.id).inserted {
            return RuleParseError(message: "duplicate rule id \"\(rule.id)\"")
        }
        if let problem = validate(rule.match, ruleID: rule.id) { return problem }
        if rule.actions.isEmpty {
            return RuleParseError(message: "rule \"\(rule.id)\" has no actions")
        }
        for (index, action) in rule.actions.enumerated() {
            if let problem = validate(action, ruleID: rule.id) { return problem }
            let isTerminal = action == .trash || isMove(action)
            if isTerminal && index != rule.actions.count - 1 {
                return RuleParseError(message: "rule \"\(rule.id)\" has actions after move/trash, which are unreachable")
            }
        }
        return nil
    }

    /// Whether `action` is a move (the other chain-terminating action besides trash).
    private static func isMove(_ action: Action) -> Bool {
        if case .move = action { return true }
        return false
    }

    /// Validate a condition tree's patterns.
    private static func validate(_ condition: Condition, ruleID: String) -> RuleParseError? {
        switch condition {
        case .all(let conditions), .any(let conditions):
            for inner in conditions {
                if let problem = validate(inner, ruleID: ruleID) { return problem }
            }
            return conditions.isEmpty ? RuleParseError(message: "rule \"\(ruleID)\" has an empty all/any group") : nil
        case .not(let inner):
            return validate(inner, ruleID: ruleID)
        case .name(.glob(let pattern)):
            return GlobMatcher.regexPattern(fromGlob: pattern) == nil
                ? RuleParseError(message: "rule \"\(ruleID)\" has a malformed glob \"\(pattern)\"") : nil
        case .name(.regex(let pattern)):
            return GlobMatcher.isValidRegex(pattern)
                ? nil : RuleParseError(message: "rule \"\(ruleID)\" has an invalid regex \"\(pattern)\"")
        case .extensions(let extensions):
            return extensions.isEmpty || extensions.contains(where: \.isEmpty)
                ? RuleParseError(message: "rule \"\(ruleID)\" has an empty extension list or entry") : nil
        case .kind, .size, .age:
            return nil
        }
    }

    /// Validate one action's templates and limits.
    private static func validate(_ action: Action, ruleID: String) -> RuleParseError? {
        switch action {
        case .move(let spec), .copy(let spec):
            return validateTemplate(spec.to, ruleID: ruleID, what: "destination")
        case .rename(let spec):
            return validateTemplate(spec.to, ruleID: ruleID, what: "rename")
        case .trash:
            return nil
        case .run(let spec):
            if !spec.command.hasPrefix("/") {
                return RuleParseError(message: "rule \"\(ruleID)\" run command must be an absolute path")
            }
            if spec.timeoutSeconds <= 0 || spec.timeoutSeconds > maxRunTimeout {
                return RuleParseError(message: "rule \"\(ruleID)\" run timeout must be within 1–\(Int(maxRunTimeout))s")
            }
            return nil
        }
    }

    /// Validate a template string used by move/copy/rename.
    private static func validateTemplate(_ template: String, ruleID: String, what: String) -> RuleParseError? {
        if template.isEmpty {
            return RuleParseError(message: "rule \"\(ruleID)\" has an empty \(what)")
        }
        return PatternRenderer.isValidTemplate(template)
            ? nil : RuleParseError(message: "rule \"\(ruleID)\" has an unknown token in \(what) \"\(template)\"")
    }

    /// Flatten a decoding failure into one line for the error badge.
    static func describe(_ error: Error) -> String {
        if case DecodingError.dataCorrupted(let context) = error {
            return context.debugDescription
        }
        if case DecodingError.keyNotFound(let key, let context) = error {
            return "missing key \"\(key.stringValue)\" at \(pathString(context))"
        }
        if case DecodingError.typeMismatch(_, let context) = error {
            return "wrong type at \(pathString(context)): \(context.debugDescription)"
        }
        if case DecodingError.valueNotFound(_, let context) = error {
            return "missing value at \(pathString(context))"
        }
        return error.localizedDescription
    }

    /// Render a coding path like "targets[0].rules[2].match".
    private static func pathString(_ context: DecodingError.Context) -> String {
        let parts = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }
        let joined = parts.joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
        return joined.isEmpty ? "top level" : joined
    }
}
