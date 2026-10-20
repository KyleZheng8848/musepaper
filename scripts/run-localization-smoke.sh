#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
SMOKE_DIR="$PROJECT_DIR/.build/localization-smoke"
mkdir -p "$SMOKE_DIR" "$PROJECT_DIR/.cache/clang"
SOURCE_FILES=("$PROJECT_DIR"/Sources/Musepaper/**/*.swift "$PROJECT_DIR"/Sources/Shared/**/*.swift)
COMPILE_FILES=()
for source in "${SOURCE_FILES[@]}"; do
  if [[ "${source:t}" != "MusepaperApp.swift" ]]; then
    COMPILE_FILES+=("$source")
  fi
done
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang" swiftc \
  -parse-as-library -swift-version 6 \
  -target "$(uname -m)-apple-macosx14.0" \
  "${COMPILE_FILES[@]}" "$PROJECT_DIR/Tests/Smoke/LocalizationSmoke.swift" \
  -o "$SMOKE_DIR/localization-smoke"
cp -R "$PROJECT_DIR"/Sources/Musepaper/Resources/*.lproj "$SMOKE_DIR/"
MUSEPAPER_LOCALIZATION_RESOURCES="$PROJECT_DIR/Sources/Musepaper/Resources" "$SMOKE_DIR/localization-smoke"
