#!/bin/bash
# integration-test.sh — prove the shims against the real filesystem.
#
# Every other test in this repo runs against fakes. They prove the planner's
# *intent* exhaustively and its *effect* not at all: nothing else runs the real
# FileManager, FSEvents-adjacent metadata reads, or the Trash. This launches the
# built app headlessly (--sweep-once) against temp directories, with every
# state location rerouted through environment overrides:
#
#   WHISK_HOME           — `~` in rules expands here
#   WHISK_RULES_FILE     — the rules file to load
#   WHISK_DATA_DIR       — activity.jsonl location
#   WHISK_DEFAULTS_SUITE — throwaway UserDefaults suite (auto-pause state etc.)
#
# Age conditions use basis "modified" here because `touch -t` can backdate
# mtime; the "added" basis cannot be backdated from a script.
#
# Usage: ./scripts/integration-test.sh        (also: `just integration`)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXEC="${PROJECT_DIR}/build/Whisk.app/Contents/MacOS/Whisk"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }

check() {
    if [ "$1" = true ]; then ok "$2"; else bad "$2"; fi
}

if [ ! -x "${APP_EXEC}" ]; then
    echo "🔨 No build found — building first..."
    (cd "${PROJECT_DIR}" && ./build.sh >/dev/null)
fi

TMP="$(mktemp -d /tmp/whisk-integration.XXXXXX)"
SUITE="whisk-integration-$$"
cleanup() {
    rm -rf "${TMP}"
    defaults delete "${SUITE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

INBOX="${TMP}/inbox"
mkdir -p "${INBOX}" "${TMP}/data"

# ─── Fixture files ────────────────────────────────────────────────────────────
echo "png-bytes" > "${INBOX}/photo.png"
echo "png-bytes" > "${INBOX}/photo 2.png"          # forces conflict uniquing at the destination
mkdir -p "${TMP}/pics"
echo "existing" > "${TMP}/pics/photo.png"
echo "screenshot" > "${INBOX}/Screenshot 2026-01-01.jpg"
echo "installer" > "${INBOX}/old-installer.dmg"
touch -t 202601010000 "${INBOX}/old-installer.dmg"  # far older than 7d
echo "installer" > "${INBOX}/new-installer.dmg"     # fresh: must survive
echo "keep" > "${INBOX}/notes.txt"                  # matches no rule

cat > "${TMP}/rules.json" <<'RULES'
// Integration fixture — exercises move+conflict, rename, and trash-by-age.
{
  version: 1,
  targets: [
    {
      path: "~/inbox",
      rules: [
        {
          id: "file-images",
          match: { extension: ["png"] },
          actions: [ { move: { to: "~/pics" } } ],
        },
        {
          id: "tidy-shots",
          match: { name: { glob: "Screenshot *.jpg" } },
          actions: [ { rename: { to: "shot-{date.modified:yyyyMMdd}.{ext}" } } ],
        },
        {
          id: "trash-old-installers",
          match: { all: [
            { extension: ["dmg"] },
            { age: { basis: "modified", olderThan: "7d" } },
          ]},
          actions: [ { trash: {} } ],
        },
      ],
    },
  ],
}
RULES

echo "🧪 Whisk integration tests (real FileManager, real Trash)"
echo ""
echo "Sweep once over ${INBOX}"

WHISK_HOME="${TMP}" \
WHISK_RULES_FILE="${TMP}/rules.json" \
WHISK_DATA_DIR="${TMP}/data" \
WHISK_DEFAULTS_SUITE="${SUITE}" \
    "${APP_EXEC}" --sweep-once >/dev/null 2>&1

ACTIVITY="${TMP}/data/activity.jsonl"

# ─── Move + conflict uniquing ─────────────────────────────────────────────────
check "$([ -f "${TMP}/pics/photo 2.png" ] && echo true || echo false)" \
    "photo.png moved and uniquified past the existing pics/photo.png"
check "$([ ! -f "${INBOX}/photo.png" ] && echo true || echo false)" \
    "photo.png left the inbox"
check "$([ "$(ls "${TMP}/pics" | wc -l | xargs)" = "3" ] && echo true || echo false)" \
    "pics holds exactly the original + both moved files"

# ─── Rename ───────────────────────────────────────────────────────────────────
RENAMED="$(ls "${INBOX}" | grep -c '^shot-[0-9]\{8\}\.jpg$' || true)"
check "$([ "${RENAMED}" = "1" ] && echo true || echo false)" \
    "screenshot renamed to shot-YYYYMMDD.jpg"

# ─── Trash by age ─────────────────────────────────────────────────────────────
check "$([ ! -f "${INBOX}/old-installer.dmg" ] && echo true || echo false)" \
    "the week-old installer went to the Trash"
check "$([ -f "${INBOX}/new-installer.dmg" ] && echo true || echo false)" \
    "the fresh installer survived"
check "$([ -f "${INBOX}/notes.txt" ] && echo true || echo false)" \
    "unmatched files are untouched"

# ─── Activity log ─────────────────────────────────────────────────────────────
check "$(grep -q '"action":"trash"' "${ACTIVITY}" && grep -q '"outcome":"ok"' "${ACTIVITY}" && echo true || echo false)" \
    "the activity log records the trash with outcome ok"
check "$(grep -q '"action":"move"' "${ACTIVITY}" && echo true || echo false)" \
    "the activity log records the moves"

# ─── Runaway budget auto-pauses the rule ──────────────────────────────────────
echo ""
echo "Runaway budget"
BUDGET_INBOX="${TMP}/budget"
mkdir -p "${BUDGET_INBOX}"
for i in 1 2 3 4 5; do echo x > "${BUDGET_INBOX}/f${i}.txt"; done
cat > "${TMP}/budget-rules.json" <<'RULES'
{
  version: 1,
  defaults: { maxActionsPerRule: 2 },
  targets: [
    { path: "~/budget", rules: [
      { id: "runaway", match: { extension: ["txt"] }, actions: [ { trash: {} } ] },
    ]},
  ],
}
RULES

WHISK_HOME="${TMP}" \
WHISK_RULES_FILE="${TMP}/budget-rules.json" \
WHISK_DATA_DIR="${TMP}/data" \
WHISK_DEFAULTS_SUITE="${SUITE}" \
    "${APP_EXEC}" --sweep-once >/dev/null 2>&1

REMAINING="$(ls "${BUDGET_INBOX}" | wc -l | xargs)"
check "$([ "${REMAINING}" = "3" ] && echo true || echo false)" \
    "only the budget's 2 actions ran (3 files remain)"
PAUSED="$(defaults read "${SUITE}" autoPausedRules 2>/dev/null || true)"
check "$(echo "${PAUSED}" | grep -q runaway && echo true || echo false)" \
    "the rule was auto-paused and persisted"

echo ""
if [ "${FAIL}" -gt 0 ]; then
    echo "❌ INTEGRATION TESTS FAILED: ${FAIL} failed, ${PASS} passed"
    exit 1
fi
echo "✅ INTEGRATION TESTS PASSED: ${PASS} checks against the real filesystem"
