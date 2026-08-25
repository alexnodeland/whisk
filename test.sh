#!/bin/bash
# test.sh — Build and run Whisk's unit tests, with an optional 100% coverage export.
#
# The LOGIC layer (pure, deterministic) — the files listed in logic-manifest.txt —
# is compiled into an instrumented libWhiskCore.dylib. The Tests/ + Tests/Fakes/
# are compiled into an XCTest bundle that links the dylib via
# `@testable import WhiskCore`, and run with `xcrun xctest`. Coverage is measured
# against the dylib so that ONLY logic files count toward the gate (shims/views/
# @main are never compiled here).
#
# Usage:
#   ./test.sh              # build + run tests
#   ./test.sh --coverage   # build + run tests + export .build-tests/cov/cov.json
#
# The hard 100% gate itself lives in scripts/coverage-gate.py (run by `just coverage`).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build-tests"
MODULE="WhiskCore"
DYLIB="${BUILD_DIR}/lib${MODULE}.dylib"
BUNDLE_DIR="${BUILD_DIR}/WhiskTests.xctest"
BUNDLE_EXEC="${BUNDLE_DIR}/Contents/MacOS/WhiskTests"
COV_DIR="${BUILD_DIR}/cov"
TARGET="arm64-apple-macosx14.0"
MANIFEST="${PROJECT_DIR}/logic-manifest.txt"

COVERAGE=false
[[ "${1:-}" == "--coverage" ]] && COVERAGE=true

# ─── The in-coverage logic file manifest ──────────────────────────────────────
# `logic-manifest.txt` is the single source of truth, shared with
# scripts/coverage-gate.py and Tests/CoverageManifestTests.swift. Only the files
# it lists are compiled into WhiskCore, so only they can count toward the gate.
if [ ! -f "${MANIFEST}" ]; then
    echo "❌ Missing ${MANIFEST}"; exit 1
fi
LOGIC_FILES=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [ -n "${line}" ] && LOGIC_FILES+=("${line}")
done < "${MANIFEST}"

if [ "${#LOGIC_FILES[@]}" -eq 0 ]; then
    echo "❌ ${MANIFEST} lists no logic files"; exit 1
fi

SDK_PATH="$(xcrun --show-sdk-path)"
XCODE_DEV="$(xcode-select -p)"
PLATFORM_DIR="${XCODE_DEV}/Platforms/MacOSX.platform/Developer"

echo "🧪 Building ${MODULE} (instrumented) + tests..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS" "${COV_DIR}"

# Resolve manifest paths to absolute and verify they exist.
LOGIC_ABS=()
for f in "${LOGIC_FILES[@]}"; do
    if [ ! -f "${PROJECT_DIR}/${f}" ]; then
        echo "❌ Missing logic file in manifest: ${f}"; exit 1
    fi
    LOGIC_ABS+=("${PROJECT_DIR}/${f}")
done

# ─── Step 1: instrumented logic dylib (coverage map lives here) ───────────────
swiftc \
    -profile-generate -profile-coverage-mapping -enable-testing \
    -emit-library -emit-module -module-name "${MODULE}" \
    -target "${TARGET}" -sdk "${SDK_PATH}" \
    -Xlinker -install_name -Xlinker "@rpath/lib${MODULE}.dylib" \
    -o "${DYLIB}" \
    "${LOGIC_ABS[@]}"

# ─── Step 2: instrumented xctest bundle linking the dylib ─────────────────────
TEST_FILES=("${PROJECT_DIR}"/Tests/*.swift "${PROJECT_DIR}"/Tests/Fakes/*.swift)
swiftc \
    -profile-generate -profile-coverage-mapping -module-name WhiskTests \
    -target "${TARGET}" -sdk "${SDK_PATH}" \
    -I "${BUILD_DIR}" -L "${BUILD_DIR}" -l"${MODULE}" \
    -I "${PLATFORM_DIR}/usr/lib" \
    -F "${PLATFORM_DIR}/Library/Frameworks" -framework XCTest \
    -L "${PLATFORM_DIR}/usr/lib" -lXCTestSwiftSupport \
    -Xlinker -bundle \
    -Xlinker -rpath -Xlinker "${PLATFORM_DIR}/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "${PLATFORM_DIR}/usr/lib" \
    -Xlinker -rpath -Xlinker "@loader_path/../../../" \
    -o "${BUNDLE_EXEC}" \
    "${TEST_FILES[@]}"

# ─── Step 2b: the Info.plist the bundle requires (swiftc emits none) ──────────
cat > "${BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>WhiskTests</string>
  <key>CFBundleIdentifier</key><string>com.alexnodeland.WhiskTests</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST

echo "✅ Compiled successfully"
echo ""
echo "🏃 Running tests..."
echo ""

# ─── Step 3: run with a unique profraw per process ────────────────────────────
# CoverageManifestTests reads this and asserts it matches the list compiled into
# the tests, so a logic file can never join the dylib without being declared.
WHISK_LOGIC_MANIFEST="$(
    IFS=:
    echo "${LOGIC_FILES[*]}"
)"
export WHISK_LOGIC_MANIFEST
export WHISK_PROJECT_DIR="${PROJECT_DIR}"
EXIT_CODE=0
LLVM_PROFILE_FILE="${COV_DIR}/whisk-%p.profraw" \
    xcrun xctest "${BUNDLE_DIR}" || EXIT_CODE=$?

if [ "${EXIT_CODE}" -ne 0 ]; then
    echo ""
    echo "❌ Some tests failed."
    exit "${EXIT_CODE}"
fi
echo ""
echo "✅ All tests passed!"

if [ "${COVERAGE}" = true ]; then
    echo ""
    echo "📊 Exporting coverage..."
    # ─── Step 4: assert a profraw was produced, then merge ────────────────────
    if ! ls "${COV_DIR}"/*.profraw >/dev/null 2>&1; then
        echo "❌ FAIL: no .profraw produced — instrumentation did not run."
        exit 1
    fi
    xcrun llvm-profdata merge -sparse "${COV_DIR}"/*.profraw -o "${COV_DIR}/whisk.profdata"

    # ─── Step 5: export per-file summary, pointed at the DYLIB ────────────────
    xcrun llvm-cov export "${DYLIB}" \
        -instr-profile="${COV_DIR}/whisk.profdata" \
        -ignore-filename-regex='(Tests/)' \
        -summary-only > "${COV_DIR}/cov.json"
    echo "✅ Coverage exported to ${COV_DIR}/cov.json"
fi
