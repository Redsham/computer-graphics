#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

if [[ $# -gt 0 ]]; then
    print -u2 "Usage: ./scripts/check-engine.sh"
    exit 2
fi

python3 scripts/check-architecture.py
./scripts/format-code.sh --check

engine_derived_data="${TMPDIR:-/tmp}/graphics-engine-check"
xcodebuild -workspace semester-5/GraphicsEngine.xcworkspace -scheme Sandbox \
    -configuration Debug -derivedDataPath "$engine_derived_data" \
    -destination 'platform=macOS,arch=arm64' \
    MTL_ENABLE_DEBUG_INFO=INCLUDE_SOURCE build

MTL_DEBUG_LAYER=1 MTL_CAPTURE_ENABLED=1 xcodebuild \
    -workspace semester-5/GraphicsEngine.xcworkspace -scheme Sandbox \
    -configuration Debug -derivedDataPath "$engine_derived_data" \
    -destination 'platform=macOS,arch=arm64' test

xcodebuild -workspace semester-5/GraphicsEngine.xcworkspace -scheme Sandbox \
    -configuration Release -derivedDataPath "$engine_derived_data" \
    -destination 'platform=macOS,arch=arm64' build
