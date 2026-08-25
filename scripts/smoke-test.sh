#!/bin/bash
# smoke-test.sh — drive the built app end to end over whisk://.
#
# `scripts/integration-test.sh` proves the shims behave against the real
# filesystem in a headless one-shot run. This proves the *launched app* does:
# real menu bar session, FSEvents watching, and the whisk:// URL scheme.
#
# It is NOT part of `just check`, and deliberately so. It needs a GUI session to
# launch an LSUIElement app and to register the URL scheme, so it is unreliable
# on a headless CI runner — and a flaky gate is worse than an honest manual one.
# Run it before cutting a release, or after touching the composition root, URL
# handling, or the watcher shim.
#
# Usage: ./scripts/smoke-test.sh        (also: `just smoke`)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${PROJECT_DIR}/build/Whisk.app"
# Match on the full build path, never a bare "Whisk.app": the developer likely
# has an installed copy in /Applications, and this must not drive or kill it.
APP_EXEC="${APP}/Contents/MacOS/Whisk"
PASS=0
FAIL=0
APP_PID=""

TMP="$(mktemp -d /tmp/whisk-smoke.XXXXXX)"
SUITE="whisk-smoke-$$"

cleanup() {
    [ -n "${APP_PID}" ] && kill "${APP_PID}" 2>/dev/null || true
    rm -rf "${TMP}"
    defaults delete "${SUITE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }

INBOX="${TMP}/inbox"
mkdir -p "${INBOX}" "${TMP}/data"
cat > "${TMP}/rules.json" <<'RULES'
{
  version: 1,
  targets: [
    { path: "~/inbox", rules: [
      { id: "sweep-txt", match: { extension: ["txt"] }, actions: [ { move: { to: "~/done" } } ] },
    ]},
  ],
}
RULES

echo "🧪 Whisk smoke test (launched app + whisk:// scheme)"

WHISK_HOME="${TMP}" \
WHISK_RULES_FILE="${TMP}/rules.json" \
WHISK_DATA_DIR="${TMP}/data" \
WHISK_DEFAULTS_SUITE="${SUITE}" \
    "${APP_EXEC}" >/dev/null 2>&1 &
APP_PID=$!
sleep 2

if ! kill -0 "${APP_PID}" 2>/dev/null; then
    bad "the app did not stay running"
    echo "❌ SMOKE TEST FAILED"
    exit 1
fi
ok "app launched and stayed running"

# A new file should be swept by the FSEvents watcher without any prodding.
echo "hello" > "${INBOX}/note.txt"
sleep 5
if [ -f "${TMP}/done/note.txt" ]; then
    ok "FSEvents sweep moved the new file"
else
    bad "FSEvents sweep did not move the file"
fi

# Drive a second file through whisk://sweep (needs the scheme registered for
# the built bundle — `open` against the bundle path registers it).
echo "again" > "${INBOX}/note2.txt"
open -g "whisk://sweep" 2>/dev/null || true
sleep 3
if [ -f "${TMP}/done/note2.txt" ]; then
    ok "whisk://sweep swept on demand"
else
    bad "whisk://sweep had no effect (is another Whisk registered for the scheme?)"
fi

LINES="$(wc -l < "${TMP}/data/activity.jsonl" 2>/dev/null | xargs || echo 0)"
if [ "${LINES}" -ge 2 ]; then
    ok "activity log recorded ${LINES} actions"
else
    bad "activity log holds ${LINES} lines, expected >= 2"
fi

echo ""
if [ "${FAIL}" -gt 0 ]; then
    echo "❌ SMOKE TEST FAILED: ${FAIL} failed, ${PASS} passed"
    exit 1
fi
echo "✅ SMOKE TEST PASSED: ${PASS} checks against the live app"
