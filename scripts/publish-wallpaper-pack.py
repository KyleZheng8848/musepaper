#!/usr/bin/env python3
"""Export a local wallpaper pack and upload it to Aliyun OSS.

Uploads:
  {keyPrefix}{packsPrefix}{packId}/manifest.json
  {keyPrefix}{packsPrefix}{packId}/artworks/*
  {keyPrefix}{packsPrefix}{packId}/references/*
  {keyPrefix}{packsPrefix}catalog.json   (index of packs)

Never uploads credentials.json.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from lib.oss_client import OssClient, resolve_oss_config  # noqa: E402


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="导出并上传本机壁纸包到 OSS")
    p.add_argument("--dry-run", action="store_true", help="只导出/列计划，不上传")
    p.add_argument("--yes", action="store_true", help="跳过体积确认")
    p.add_argument("--pack-dir", type=Path, default=None, help="已有 pack 目录则跳过导出")
    p.add_argument("--name", default="")
    p.add_argument("--pack-id", default="")
    p.add_argument("--series", action="append", default=[])
    p.add_argument("--tag", action="append", default=[])
    p.add_argument("--favorites", action="store_true")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--include-source", action="store_true")
    p.add_argument("--metadata-only", action="store_true")
    p.add_argument("--skip-existing", action="store_true", default=True, help="同大小对象跳过（默认开）")
    p.add_argument("--no-skip-existing", action="store_true")
    p.add_argument("--concurrency", type=int, default=4)
    return p.parse_args()


def export_pack(args: argparse.Namespace) -> Path:
    cmd = [sys.executable, str(ROOT / "scripts" / "export-wallpaper-pack.py")]
    if args.name:
        cmd += ["--name", args.name]
    if args.pack_id:
        cmd += ["--pack-id", args.pack_id]
    for s in args.series:
        cmd += ["--series", s]
    for t in args.tag:
        cmd += ["--tag", t]
    if args.favorites:
        cmd.append("--favorites")
    if args.limit:
        cmd += ["--limit", str(args.limit)]
    if args.include_source:
        cmd.append("--include-source")
    if args.metadata_only:
        cmd.append("--metadata-only")
    print("→ 导出壁纸包…", flush=True)
    out = subprocess.check_output(cmd, text=True)
    print(out, flush=True)
    info = json.loads(out)
    return Path(info["out"])


def iter_pack_files(pack_dir: Path) -> list[Path]:
    files: list[Path] = []
    for path in sorted(pack_dir.rglob("*")):
        if path.is_file():
            files.append(path)
    return files


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} TB"


def update_catalog(oss: OssClient, cfg: dict, entry: dict, *, dry_run: bool) -> str:
    catalog_key = f"{cfg['keyPrefix']}{cfg['packsPrefix']}catalog.json"
    existing = {"schemaVersion": 1, "updatedAt": "", "packs": []}
    # Try download existing catalog via public URL first (anonymous), else list.
    try:
        import urllib.request

        with urllib.request.urlopen(cfg["baseUrl"] + cfg["packsPrefix"] + "catalog.json", timeout=30) as resp:
            existing = json.loads(resp.read().decode("utf-8"))
    except Exception:
        existing = {"schemaVersion": 1, "packs": []}

    packs = [p for p in (existing.get("packs") or []) if p.get("packId") != entry["packId"]]
    packs.insert(0, entry)
    # Keep newest N
    keep = int(cfg.get("keepPacks") or 30)
    packs = packs[:keep]
    catalog = {
        "schemaVersion": 1,
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packs": packs,
    }
    body = (json.dumps(catalog, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if dry_run:
        print(f"DRY  catalog → {catalog_key} ({len(packs)} packs)")
        return cfg["baseUrl"] + cfg["packsPrefix"] + "catalog.json"
    oss.put_bytes(body, catalog_key, content_type="application/json")
    return oss.public_url(catalog_key)


def main() -> int:
    args = parse_args()
    skip_existing = args.skip_existing and not args.no_skip_existing

    if args.pack_dir:
        pack_dir = args.pack_dir.resolve()
        if not (pack_dir / "manifest.json").is_file():
            raise SystemExit(f"pack 目录缺少 manifest.json：{pack_dir}")
    else:
        # Safety: full library without filter is huge — require --yes unless limited.
        if not any([args.series, args.tag, args.favorites, args.limit, args.metadata_only, args.yes]):
            raise SystemExit(
                "全库上传体积可能很大。请加筛选，例如：\n"
                "  --series 孤独宇宙\n"
                "  --favorites\n"
                "  --limit 50\n"
                "或确认全量：--yes"
            )
        pack_dir = export_pack(args)

    manifest = json.loads((pack_dir / "manifest.json").read_text(encoding="utf-8"))
    files = iter_pack_files(pack_dir)
    total = sum(f.stat().st_size for f in files)
    print(f"→ pack {manifest.get('packId')} · {len(files)} 文件 · {human(total)}", flush=True)

    if total > 2 * 1024 ** 3 and not args.yes and not args.dry_run:
        raise SystemExit(f"体积 {human(total)} > 2GB，请加 --yes 确认上传")

    cfg = resolve_oss_config(ROOT.resolve(), require_credentials=not args.dry_run)
    pack_id = manifest["packId"]
    remote_root = f"{cfg['keyPrefix']}{cfg['packsPrefix']}{pack_id}/"
    print(f"→ OSS 前缀 {remote_root}", flush=True)
    print(f"→ 公网根 {cfg['baseUrl']}{cfg['packsPrefix']}{pack_id}/", flush=True)

    if args.dry_run:
        for f in files[:20]:
            rel = f.relative_to(pack_dir).as_posix()
            print(f"DRY  {f} → {remote_root}{rel}")
        if len(files) > 20:
            print(f"DRY  … 另有 {len(files) - 20} 个文件")
        entry = {
            "packId": pack_id,
            "name": manifest.get("name"),
            "version": manifest.get("version"),
            "createdAt": manifest.get("createdAt"),
            "stats": manifest.get("stats"),
            "manifestUrl": cfg["baseUrl"] + cfg["packsPrefix"] + f"{pack_id}/manifest.json",
            "prefix": cfg["packsPrefix"] + f"{pack_id}/",
        }
        catalog_url = cfg["baseUrl"] + cfg["packsPrefix"] + "catalog.json"
        print(json.dumps({"dryRun": True, "packId": pack_id, "files": len(files), "bytes": total, "catalogUrl": catalog_url, "manifestUrl": entry["manifestUrl"]}, ensure_ascii=False, indent=2))
        return 0

    oss = OssClient(cfg)

    def on_retry(info: dict) -> None:
        print(f"  retry {info['key']} #{info['attempt']} wait {info['waitMs']}ms · {info['error']}", flush=True)

    oss.on_retry = on_retry

    uploaded = 0
    skipped = 0
    bytes_up = 0
    t0 = time.time()
    for index, path in enumerate(files, 1):
        rel = path.relative_to(pack_dir).as_posix()
        key = remote_root + rel
        size = path.stat().st_size
        if skip_existing:
            remote_size = oss.head_size(key)
            if remote_size is not None and remote_size == size:
                skipped += 1
                if index % 50 == 0 or index == len(files):
                    print(f"  [{index}/{len(files)}] skip {rel}", flush=True)
                continue
        print(f"  [{index}/{len(files)}] put {rel} ({human(size)})", flush=True)
        oss.put_file(path, key)
        uploaded += 1
        bytes_up += size

    entry = {
        "packId": pack_id,
        "name": manifest.get("name"),
        "version": manifest.get("version"),
        "createdAt": manifest.get("createdAt"),
        "contentDigest": manifest.get("contentDigest"),
        "stats": manifest.get("stats"),
        "filters": manifest.get("filters"),
        "manifestUrl": oss.public_url(remote_root + "manifest.json"),
        "prefix": cfg["packsPrefix"] + f"{pack_id}/",
    }
    catalog_url = update_catalog(oss, cfg, entry, dry_run=False)
    elapsed = time.time() - t0
    print(
        json.dumps(
            {
                "packId": pack_id,
                "uploaded": uploaded,
                "skipped": skipped,
                "bytesUploaded": bytes_up,
                "elapsedSec": round(elapsed, 1),
                "manifestUrl": entry["manifestUrl"],
                "catalogUrl": catalog_url,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
