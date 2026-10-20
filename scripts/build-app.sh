#!/bin/zsh
set -euo pipefail

# 编译 Musepaper.app
# 可选：
#   ARCH=arm64|x86_64|x64   目标架构（默认本机）
#   BUILD=202608261400      固定 CFBundleVersion（双架构同号）
#   OUT_APP=/path/to.app    输出路径（默认 dist/Musepaper.app）

PROJECT_DIR="${0:A:h:h}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

RAW_ARCH="${ARCH:-$(uname -m)}"
case "$RAW_ARCH" in
  arm64|aarch64)
    ARCH_TAG="arm64"
    SWIFT_TARGET="arm64-apple-macosx14.0"
    ;;
  x86_64|x64)
    ARCH_TAG="x64"
    SWIFT_TARGET="x86_64-apple-macosx14.0"
    ;;
  *)
    echo "不支持的架构：$RAW_ARCH（用 ARCH=arm64 或 ARCH=x64）" >&2
    exit 1
    ;;
esac

BUILD_DIR="$PROJECT_DIR/.build/app-bundle-$ARCH_TAG"
MODULE_CACHE="$PROJECT_DIR/.cache/clang-$ARCH_TAG"
APP_DIR="${OUT_APP:-$PROJECT_DIR/dist/Musepaper.app}"
TEMP_APP="$BUILD_DIR/Musepaper.app"

mkdir -p "$MODULE_CACHE" "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources" "$PROJECT_DIR/dist"
rm -rf "$TEMP_APP"
mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources"

VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/Packaging/VERSION")"
if ! grep -q "static let marketing = \"$VERSION\"" "$PROJECT_DIR/Sources/Musepaper/Domain/AppVersion.swift"; then
  echo "AppVersion.marketing 必须和 Packaging/VERSION ($VERSION) 一致" >&2
  exit 1
fi
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"

SOURCE_FILES=("$PROJECT_DIR"/Sources/Musepaper/**/*.swift "$PROJECT_DIR"/Sources/Shared/**/*.swift)
print -r -- "→ swiftc ($ARCH_TAG / $SWIFT_TARGET)"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -parse-as-library \
  -swift-version 6 \
  -target "$SWIFT_TARGET" \
  -framework CoreLocation \
  "${SOURCE_FILES[@]}" \
  -o "$TEMP_APP/Contents/MacOS/Musepaper"

# 确认产出架构
BIN_ARCH="$(/usr/bin/lipo -archs "$TEMP_APP/Contents/MacOS/Musepaper" 2>/dev/null || true)"
case "$ARCH_TAG" in
  arm64) EXPECT="arm64" ;;
  x64) EXPECT="x86_64" ;;
esac
if [[ "$BIN_ARCH" != *"$EXPECT"* ]]; then
  echo "产物架构异常：lipo=$BIN_ARCH，期望含 $EXPECT" >&2
  exit 1
fi

cp "$PROJECT_DIR/Packaging/Info.plist" "$TEMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$TEMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$TEMP_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Packaging/Resources/Musepaper.icns" "$TEMP_APP/Contents/Resources/Musepaper.icns"
codesign --force --deep --sign - "$TEMP_APP"

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
mv "$TEMP_APP" "$APP_DIR"

echo "$APP_DIR"
echo "Musepaper $VERSION ($BUILD) · $ARCH_TAG ($BIN_ARCH)"
