# ADR 0005 — Pure planner/effect architecture with a hard 100% coverage gate

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: NoDoze ADR 0006/0012 (origin), CLAUDE.md coverage boundary

## Context

A rule engine that moves and trashes files must be trustworthy. The house
standard (from NoDoze) achieves that by making every decision pure and
measuring it at 100% region/line/function coverage, with I/O confined to
audited near-zero-branch shims.

## Decision

The heart is `SweepPlanner.plan(target, facts, guardState, context) → SweepPlan`;
`SweepCoordinator` owns intent and applies plans through ports (protocols).
`logic-manifest.txt` pins the coverage boundary; `test.sh` compiles exactly
those files into an instrumented dylib; `coverage-gate.py` enforces 100% on
region, line, and function for every manifest file; `CoverageManifestTests`
forces every new Sources file to be classified; `shim-audit.py` holds each shim
to a recorded branch budget.

## Alternatives considered

- Conventional "high" coverage — decays; 100%-on-a-pinned-set is enforceable
  and honest about what is measured.
- Integration-first testing — slower, flakier, and cannot exhaust the
  planner's decision space.

## Consequences

### Positive
- Every destructive decision is exercised by tests before it ever touches a
  real file.

### Negative / trade-offs
- Unreachable defensive branches are forbidden in core files (they read as
  uncovered regions); code must be written coverage-consciously.

### Follow-ups
- None.
