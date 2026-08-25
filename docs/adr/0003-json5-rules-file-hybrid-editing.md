# ADR 0003 — JSON5 rules file as source of truth, with a narrow GUI editor

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §2, ADR 0001

## Context

Rules must be low-friction to author, versionable, and syncable across
machines (the user's workflow leans on plain files). A config file needs
comments and trailing commas to be pleasant; YAML would require vendoring a
parser under the no-dependency constraint of the pure-swiftc build, and that
parser would itself fall inside the 100% coverage gate.

## Decision

`~/.config/whisk/rules.json`, decoded with Foundation's
`JSONDecoder.allowsJSON5` (comments, trailing commas, unquoted keys — zero
dependencies). The file is the source of truth: vnode-watched, hot-reloaded,
last-good rules kept on parse failure with the diagnostic surfaced. The GUI
editor covers exactly the v1 vocabulary, shows anything richer as read-only
("edit in file"), and writes strict pretty JSON — warning before a save that
would drop hand-written comments.

## Alternatives considered

- YAML — nicer to hand-write, but demands a vendored parser: a large,
  hard-to-cover surface for marginal gain over JSON5.
- Strict JSON — no comments; the seed file and examples want them.
- GUI-only storage (Hazel-style) — opaque, unsyncable, and against the
  file-first philosophy.

## Consequences

### Positive
- Zero parsing dependencies; comments and trailing commas work today.
- Rules diff, sync, and restore like any dotfile.

### Negative / trade-offs
- ~~A GUI save flattens comments (warned, and the file remains authoritative).~~
  Amended by [ADR 0013](0013-comment-preserving-editor-saves.md): saves now
  preserve comments through a lossless document model.
- JSON5 is read-relaxed only; the editor normalizes formatting on save.

### Follow-ups
- None for v1.
