# ADR 0002 — justfile is the primary runner, Makefile mirrors it

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: NoDoze ADR 0005

## Context

The house convention exposes one verb set (setup/build/test/coverage/lint/fmt/
check/…) across every repo. `just` has better ergonomics (recipe listing,
arguments); `make` is muscle memory.

## Decision

`justfile` is canonical. A thin `Makefile` mirrors the same verbs and delegates
to the same scripts. CI calls `just`.

## Alternatives considered

- Makefile only — no recipe args (release version), worse listing.
- justfile only — breaks `make check` muscle memory across the fleet.

## Consequences

### Positive
- One verb set everywhere; either entry point works.

### Negative / trade-offs
- Two files to keep in sync (they only delegate, so drift is unlikely).

### Follow-ups
- None.
