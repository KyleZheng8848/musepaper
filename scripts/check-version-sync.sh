#!/bin/zsh
set -euo pipefail

# 校验版本三处（+ changelog）一致，形态对齐 CPET check:version。
#   Packaging/VERSION
#   Sources/Musepaper/Domain/AppVersion.swift  marketing
#   Packaging/Info.plist  CFBundleShortVersionString
#   CHANGELOG.md 首条 ## <版本> — <日期>
#   Sources/Musepaper/Domain/Changelog.swift  entries[0]
#   release/latest.json 的 version（存在才校验，且不得比源码新）

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

VERSION="$(tr -d '[:space:]' < Packaging/VERSION)"
errors=0
warn() { print -r -- "WARN  $1" >&2 }
fail() { print -r -- "FAIL  $1" >&2; errors=$((errors + 1)) }
ok() { print -r -- "OK    $1" }

if ! grep -q "static let marketing = \"$VERSION\"" Sources/Musepaper/Domain/AppVersion.swift; then
  fail "AppVersion.marketing 与 Packaging/VERSION ($VERSION) 不一致"
else
  ok "AppVersion.marketing = $VERSION"
fi

PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist 2>/dev/null || true)"
if [[ "$PLIST_VER" != "$VERSION" ]]; then
  fail "Info.plist CFBundleShortVersionString=$PLIST_VER，期望 $VERSION"
else
  ok "Info.plist = $VERSION"
fi

CHANGELOG_HEAD="$(awk '/^##[[:space:]]+/ { print; exit }' CHANGELOG.md)"
if [[ ! "$CHANGELOG_HEAD" =~ ^##[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+[—–-][[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  fail "CHANGELOG.md 首条须为「## x.y.z — YYYY-MM-DD」"
else
  CL_VER="${match[1]}"
  CL_DATE="${match[2]}"
  if [[ "$CL_VER" != "$VERSION" ]]; then
    fail "CHANGELOG.md 首条版本 $CL_VER ≠ $VERSION"
  else
    ok "CHANGELOG.md = $VERSION ($CL_DATE)"
  fi
fi

SWIFT_BLOCK="$(python3 - <<'PY'
from pathlib import Path
import re
src = Path('Sources/Musepaper/Domain/Changelog.swift').read_text()
m = re.search(
    r'ChangelogEntry\(\s*version:\s*"([^"]+)"\s*,\s*date:\s*"([^"]+)"',
    src,
)
if not m:
    raise SystemExit('NO_ENTRY')
print(f"{m.group(1)}|{m.group(2)}")
PY
)" || SWIFT_BLOCK="NO_ENTRY"
if [[ "$SWIFT_BLOCK" == "NO_ENTRY" ]]; then
  fail "Changelog.swift 找不到首条 ChangelogEntry"
else
  SW_VER="${SWIFT_BLOCK%%|*}"
  SW_DATE="${SWIFT_BLOCK##*|}"
  if [[ "$SW_VER" != "$VERSION" ]]; then
    fail "Changelog.swift 首条版本 $SW_VER ≠ $VERSION"
  elif [[ -n "${CL_DATE:-}" && "$SW_DATE" != "$CL_DATE" ]]; then
    fail "Changelog.swift 日期 $SW_DATE ≠ CHANGELOG.md $CL_DATE"
  else
    ok "Changelog.swift = $VERSION ($SW_DATE)"
  fi
fi

if [[ -f release/latest.json ]]; then
  LATEST="$(python3 -c 'import json; print(json.load(open("release/latest.json"))["version"])')"
  if [[ "$LATEST" == "$VERSION" ]]; then
    ok "release/latest.json = $VERSION"
  else
    # 刚 bump、尚未重打包时清单落后是正常的；比源码新才是错误
  python3 - <<PY
def parse(v):
    return tuple(int(x) for x in v.split("."))
src, latest = "$VERSION", "$LATEST"
if parse(latest) > parse(src):
    raise SystemExit(f"latest.json ({latest}) 比源码 ({src}) 还新")
print(f"NOTE  release/latest.json 仍是 {latest}（打包后会更新）")
PY
  fi
fi

if (( errors > 0 )); then
  print -r -- "版本校验失败（$errors）" >&2
  exit 1
fi
print -r -- "版本校验通过：$VERSION"
