# ADR 0013 — Editor saves preserve comments via a lossless document model

- Status: Accepted (amends ADR 0003)
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: ADR 0003, ADR 0005

## Context

ADR 0003 accepted that a GUI save flattens hand-written comments to strict
JSON, behind a warning dialog. In use that was the editor's worst moment: the
dialog is scary, the choice is lose-comments-or-abort, and a file the user
deliberately commented (the whole point of a JSON5 rules file) gets silently
homogenized the first time they touch a checkbox.

## Decision

`RulesText` (in the covered core) parses the rules file into a small lossless
document model — values plus the comments attached to each member and element
— and the editor saves through `RulesText.encode(_:preserving:)`:

- A rule the editor did not change keeps its original node verbatim, inner
  comments included; change detection decodes the original element and
  compares it to the draft.
- An edited rule is regenerated but keeps its leading comments; a deleted rule
  takes its comments with it; rules are matched by `id`, targets by `path`.
- Everything outside `targets` — the header comment, `version`, `defaults`,
  unknown keys — is untouched.
- An unparsable original falls back to strict encoding (nothing to preserve).

Formatting normalizes on save (indentation, trailing commas); comments and
content are what's preserved, not byte-for-byte layout. The warning dialog is
gone; the editor footer states the guarantee instead.

## Alternatives considered

- Keep the warning dialog — the problem, not a solution.
- Byte-surgical text patches — preserves formatting too, but the span
  bookkeeping under reorders/deletes is far more intricate to prove.
- A full JSON5 CST with token-level fidelity — more machinery than the rules
  vocabulary needs; the gate would price it accordingly.

## Consequences

### Positive
- Hand comments and GUI editing finally compose; the hybrid model (ADR 0003)
  loses its sharpest edge.
- The document model is pure, in the 100% gate, and reusable.

### Negative
- Comments inside a rule the editor modified are dropped (its leading comment
  survives); same-line trailing comments re-attach to the following entry.
- Saves normalize formatting, so a diff-conscious user sees whitespace churn
  on first GUI save.
