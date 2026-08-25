# Changelog

All notable changes to Whisk. Full release notes with downloads live on the
[GitHub Releases page](https://github.com/alexnodeland/whisk/releases).

## v0.4.0 — 2026-08-25

- GUI saves preserve hand-written comments (ADR 0013): a lossless document
  model keeps untouched rules verbatim and edited rules' leading comments;
  the "comments will be dropped" dialog is gone
- Editor clarity: an Unsaved-changes badge, a prominent Save with a "Saved"
  confirmation, disabled Save/Revert when clean, an obviously-editable rule
  name field, and token hints on move/rename/run patterns
- Strict threshold pickers: age is a number with minutes/hours/days/weeks,
  size a number with KB/MB/GB — no more "7d"/"100KB" codes in the form
- Settings gains an Activity tab and a shell-approvals manager in Setup
  (pending commands can be approved/rejected, granted ones revoked)
- Fixed: launch could hang on the folder-access consent dialog — macOS
  re-asks after every upgrade of an unsigned build, the first directory read
  blocks inside the dialog, and on the main thread that starved the menu and
  the updater's timers. Target folders are now probed on a background thread
  before sweeping starts. Whisk also opts out of App Nap and re-checks for
  updates on menu open and system wake
- The rules file location honors `XDG_CONFIG_HOME` (default `~/.config`)

## v0.3.0 — 2026-08-25

- Settings window (⌘, from the popover) with General (launch at login,
  notifications, update policy), Appearance (menu bar icon choice, recent-list
  length), Setup (rules file, watched-folder access status, activity log,
  whisk:// reference), and About tabs
- The menu bar popover slims down to its at-a-glance job: status, Run Now,
  pause, dry-run, approvals, recent activity, and Edit Rules — everything
  configuration-shaped moved into Settings
- Appearance options: classic sparkles icon as an alternative to the brand
  whisk, and a configurable recent-actions count (clamped 1–50)

## v0.2.0 — 2026-08-25

- In-app updater (ADR 0012): daily background check against GitHub releases,
  an Install button in the menu with a once-per-version notification, and an
  opt-in "Install updates automatically" switch. Downloads the same
  stable-named zip the Homebrew cask pins.
- Menu bar icon is now the brand whisk (template-drawn, pause bars when
  paused) instead of a generic SF Symbol.
- Readability: popover buttons now draw their own high-contrast bezel — the
  MenuBarExtra window never becomes key, so system bezels rendered their
  washed-out "inactive" look — and accent-tinted text links are gone.

## v0.1.1 — 2026-08-25

- Lower the minimum macOS from 26 to 14 (Sonoma). The 26 floor was inherited
  from the project template, not required by anything Whisk uses — the newest
  APIs in the app (`ContentUnavailableView`, two-parameter `onChange`) are
  macOS 14.

## v0.1.0 — 2026-08-25

- Initial release: rule-based folder cleanup from the menu bar
- Declarative JSON5 rules file at `~/.config/whisk/rules.json`, hot-reloaded,
  with a built-in editor window for the common cases
- Conditions: name glob/regex, extension, kind, size, age (created/modified/added),
  nested `all`/`any`/`not`
- Actions: move/copy with `{date.*}` destination patterns and conflict
  policies, rename templates, Trash-by-age, and approved shell commands
- FSEvents watching with debounce, age-based wake-ups, and a safety-net rescan
- Loop protection: self-write ledger, per-file cooldowns, and action budgets
  that auto-pause runaway rules
- Shell-command safety: argv-only execution, sanitized environment, timeouts,
  and first-run approval from the menu
- Dry-run preview mode, pause/resume (including "for 1 hour"), Run Now
- Per-rule and global notifications
- Activity log (JSONL) with an in-app activity window
- `whisk://` URL scheme: sweep, pause, resume, dry-run
- Launch at login; Homebrew cask distribution
- Project site: one self-contained page with no external requests — the deploy
  workflow fails if that ever stops being true — plus an illustrated README
  with hand-drawn animated SVG diagrams
