#!/bin/bash
# 本体を混在なく置き換え、起動先を /Applications の1か所に固定する。
set -euo pipefail
cd "$(dirname "$0")"
source_app="$PWD/build/Applications.noindex/UltraScale.app"
target_app=/Applications/UltraScale.app
codesign --verify --strict "$source_app"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")" = local.codex.UltraScale
if [[ $# == 0 ]]; then
  ./scripts/check-update-identity.sh "$source_app" "$target_app"
elif [[ $# != 1 || "$1" != --replace-signing-identity ]]; then
  printf '使い方: ./install.sh [--replace-signing-identity]\n' >&2
  exit 2
fi
running() { ps -ax -o comm= | /usr/bin/awk '$0 == "/Applications/UltraScale.app/Contents/MacOS/UltraScale" {found=1} END {exit !found}'; }
if running; then
  osascript -e 'tell application "/Applications/UltraScale.app" to quit'
  for attempt in {1..20}; do running || break; sleep 0.5; done
  if running; then printf 'UltraScaleが終了していないため更新を中止しました。\n' >&2; exit 1; fi
fi
stage="$(mktemp -d /Applications/.ultrascale-install.XXXXXX)"
installed=0
cleanup() {
  if [[ "$installed" == 0 && -d "$stage/previous.app" && ! -e "$target_app" ]]; then mv "$stage/previous.app" "$target_app"; fi
  if [[ -d "$stage/previous.app" ]]; then
    printf '旧版を保持しています: %s\n' "$stage/previous.app" >&2
  else rm -rf "$stage"; fi
}
trap cleanup EXIT
ditto "$source_app" "$stage/UltraScale.app"
codesign --verify --strict "$stage/UltraScale.app"
mkdir -p build/archives
if [[ -d "$target_app" ]]; then
  ditto -c -k --keepParent "$target_app" "build/archives/installed-$(date +%Y%m%d-%H%M%S).zip"
  mv "$target_app" "$stage/previous.app"
fi
mv "$stage/UltraScale.app" "$target_app"
codesign --verify --strict "$target_app"
installed=1
rm -rf "$stage/previous.app"
registrar=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$registrar" -u "$source_app" >/dev/null 2>&1 || true
"$registrar" -f "$target_app"
# 同じ識別子の起動可能コピーを残さない。再ビルドで再生成できる。
rm -rf "$source_app"
printf '本体を更新しました: %s\n起動: open %s\n署名が変わった場合、権限の再許可が必要です。\n' "$target_app" "$target_app"
