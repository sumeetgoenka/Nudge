#!/bin/bash
#
# build.sh — Build AnayHub.app from source without Xcode.
#
# Usage:
#   ./build.sh         # build only
#   ./build.sh run     # build and launch
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AnayHub"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

rm -rf build
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

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
    main.swift
)
swiftc \
    -O \
    -target arm64-apple-macos12.0 \
    -framework Cocoa \
    -o "${MACOS_DIR}/${APP_NAME}" \
    "${SOURCES[@]}"

echo "→ Copying Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

echo "→ Copying launchd template..."
cp com.anayhub.launcher.plist "${RES_DIR}/com.anayhub.launcher.plist"

echo "→ Copying app icon..."
cp AppIcon.icns "${RES_DIR}/AppIcon.icns"

echo "→ Ad-hoc codesigning..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "✓ Built ${APP_DIR}"

if [[ "${1:-}" == "run" ]]; then
    # Kill any previous instance
    pkill -f "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    echo "→ Launching..."
    open "${APP_DIR}"
fi
