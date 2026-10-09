#!/bin/bash
# Builds NotchIsland.app (needs Xcode 26+ for Liquid Glass APIs) and launches it.
set -euo pipefail
cd "$(dirname "$0")"

# Quit any running copy so the new build actually launches.
pkill -x NotchIsland 2>/dev/null || true

swift build -c release

APP="NotchIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS keeps the mic / speech permissions between launches.
codesign --force --deep --sign - --entitlements NotchIsland.entitlements "$APP"

echo "Built $APP"
open "$APP"
