# Contributing to Whisk

Thanks for helping keep folders clean. Ground truth for behavior is
[`docs/rfcs/0001-whisk.md`](../docs/rfcs/0001-whisk.md) and the ADRs under
[`docs/adr/`](../docs/adr/); read [`CLAUDE.md`](../CLAUDE.md) for the
architecture rules before writing code.

## Setup

```bash
just setup     # brew bundle + git hooks
just check     # the full CI gate — keep it green
```

## The rules that gate every PR

- **The logic core stays at 100%** region/line/function coverage
  (`just coverage`). New Sources files must be classified in
  `logic-manifest.txt` *or* `Tests/CoverageManifestTests.swift`'s exclusions —
  the suite fails until you decide.
- **Shims hold no decisions.** `just shim-audit` budgets each excluded file's
  branch points; lift logic into a covered pure function instead of raising a
  budget.
- **New behavior gets a Gherkin scenario** in `docs/acceptance/` mapping to its
  XCTest, and a line in `traceability.md`.
- **Architecture changes get an ADR** (`docs/adr/0000-template.md`); Accepted
  ADRs are immutable — supersede, don't edit.
- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`); squash-merge
  with the PR number.

## Manual verification

`just smoke` drives the launched app over `whisk://` (needs a GUI session; not
part of `check` on purpose). The release checklist lives in
[`docs/acceptance/traceability.md`](../docs/acceptance/traceability.md).
