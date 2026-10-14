#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-../UltraScale.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics Sources/DisplayEngine.m Sources/App.m \
  -o "$app/Contents/MacOS/UltraScale"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'ビルド完了: %s\n' "$app"
