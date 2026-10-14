#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-build/UltraScale.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics Sources/DisplayEngine.m Sources/App.m \
  -o "$app/Contents/MacOS/UltraScale"
cp Info.plist "$app/Contents/Info.plist"
for color in Blue Green; do
  iconset="build/Icon${color}.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "Assets/Icons/Icon${color}.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "Assets/Icons/Icon${color}.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$app/Contents/Resources/Icon${color}.icns"
done
codesign --force --sign - "$app"
printf 'ビルド完了: %s\n' "$app"
