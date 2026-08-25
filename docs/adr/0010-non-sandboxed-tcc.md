# ADR 0010 — Non-sandboxed app; folder access via standard TCC prompts

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: RFC 0001 §6

## Context

Whisk's whole job is touching user folders. Distribution is outside the Mac
App Store (Homebrew cask), so the sandbox is optional.

## Decision

`com.apple.security.app-sandbox = false`. Folder access relies on standard TCC
consent (usage strings for Downloads/Desktop/Documents in Info.plist); the
first enumeration of a protected folder triggers the system prompt, and a
denial surfaces as a per-target "No access" badge in the menu rather than a
silent failure. No security-scoped bookmarks (a sandbox mechanism). Full Disk
Access is never required, only documented for exotic locations.

## Alternatives considered

- Sandbox + security-scoped bookmarks — obligatory folder-picker ceremony for
  every target and constant bookmark bookkeeping, for no distribution benefit
  outside MAS.

## Consequences

### Positive
- Targets are just paths in a file; consent stays native and one-time.

### Negative / trade-offs
- No sandbox hardening; mitigated by the shell approval gate (ADR 0007) and
  Trash-only removals (ADR 0008).

### Follow-ups
- Revisit if MAS distribution is ever wanted.
