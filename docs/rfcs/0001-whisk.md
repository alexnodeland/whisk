# RFC 0001 — Whisk

- Status: Accepted
- Date: 2026-08-25
- This document is ground truth for Whisk's v1 behavior. Architecture decisions
  are recorded in [`../adr/`](../adr/); acceptance scenarios in
  [`../acceptance/`](../acceptance/).

## 1. Product

Whisk is a macOS menu-bar utility that keeps target directories clean by
applying user-defined rules — a lightweight, scriptable Hazel. The user points
it at folders (Downloads, Desktop, project inboxes), writes rules in a
declarative file (or the built-in editor), and Whisk sweeps those folders when
their contents change, when files age into a rule, and on a safety-net cadence.

Non-goals for v1: recursive folder watching (rules see a target's direct
children only), Spotlight/metadata conditions beyond the schema below, an
in-app updater (ADR 0009), Mac App Store distribution.

## 2. The rules file

`~/.config/whisk/rules.json` — JSON5-relaxed JSON (comments, trailing commas,
unquoted keys; ADR 0003). The file is the source of truth: Whisk hot-reloads it
on every save, and the GUI editor writes strict JSON back to it (warning first
when hand-written comments would be dropped). A parse failure never wipes
state: the last-good rules stay active, the menu shows the diagnostic, and a
notification fires. On first launch, Whisk seeds the file with a disabled
starter rule.

### 2.1 Schema (version 1)

```json5
{
  version: 1,                    // required, must be 1
  defaults: {                    // optional
    cooldownSeconds: 30,         // per-(file, rule) re-trigger guard
    maxActionsPerRule: 100,      // per sweep; exceeding auto-pauses the rule
    maxActionsPerSweep: 500,     // whole-sweep budget
  },
  targets: [                     // required, non-empty; paths unique
    {
      path: "~/Downloads",       // ~ expands to the user's home
      rules: [ /* ordered */ ],
    },
  ],
}
```

Rule:

```json5
{
  id: "unique-across-file",      // required
  name: "Shown in menus",        // optional (falls back to id)
  enabled: true,                 // default true
  notify: true,                  // default true
  match: { /* condition */ },    // required
  actions: [ /* ≥1, ordered */ ],
}
```

Conditions — exactly one key per object, nesting freely:

| Condition | Shape | Semantics |
| --- | --- | --- |
| `all` / `any` | `{ all: [c, …] }` | conjunction / disjunction (non-empty) |
| `not` | `{ not: c }` | negation |
| `name` | `{ name: { glob: "*.png" } }` or `{ name: { regex: "^x" } }` | case-insensitive full-name match; glob supports `*` `?` `[…]` `{a,b}` |
| `extension` | `{ extension: ["dmg", "pkg"] }` | case-insensitive |
| `kind` | `{ kind: "file" \| "directory" }` | |
| `size` | `{ size: { over: "100KB", under: "2GB" } }` | strict bounds; units B/KB/MB/GB (binary) |
| `age` | `{ age: { basis: "added", olderThan: "7d", newerThan: "1h" } }` | basis `created`/`modified`/`added` (default added); units s/m/h/d/w |

Actions — exactly one key per object; `move` and `trash` end the chain (the
parser rejects actions after them); `rename` re-threads the file's projected
path into subsequent actions:

| Action | Shape | Semantics |
| --- | --- | --- |
| `move` / `copy` | `{ move: { to: "~/Pics/{date.modified:yyyy-MM}", onConflict: "rename" } }` | destination is a directory; relative paths resolve against the target; `onConflict` ∈ rename (Finder-style " 2") / skip / replace |
| `rename` | `{ rename: { to: "shot-{date.created:yyyyMMdd}.{ext}" } }` | within the file's directory; conflicts uniquify |
| `trash` | `{ trash: {} }` | macOS Trash, never delete |
| `run` | `{ run: { command: "/abs/path", args: ["-v"], timeoutSeconds: 30 } }` | argv-only; file path appended as final arg; timeout 1–300s |

Templates may use `{name}` (stem), `{ext}` (lowercase), and
`{date.created|modified|added:FORMAT}` (Unicode date format, POSIX locale,
local time zone).

## 3. Sweeping model

A sweep of a target always re-enumerates the directory and plans from that
snapshot (events are only triggers; ADR 0004). Triggers: FSEvents (2s
debounce), an age wake-up timer (the earliest instant any `olderThan` bound
could newly match, clamped 30s–1h), a 30-minute safety-net rescan, launch,
wake-from-sleep, rules reload, `whisk://sweep`, and Run Now (which overrides
pause). Hidden files are excluded. Rules apply in file order; a file consumed
by move/trash is skipped by later rules in that sweep.

## 4. Safety

- **Trash, never delete** (ADR 0008); `replace` conflicts remove exactly the
  one colliding destination entry.
- **Dry-run mode** previews every action into the activity log and
  notifications without touching anything (shell commands do not run).
- **Loop protection** (ADR 0006): FSEvents for paths Whisk itself just wrote
  are dropped (10s window); a (file, rule) pair cools down 30s between
  actions; budgets auto-pause runaway rules (persisted, surfaced in the menu,
  re-enable from there).
- **Shell approval** (ADR 0007): a `run` action executes only after its exact
  (command, args) pair is approved once from the menu; new or changed commands
  are held and notified. Sanitized environment (`PATH`, `HOME`, `WHISK_FILE`,
  `WHISK_RULE_ID`), cwd = the target, SIGTERM→SIGKILL on timeout, output
  captured (4KB) into the activity log.

## 5. Surfaces

- **Menu bar popover**: per-target status (last sweep, action count, TCC
  denial badge), rules-file error badge, Run Now, Pause (1h / indefinite) /
  Resume, dry-run toggle, pending approvals, auto-paused rules, recent
  activity (last 10 + full window), Open Rules File, Edit Rules, notifications
  and launch-at-login toggles.
- **Notifications**: batched per rule per sweep; failures collected; runaway
  pauses, pending approvals, and rules-file errors always notify (subject to
  the global toggle).
- **Activity log**: JSONL at `~/Library/Application Support/Whisk/activity.jsonl`,
  retained min(1000 entries, 30 days).
- **URL scheme**: `whisk://sweep`, `whisk://pause[?minutes=N]`,
  `whisk://resume`, `whisk://dry-run[?enabled=true|false]`.
- **Headless**: `--sweep-once` plus `WHISK_HOME` / `WHISK_RULES_FILE` /
  `WHISK_DATA_DIR` / `WHISK_DEFAULTS_SUITE` env overrides (integration tests).

## 6. Permissions & distribution

Non-sandboxed Developer-ID-style app (ADR 0010): folder access via standard
TCC prompts, surfaced as a "No access" badge when denied. Distributed as a
Homebrew cask in `alexnodeland/tap` plus a GitHub release ZIP (ADR 0011);
unsigned for now, so the cask carries the quarantine caveat.
