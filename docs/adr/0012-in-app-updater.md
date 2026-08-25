# ADR 0012 — In-app updater: daily check, opt-in auto-install

- Status: Accepted (supersedes the "defer to v2" decision of ADR 0009)
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: ADR 0009, ADR 0011, NoDoze ADR 0018

## Context

ADR 0009 deferred updating to `brew upgrade`. In practice the tap path grew
real friction on secondary machines: stale tap clones, the new Homebrew
tap-trust prompt, and a re-quarantined bundle after every upgrade. The user
asked for the app to keep itself fresh.

## Decision

Whisk checks GitHub's latest-release API daily and offers the update in the
menu with a notification (once per version). Two settings, both in the menu:
**Check for updates automatically** (default on) and **Install updates
automatically** (default off). Installing downloads the same stable-named
`Whisk-universal.zip` the cask pins, unpacks it, verifies the archive holds a
real `Whisk.app`, swaps the bundle in a detached shell, and relaunches.

The architecture follows the house pattern: `UpdatePlanner` (version ordering,
cadence, payload parsing) and `UpdateCoordinator` (orchestration) are pure and
inside the 100% gate; `UpdateFetcher` (URLSession) and `UpdateInstaller`
(ditto + swap + relaunch) are audited shims.

## Integrity model

Trust anchor is TLS to `github.com` for a hardcoded repo path — exactly the
anchor the Homebrew flow starts from, since the tap's cron reads the same
endpoint to pin its sha256. Ed25519 signature verification (the `.sig` the
release workflow can publish, ADR 0009) remains future work; until then
auto-install stays off by default, and the installer refuses archives that do
not contain `Whisk.app`.

## Alternatives considered

- Stay brew-only — the friction this ADR exists to remove.
- Sparkle — a dependency, against ADR 0001.
- Verify Ed25519 now — no signing key exists in CI yet; shipping the check
  without a key would be theater.

## Consequences

### Positive
- Updates reach every machine without touching a terminal.
- Both channels ship byte-identical archives, so switching between them is safe.

### Negative
- A self-updated app drifts ahead of the cask's pinned version until the next
  `brew upgrade` overwrites it with the same-or-newer build — harmless, but
  `brew list --cask` will under-report the version.
- Ad-hoc signatures change per release, so macOS may re-prompt for folder
  access after an update (same behavior as a brew upgrade).
