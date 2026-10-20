#!/usr/bin/env python3
"""Publish Musepaper release artifacts to Aliyun OSS.

Order (must not reverse):
  1. versioned + latest dmg/zip (both arches)
  2. enriched latest.json
  3. index.html download page

Never uploads credentials or .env.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from lib.oss_client import OssClient, resolve_oss_config  # noqa: E402

ARTIFACT_RE = re.compile(
    r"^Musepaper-(\d+\.\d+\.\d+(?:-[\w.]+)?)-(arm64|x64)\.(dmg|zip)$",
    re.I,
)


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024.0
    return f"{n:.1f} GB"


def collect_uploads(manifest: dict, release_dir: Path) -> list[Path]:
    arts = manifest.get("artifacts") or {}
    names: list[str] = []
    for tag in manifest.get("architectures") or list(arts.keys()):
        block = arts.get(tag) or {}
        for key in ("dmg", "zip", "latestDmg", "latestZip"):
            name = block.get(key)
            if name:
                names.append(name)
    # unique preserve order
    seen: set[str] = set()
    paths: list[Path] = []
    for name in names:
        if name in seen:
            continue
        seen.add(name)
        path = release_dir / name
        if not path.is_file():
            raise SystemExit(f"缺少 release 产物：{path}")
        if path.stat().st_size < 100_000:
            raise SystemExit(f"产物过小：{path} ({path.stat().st_size} bytes)")
        paths.append(path)
    if not paths:
        raise SystemExit("latest.json 未声明可上传产物")
    return paths


def enrich_manifest(manifest: dict, base_url: str) -> dict:
    out = dict(manifest)
    arts = dict(out.get("artifacts") or {})
    enriched: dict = {}
    for tag, block in arts.items():
        if not isinstance(block, dict):
            continue
        nb = dict(block)
        for key in ("dmg", "zip", "latestDmg", "latestZip"):
            name = nb.get(key)
            if name:
                nb[f"{key}Url"] = base_url + name
        enriched[tag] = nb
    out["artifacts"] = enriched
    out["downloadPage"] = base_url + "index.html"
    out["latestJson"] = base_url + "latest.json"
    out["packsCatalog"] = base_url + "packs/catalog.json"
    return out


def prepare_web_icon(dest: Path) -> Path | None:
    src = ROOT / "Packaging" / "Resources" / "AppIcon-1024.png"
    if not src.is_file():
        return None
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        ["sips", "-s", "format", "png", "-Z", "256", str(src), "--out", str(dest)],
        stdout=subprocess.DEVNULL,
    )
    return dest if dest.is_file() else None


def snapshot_catalog(url: str, dest: Path) -> Path | None:
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            dest.write_bytes(resp.read())
        return dest
    except Exception:
        return None


def remote_versioned_files(oss: OssClient, prefix: str) -> list[dict]:
    extra: list[dict] = []
    for item in oss.list(prefix):
        name = item["key"][len(prefix) :] if item["key"].startswith(prefix) else item["key"]
        if "/" in name or not ARTIFACT_RE.match(name):
            continue
        extra.append({"name": name, "size": item["size"]})
    return extra


def generate_index(
    manifest_path: Path,
    release_dir: Path,
    base_url: str,
    out: Path,
    *,
    extra_files: list[dict] | None = None,
    catalog_path: Path | None = None,
    icon_url: str = "",
) -> None:
    extra_path = release_dir / "download-extra-files.json"
    cmd = [
        sys.executable,
        str(ROOT / "scripts" / "gen-download-page.py"),
        "--manifest",
        str(manifest_path),
        "--base-url",
        base_url,
        "--packs-catalog-url",
        base_url + "packs/catalog.json",
        "--release-dir",
        str(release_dir),
        "--out",
        str(out),
        "--changelog",
        str(ROOT / "CHANGELOG.md"),
    ]
    if extra_files:
        extra_path.write_text(json.dumps(extra_files, ensure_ascii=False), encoding="utf-8")
        cmd.extend(["--extra-files", str(extra_path)])
    if catalog_path and catalog_path.is_file():
        cmd.extend(["--catalog", str(catalog_path)])
    if icon_url:
        cmd.extend(["--icon-url", icon_url])
    subprocess.check_call(cmd)


def main() -> int:
    ap = argparse.ArgumentParser(description="上传 Musepaper 安装包 + latest.json + index.html 到 OSS")
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("--skip-existing", action="store_true", default=True)
    ap.add_argument("--no-skip-existing", action="store_true")
    args = ap.parse_args()
    skip_existing = args.skip_existing and not args.no_skip_existing

    release_dir = ROOT / "release"
    manifest_path = release_dir / "latest.json"
    if not manifest_path.is_file():
        raise SystemExit("缺少 release/latest.json，先跑 ./scripts/package-release.sh")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    version = manifest.get("version")
    if not version:
        raise SystemExit("latest.json 缺少 version")

    uploads = collect_uploads(manifest, release_dir)
    cfg = resolve_oss_config(ROOT, require_credentials=not args.dry_run)
    base_url = cfg["baseUrl"]
    prefix = cfg["keyPrefix"]
    icon_url = base_url + "assets/icon.png"
    icon_local = prepare_web_icon(release_dir / "assets" / "icon.png")
    catalog_local = snapshot_catalog(base_url + "packs/catalog.json", release_dir / "packs.catalog.json")

    print(
        f"→ Musepaper {version} → oss://{cfg['bucket']}/{prefix}"
        f"{'（dry-run）' if args.dry_run else ''}",
        flush=True,
    )

    extra_files: list[dict] = []
    if not args.dry_run:
        listing_oss = OssClient(cfg)
        extra_files = remote_versioned_files(listing_oss, prefix)

    index_local = release_dir / "index.html"
    generate_index(
        manifest_path,
        release_dir,
        base_url,
        index_local,
        extra_files=extra_files,
        catalog_path=catalog_local,
        icon_url=icon_url if icon_local else "",
    )
    enriched = enrich_manifest(manifest, base_url)
    # CPET-compatible fields for update checkers.
    assets = []
    for tag in enriched.get("architectures") or list((enriched.get("artifacts") or {}).keys()):
        block = (enriched.get("artifacts") or {}).get(tag) or {}
        for key in ("dmg", "zip"):
            name = block.get(key)
            url = block.get(f"{key}Url")
            if name and url:
                assets.append({"name": name, "url": url})
    enriched["assets"] = assets
    enriched["releasesUrl"] = enriched.get("downloadPage") or (base_url + "index.html")
    enriched_path = release_dir / "latest.published.json"
    enriched_path.write_text(json.dumps(enriched, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.dry_run:
        for path in uploads:
            print(f"DRY  {path.name} → {prefix}{path.name} ({human(path.stat().st_size)})")
        if icon_local:
            print(f"DRY  assets/icon.png → {prefix}assets/icon.png ({human(icon_local.stat().st_size)})")
        print(f"DRY  latest.json → {prefix}latest.json")
        print(f"DRY  index.html → {prefix}index.html")
        print(
            json.dumps(
                {
                    "dryRun": True,
                    "version": version,
                    "files": len(uploads) + 2,
                    "downloadPage": base_url + "index.html",
                    "latestJson": base_url + "latest.json",
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    oss = OssClient(cfg)

    def on_retry(info: dict) -> None:
        print(
            f"  retry {info['key']} #{info['attempt']} wait {info['waitMs']}ms · {info['error']}",
            flush=True,
        )

    oss.on_retry = on_retry

    uploaded = 0
    skipped = 0
    t0 = time.time()
    for path in uploads:
        key = prefix + path.name
        size = path.stat().st_size
        if skip_existing:
            remote = oss.head_size(key)
            if remote is not None and remote == size:
                print(f"  skip {path.name} ({human(size)})", flush=True)
                skipped += 1
                continue
        print(f"  put {path.name} ({human(size)}) …", flush=True, end=" ")
        started = time.time()
        oss.put_file(path, key)
        print(f"ok {time.time() - started:.1f}s", flush=True)
        uploaded += 1

    if icon_local:
        icon_key = prefix + "assets/icon.png"
        icon_size = icon_local.stat().st_size
        remote_icon = oss.head_size(icon_key) if skip_existing else None
        if remote_icon is not None and remote_icon == icon_size:
            print(f"  skip assets/icon.png ({human(icon_size)})", flush=True)
            skipped += 1
        else:
            print(f"  put assets/icon.png ({human(icon_size)}) …", flush=True, end=" ")
            oss.put_file(icon_local, icon_key)
            print("ok", flush=True)
            uploaded += 1

    shot_local = ROOT / "assets" / "screenshots" / "ui-main.png"
    if shot_local.is_file():
        shot_key = prefix + "assets/screenshots/ui-main.png"
        shot_size = shot_local.stat().st_size
        remote_shot = oss.head_size(shot_key) if skip_existing else None
        if remote_shot is not None and remote_shot == shot_size:
            print(f"  skip assets/screenshots/ui-main.png ({human(shot_size)})", flush=True)
            skipped += 1
        else:
            print(f"  put assets/screenshots/ui-main.png ({human(shot_size)}) …", flush=True, end=" ")
            oss.put_file(shot_local, shot_key)
            print("ok", flush=True)
            uploaded += 1

    # Manifests last — so clients never see a version whose packages 404.
    print("  put latest.json …", flush=True, end=" ")
    oss.put_file(enriched_path, prefix + "latest.json")
    print("ok", flush=True)
    print("  put index.html …", flush=True, end=" ")
    oss.put_file(index_local, prefix + "index.html")
    print("ok", flush=True)

    # Keep local latest.json as source of truth without remote-only URL fields;
    # published copy stays in latest.published.json for debugging.
    elapsed = time.time() - t0
    print(
        json.dumps(
            {
                "version": version,
                "uploaded": uploaded,
                "skipped": skipped,
                "elapsedSec": round(elapsed, 1),
                "downloadPage": base_url + "index.html",
                "latestJson": base_url + "latest.json",
                "packsCatalog": base_url + "packs/catalog.json",
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
