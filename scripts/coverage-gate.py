#!/usr/bin/env python3
"""coverage-gate.py — fail unless every in-coverage logic file is 100% covered.

Reads the JSON produced by `xcrun llvm-cov export ... -summary-only` and enforces
a hard 100.0% threshold on REGION, LINE, and FUNCTION coverage for every file in
the report. REGION is primary: line% can read 100% while a branch is unexercised.

Usage:
    python3 scripts/coverage-gate.py .build-tests/cov/cov.json [logic-manifest.txt]
"""

import json
import sys
from pathlib import Path
from typing import NoReturn

THRESHOLD = 100.0

DEFAULT_MANIFEST = Path(__file__).resolve().parent.parent / "logic-manifest.txt"

# Ports.swift is compiled into the dylib but declares only protocols and value
# types — no executable regions — so it never appears in the coverage report and
# is exempt from the required-files pin below.
REGIONLESS_FILES = {"Ports.swift"}


def fail(msg: str) -> NoReturn:
    print(f"❌ COVERAGE GATE FAILED: {msg}")
    sys.exit(1)


def required_files(manifest: Path) -> set[str]:
    """The logic files that must each show up in the report.

    This is the manifest pin (ADR 0005): if a file is silently dropped from the
    dylib invocation it goes missing here and the gate fails, rather than quietly
    shrinking the denominator and reporting a green 100%.
    """
    try:
        raw = manifest.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read logic manifest {manifest}: {exc}")

    names = set()
    for line in raw.splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            names.add(Path(entry).name)
    if not names:
        fail(f"logic manifest {manifest} lists no files")
    return names - REGIONLESS_FILES


def main() -> None:
    if len(sys.argv) not in (2, 3):
        fail("usage: coverage-gate.py <cov.json> [logic-manifest.txt]")
    path = sys.argv[1]
    manifest = Path(sys.argv[2]) if len(sys.argv) == 3 else DEFAULT_MANIFEST
    expected = required_files(manifest)

    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        fail(f"coverage file not found: {path} (did test.sh --coverage run?)")
    except json.JSONDecodeError as exc:
        fail(f"coverage file is not valid JSON: {exc}")

    exports = data.get("data") or []
    if not exports:
        fail("coverage JSON has no `data` exports")

    files = exports[0].get("files") or []
    if not files:
        fail("coverage JSON lists zero files — the dylib/profile did not match any source")

    worst = []
    all_ok = True
    seen = set()
    for entry in files:
        name = entry.get("filename", "<unknown>")
        summary = entry.get("summary", {})
        regions = summary.get("regions", {}).get("percent", 0.0)
        lines = summary.get("lines", {}).get("percent", 0.0)
        functions = summary.get("functions", {}).get("percent", 0.0)

        ok = regions >= THRESHOLD and lines >= THRESHOLD and functions >= THRESHOLD
        short = name.split("/")[-1]
        seen.add(short)
        mark = "✅" if ok else "❌"
        print(f"  {mark} {short:30} region {regions:6.2f}%  line {lines:6.2f}%  func {functions:6.2f}%")
        if not ok:
            all_ok = False
            worst.append(short)

    print()
    missing = expected - seen
    if missing:
        fail(f"required logic file(s) absent from coverage report (silently dropped?): {', '.join(sorted(missing))}")
    if not all_ok:
        fail(f"{len(worst)} file(s) below {THRESHOLD:.0f}%: {', '.join(worst)}")
    print(f"✅ COVERAGE GATE PASSED: all {len(files)} logic files at {THRESHOLD:.0f}% region/line/function.")


if __name__ == "__main__":
    main()
