#!/usr/bin/env python3
"""Generate self-contained Musepaper download index.html from latest.json.

Page shape follows CPET: stable latest-* links, install note, changelog,
version history, then footer. Visual language stays Musepaper (amber / paper).
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_page_theme import (
    APP_ACCENTS,
    release_app_header,
    release_hub_footer,
    release_page_css,
    release_page_decor,
)

ARTIFACT_RE = re.compile(
    r"^Musepaper-(\d+\.\d+\.\d+(?:-[\w.]+)?)-(arm64|x64)\.(dmg|zip)$",
    re.I,
)
CHANGELOG_HEAD = re.compile(r"^##\s+(.+?)\s+[—–-]\s+(\d{4}-\d{2}-\d{2})\s*$")
HISTORY_LIMIT = 16

PAGE_COPY = {
    "tagline": "Mac 动态壁纸 · 用 AI 生成",
    "intro": (
        "Musepaper 把 AI 生成的图片变成会动的 Mac 桌面壁纸。"
        "支持多种光影效果，Intel 和 Apple 芯片 Mac 都能用。"
    ),
}

PAGE_SCREENSHOTS = [
    {
        "remote_name": "ui-main.png",
        "alt": "Musepaper 主界面",
        "caption": "主窗口：选壁纸、调光影效果",
    },
]


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def mb(n: int) -> str:
    return f"{n / 1048576:.0f} MB" if n else ""


def version_key(ver: str) -> tuple:
    core, _, pre = ver.partition("-")
    nums = tuple(int(p) if p.isdigit() else 0 for p in core.split("."))
    return (nums, pre == "", pre)


def format_date(raw: str) -> str:
    raw = (raw or "").strip()
    match = re.match(r"^(\d{4})-(\d{2})-(\d{2})", raw)
    if not match:
        return raw
    year, month, day = match.groups()
    return f"{int(year)}/{int(month)}/{int(day)}"


def parse_changelog(markdown: str) -> list[dict]:
    entries: list[dict] = []
    current: dict | None = None
    for line in markdown.splitlines():
        head = CHANGELOG_HEAD.match(line)
        if head:
            if current:
                entries.append(current)
            current = {
                "version": head.group(1).strip(),
                "date": head.group(2),
                "highlights": [],
            }
            continue
        if current is None:
            continue
        bullet = re.match(r"^[-*]\s+(.*\S)\s*$", line)
        if bullet:
            current["highlights"].append(bullet.group(1).replace("`", ""))
    if current:
        entries.append(current)
    return entries


def collect_versioned_files(release_dir: Path, extra: list[dict] | None = None) -> dict[str, int]:
    files: dict[str, int] = {}
    if release_dir.is_dir():
        for path in release_dir.iterdir():
            if path.is_file() and ARTIFACT_RE.match(path.name):
                files[path.name] = path.stat().st_size
    for item in extra or []:
        name = str(item.get("name") or "")
        if name and ARTIFACT_RE.match(name):
            files.setdefault(name, int(item.get("size") or 0))
    return files


def history_entries(files: dict[str, int], *, base_url: str, limit: int = HISTORY_LIMIT) -> list[dict]:
    by_version: dict[str, list[dict]] = {}
    for name, size in files.items():
        hit = ARTIFACT_RE.match(name)
        if not hit or hit.group(3).lower() != "dmg":
            continue
        arch = hit.group(2).lower()
        by_version.setdefault(hit.group(1), []).append(
            {
                "label": "Apple Silicon" if arch == "arm64" else "Intel",
                "url": base_url + name,
                "size": size,
            }
        )
    versions = sorted(by_version, key=version_key, reverse=True)
    history = []
    for ver in versions[:limit]:
        chips = sorted(by_version[ver], key=lambda f: f["label"])
        if chips:
            history.append({"version": ver, "files": chips})
    return history


def featured_packs(catalog: dict | None) -> list[dict]:
    if not catalog:
        return []
    packs = []
    for pack in catalog.get("packs") or []:
        stats = pack.get("stats") or {}
        count = int(stats.get("artworkCount") or 0)
        if count < 10:
            continue
        packs.append(
            {
                "name": pack.get("name") or pack.get("packId") or "未命名",
                "count": count,
                "bytes": int(stats.get("bytes") or 0),
                "createdAt": pack.get("createdAt") or "",
            }
        )
    return packs


def load_json(path: Path | None) -> dict | list | None:
    if path is None or not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


JS = """
    (async function () {
      let arch = null;
      try {
        if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
          const u = await navigator.userAgentData.getHighEntropyValues(["architecture"]);
          if (u.architecture === "arm") arch = "arm64";
          if (u.architecture === "x86") arch = "x64";
        }
      } catch (e) {}
      if (!arch) {
        const ua = navigator.userAgent || "";
        if (/Macintosh|Mac OS X/.test(ua)) arch = "arm64";
      }
      if (!arch) return;
      document.querySelectorAll(".card[data-arch]").forEach((el) => {
        if (el.getAttribute("data-arch") === arch) el.classList.add("recommended");
      });
    })();
"""


def screenshots_html(shots: list[dict]) -> str:
    if not shots:
        return ""
    figures = []
    for shot in shots:
        url = str(shot.get("url") or "")
        if not url:
            continue
        alt = esc(shot.get("alt") or "界面截图")
        cap = shot.get("caption")
        cap_html = f"<figcaption>{esc(cap)}</figcaption>" if cap else ""
        figures.append(
            f"<figure><img src=\"{esc(url)}\" alt=\"{alt}\" loading=\"lazy\">{cap_html}</figure>"
        )
    if not figures:
        return ""
    return f"""
  <section>
    <h2>界面预览</h2>
    <div class="shots">{''.join(figures)}</div>
  </section>"""


def default_screenshots(base_url: str, version: str) -> list[dict]:
    if not base_url.endswith("/"):
        base_url += "/"
    out = []
    for item in PAGE_SCREENSHOTS:
        out.append(
            {
                "url": f"{base_url}assets/screenshots/{item['remote_name']}?v={version}",
                "alt": item.get("alt") or "",
                "caption": item.get("caption") or "",
            }
        )
    return out


def render(
    manifest: dict,
    *,
    base_url: str,
    packs_catalog_url: str,
    sizes: dict[str, int],
    history: list[dict],
    packs: list[dict],
    icon_url: str = "",
    screenshots: list[dict] | None = None,
) -> str:
    version = str(manifest.get("version") or "")
    build = str(manifest.get("build") or "")
    shots = screenshots if screenshots is not None else default_screenshots(base_url, version)
    screenshots_block = screenshots_html(shots)
    date = format_date(str(manifest.get("date") or ""))
    highlights = [str(x) for x in (manifest.get("highlights") or []) if str(x).strip()]
    arts = manifest.get("artifacts") or {}

    cards: list[str] = []
    for tag, label, hint in (
        ("arm64", "macOS · Apple Silicon", "M1 / M2 / M3 / M4"),
        ("x64", "macOS · Intel", "Intel 芯片"),
    ):
        block = arts.get(tag) or {}
        dmg = block.get("latestDmg") or block.get("dmg")
        zip_name = block.get("latestZip") or block.get("zip")
        if not dmg:
            continue
        dmg_size = mb(sizes.get(dmg, 0) or sizes.get(block.get("dmg") or "", 0))
        zip_size = mb(sizes.get(zip_name or "", 0) or sizes.get(block.get("zip") or "", 0))
        zip_link = (
            f'<a class="alt" href="{esc(base_url + zip_name)}" download>免挂载 zip · {esc(zip_size)}</a>'
            if zip_name
            else ""
        )
        cards.append(
            f"""
      <article class="card" data-arch="{esc(tag)}">
        <span class="fit">适合这台 Mac</span>
        <div class="card-head">
          <span class="card-title">{esc(label)}</span>
          <span class="card-hint">{esc(hint)}</span>
        </div>
        <a class="btn" href="{esc(base_url + dmg)}" download>
          下载 DMG
          {f'<span class="size">{esc(dmg_size)}</span>' if dmg_size else ""}
        </a>
        {zip_link}
      </article>"""
        )

    highlight_html = ""
    if highlights:
        items = "".join(f"<li>{esc(x)}</li>" for x in highlights)
        highlight_html = f"""
  <section>
    <h2>{esc(version)} 更新了什么</h2>
    <ul>{items}</ul>
  </section>"""

    packs_html = ""
    if packs:
        rows = []
        for pack in packs:
            count = f"{pack['count']} 张"
            size = mb(int(pack.get("bytes") or 0))
            when = format_date(str(pack.get("createdAt") or "")[:10])
            meta = " · ".join(x for x in (count, size, when) if x)
            rows.append(
                f'<div class="pack"><strong>{esc(pack["name"])}</strong><span class="meta">{esc(meta)}</span></div>'
            )
        packs_html = f"""
  <section>
    <h2>壁纸包</h2>
    <div class="note">
      <p style="margin:0 0 12px;color:var(--muted)">应用里可导入现成系列。完整清单在 <a href="{esc(packs_catalog_url)}">packs/catalog.json</a>。</p>
      <div class="packs">{"".join(rows)}</div>
    </div>
  </section>"""

    history_html = ""
    if history:
        rows = []
        for item in history:
            now = '<span class="now">最新</span>' if item["version"] == version else ""
            chips = "".join(
                f'<a class="hchip" href="{esc(f["url"])}">{esc(f["label"])}<span class="size">{esc(mb(int(f["size"] or 0)))}</span></a>'
                for f in item["files"]
            )
            rows.append(
                f'<li><span class="hv">{esc(item["version"])}{now}</span><span class="hfiles">{chips}</span></li>'
            )
        history_html = f"""
  <section>
    <h2>全部版本</h2>
    <div class="note">
      <p style="margin:0 0 14px;color:var(--muted)">最新版在最上面；新版有问题时可以直接退回。只保留最近若干版。</p>
      <ul class="history">{"".join(rows)}</ul>
    </div>
  </section>"""

    tagline = PAGE_COPY["tagline"]
    if build:
        tagline += f" · build {build}"
    header_html = release_app_header(
        app_name="Musepaper",
        version=version,
        tagline=tagline,
        date=date,
        icon_url=icon_url,
        esc=esc,
    )
    footer_html = release_hub_footer(
        manifest_url=base_url + "latest.json",
        extra_html="<p>上面的下载链接固定不变，永远指向最新版，可以直接分享。</p>",
        esc=esc,
    )

    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Musepaper {esc(version)} · 下载</title>
  <meta name="description" content="Musepaper {esc(version)}：原生 macOS AI 壁纸。下载 Apple Silicon / Intel 安装包。">
  <meta name="color-scheme" content="light">
  <style>{release_page_css(APP_ACCENTS["musepaper"])}</style>
</head>
<body>
{release_page_decor()}
<div class="page">
{header_html}
  <p class="intro">{esc(PAGE_COPY["intro"])}</p>
  {screenshots_block}

  <section>
    <div class="grid">{"".join(cards) or '<p class="sub">这一版还没有可下载的安装包。</p>'}</div>
  </section>

  <section>
    <h2>Mac 怎么装</h2>
    <div class="note">
      <p style="margin:0 0 8px"><strong>不要直接双击 Musepaper.app。</strong>未公证时系统可能提示「无法验证」——不是软件坏了。</p>
      <p style="margin:0 0 8px">推荐：打开 DMG → 双击 <strong>安装并打开.command</strong>（允许终端运行）→ 自动装好并启动。</p>
      <p style="margin:0 0 8px">若仍被拦：系统设置 → 隐私与安全性 → 找到 Musepaper → <strong>仍要打开</strong>。或终端执行：</p>
      <pre>xattr -cr "/Applications/Musepaper.app"
"/Applications/Musepaper.app/Contents/MacOS/Musepaper" &amp;</pre>
      <p style="margin:12px 0 0;color:var(--muted)">想彻底免弹窗，需要 Apple 开发者公证。</p>
    </div>
  </section>
  {highlight_html}
  {packs_html}
  {history_html}

  {footer_html}
</div>
<script>{JS}</script>
</body>
</html>
"""


def render_from_inputs(
    manifest: dict,
    *,
    base_url: str,
    packs_catalog_url: str,
    release_dir: Path,
    extra_files: list[dict] | None = None,
    catalog: dict | None = None,
    changelog: str = "",
    icon_url: str = "",
) -> str:
    if not base_url.endswith("/"):
        base_url += "/"
    if not (manifest.get("highlights") or []) and changelog:
        for entry in parse_changelog(changelog):
            if entry["version"] == str(manifest.get("version") or ""):
                manifest = dict(manifest)
                manifest["highlights"] = entry["highlights"]
                break
    sizes: dict[str, int] = {}
    if release_dir.is_dir():
        for path in release_dir.iterdir():
            if path.is_file():
                sizes[path.name] = path.stat().st_size
    for item in extra_files or []:
        name = str(item.get("name") or "")
        if name:
            sizes.setdefault(name, int(item.get("size") or 0))
    history = history_entries(
        collect_versioned_files(release_dir, extra_files),
        base_url=base_url,
    )
    return render(
        manifest,
        base_url=base_url,
        packs_catalog_url=packs_catalog_url,
        sizes=sizes,
        history=history,
        packs=featured_packs(catalog),
        icon_url=icon_url,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--packs-catalog-url", required=True)
    ap.add_argument("--release-dir", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--changelog", type=Path)
    ap.add_argument("--catalog", type=Path)
    ap.add_argument("--extra-files", type=Path)
    ap.add_argument("--icon-url", default="")
    args = ap.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    extra = load_json(args.extra_files)
    catalog = load_json(args.catalog)
    changelog = args.changelog.read_text(encoding="utf-8") if args.changelog and args.changelog.is_file() else ""
    html_text = render_from_inputs(
        manifest,
        base_url=args.base_url,
        packs_catalog_url=args.packs_catalog_url,
        release_dir=args.release_dir,
        extra_files=extra if isinstance(extra, list) else None,
        catalog=catalog if isinstance(catalog, dict) else None,
        changelog=changelog,
        icon_url=args.icon_url,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html_text, encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
