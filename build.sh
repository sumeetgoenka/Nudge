#!/bin/bash
#
# build.sh — Build Nudge.app from source without Xcode.
#
# Usage:
#   ./build.sh         # build only
#   ./build.sh run     # build and launch
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Nudge"
APP_DIR="build/${APP_NAME}.app"
STAGING_DIR="build/staging"
CONTENTS="${STAGING_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"
FRAMEWORKS_DIR="${CONTENTS}/Frameworks"

rm -rf build
mkdir -p "${MACOS_DIR}" "${RES_DIR}" "${FRAMEWORKS_DIR}"

echo "→ Compiling Swift sources..."
SOURCES=(
    Sources/Schedule.swift
    Sources/ScheduleStore.swift
    Sources/ProgressStats.swift
    Sources/Corner.swift
    Sources/HUDViews.swift
    Sources/AppDelegate.swift
    Sources/AppDelegate+Expanded.swift
    Sources/AppDelegate+ScheduleEditor.swift
    Sources/AppDelegate+ScheduleCalendar.swift
    Sources/AppDelegate+Progress.swift
    Sources/AppDelegate+Instructions.swift
    Sources/AppDelegate+More.swift
    Sources/AppDelegate+Backlog.swift
    Sources/AppDelegate+Onboarding.swift
    main.swift
)
swiftc \
    -O \
    -target arm64-apple-macos12.0 \
    -framework Cocoa \
    -framework Sparkle \
    -F Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "${MACOS_DIR}/${APP_NAME}" \
    "${SOURCES[@]}"

echo "→ Copying Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

echo "→ Copying app icon..."
cp AppIcon.icns "${RES_DIR}/AppIcon.icns"

echo "→ Embedding Sparkle framework..."
cp -a Sparkle/Sparkle.framework "${FRAMEWORKS_DIR}/"

echo "→ Finalizing .app bundle..."
mv "${STAGING_DIR}" "${APP_DIR}"

SIGN_ID="${SIGN_ID:--}"   # default: ad-hoc. For release: SIGN_ID="Developer ID Application: Sumeet Goenka (G7CS4NV8PF)"

if [[ "$SIGN_ID" == "-" ]]; then
    echo "→ Ad-hoc codesigning..."
    codesign --force --deep --sign - "${APP_DIR}/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
else
    echo "→ Codesigning with Developer ID + hardened runtime..."
    # Sign Sparkle's internal XPC helpers + framework first
    SPARKLE_FW="${APP_DIR}/Contents/Frameworks/Sparkle.framework"
    for xpc in "${SPARKLE_FW}/Versions/B/XPCServices"/*.xpc; do
        [[ -d "$xpc" ]] || continue
        codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$xpc"
    done
    for helper in "${SPARKLE_FW}/Versions/B/Autoupdate" "${SPARKLE_FW}/Versions/B/Updater.app"; do
        [[ -e "$helper" ]] && codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$helper"
    done
    codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$SPARKLE_FW"
    # Sign the main app last
    codesign --force --timestamp --options runtime \
        --entitlements Nudge.entitlements \
        --sign "$SIGN_ID" "${APP_DIR}"
fi

echo "✓ Built ${APP_DIR}"

if [[ "${1:-}" == "run" ]]; then
    # Kill any previous instance
    pkill -f "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    echo "→ Launching..."
    open "${APP_DIR}"
fi
