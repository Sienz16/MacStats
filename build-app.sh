#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="MacStats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacStats "$APP/Contents/MacOS/MacStats"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "Built $APP"
