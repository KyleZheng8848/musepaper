#!/bin/zsh
set -euo pipefail

# Musepaper 更新表面终检（双架构 mac）。
# 源码版本 = release/latest.json = arm64+x64 产物；可选校验 /Applications。
#
# 用法：./scripts/verify-surface.sh
# 可选：SKIP_APP=1 跳过本机 Applications 校验

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

errors=0
fail() { print -r -- "FAIL  $1" >&2; errors=$((errors + 1)) }
ok() { print -r -- "OK    $1" }
note() { print -r -- "NOTE  $1" }

print -r -- "→ 校验源码版本五处"
if ! "$PROJECT_DIR/scripts/check-version-sync.sh"; then
  fail "check-version-sync 未通过"
else
  ok "源码版本五处一致"
fi

VERSION="$(tr -d '[:space:]' < Packaging/VERSION)"
HOST_RAW="$(uname -m)"
case "$HOST_RAW" in
  arm64|aarch64) HOST_TAG="arm64" ;;
  x86_64) HOST_TAG="x64" ;;
  *) HOST_TAG="arm64" ;;
esac

LATEST_JSON="$PROJECT_DIR/release/latest.json"
if [[ ! -f "$LATEST_JSON" ]]; then
  fail "缺少 release/latest.json（先跑 package-release.sh）"
  LATEST_VER=""
  LATEST_BUILD=""
  ARCH_TAGS=()
else
  eval "$(python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path("release/latest.json").read_text())
ver = data.get("version", "")
build = data.get("build", "")
arches = data.get("architectures")
if not arches:
    # 旧格式单 arch
    a = data.get("arch")
    arches = [a] if a else []
arts = data.get("artifacts") or {}
# 旧格式：artifacts 直接是文件名
if arts and "dmg" in arts and not any(k in arts for k in ("arm64", "x64")):
    tag = data.get("arch") or "arm64"
    arts = {tag: arts}
print(f"LATEST_VER={ver!r}")
print(f"LATEST_BUILD={build!r}")
print("ARCH_TAGS=(" + " ".join(repr(a) for a in arches) + ")")
print("ARTIFACTS_JSON=" + repr(json.dumps(arts, ensure_ascii=False)))
PY
)"
  if [[ "$LATEST_VER" != "$VERSION" ]]; then
    fail "latest.json version=$LATEST_VER != 源码 $VERSION"
  else
    ok "latest.json version = $VERSION (build $LATEST_BUILD)"
  fi
  if (( ${#ARCH_TAGS[@]} == 0 )); then
    fail "latest.json 未声明 architectures"
  else
    ok "architectures = ${ARCH_TAGS[*]}"
  fi
  # 完整发版默认要求双架构
  has_arm=0
  has_x64=0
  for a in "${ARCH_TAGS[@]}"; do
    [[ "$a" == "arm64" ]] && has_arm=1
    [[ "$a" == "x64" ]] && has_x64=1
  done
  if (( has_arm == 0 || has_x64 == 0 )); then
    fail "完整发版需要同时有 arm64 与 x64（当前：${ARCH_TAGS[*]}）"
  else
    ok "双架构齐全（arm64 + x64）"
  fi
fi

for tag in "${ARCH_TAGS[@]:-}"; do
  for kind in dmg zip; do
    ver_file="release/Musepaper-${VERSION}-${tag}.${kind}"
    latest_file="release/Musepaper-latest-${tag}.${kind}"
    for artifact in "$ver_file" "$latest_file"; do
      if [[ ! -f "$artifact" ]]; then
        fail "缺少 $artifact"
      else
        BYTES="$(/usr/bin/stat -f%z "$artifact" 2>/dev/null || echo 0)"
        if (( BYTES < 100000 )); then
          fail "$artifact 过小（${BYTES} bytes）"
        else
          ok "存在 $artifact (${BYTES} bytes)"
        fi
      fi
    done
  done
  if [[ -f "release/Musepaper-${VERSION}-${tag}.dmg" && -f "release/Musepaper-latest-${tag}.dmg" ]]; then
    SZ1="$(/usr/bin/stat -f%z "release/Musepaper-${VERSION}-${tag}.dmg")"
    SZ2="$(/usr/bin/stat -f%z "release/Musepaper-latest-${tag}.dmg")"
    if [[ "$SZ1" != "$SZ2" ]]; then
      fail "latest $tag dmg 大小不一致"
    else
      ok "latest $tag dmg 与版本化包大小一致"
    fi
  fi
done

if [[ -d dist/Musepaper.app ]]; then
  DIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Musepaper.app/Contents/Info.plist 2>/dev/null || true)"
  DIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/Musepaper.app/Contents/Info.plist 2>/dev/null || true)"
  DIST_ARCH="$(/usr/bin/lipo -archs dist/Musepaper.app/Contents/MacOS/Musepaper 2>/dev/null || true)"
  if [[ "$DIST_VER" != "$VERSION" ]]; then
    fail "dist/Musepaper.app 版本 $DIST_VER != $VERSION"
  else
    ok "dist/Musepaper.app = $VERSION ($DIST_BUILD) lipo=$DIST_ARCH"
  fi
  if [[ -n "${LATEST_BUILD:-}" && -n "$DIST_BUILD" && "$DIST_BUILD" != "$LATEST_BUILD" ]]; then
    fail "dist build $DIST_BUILD != latest.json build $LATEST_BUILD"
  fi
  case "$HOST_TAG" in
    arm64)
      [[ "$DIST_ARCH" == *arm64* ]] || fail "本机为 arm64，但 dist 二进制是 $DIST_ARCH"
      ;;
    x64)
      [[ "$DIST_ARCH" == *x86_64* ]] || fail "本机为 x64，但 dist 二进制是 $DIST_ARCH"
      ;;
  esac
else
  fail "缺少 dist/Musepaper.app"
fi

if [[ "${SKIP_APP:-0}" == "1" ]]; then
  note "跳过 /Applications 校验（SKIP_APP=1）"
elif [[ -d /Applications/Musepaper.app ]]; then
  APP_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Musepaper.app/Contents/Info.plist 2>/dev/null || true)"
  if [[ "$APP_VER" != "$VERSION" ]]; then
    fail "/Applications/Musepaper.app = $APP_VER，期望 $VERSION（需 ditto 安装）"
  else
    ok "/Applications/Musepaper.app = $VERSION"
  fi
else
  fail "未安装 /Applications/Musepaper.app（完整更新应装本机）"
fi

print -r -- ""
if (( errors > 0 )); then
  print -r -- "verify-surface 失败（$errors）— 禁止宣称已更新" >&2
  exit 1
fi
print -r -- "verify-surface OK · Musepaper $VERSION · ${ARCH_TAGS[*]:-}"
