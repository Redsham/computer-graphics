#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift_sources=()
native_sources=()

while IFS= read -r -d '' file; do
    case "$file" in
        *.swift) swift_sources+=("$file") ;;
        *.c|*.h|*.cpp|*.hpp|*.metal|*.glsl) native_sources+=("$file") ;;
    esac
done < <(git ls-files -z)

case "${1:-}" in
    --check)
        xcrun swift-format lint --strict --configuration .swift-format "${swift_sources[@]}"

        for file in "${native_sources[@]}"; do
            xcrun clang-format --assume-filename=source.cpp --dry-run --Werror "$file"
        done
        ;;
    "")
        xcrun swift-format format --configuration .swift-format --in-place "${swift_sources[@]}"

        for file in "${native_sources[@]}"; do
            xcrun clang-format --assume-filename=source.cpp -i "$file"
        done
        ;;
    *)
        echo "Usage: $0 [--check]" >&2
        exit 2
        ;;
esac
