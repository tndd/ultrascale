#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-build/Applications.noindex/UltraScale.app}"
mkdir -p "$(dirname "$app")"
app_parent="$(cd "$(dirname "$app")" && pwd -P)"
app_binary="$app_parent/$(basename "$app")/Contents/MacOS/UltraScale"
if [[ "$app_parent/$(basename "$app")" == /Applications/UltraScale.app ]]; then
  printf '本体への直接ビルドは禁止です。./build.sh の後に ./install.sh を使ってください。\n' >&2
  exit 1
fi
# 実行中のバンドルを上書きすると、プロセスと権限登録先の署名が食い違う。
for pid in $(pgrep -x UltraScale || true); do
  running_binary="$(ps -p "$pid" -o comm= || true)"
  if [[ "$running_binary" == "$app_binary" ]]; then
    printf '実行中のUltraScaleは上書きできません。build/へビルドし、アプリ終了後に置き換えてください。\n' >&2
    exit 1
  fi
done
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ImageIO -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo Sources/ImagePipeline.m Sources/FramePresenter.m Sources/DisplayEngine.m Sources/App.m \
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
codesign --force --sign "${ULTRASCALE_SIGNING_IDENTITY:--}" "$app"
if [[ "${ULTRASCALE_SIGNING_IDENTITY:--}" == '-' ]]; then
  printf 'アドホック署名: 更新で権限の再許可が必要になる場合があります。置き換え後は必ずアプリを起動し直してください。\n' >&2
fi
printf 'ビルド完了: %s\n' "$app"
