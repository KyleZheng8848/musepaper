#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUT="$PROJECT_DIR/.build/smoke/provider-smoke"
mkdir -p "${OUT:h}" "$PROJECT_DIR/.cache/clang"

CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang" swiftc \
  -swift-version 6 \
  -target "$(uname -m)-apple-macosx14.0" \
  "$PROJECT_DIR/Sources/Musepaper/Localization/AppLanguage.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Localization/L10n.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/ModelConfiguration.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/PromptModelConfiguration.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/PromptDraft.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/Generation.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/InspirationChannel.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Domain/MusepaperError.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Persistence/CredentialStore.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Providers/ImageProvider.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Providers/OpenAIImageProvider.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/GenerationPipeline.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/PromptAgent.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/PromptComposer.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/VariationPlanner.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/DesktopChromeCropper.swift" \
  "$PROJECT_DIR/Sources/Musepaper/Services/WallpaperImageAdapter.swift" \
  "$PROJECT_DIR/Tests/Smoke/ProviderSmoke.swift" \
  -o "$OUT"

"$OUT"
