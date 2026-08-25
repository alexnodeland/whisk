#!/bin/bash
# build.sh — Compile Whisk into a macOS .app bundle.
#
# Whisk is a menu-bar app that keeps target folders clean by applying
# user-defined rules (a lightweight Hazel). It builds with pure `swiftc` —
# no Swift Package Manager, no Xcode project. All Sources/*.swift compile as a
# single module (the app).
#
# Usage:
#   ./build.sh                            # Dev build (arm64 only, fast)
#   ./build.sh --release                  # Universal binary (arm64 + x86_64) + ZIP
#   ./build.sh --release --version v1.0.0 # Release build with version injected
#
# Environment variables:
#   CODESIGN_IDENTITY  — Developer ID for signing (omit for ad-hoc)
#   NOTARIZE_PROFILE   — Keychain profile for notarytool (requires CODESIGN_IDENTITY)
#
# Output: ./build/Whisk.app

set -euo pipefail

APP_NAME="Whisk"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
DEPLOY_TARGET="26.0"

RELEASE=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) RELEASE=true; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "🔨 Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

SWIFT_FLAGS=(
    Sources/*.swift
    -parse-as-library
    -framework SwiftUI
    -framework AppKit
    -framework UserNotifications
    -framework ServiceManagement
    -framework CoreServices
    -O
)

if [ "$RELEASE" = true ]; then
    echo "📦 Release build (universal binary)..."

    echo "  Compiling arm64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx${DEPLOY_TARGET} \
        -o "${BUILD_DIR}/${APP_NAME}-arm64"

    echo "  Compiling x86_64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target x86_64-apple-macosx${DEPLOY_TARGET} \
        -o "${BUILD_DIR}/${APP_NAME}-x86_64"

    echo "  Creating universal binary..."
    lipo -create \
        "${BUILD_DIR}/${APP_NAME}-arm64" \
        "${BUILD_DIR}/${APP_NAME}-x86_64" \
        -output "${MACOS}/${APP_NAME}"

    rm "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
else
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx${DEPLOY_TARGET} \
        -o "${MACOS}/${APP_NAME}"
fi

cp Info.plist "${CONTENTS}/Info.plist"

# Determine version: explicit --version > latest git tag > Info.plist default
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || true)
fi
if [ -n "$VERSION" ]; then
    CLEAN_VERSION="${VERSION#v}"
    echo "  Setting version to ${CLEAN_VERSION}..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
fi

# App icon
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "${RESOURCES}/"
fi

# Code signing
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "🔏 Signing with identity: ${CODESIGN_IDENTITY}..."
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime \
        --entitlements ${APP_NAME}.entitlements --timestamp "${APP_BUNDLE}"
else
    codesign --force --sign - --options runtime \
        --entitlements ${APP_NAME}.entitlements "${APP_BUNDLE}"
fi

echo "✅ Built successfully: ${APP_BUNDLE}"

if [ "$RELEASE" = true ]; then
    lipo -info "${MACOS}/${APP_NAME}"

    # Never fall back to "universal" here: the release workflow publishes a
    # deliberately stable-named Whisk-universal.zip for the Homebrew cask, and an
    # untagged local build must not produce a file that looks like that artifact.
    ZIP_NAME="${APP_NAME}-${VERSION:-dev}.zip"
    echo "📦 Creating ${ZIP_NAME}..."
    ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/${ZIP_NAME}"
    echo "✅ Archive: ${BUILD_DIR}/${ZIP_NAME}"

    if [ -n "${CODESIGN_IDENTITY:-}" ] && [ -n "${NOTARIZE_PROFILE:-}" ]; then
        echo "📋 Notarizing..."
        xcrun notarytool submit "${BUILD_DIR}/${ZIP_NAME}" \
            --keychain-profile "$NOTARIZE_PROFILE" --wait
        xcrun stapler staple "${APP_BUNDLE}"
        rm "${BUILD_DIR}/${ZIP_NAME}"
        ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/${ZIP_NAME}"
        echo "✅ Notarized and stapled"
    fi
else
    echo ""
    echo "Run with:  open ${APP_BUNDLE}"
fi
