#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ImageIO -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Sources/DisplayEngine.m Tests/EngineTests.m -o build/EngineTests
./build/EngineTests "${1:-}"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ImageIO -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Tests/PermissionTests.m -o build/PermissionTests
./build/PermissionTests
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 -framework Cocoa -framework CoreImage -framework Metal -I Sources Sources/ImagePipeline.m Tests/ImagePipelineTests.m -o build/ImagePipelineTests
./build/ImagePipelineTests
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework ImageIO -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Tests/SnapshotTests.m -o build/SnapshotTests
./build/SnapshotTests
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Cocoa -framework CoreGraphics -framework ImageIO -framework ScreenCaptureKit -framework MetalKit -framework Metal -framework CoreImage -framework CoreMedia -framework CoreVideo -I Sources Sources/ImagePipeline.m Sources/FramePresenter.m Sources/DisplayEngine.m Tests/AppRecoveryTests.m -o build/AppRecoveryTests
./build/AppRecoveryTests
test_app="$PWD/build/Applications.noindex/UltraScale.app"
trap '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$test_app" >/dev/null 2>&1 || true' EXIT
./build.sh "$test_app"
"$test_app/Contents/MacOS/UltraScale" --ui-test "$PWD/build/ui.png"
