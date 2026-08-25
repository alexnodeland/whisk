# Architecture Decision Records

MADR-style records ([template](0000-template.md)). ADRs are immutable once
Accepted; reversing one means a new superseding ADR.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-pure-swiftc-build.md) | Pure swiftc build (no Xcode project, no SPM) | Accepted |
| [0002](0002-justfile-primary-runner.md) | justfile primary runner, Makefile mirror | Accepted |
| [0003](0003-json5-rules-file-hybrid-editing.md) | JSON5 rules file + narrow GUI editor | Accepted |
| [0004](0004-fsevents-plus-timed-sweeps.md) | FSEvents triggers + timed sweeps | Accepted |
| [0005](0005-planner-effect-architecture-coverage-gate.md) | Pure planner/effect architecture + 100% gate | Accepted |
| [0006](0006-loop-guard-layers.md) | Four loop-protection layers | Accepted |
| [0007](0007-shell-approval-argv-only.md) | Shell actions: argv-only + first-run approval | Accepted |
| [0008](0008-trash-not-delete.md) | Trash, never delete | Accepted |
| [0009](0009-defer-self-updater.md) | Defer the in-app updater to v2 | Accepted |
| [0010](0010-non-sandboxed-tcc.md) | Non-sandboxed; TCC prompts for folder access | Accepted |
| [0011](0011-homebrew-cask-distribution.md) | Pinned Homebrew cask in alexnodeland/tap | Accepted |
