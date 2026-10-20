#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
NEW="${1:-}"
NOTES="${2:-}"
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：./scripts/bump-version.sh 0.5.1 [\"要点1|要点2\"]" >&2
  exit 1
fi

TODAY="$(date +%Y-%m-%d)"
if [[ -z "$NOTES" ]]; then
  NOTES="版本 $NEW 发布"
fi

# split notes by |
python3 - <<PY
from pathlib import Path
import re, json

root = Path("$PROJECT_DIR")
version = "$NEW"
date = "$TODAY"
notes = [n.strip() for n in """$NOTES""".split("|") if n.strip()]
if not notes:
    notes = [f"版本 {version} 发布"]

# VERSION + AppVersion + Info.plist
(root / "Packaging/VERSION").write_text(version + "\n")
av = root / "Sources/Musepaper/Domain/AppVersion.swift"
av.write_text(re.sub(
    r'static let marketing = "[^"]+"',
    f'static let marketing = "{version}"',
    av.read_text(),
))
import subprocess
subprocess.check_call([
    "/usr/libexec/PlistBuddy",
    "-c", f"Set :CFBundleShortVersionString {version}",
    str(root / "Packaging/Info.plist"),
])

# CHANGELOG.md prepend
cl = root / "CHANGELOG.md"
body = cl.read_text() if cl.exists() else "# Musepaper — release notes\n"
# strip leading title-only if present; keep rest
rest = body
if rest.lstrip().startswith("#"):
    # keep everything after first heading block's following content
    pass
bullets = "\n".join(f"- {n}" for n in notes)
entry = f"## {version} — {date}\n{bullets}\n"
# Insert after first markdown title line if present
if re.match(r"^#\s", rest):
    lines = rest.splitlines(True)
    # find end of title section (first blank after title, or after first line)
    insert_at = 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1
    # if next is already ## version, we'll prepend before it
    new = "".join(lines[:insert_at]) + "\n" + entry + "\n" + "".join(lines[insert_at:])
else:
    new = f"# Musepaper — release notes\n\n{entry}\n{rest}"
# Avoid duplicate same version at top
new = re.sub(
    rf"(## {re.escape(version)} — [0-9-]+\n(?:- .+\n)+)\n## {re.escape(version)} —",
    rf"## {version} —",
    new,
    count=1,
)
cl.write_text(new)

# Changelog.swift — replace first entry or rewrite array head
swift = root / "Sources/Musepaper/Domain/Changelog.swift"
src = swift.read_text()
highlights = ",\n                ".join(json.dumps(n, ensure_ascii=False) for n in notes)
block = f'''        ChangelogEntry(
            version: "{version}",
            date: "{date}",
            highlights: [
                {highlights}
            ]
        )'''
if "ChangelogEntry(" in src:
    # replace first ChangelogEntry(...) up to next entry or closing ]
    src2, n = re.subn(
        r"ChangelogEntry\(\s*version:\s*\"[^\"]+\"[\s\S]*?\)(?=\s*,\s*\n\s*ChangelogEntry|\s*\n\s*\])",
        block,
        src,
        count=1,
    )
    if n == 0:
        src2 = src.replace(
            "static let entries: [ChangelogEntry] = [",
            "static let entries: [ChangelogEntry] = [\n" + block + ",",
            1,
        )
    swift.write_text(src2)
else:
    raise SystemExit("Changelog.swift 缺少 entries 数组")

print(version)
PY
