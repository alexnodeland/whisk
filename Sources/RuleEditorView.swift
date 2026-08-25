// RuleEditorView.swift
// The built-in rules editor (deliberately narrow, ADR 0003): targets, per-target
// rule lists (enable/reorder/delete), and a form covering exactly the v1
// condition/action vocabulary. A rule whose match is anything other than a flat
// `all` of simple conditions shows as read-only with "Edit in file". Saving
// writes strict JSON — the file stays the source of truth.
// Exempt from coverage and audit (presentation only).

import SwiftUI

/// The rules editor window.
struct RuleEditorView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var draft: RuleSet?
    @State private var selectedTarget = 0
    @State private var justSaved = false

    /// Whether the draft differs from what the file currently holds.
    private var isDirty: Bool {
        draft != nil && draft != model.ruleSet
    }

    var body: some View {
        Group {
            if let set = draft {
                editor(set)
            } else {
                ContentUnavailableView(
                    "No rules loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(model.rulesError ?? "Fix the rules file and it will hot-reload."))
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { draft = model.ruleSet }
        .onChange(of: model.ruleSet) { _, newValue in
            // The file changed on disk (a save landing, or an outside edit).
            // Only clobber the draft when it holds nothing the file doesn't.
            if !isDirty { draft = newValue }
        }
    }

    private func editor(_ set: RuleSet) -> some View {
        VStack(spacing: 0) {
            HSplitView {
                targetList(set)
                    .frame(minWidth: 180, maxWidth: 240)
                ruleList(set)
                    .frame(minWidth: 400)
            }
            Divider()
            HStack(spacing: 10) {
                Text((model.rulesPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Comments in the file are preserved when you save.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if isDirty {
                    Label("Unsaved changes", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if justSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button("Revert") { draft = model.ruleSet }
                    .disabled(!isDirty)
                Button("Save") { save() }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            }
            .padding(10)
        }
    }

    private func save() {
        guard let draft else { return }
        model.saveRules(draft)
        justSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            justSaved = false
        }
    }

    // MARK: Targets

    private func targetList(_ set: RuleSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedTarget) {
                ForEach(Array(set.targets.enumerated()), id: \.offset) { index, target in
                    Label(target.path, systemImage: "folder")
                        .tag(index)
                }
            }
            Divider()
            HStack {
                Button {
                    draft?.targets.append(Target(path: "~/", rules: []))
                    selectedTarget = (draft?.targets.count ?? 1) - 1
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    guard set.targets.indices.contains(selectedTarget) else { return }
                    draft?.targets.remove(at: selectedTarget)
                    selectedTarget = 0
                } label: {
                    Image(systemName: "minus")
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    // MARK: Rules

    private func ruleList(_ set: RuleSet) -> some View {
        Group {
            if set.targets.indices.contains(selectedTarget) {
                let target = set.targets[selectedTarget]
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Target folder", text: targetPathBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        ForEach(Array(target.rules.enumerated()), id: \.offset) { index, _ in
                            RuleCard(
                                rule: ruleBinding(index),
                                onDelete: { draft?.targets[selectedTarget].rules.remove(at: index) },
                                onMoveUp: index > 0 ? { draft?.targets[selectedTarget].rules.swapAt(index, index - 1) } : nil,
                                onMoveDown: index < target.rules.count - 1
                                    ? { draft?.targets[selectedTarget].rules.swapAt(index, index + 1) } : nil)
                        }
                        Button {
                            draft?.targets[selectedTarget].rules.append(
                                Rule(
                                    id: "rule-\(Int.random(in: 1000...9999))", match: .all([.kind(.file)]),
                                    actions: [.trash]))
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                        }
                    }
                    .padding(12)
                }
            } else {
                Text("Select a target")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var targetPathBinding: Binding<String> {
        Binding(
            get: { draft?.targets[safe: selectedTarget]?.path ?? "" },
            set: { draft?.targets[safe: selectedTarget]?.path = $0 })
    }

    private func ruleBinding(_ index: Int) -> Binding<Rule> {
        Binding(
            get: {
                draft?.targets[safe: selectedTarget]?.rules[safe: index]
                    ?? Rule(id: "?", match: .all([]), actions: [.trash])
            },
            set: { draft?.targets[safe: selectedTarget]?.rules[safe: index] = $0 })
    }
}

/// One editable rule.
private struct RuleCard: View {
    @Binding var rule: Rule
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden()
                    .help("Enable or disable this rule")
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Rule name", text: nameBinding, prompt: Text("Name this rule…"))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .help("The rule's display name — click to rename")
                Spacer()
                if let onMoveUp {
                    Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                }
                if let onMoveDown {
                    Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)

            if let simple = SimpleMatch(rule.match) {
                ConditionEditor(
                    match: Binding(
                        get: { SimpleMatch(rule.match) ?? simple },
                        set: { rule.match = $0.condition }))
            } else {
                Label("This rule's conditions are more complex than the editor covers — edit them in the file.", systemImage: "curlybraces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActionsEditor(actions: $rule.actions)

            Toggle("Notify", isOn: $rule.notify)
                .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { rule.name ?? rule.id },
            set: { rule.name = $0.isEmpty ? nil : $0 })
    }
}

/// The editable flat form of a match: an `all` of at most one of each simple
/// condition. Anything else falls back to edit-in-file.
private struct SimpleMatch {
    var glob = ""
    var extensions = ""
    var kind: FileKind?
    /// Age threshold in seconds; nil (or 0) means no age condition.
    var olderThanSeconds: TimeInterval?
    /// Size threshold in bytes; nil (or 0) means no size condition.
    var minSizeBytes: UInt64?

    init?(_ condition: Condition) {
        guard case .all(let parts) = condition else { return nil }
        for part in parts {
            switch part {
            case .name(.glob(let value)): glob = value
            case .extensions(let values): extensions = values.joined(separator: ", ")
            case .kind(let value): kind = value
            case .age(let bound):
                guard let seconds = bound.olderThanSeconds, bound.newerThanSeconds == nil, bound.basis == .added else { return nil }
                olderThanSeconds = seconds
            case .size(let bound):
                guard let over = bound.overBytes, bound.underBytes == nil else { return nil }
                minSizeBytes = over
            default:
                return nil
            }
        }
    }

    /// Rebuild the condition tree from the form fields; empty fields drop out.
    var condition: Condition {
        var parts: [Condition] = []
        if let kind { parts.append(.kind(kind)) }
        if !glob.isEmpty { parts.append(.name(.glob(glob))) }
        let exts = extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !exts.isEmpty { parts.append(.extensions(exts)) }
        if let seconds = olderThanSeconds, seconds > 0 {
            parts.append(.age(AgeCondition(basis: .added, olderThanSeconds: seconds, newerThanSeconds: nil)))
        }
        if let bytes = minSizeBytes, bytes > 0 {
            parts.append(.size(SizeCondition(overBytes: bytes, underBytes: nil)))
        }
        return .all(parts.isEmpty ? [.kind(.file)] : parts)
    }
}

/// Form fields for the simple-match vocabulary.
private struct ConditionEditor: View {
    @Binding var match: SimpleMatch

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            GridRow {
                Text("Kind").gridColumnAlignment(.trailing).font(.caption)
                Picker("", selection: $match.kind) {
                    Text("Any").tag(FileKind?.none)
                    Text("Files").tag(FileKind?.some(.file))
                    Text("Folders").tag(FileKind?.some(.directory))
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Name glob").font(.caption)
                TextField("*.png", text: $match.glob)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
            GridRow {
                Text("Extensions").font(.caption)
                TextField("dmg, pkg", text: $match.extensions)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
            GridRow {
                Text("Older than").font(.caption)
                AmountUnitPicker(
                    amount: Binding(
                        get: { match.olderThanSeconds.map { UInt64($0) } },
                        set: { match.olderThanSeconds = $0.map(TimeInterval.init) }),
                    units: [("minutes", 60), ("hours", 3600), ("days", 86400), ("weeks", 604_800)],
                    defaultUnit: 86400,
                    offLabel: "any age")
            }
            GridRow {
                Text("Larger than").font(.caption)
                AmountUnitPicker(
                    amount: $match.minSizeBytes,
                    units: [("KB", 1024), ("MB", 1024 * 1024), ("GB", 1024 * 1024 * 1024)],
                    defaultUnit: 1024 * 1024,
                    offLabel: "any size")
            }
        }
        .font(.caption)
    }
}

/// A strict "number + unit" control for thresholds, replacing free-text values
/// like "7d" or "100KB". Off (no threshold) is an explicit state with its own
/// label, entered by clearing the number and left by typing one.
///
/// The selected unit is view state, NOT derived from the amount — deriving it
/// makes the picker snap back whenever the amount is empty or doesn't divide
/// evenly by the chosen unit.
private struct AmountUnitPicker: View {
    @Binding var amount: UInt64?
    let units: [(label: String, scale: UInt64)]
    let offLabel: String
    @State private var unit: UInt64

    init(amount: Binding<UInt64?>, units: [(label: String, scale: UInt64)], defaultUnit: UInt64, offLabel: String) {
        _amount = amount
        self.units = units
        self.offLabel = offLabel
        // Show the stored amount in the largest unit that divides it evenly.
        let stored = amount.wrappedValue ?? 0
        let fitting = units.reversed().first { stored > 0 && stored % $0.scale == 0 }?.scale
        _unit = State(initialValue: fitting ?? defaultUnit)
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("—", value: valueBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Picker("", selection: $unit) {
                ForEach(units, id: \.scale) { unit in
                    Text(unit.label).tag(unit.scale)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: unit) { oldUnit, newUnit in
                // Re-express the same count in the new unit: "7 days" becomes
                // "7 weeks" — the count is what the user typed and keeps.
                if let current = amount, current > 0 {
                    amount = max(current / oldUnit, 1) * newUnit
                }
            }
            if amount == nil || amount == 0 {
                Text(offLabel)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    amount = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this condition")
            }
        }
    }

    private var valueBinding: Binding<Int?> {
        Binding(
            get: {
                guard let amount, amount > 0 else { return nil }
                return Int(amount / unit)
            },
            set: { newValue in
                guard let newValue, newValue > 0 else {
                    amount = nil
                    return
                }
                amount = UInt64(newValue) * unit
            })
    }
}

/// Editable ordered action list.
private struct ActionsEditor: View {
    @Binding var actions: [Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(actions.enumerated()), id: \.offset) { index, _ in
                ActionRowEditor(
                    action: Binding(
                        get: { actions[safe: index] ?? .trash },
                        set: { actions[safe: index] = $0 }),
                    onDelete: { actions.remove(at: index) })
            }
            Menu {
                Button("Move to folder…") { actions.append(.move(MoveSpec(to: "~/"))) }
                Button("Copy to folder…") { actions.append(.copy(MoveSpec(to: "~/"))) }
                Button("Rename…") { actions.append(.rename(RenameSpec(to: "{name}.{ext}"))) }
                Button("Trash") { actions.append(.trash) }
                Button("Run command…") { actions.append(.run(RunSpec(command: "/usr/bin/true"))) }
            } label: {
                Label("Add Action", systemImage: "plus")
                    .font(.caption)
            }
            .fixedSize()
        }
    }
}

/// One action row.
private struct ActionRowEditor: View {
    @Binding var action: Action
    let onDelete: () -> Void

    var body: some View {
        HStack {
            switch action {
            case .move(let spec):
                Label("Move to", systemImage: "arrow.turn.down.right").font(.caption)
                field(spec.to, prompt: "~/folder/{date.modified:yyyy-MM}", help: Self.tokenHelp) {
                    action = .move(MoveSpec(to: $0, onConflict: spec.onConflict))
                }
            case .copy(let spec):
                Label("Copy to", systemImage: "doc.on.doc").font(.caption)
                field(spec.to, prompt: "~/folder/{date.modified:yyyy-MM}", help: Self.tokenHelp) {
                    action = .copy(MoveSpec(to: $0, onConflict: spec.onConflict))
                }
            case .rename(let spec):
                Label("Rename to", systemImage: "pencil").font(.caption)
                field(spec.to, prompt: "{name}.{ext}", help: Self.tokenHelp) {
                    action = .rename(RenameSpec(to: $0))
                }
            case .trash:
                Label("Move to Trash", systemImage: "trash").font(.caption)
                Spacer()
            case .run(let spec):
                Label("Run", systemImage: "terminal").font(.caption)
                field(
                    ([spec.command] + spec.args).joined(separator: " "),
                    prompt: "/absolute/path/to/command --flag",
                    help: "Absolute command path plus arguments; the matched file is appended as the final argument."
                ) { text in
                    let parts = text.split(separator: " ").map(String.init)
                    action = .run(
                        RunSpec(
                            command: parts.first ?? "", args: Array(parts.dropFirst()),
                            timeoutSeconds: spec.timeoutSeconds))
                }
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
        }
    }

    /// The tokens every destination and rename pattern understands.
    private static let tokenHelp =
        "Tokens: {name} the filename without extension · {ext} the extension · "
        + "{date.created|modified|added:FORMAT} e.g. {date.modified:yyyy-MM}"

    private func field(
        _ value: String, prompt: String, help: String, set: @escaping (String) -> Void
    ) -> some View {
        TextField("", text: Binding(get: { value }, set: set), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .help(help)
    }
}

/// Safe collection subscripting for bindings into the draft.
extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set {
            guard indices.contains(index), let newValue else { return }
            self[index] = newValue
        }
    }
}
