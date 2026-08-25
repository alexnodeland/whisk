# ADR 0007 — Shell actions: argv-only execution behind first-run approval

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §4

## Context

`run` is the escape hatch that makes Whisk composable, and also its largest
safety surface: a synced rules file means a tampered file could execute
commands.

## Decision

- argv-only: `command` is an absolute executable path, `args` an array; the
  file path is appended as the final argument and exported as `WHISK_FILE`.
  No shell, no string interpolation.
- First-run approval: the verbatim (command, args) pair is the key; unknown or
  changed keys hold the action, notify, and wait for menu approval. Approvals
  persist; rejection silences for the session.
- Sanitized env (PATH/HOME/WHISK_FILE/WHISK_RULE_ID), cwd = target, timeout
  1–300s with SIGTERM→SIGKILL, output captured (4KB) to the activity log.
  Disabled entirely in dry-run.

## Alternatives considered

- `sh -c` strings — injection by construction; rejected.
- No approval gate — a synced/tampered rules file becomes remote execution.
- Hash-based approval keys — opaque to display; verbatim keys read exactly as
  what will run.

## Consequences

### Positive
- The dangerous path is opt-in twice: once in the file, once in the menu.

### Negative / trade-offs
- Editing a command's args re-triggers approval (deliberate).

### Follow-ups
- None.
