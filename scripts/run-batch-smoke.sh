#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUT="$PROJECT_DIR/.build/smoke/batch-flow-smoke"
mkdir -p "${OUT:h}" "$PROJECT_DIR/.cache/clang"

SOURCE_FILES=("$PROJECT_DIR"/Sources/Musepaper/**/*.swift "$PROJECT_DIR"/Sources/Shared/**/*.swift)
COMPILE_FILES=()
for source in "${SOURCE_FILES[@]}"; do
  if [[ "${source:t}" != "MusepaperApp.swift" ]]; then
    COMPILE_FILES+=("$source")
  fi
done

CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang" swiftc \
  -parse-as-library \
  -swift-version 6 \
  -target "$(uname -m)-apple-macosx14.0" \
  "${COMPILE_FILES[@]}" \
  "$PROJECT_DIR/Tests/Smoke/BatchFlowSmoke.swift" \
  -o "$OUT" -musepaper.interfaceLanguage zh-Hans

"$OUT" -musepaper.interfaceLanguage zh-Hans
