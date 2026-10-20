#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"
exec python3 "$PROJECT_DIR/scripts/publish-wallpaper-pack.py" "$@"
