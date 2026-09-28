#!/usr/bin/env bash
# Builds KomorebiMenubar.app from the SwiftPM executable (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/KomorebiMenubar.app"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KomorebiMenubar" "$APP/Contents/MacOS/KomorebiMenubar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally on Apple silicon.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
