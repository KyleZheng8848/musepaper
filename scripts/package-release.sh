#!/bin/zsh
set -euo pipefail

# 打出双架构 mac 发布物（Apple Silicon + Intel）：
#   release/Musepaper-<ver>-arm64.{dmg,zip}
#   release/Musepaper-<ver>-x64.{dmg,zip}
#   release/Musepaper-latest-{arm64,x64}.{dmg,zip}
#   release/latest.json
#
# 用法：./scripts/package-release.sh
# 可选：
#   KEEP=20 ./scripts/package-release.sh
#   ARCHS="arm64" ./scripts/package-release.sh
#   ARCHS="arm64 x64" ./scripts/package-release.sh   # 默认

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

"$PROJECT_DIR/scripts/check-version-sync.sh"

VERSION="$(tr -d '[:space:]' < Packaging/VERSION)"
KEEP="${KEEP:-20}"
RELEASE_DIR="$PROJECT_DIR/release"
mkdir -p "$RELEASE_DIR"

typeset -a ARCH_TAGS
if [[ -n "${ARCHS:-}" ]]; then
  for a in ${=ARCHS}; do
    case "$a" in
      arm64|aarch64) ARCH_TAGS+=(arm64) ;;
      x86_64|x64) ARCH_TAGS+=(x64) ;;
      *) print -r -- "不支持的 ARCHS 项：$a" >&2; exit 1 ;;
    esac
  done
else
  ARCH_TAGS=(arm64 x64)
fi

# 去重保序
typeset -a UNIQUE_TAGS
for a in "${ARCH_TAGS[@]}"; do
  found=0
  for b in "${UNIQUE_TAGS[@]:-}"; do
    [[ "$a" == "$b" ]] && { found=1; break }
  done
  (( found )) || UNIQUE_TAGS+=("$a")
done
ARCH_TAGS=("${UNIQUE_TAGS[@]}")

HOST_RAW="$(uname -m)"
case "$HOST_RAW" in
  arm64|aarch64) HOST_TAG="arm64" ;;
  x86_64) HOST_TAG="x64" ;;
  *) HOST_TAG="arm64" ;;
esac

SHARED_BUILD="$(date +%Y%m%d%H%M)"
print -r -- "→ 打包 Musepaper $VERSION (build $SHARED_BUILD)：${ARCH_TAGS[*]}"

DATE="$(python3 - <<'PY'
from pathlib import Path
import re
src = Path('CHANGELOG.md').read_text()
m = re.search(r'^##\s+[0-9.]+\s+[—–-]\s+(\d{4}-\d{2}-\d{2})', src, re.M)
print(m.group(1) if m else '')
PY
)"
[[ -n "$DATE" ]] || DATE="$(date +%Y-%m-%d)"

python3 - <<'PY'
from pathlib import Path
import json, re
src = Path('Sources/Musepaper/Domain/Changelog.swift').read_text()
m = re.search(
    r'ChangelogEntry\(\s*version:\s*"[^"]+"\s*,\s*date:\s*"[^"]+"\s*,\s*highlights:\s*\[(.*?)\]\s*\)',
    src,
    re.S,
)
items = re.findall(r'"((?:\\.|[^"\\])*)"', m.group(1)) if m else []
Path('release/.highlights.json').write_text(json.dumps(items, ensure_ascii=False))
PY

package_one() {
  local arch_tag="$1"
  local app_out="$PROJECT_DIR/dist/Musepaper-$arch_tag.app"

  print -r -- ""
  print -r -- "→ [$arch_tag] 编译"
  ARCH="$arch_tag" BUILD="$SHARED_BUILD" OUT_APP="$app_out" \
    "$PROJECT_DIR/scripts/build-app.sh"

  local dmg_name="Musepaper-${VERSION}-${arch_tag}.dmg"
  local zip_name="Musepaper-${VERSION}-${arch_tag}.zip"
  local dmg_path="$RELEASE_DIR/$dmg_name"
  local zip_path="$RELEASE_DIR/$zip_name"
  local latest_dmg="$RELEASE_DIR/Musepaper-latest-${arch_tag}.dmg"
  local latest_zip="$RELEASE_DIR/Musepaper-latest-${arch_tag}.zip"
  local zip_stage="$PROJECT_DIR/.build/zip-stage-$arch_tag"
  local stage="$PROJECT_DIR/.build/dmg-stage-$arch_tag"

  print -r -- "→ [$arch_tag] 打 zip：$zip_name"
  rm -f "$zip_path"
  rm -rf "$zip_stage"
  mkdir -p "$zip_stage"
  ditto "$app_out" "$zip_stage/Musepaper.app"
  (
    cd "$zip_stage"
    /usr/bin/zip -r -y -q "$zip_path" Musepaper.app
  )
  rm -rf "$zip_stage"

  print -r -- "→ [$arch_tag] 准备 DMG"
  rm -rf "$stage"
  mkdir -p "$stage"
  ditto "$app_out" "$stage/Musepaper.app"
  cp "$PROJECT_DIR/Packaging/mac-first-open.command" "$stage/安装并打开.command"
  chmod +x "$stage/安装并打开.command"
  ln -s /Applications "$stage/Applications"

  print -r -- "→ [$arch_tag] 生成 DMG：$dmg_name"
  rm -f "$dmg_path"
  hdiutil create \
    -volname "Musepaper $VERSION ($arch_tag)" \
    -srcfolder "$stage" \
    -ov -format UDZO \
    "$dmg_path" >/dev/null
  rm -rf "$stage"

  cp -f "$dmg_path" "$latest_dmg"
  cp -f "$zip_path" "$latest_zip"

  hdiutil detach "/Volumes/Musepaper $VERSION ($arch_tag)" -force >/dev/null 2>&1 || true
  local mount
  mount="$(python3 - <<PY
import plistlib, subprocess, time, os
raw = subprocess.check_output(
    ["hdiutil", "attach", "$dmg_path", "-nobrowse", "-readonly", "-plist"],
    stderr=subprocess.DEVNULL,
)
idx = raw.find(b"<plist")
if idx < 0:
    raise SystemExit("no plist from hdiutil attach")
data = plistlib.loads(raw[idx:])
mount = next((e.get("mount-point") for e in data.get("system-entities", []) if e.get("mount-point")), "")
if not mount:
    raise SystemExit("no mount-point")
for _ in range(20):
    if os.path.isdir(os.path.join(mount, "Musepaper.app")):
        break
    time.sleep(0.1)
print(mount)
PY
)"
  if [[ ! -d "$mount/Musepaper.app" ]]; then
    print -r -- "[$arch_tag] DMG 内缺少 Musepaper.app" >&2
    hdiutil detach "$mount" -force >/dev/null 2>&1 || true
    exit 1
  fi
  if [[ ! -f "$mount/安装并打开.command" ]]; then
    print -r -- "[$arch_tag] DMG 内缺少「安装并打开.command」" >&2
    hdiutil detach "$mount" -force >/dev/null 2>&1 || true
    exit 1
  fi
  local dmg_bin_arch
  dmg_bin_arch="$(/usr/bin/lipo -archs "$mount/Musepaper.app/Contents/MacOS/Musepaper" 2>/dev/null || true)"
  case "$arch_tag" in
    arm64)
      if [[ "$dmg_bin_arch" != *arm64* ]]; then
        print -r -- "[$arch_tag] DMG 内二进制不是 arm64：$dmg_bin_arch" >&2
        hdiutil detach "$mount" -force >/dev/null 2>&1 || true
        exit 1
      fi
      ;;
    x64)
      if [[ "$dmg_bin_arch" != *x86_64* ]]; then
        print -r -- "[$arch_tag] DMG 内二进制不是 x86_64：$dmg_bin_arch" >&2
        hdiutil detach "$mount" -force >/dev/null 2>&1 || true
        exit 1
      fi
      ;;
  esac
  hdiutil detach "$mount" -force >/dev/null 2>&1 || true

  print -r -- "→ [$arch_tag] OK · lipo=$dmg_bin_arch"
  ls -lh "$dmg_path" "$zip_path"
}

for tag in "${ARCH_TAGS[@]}"; do
  package_one "$tag"
done

if [[ -d "dist/Musepaper-${HOST_TAG}.app" ]]; then
  rm -rf dist/Musepaper.app
  ditto "dist/Musepaper-${HOST_TAG}.app" dist/Musepaper.app
  print -r -- "→ dist/Musepaper.app ← ${HOST_TAG}"
elif [[ -d "dist/Musepaper-${ARCH_TAGS[1]}.app" ]]; then
  rm -rf dist/Musepaper.app
  ditto "dist/Musepaper-${ARCH_TAGS[1]}.app" dist/Musepaper.app
fi

python3 - <<PY
import json
from pathlib import Path

version = "$VERSION"
build = "$SHARED_BUILD"
date = "$DATE"
host = "$HOST_TAG"
arch_tags = """${ARCH_TAGS[*]}""".split()
highlights = json.loads(Path("release/.highlights.json").read_text())
artifacts = {
    tag: {
        "dmg": f"Musepaper-{version}-{tag}.dmg",
        "zip": f"Musepaper-{version}-{tag}.zip",
        "latestDmg": f"Musepaper-latest-{tag}.dmg",
        "latestZip": f"Musepaper-latest-{tag}.zip",
    }
    for tag in arch_tags
}
manifest = {
    "name": "Musepaper",
    "version": version,
    "build": build,
    "date": date,
    "architectures": arch_tags,
    "arch": host if host in arch_tags else arch_tags[0],
    "artifacts": artifacts,
    "highlights": highlights,
}
Path("release/latest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
Path("release/.highlights.json").unlink(missing_ok=True)
print("→ 写入 release/latest.json")
PY

python3 - <<PY
from pathlib import Path
import re
release = Path("release")
keep = int("$KEEP")
pat = re.compile(r"^Musepaper-(\d+\.\d+\.\d+)-(arm64|x64)\.(dmg|zip)$")
by_arch = {"arm64": set(), "x64": set()}
for p in release.iterdir():
    m = pat.match(p.name)
    if m:
        by_arch[m.group(2)].add(m.group(1))
for arch, versions in by_arch.items():
    ordered = sorted(versions, key=lambda v: tuple(int(x) for x in v.split(".")), reverse=True)
    drop = set(ordered[keep:])
    for p in list(release.iterdir()):
        m = pat.match(p.name)
        if m and m.group(2) == arch and m.group(1) in drop:
            p.unlink()
            print(f"→ 清理旧包 {p.name}")
PY

print -r -- ""
print -r -- "Musepaper $VERSION ($SHARED_BUILD) · ${ARCH_TAGS[*]}"
print -r -- "  $RELEASE_DIR/latest.json"
for tag in "${ARCH_TAGS[@]}"; do
  print -r -- "  $RELEASE_DIR/Musepaper-${VERSION}-${tag}.dmg"
  print -r -- "  $RELEASE_DIR/Musepaper-${VERSION}-${tag}.zip"
done
