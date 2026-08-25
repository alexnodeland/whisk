# ADR 0009 — Defer the in-app updater to v2; keep releases updater-ready

- Status: Superseded by [ADR 0012](0012-in-app-updater.md)
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: NoDoze ADR 0018, ADR 0011

## Context

NoDoze's updater (release checking, Ed25519 signature verification, atomic
install) is its largest shim surface. Whisk already ships through a tap whose
cron auto-bumps pinned casks within ~12h of a release.

## Decision

v1 updates via `brew upgrade whisk`. The release workflow keeps the optional
Ed25519 digest-signing step (publishing `Whisk-universal.zip.sig` when the
`UPDATE_SIGNING_KEY` secret exists), so a future updater can verify every
release that predates it.

## Alternatives considered

- Ship the updater now — big shim surface, duplicate of brew for this user
  base, delays v1.
- Sparkle — a dependency, against ADR 0001.

## Consequences

### Positive
- v1 stays small; update integrity groundwork costs one CI step.

### Negative / trade-offs
- Non-brew users update manually until v2.

### Follow-ups
- Adopt the NoDoze updater core when v2 wants it.
