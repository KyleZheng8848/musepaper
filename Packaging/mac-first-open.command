#!/bin/bash
# Musepaper 首次安装：拷到「应用程序」、清隔离，并从本终端直接启动。
# 勿用 Finder 双击 Musepaper.app / 勿用 `open`——会走 Gatekeeper，未公证时弹「无法验证」。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/Musepaper.app"
DEST="/Applications/Musepaper.app"
BIN="$DEST/Contents/MacOS/Musepaper"

alert() {
  osascript <<EOF >/dev/null 2>&1 || echo "$1: $2" >&2
display alert "$1" message "$2" as critical
EOF
}

notify() {
  osascript <<EOF >/dev/null 2>&1 || true
display notification "$1" with title "Musepaper"
EOF
}

if [[ ! -d "$SRC" ]]; then
  alert "找不到 Musepaper.app" "请先双击打开 DMG，再在磁盘里运行「安装并打开」。"
  exit 1
fi

notify "正在安装到应用程序文件夹…"
rm -rf "$DEST"
ditto "$SRC" "$DEST"

xattr -cr "$DEST" 2>/dev/null || true
find "$DEST" -print0 | while IFS= read -r -d '' f; do
  xattr -c "$f" 2>/dev/null || true
done
if xattr -lr "$DEST" 2>/dev/null | grep -q 'com.apple.quarantine'; then
  alert "清除隔离失败" "请在终端执行：xattr -cr /Applications/Musepaper.app"
  exit 1
fi

codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

if [[ ! -x "$BIN" ]]; then
  alert "安装失败" "应用程序不完整，请重新下载 DMG 后再试。"
  exit 1
fi

pkill -f '/Applications/Musepaper.app/Contents/MacOS/Musepaper' 2>/dev/null || true
sleep 0.3
notify "正在启动 Musepaper…"
nohup "$BIN" >/dev/null 2>&1 &
disown || true
sleep 1.2

if pgrep -f '/Applications/Musepaper.app/Contents/MacOS/Musepaper' >/dev/null 2>&1; then
  notify "Musepaper 已启动"
  osascript -e 'tell application "Terminal" to close (first window whose name contains "安装并打开")' >/dev/null 2>&1 || true
  exit 0
fi

alert "仍未启动" "请打开「系统设置 → 隐私与安全性」，若看到 Musepaper 被拦截，点「仍要打开」。或把本脚本再运行一次。"
open "x-apple.systempreferences:com.apple.preference.security" >/dev/null 2>&1 || true
exit 1
