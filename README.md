<div align="center">

<img src="docs/site/icon.png" width="128" alt="Whisk icon" />

# Whisk

**Keep your folders clean, automatically.**

A sleek menu bar utility for macOS that tidies target folders by the rules you
set — a lightweight, scriptable take on Hazel.

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)](#install)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](#development)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![CI](https://github.com/alexnodeland/whisk/actions/workflows/ci.yml/badge.svg)](https://github.com/alexnodeland/whisk/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/alexnodeland/whisk)](https://github.com/alexnodeland/whisk/releases)

</div>

---

Point Whisk at a folder — Downloads, Desktop, an inbox — and give it rules:
*move images to Pictures, sorted by month. Rename screenshots. Trash installers
a week after they land. Run my script on every new zip.* Whisk watches the
folder, sweeps when things change (and as files age), notifies you about what
it did, and keeps everything undoable by preferring the Trash.

## ✨ Features

- **Declarative rules file** — `~/.config/whisk/rules.json` is the source of
  truth: JSON5 (comments + trailing commas), hot-reloaded on every save,
  versionable and syncable. A built-in editor window covers the common cases.
- **Conditions**: name globs & regexes, extensions, file/folder kind, size,
  and age (created / modified / added), nested under `all` / `any` / `not`.
- **Actions**: move/copy with date-pattern destinations (`{date.modified:yyyy-MM}`),
  rename templates, Trash-by-age, and shell commands.
- **Safe by design**: dry-run preview mode, Trash instead of delete, per-file
  cooldowns and action budgets that auto-pause runaway rules, and first-run
  approval for every shell command (argv-only — never a shell string).
- **Notifications** you control, per rule and globally.
- **Scriptable**: `whisk://sweep`, `whisk://pause?minutes=60`, `whisk://resume`,
  `whisk://dry-run` — plus an append-only JSONL activity log.

## 📦 Install

```bash
brew tap alexnodeland/tap
brew install --cask whisk
```

Or download `Whisk-universal.zip` from the
[latest release](https://github.com/alexnodeland/whisk/releases/latest),
unzip, and drag `Whisk.app` to Applications. Builds are currently unsigned;
clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Whisk.app
```

On first launch Whisk writes a starter rules file and asks for access to the
folders your rules target (standard macOS consent prompts).

## 📝 Rules

```json5
// ~/.config/whisk/rules.json — reloaded whenever it changes
{
  version: 1,
  targets: [
    {
      path: "~/Downloads",
      rules: [
        {
          id: "file-images",
          match: { all: [
            { name: { glob: "*.{png,jpg,jpeg,heic}" } },
            { size: { over: "100KB" } },
          ]},
          actions: [
            { move: { to: "~/Pictures/Inbox/{date.modified:yyyy-MM}", onConflict: "rename" } },
          ],
        },
        {
          id: "trash-old-installers",
          match: { all: [
            { extension: ["dmg", "pkg"] },
            { age: { basis: "added", olderThan: "7d" } },
          ]},
          actions: [ { trash: {} } ],
        },
        {
          id: "unpack",
          notify: false,
          match: { extension: ["zip"] },
          actions: [ { run: { command: "/opt/homebrew/bin/my-unpack", timeoutSeconds: 60 } } ],
        },
      ],
    },
  ],
}
```

The full schema lives in [`docs/rfcs/0001-whisk.md`](docs/rfcs/0001-whisk.md).
Rules are applied in order; a file consumed by `move`/`trash` is skipped by
later rules in the same sweep. Shell commands are held until you approve them
once from the menu.

## 🔗 URL scheme

| URL | Effect |
| --- | --- |
| `whisk://sweep` | Sweep every target now |
| `whisk://pause` / `whisk://pause?minutes=60` | Pause (indefinitely / for a while) |
| `whisk://resume` | Resume sweeping |
| `whisk://dry-run?enabled=true` | Toggle preview mode |

## 🛠 Development

```bash
just setup      # one-time: tools + git hooks
just build      # dev build → build/Whisk.app
just test       # unit tests
just check      # the full CI gate (lint, format, shim audit, 100% coverage, integration)
just dev        # build and open
```

Ground truth is the RFC and the ADRs under [`docs/adr/`](docs/adr/); behavior
is specified as Gherkin in [`docs/acceptance/`](docs/acceptance/), each scenario
mapping to an XCTest. See [`CLAUDE.md`](CLAUDE.md) for the architecture rules.

## 🤝 Contributing

Issues and PRs welcome — see [CONTRIBUTING](.github/CONTRIBUTING.md). New
behavior needs a Gherkin scenario and keeps the logic core at 100% coverage.

## 📄 License

[MIT](LICENSE) © alexnodeland
