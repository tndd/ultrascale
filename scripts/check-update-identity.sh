#!/bin/bash
# 許可の引き継ぎ先を変える更新を、本体の終了・置換より前に止める。
set -euo pipefail
candidate="$1"
installed="$2"
[[ -e "$installed" ]] || exit 0
old_requirement="$(codesign -d -r- "$installed" 2>&1 | sed -n 's/^# designated => //p')"
new_requirement="$(codesign -d -r- "$candidate" 2>&1 | sed -n 's/^# designated => //p')"
if [[ -z "$old_requirement" || -z "$new_requirement" ]]; then
  printf '署名の識別条件を取得できないため、更新を中止しました。\n' >&2
  exit 2
fi
if [[ "$old_requirement" != "$new_requirement" ]]; then
  printf '署名の識別が変わり、許可が引き継がれない更新を中止しました。\n同じ証明書で継続署名してください。署名を意図的に切り替える場合だけ --replace-signing-identity を指定できます。\n' >&2
  exit 1
fi
