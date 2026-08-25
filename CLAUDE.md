# Whisk — Claude Code Context

Whisk is a macOS menu-bar app that keeps target folders clean by applying
user-defined rules (a lightweight Hazel). Ground truth lives in
[`docs/rfcs/0001-whisk.md`](docs/rfcs/0001-whisk.md) and the ADRs under
[`docs/adr/`](docs/adr/). Behaviour is specified as Gherkin in
[`docs/acceptance/`](docs/acceptance/), each scenario mapping to an XCTest.

## Build & Test (primary runner is `just`)

```bash
just setup          # One-time: install just + tools + git hooks
just build          # Dev build (arm64) → build/Whisk.app
just test           # Run unit tests
just coverage       # Tests + HARD 100% coverage gate on the logic layer
just lint           # SwiftLint --strict
just fmt            # swift-format in place
just fmt-check      # Format check (CI)
just check          # lint + fmt + shim-audit + coverage + integration (the CI gate)
just integration    # Headless --sweep-once against real temp dirs and the real Trash
just smoke          # Launch the built app and drive it over whisk:// (GUI session)
just shim-audit     # Fail if an I/O shim has regrown decision logic
just dev            # Build and open the app
just clean          # Remove build artifacts
```

A thin `Makefile` mirrors these (ADR 0002).

## Architecture (hexagonal core + pure planner)

- **Pure `swiftc` build** — no SPM, no Xcode project. The release app compiles
  all `Sources/*.swift` as one module via `build.sh`. (ADR 0001)
- **Logic core (100%-covered):** the heart is
  `SweepPlanner.plan(target, facts, guardState, context) -> SweepPlan` — given a
  metadata snapshot of one directory, produce planned actions, held approvals,
  and rules to auto-pause. `SweepCoordinator` sits above it and owns intent:
  when to sweep (FSEvents debounce, age wake-ups, rescan cadence, whisk://),
  and how plans become effects through the **ports** (protocols in
  `Ports.swift`). Real impls are thin **shims** (excluded from coverage);
  tests use **fakes**.
- **A sweep always re-enumerates the whole target.** FSEvents are triggers,
  never the source of truth — a missed or coalesced event costs nothing.
  (ADR 0004)
- **`AppViewModel` holds no decisions.** It mirrors the coordinator into
  `@Published` properties. If you write an `if` there, the decision belongs in
  the coordinator or a policy type.
- **Loop protection** (ADR 0006): self-write ledger drops FSEvents for paths
  Whisk just wrote; per-(file, rule) cooldowns; per-rule and per-sweep action
  budgets that auto-pause runaways; plan-time cycle refusal for moves into the
  source's own directory or itself.
- **Shell safety** (ADR 0007): argv-only (`command` + `args` array, file path
  appended + `WHISK_FILE`), sanitized env, timeout with SIGTERM→SIGKILL, and a
  first-run approval gate keyed on the verbatim (command, args) pair.
- **Launch wiring lives in `applicationDidFinishLaunching`, never `.onAppear`.**
  `MenuBarExtra` content is built lazily, so `.onAppear` does not fire until
  the popover first opens — which would silently disable the watcher, timers,
  and URL scheme.

## The coverage boundary (read before adding a file)

A file is **in coverage** iff it makes ZERO direct calls to Process /
FileManager / FSEvents / UN* / NSWorkspace / Timer / `Date()` / UserDefaults
and contains ZERO SwiftUI/AppKit view bodies.

[`logic-manifest.txt`](logic-manifest.txt) is the **single source of truth** for
that list. It is read by `test.sh` (what to compile into the coverage dylib), by
`scripts/coverage-gate.py` (which files must appear in the report), and by
`Tests/CoverageManifestTests.swift`, which pins its own copy against it AND
asserts that **every** file in `Sources/` is either in the manifest or in an
explicit `declaredExclusions` entry with a stated reason. Adding a Swift file to
`Sources/` fails the suite until you classify it. If you add a shim, keep it
near zero-branch (decisions get lifted into a tested pure function — see
`FileFacts.fromResource` and `SweepCoordinator.targetRoot`).

## Key gotchas

- **Two compilations of logic files.** The release build compiles them as part
  of the app module; `test.sh` compiles ONLY the manifest's files into
  `libWhiskCore.dylib` (with `-enable-testing`) and the tests
  `@testable import WhiskCore`. Logic files must not reference shim/view types.
- **`.xctest` needs an `Info.plist`.** A `swiftc`-built bundle has none;
  `test.sh` writes it, or `xcrun xctest` fails to locate the executable.
- **REGION coverage is primary** — line% can read 100% with a branch
  unexercised. Avoid unreachable defensive branches in core files (prefer
  `try!` on encodes that cannot fail, non-failable `String(decoding:)`, and
  testable fallbacks) or the gate will flag them.
- **Environment overrides** for headless/integration runs: `WHISK_HOME`,
  `WHISK_RULES_FILE`, `WHISK_DATA_DIR`, `WHISK_DEFAULTS_SUITE`, and the
  `--sweep-once` flag (sweeps once, then exits).
- **SourceKit false positives** — "Cannot find X in scope" across files is
  expected (no SPM package); only `just build` / `just test` matter.

## Coding conventions

- 4-space indentation, 140-char lines (`.swift-format`); SwiftLint `--strict`.
- Logic files import only `Foundation`. Keep SwiftUI/AppKit out of the core.
- `UserDefaults` only behind the `KeyValueStore` port.
