# ADR 0011 — Distribution: pinned Homebrew cask in alexnodeland/tap

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: ADR 0009, dist/Casks/whisk.rb

## Context

The tap (`alexnodeland/homebrew-tap`) moved to pinned `version` + `sha256`
casks with stable-named release assets, auto-bumped twice daily by its
`scripts/bump.py` cron — because `brew upgrade` skips `:latest` casks and the
checksum is the only integrity check for unsigned apps.

## Decision

Release workflow publishes a stable-named `Whisk-universal.zip` on every `v*`
tag. The cask lives in the tap, pinned, with the standard quarantine caveat;
`dist/Casks/whisk.rb` in this repo is the template whose version/sha256 are
deliberately-drifting placeholders (the tap's copy is live). The cask is added
to the tap once, manually, after the first release; the cron bumps it
thereafter.

## Alternatives considered

- `version :latest` + `sha256 :no_check` — silently skipped by `brew upgrade`,
  and checksum-free; the tap already migrated away from this.
- Homebrew core — needs notability; the personal tap is the house channel.

## Consequences

### Positive
- Releases reach users within ~12h with zero per-release tap work.

### Negative / trade-offs
- The in-repo template drifts from the live cask by design (documented in
  dist/README.md).

### Follow-ups
- None.
