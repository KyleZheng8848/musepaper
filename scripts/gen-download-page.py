#!/usr/bin/env python3
"""Generate self-contained Musepaper download index.html from latest.json."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


def mb(n: int) -> str:
    return f"{n / 1048576:.0f} MB" if n else ""


def render(manifest: dict, *, base_url: str, packs_catalog_url: str, sizes: dict[str, int]) -> str:
    version = html.escape(str(manifest.get("version", "")))
    build = html.escape(str(manifest.get("build", "")))
    date = html.escape(str(manifest.get("date", "")))
    highlights = manifest.get("highlights") or []
    arts = manifest.get("artifacts") or {}

    def url_for(name: str) -> str:
        return base_url + name

    cards = []
    for tag, label, hint in (
        ("arm64", "macOS · Apple Silicon", "M1 / M2 / M3 / M4"),
        ("x64", "macOS · Intel", "Intel 芯片"),
    ):
        block = arts.get(tag) or {}
        dmg = block.get("dmg") or block.get("latestDmg")
        zip_name = block.get("zip") or block.get("latestZip")
        if not dmg:
            continue
        dmg_size = mb(sizes.get(dmg, 0))
        zip_size = mb(sizes.get(zip_name or "", 0))
        cards.append(
            f"""
      <article class="card" data-arch="{html.escape(tag)}">
        <h2>{html.escape(label)}</h2>
        <p class="hint">{html.escape(hint)}</p>
        <a class="btn primary" href="{html.escape(url_for(dmg))}">下载 DMG {html.escape(dmg_size)}</a>
        {f'<a class="btn ghost" href="{html.escape(url_for(zip_name))}">ZIP {html.escape(zip_size)}</a>' if zip_name else ''}
      </article>"""
        )

    hl = "".join(f"<li>{html.escape(str(x))}</li>" for x in highlights)
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Musepaper {version}</title>
  <style>
    :root {{
      --bg: #070809;
      --ink: #f2eee6;
      --muted: rgba(255,255,255,.48);
      --amber: #ed8c33;
      --panel: rgba(255,255,255,.045);
      --border: rgba(255,255,255,.1);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; min-height: 100vh; color: var(--ink);
      font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(900px 420px at 88% -10%, rgba(237,140,51,.14), transparent 60%),
        linear-gradient(180deg, #0b0c0e, var(--bg));
    }}
    main {{ max-width: 920px; margin: 0 auto; padding: 56px 24px 80px; }}
    .brand {{
      font: 600 42px/1.1 "New York", "Iowan Old Style", Georgia, serif;
      letter-spacing: -.02em; margin: 0 0 10px;
    }}
    .lede {{ color: var(--muted); max-width: 36rem; margin: 0 0 28px; }}
    .meta {{ color: var(--muted); font-size: 13px; margin-bottom: 28px; }}
    .meta strong {{ color: var(--ink); }}
    .grid {{ display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }}
    .card {{
      background: var(--panel); border: 1px solid var(--border);
      border-radius: 18px; padding: 22px; display: grid; gap: 10px;
    }}
    .card.recommended {{ border-color: rgba(237,140,51,.55); box-shadow: 0 0 0 1px rgba(237,140,51,.18); }}
    .card h2 {{ margin: 0; font-size: 18px; }}
    .hint {{ margin: 0; color: var(--muted); font-size: 13px; }}
    .badge {{
      display: none; width: fit-content; font-size: 11px; font-weight: 700;
      color: #111; background: var(--amber); border-radius: 999px; padding: 3px 9px;
    }}
    .card.recommended .badge {{ display: inline-block; }}
    .btn {{
      display: inline-flex; align-items: center; justify-content: center;
      min-height: 42px; border-radius: 11px; text-decoration: none; font-weight: 650;
      padding: 0 14px;
    }}
    .btn.primary {{ background: var(--amber); color: #111; }}
    .btn.ghost {{ color: var(--ink); border: 1px solid var(--border); }}
    .notes {{ margin-top: 34px; padding: 18px 20px; border-radius: 16px; background: var(--panel); border: 1px solid var(--border); }}
    .notes h3 {{ margin: 0 0 8px; font-size: 14px; color: var(--muted); letter-spacing: .08em; text-transform: uppercase; }}
    .notes ul {{ margin: 0; padding-left: 1.1rem; }}
    .foot {{ margin-top: 28px; color: var(--muted); font-size: 13px; }}
    .foot a {{ color: var(--ink); }}
    code {{ font-size: 12px; }}
  </style>
</head>
<body>
  <main>
    <p class="meta">Musepaper · AI 壁纸</p>
    <h1 class="brand">下载 Musepaper {version}</h1>
    <p class="lede">原生 macOS 应用。打开 DMG 后请双击「安装并打开.command」，不要直接点未公证的 App。</p>
    <p class="meta">版本 <strong>{version}</strong> · build {build} · {date}</p>
    <div class="grid">
      {''.join(cards)}
    </div>
    {"<section class='notes'><h3>本版要点</h3><ul>" + hl + "</ul></section>" if hl else ""}
    <p class="foot">
      清单：<a href="{html.escape(base_url + "latest.json")}"><code>latest.json</code></a>
      · 壁纸包：<a href="{html.escape(packs_catalog_url)}"><code>packs/catalog.json</code></a>
    </p>
  </main>
  <script>
    (async function () {{
      let arch = null;
      try {{
        if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {{
          const u = await navigator.userAgentData.getHighEntropyValues(["architecture"]);
          if (u.architecture === "arm") arch = "arm64";
          if (u.architecture === "x86") arch = "x64";
        }}
      }} catch (e) {{}}
      if (!arch) {{
        const ua = navigator.userAgent || "";
        if (/Macintosh|Mac OS X/.test(ua)) arch = "arm64"; // 近年 Mac 默认推荐 Apple Silicon
      }}
      if (!arch) return;
      document.querySelectorAll(".card").forEach((el) => {{
        if (el.getAttribute("data-arch") === arch) {{
          el.classList.add("recommended");
          const badge = document.createElement("span");
          badge.className = "badge";
          badge.textContent = "适合这台 Mac";
          el.insertBefore(badge, el.firstChild);
        }}
      }});
    }})();
  </script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--packs-catalog-url", required=True)
    ap.add_argument("--release-dir", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    sizes: dict[str, int] = {}
    for path in args.release_dir.iterdir():
        if path.is_file():
            sizes[path.name] = path.stat().st_size
    html_text = render(
        manifest,
        base_url=args.base_url if args.base_url.endswith("/") else args.base_url + "/",
        packs_catalog_url=args.packs_catalog_url,
        sizes=sizes,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html_text, encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
