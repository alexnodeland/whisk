# ADR 0004 — FSEvents triggers + timed sweeps; a sweep always re-enumerates

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §3

## Context

Age conditions ("older than 7d") become true with no filesystem event at all,
so event watching alone cannot be the model. FSEvents also coalesces and drops
events under load.

## Decision

Events are only *triggers*. Every sweep re-enumerates the whole target and
plans from that snapshot. Triggers: FSEventStream per target (file-level
events, ~2s latency), a pure age wake-up (`SweepScheduler.nextWakeDelay`
computes the earliest future instant any olderThan bound could newly match,
clamped 30s–1h), a 30-minute safety-net rescan, launch, wake-from-sleep,
rules reload, `whisk://sweep`, and Run Now.

## Alternatives considered

- Event-driven state tracking — fragile against coalescing/drops; the
  re-enumerate model makes missed events free.
- Polling only — either laggy or wasteful; events give responsiveness cheaply.

## Consequences

### Positive
- Missed/coalesced events cost nothing; the planner stays pure (snapshot in,
  plan out).
- Age rules fire close to on time without a tight poll.

### Negative / trade-offs
- A sweep is O(directory size); acceptable for the flat, non-recursive targets
  of v1.

### Follow-ups
- Recursive targets would need per-subtree enumeration budgets first.
