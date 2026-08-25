#!/usr/bin/env python3
"""shim-audit.py — keep the I/O shims from quietly regrowing logic.

The 100% coverage gate is only honest if the excluded files contain no decisions
(ADR 0005). This counts branch points in each excluded shim and holds them to a
recorded budget. It is deliberately a budget and not a ban: a shim legitimately
needs a `guard let` to unwrap a system API, and a `do/catch` around a throwing
call. What it must not do is accumulate them. When this fails, the fix is almost
never to raise the number — it is to lift the decision into a pure, covered file.

SwiftUI views and the composition root are exempt: a view body is branchy by
nature, and its branches are presentation, not policy.

Usage:
    python3 scripts/shim-audit.py [--update]

    --update rewrites the budgets below to the measured values. Use it when you
    have deliberately restructured a shim, and expect the diff to be reviewed.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"

# Max branch points permitted per shim. Lower is better. Raising one is a claim
# that the new branch is mechanism rather than a decision, and that claim belongs
# in the diff — so record the reason next to the number.
BUDGETS = {
    "ActivityStore.swift": 2,
    "CommandRunner.swift": 3,
    # All five are API mechanism, not policy: empty-array guard before
    # FSEventStreamCreate, creation-failure guard, teardown guard, vnode fd
    # guard, and the atomic-save re-arm check. Event-to-target routing (the one
    # real decision) lives in SweepCoordinator.targetRoot, covered.
    "FSEventsWatcher.swift": 5,
    "FileOps.swift": 2,
    "MetadataReader.swift": 1,
    "Notifier.swift": 0,
    # Two ?? fallbacks: the WHISK_RULES_FILE test override, and the XDG
    # convention's XDG_CONFIG_HOME → ~/.config default — wiring, not policy.
    "RulesFileStore.swift": 2,
    "SystemScheduler.swift": 0,
    # The single ?? falls back to UserDefaults.standard when the
    # WHISK_DEFAULTS_SUITE test override is absent — wiring, not policy.
    "SystemServices.swift": 1,
    "UpdateFetcher.swift": 1,
    # All execution-mechanism guards: two launch do/catch, and the unpacked-
    # bundle validity check before anything touches /Applications. Whether to
    # install at all is decided in UpdateCoordinator, covered.
    "UpdateInstaller.swift": 3,
}

# Files where branching is presentation or wiring, not policy.
EXEMPT = {
    "WhiskApp.swift",
    "AppViewModel.swift",
    "MenuContentView.swift",
    "RuleEditorView.swift",
    "ActivityListView.swift",
    "SettingsView.swift",
}

# Constructs that represent a decision the code is making.
#
# Each keyword carries a negative lookahead for a following colon, because Swift
# argument labels are spelled like keywords — `run(cmd, for: file)` is a function
# call, not a loop.
BRANCH_PATTERNS = [
    r"\bif\b(?!\s*:)",
    r"\bguard\b(?!\s*:)",
    r"\bswitch\b(?!\s*:)",
    r"\bcatch\b(?!\s*:)",
    r"\bwhile\b(?!\s*:)",
    r"\bfor\b(?!\s*:)",
    r"\?\?",
]
BRANCH_RE = re.compile("|".join(BRANCH_PATTERNS))


def fail(msg: str) -> NoReturn:
    print(f"❌ SHIM AUDIT FAILED: {msg}")
    sys.exit(1)


def strip_noise(source: str) -> str:
    """Remove comments and string literals so their contents cannot be miscounted."""
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"""(?:.|\n)*?"""', '""', source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    return source


def count_branches(path: Path) -> int:
    return len(BRANCH_RE.findall(strip_noise(path.read_text(encoding="utf-8"))))


def main() -> None:
    update = "--update" in sys.argv[1:]

    missing = [name for name in BUDGETS if not (SOURCES / name).exists()]
    if missing:
        fail(f"budgeted shim(s) no longer in Sources/: {', '.join(sorted(missing))} — remove them from BUDGETS")

    measured = {name: count_branches(SOURCES / name) for name in sorted(BUDGETS)}

    if update:
        text = Path(__file__).read_text(encoding="utf-8")
        for name, count in measured.items():
            text = re.sub(rf'("{re.escape(name)}": )\d+', rf"\g<1>{count}", text)
        Path(__file__).write_text(text, encoding="utf-8")
        print("✅ budgets updated — review the diff")
        return

    over = []
    for name, count in measured.items():
        budget = BUDGETS[name]
        mark = "✅" if count <= budget else "❌"
        slack = "" if count == budget else f"  ({budget - count:+d} vs budget)"
        print(f"  {mark} {name:26} {count:2d} branch points, budget {budget:2d}{slack}")
        if count > budget:
            over.append(f"{name} ({count} > {budget})")

    print()
    if over:
        fail(
            f"{len(over)} shim(s) over budget: {', '.join(over)}.\n"
            "   Lift the decision into a pure, covered file rather than raising the budget."
        )
    print(f"✅ SHIM AUDIT PASSED: {len(measured)} shims within budget ({len(EXEMPT)} view/entry files exempt).")


if __name__ == "__main__":
    main()
