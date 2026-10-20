#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
exec python3 "$PROJECT_DIR/scripts/verify-published.py" "$@"
