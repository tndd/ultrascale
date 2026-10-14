#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -I Sources Sources/DisplayEngine.m Tests/EngineTests.m -o build/EngineTests
./build/EngineTests "${1:-}"
./build.sh build/UltraScale.app
./build/UltraScale.app/Contents/MacOS/UltraScale --ui-test "$PWD/build/ui.png"
