# ADR 0001 — Pure swiftc build (no Xcode project, no SPM)

- Status: Accepted
- Date: 2026-08-25
- Deciders: alexnodeland
- Related: NoDoze ADR 0004 (the origin of this convention), ADR 0005

## Context

Whisk follows the house template established by NoDoze and StatusBar: a small
menu-bar app whose entire source fits one module. Xcode projects add merge-hostile
pbxproj churn; SPM adds a package layer that buys nothing for a single-target app
but complicates the custom coverage harness (test.sh compiles a hand-picked
subset of files into an instrumented dylib).

## Decision

All Sources/*.swift compile as one module via `swiftc` in `build.sh`. Tests are
built by `test.sh` as a hand-assembled `.xctest` bundle linking an instrumented
`libWhiskCore.dylib` containing only the files in `logic-manifest.txt`.

## Alternatives considered

- SPM package — standard, but the coverage boundary (ADR 0005) needs file-level
  control over what is compiled and measured; SPM targets are directory-scoped.
- Xcode project — heavyweight, and no one edits this repo in Xcode.

## Consequences

### Positive
- Zero project-file churn; `build.sh` is the whole build story.
- The coverage dylib matches the manifest exactly.

### Negative / trade-offs
- SourceKit reports cross-file "cannot find in scope" noise (no package); only
  `just build` / `just test` are authoritative.

### Follow-ups
- None.
