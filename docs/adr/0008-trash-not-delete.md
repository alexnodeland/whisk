# ADR 0008 — Trash, never delete

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §4

## Context

Automated cleanup must be recoverable; a wrong rule will eventually match the
wrong file.

## Decision

The only removal action a rule can express is `trash`, implemented with
`FileManager.trashItem` (the resulting Trash URL is logged). The internal
`remove` port method exists solely for the explicit `replace` conflict policy,
which removes exactly the one colliding destination entry.

## Alternatives considered

- A `delete` action — unrecoverable; anything a user wants gone forever can go
  via Trash + emptying it, or a `run` command they explicitly approve.

## Consequences

### Positive
- Every Whisk-initiated removal is undoable from the Trash.

### Negative / trade-offs
- Trash grows; that is the user's visible, reversible problem rather than a
  silent destructive one.

### Follow-ups
- None.
