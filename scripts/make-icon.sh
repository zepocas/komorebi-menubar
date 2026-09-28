#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg (built-in macOS tools only).
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift Resources/AppIcon.svg "$ICONSET"
iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
echo "Wrote Resources/AppIcon.icns"
