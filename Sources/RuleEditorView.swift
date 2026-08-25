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
    @State private var confirmCommentLoss = false

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
        .onChange(of: model.ruleSet) { _, newValue in draft = newValue }
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
            HStack {
                Text(model.rulesPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Revert") { draft = model.ruleSet }
                Button("Save") {
                    if model.rulesFileHasComments {
                        confirmCommentLoss = true
                    } else {
                        save()
                    }
                }
                .keyboardShortcut("s")
            }
            .padding(10)
        }
        .confirmationDialog(
            "The rules file contains comments. Saving from the editor writes strict JSON and removes them.",
            isPresented: $confirmCommentLoss
        ) {
            Button("Save and drop comments", role: .destructive) { save() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save() {
        guard let draft else { return }
        model.saveRules(draft)
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
                TextField("Rule name", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.headline)
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
    var olderThan = ""
    var minSize = ""

    init?(_ condition: Condition) {
        guard case .all(let parts) = condition else { return nil }
        for part in parts {
            switch part {
            case .name(.glob(let value)): glob = value
            case .extensions(let values): extensions = values.joined(separator: ", ")
            case .kind(let value): kind = value
            case .age(let bound):
                guard let seconds = bound.olderThanSeconds, bound.newerThanSeconds == nil, bound.basis == .added else { return nil }
                olderThan = Units.formatDuration(seconds)
            case .size(let bound):
                guard let over = bound.overBytes, bound.underBytes == nil else { return nil }
                minSize = Units.formatSize(over)
            default:
                return nil
            }
        }
    }

    /// Rebuild the condition tree from the form fields; unparsable fields drop out.
    var condition: Condition {
        var parts: [Condition] = []
        if let kind { parts.append(.kind(kind)) }
        if !glob.isEmpty { parts.append(.name(.glob(glob))) }
        let exts = extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !exts.isEmpty { parts.append(.extensions(exts)) }
        if let seconds = Units.duration(olderThan) {
            parts.append(.age(AgeCondition(basis: .added, olderThanSeconds: seconds, newerThanSeconds: nil)))
        }
        if let bytes = Units.size(minSize) {
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
                TextField("7d", text: $match.olderThan)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 80)
            }
            GridRow {
                Text("Larger than").font(.caption)
                TextField("100KB", text: $match.minSize)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 80)
            }
        }
        .font(.caption)
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
                field(spec.to) { action = .move(MoveSpec(to: $0, onConflict: spec.onConflict)) }
            case .copy(let spec):
                Label("Copy to", systemImage: "doc.on.doc").font(.caption)
                field(spec.to) { action = .copy(MoveSpec(to: $0, onConflict: spec.onConflict)) }
            case .rename(let spec):
                Label("Rename to", systemImage: "pencil").font(.caption)
                field(spec.to) { action = .rename(RenameSpec(to: $0)) }
            case .trash:
                Label("Move to Trash", systemImage: "trash").font(.caption)
                Spacer()
            case .run(let spec):
                Label("Run", systemImage: "terminal").font(.caption)
                field(([spec.command] + spec.args).joined(separator: " ")) { text in
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

    private func field(_ value: String, set: @escaping (String) -> Void) -> some View {
        TextField("", text: Binding(get: { value }, set: set))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
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
