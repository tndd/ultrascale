#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Sources/DisplayEngine.m Tests/EngineTests.m -o build/EngineTests
./build/EngineTests "${1:-}"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 -framework Cocoa -framework CoreImage -framework Metal -I Sources Sources/ImagePipeline.m Tests/ImagePipelineTests.m -o build/ImagePipelineTests
./build/ImagePipelineTests
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Sources/DisplayEngine.m Tests/AppRecoveryTests.m -o build/AppRecoveryTests
./build/AppRecoveryTests
./build.sh build/UltraScale.app
./build/UltraScale.app/Contents/MacOS/UltraScale --ui-test "$PWD/build/ui.png"
