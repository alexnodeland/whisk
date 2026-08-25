# Changelog

All notable changes to Whisk. Full release notes with downloads live on the
[GitHub Releases page](https://github.com/alexnodeland/whisk/releases).

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
