#!/usr/bin/env bash
# Builds KomorebiMenubar.app from the SwiftPM executable (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/KomorebiMenubar.app"
# Version from the nearest v* tag (v0.1 -> 0.1) unless VERSION is set; build number = commit count.
VERSION="${VERSION:-$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KomorebiMenubar" "$APP/Contents/MacOS/KomorebiMenubar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally on Apple silicon.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP ($VERSION, build $BUILD)"
