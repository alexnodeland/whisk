# ADR 0006 — Four independent loop-protection layers

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §4

## Context

Rules can feed themselves: a move into a watched folder re-triggers events; two
targets can move files into each other; a bad rename can oscillate. Any single
guard has holes.

## Decision

Four pure layers in `LoopGuard` + `SweepPlanner`:
1. **Self-write ledger** — FSEvents for paths Whisk itself wrote within 10s are
   dropped.
2. **Per-(file, rule) cooldown** — default 30s between actions by the same rule
   on the same path.
3. **Action budgets** — per-rule (100/sweep; exceeding auto-pauses the rule,
   persisted and surfaced) and per-sweep (500; exceeding truncates the sweep).
4. **Plan-time cycle refusal** — a move/copy whose destination is the source's
   own directory, the source itself, or inside it is refused at planning.

## Alternatives considered

- Ledger only — blind to indirect loops (A→B, B→A between two watched dirs).
- Budgets only — a runaway still performs its budget every sweep forever;
  auto-pause stops it once.

## Consequences

### Positive
- A misconfigured rule degrades into a paused rule and a notification, not a
  filesystem storm.

### Negative / trade-offs
- A legitimately huge one-off cleanup can trip a budget; the fix is Run Now
  after re-enabling, or raising `defaults.maxActionsPerRule`.

### Follow-ups
- None.
