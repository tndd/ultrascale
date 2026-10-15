#!/bin/bash
# 外部画面・画面収録・アクセシビリティ権限を使わない画素検証。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreImage -framework Metal -I Sources \
  Sources/ImagePipeline.m Tests/QualityLab.m -o build/QualityLab
./build/QualityLab "${1:-build/quality-lab}" "${2:-120}" "${3:-}"
