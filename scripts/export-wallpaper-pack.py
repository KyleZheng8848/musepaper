#!/usr/bin/env python3
"""Export local Musepaper library into a portable wallpaper pack.

Includes wallpaper PNGs, .prompt.json sidecars, tags, series (channels),
and optional smart collections / playlists. Never includes credentials.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


HOME = Path.home()
DEFAULT_SNAPSHOT = HOME / "Library/Application Support/Musepaper/snapshot.json"
DEFAULT_PICTURES = HOME / "Pictures/Musepaper"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="导出本机壁纸包（图 + Prompt + tag + 系列）")
    p.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    p.add_argument("--out", type=Path, default=None, help="输出目录（默认 .build/packs/<packId>）")
    p.add_argument("--name", default="", help="包显示名")
    p.add_argument("--pack-id", default="", help="包 ID（默认自动生成）")
    p.add_argument("--series", action="append", default=[], help="按系列名或 UUID 过滤，可多次")
    p.add_argument("--tag", action="append", default=[], help="必须包含的标签，可多次（AND）")
    p.add_argument("--favorites", action="store_true", help="只导出收藏")
    p.add_argument("--limit", type=int, default=0, help="最多导出 N 张（按时间倒序）")
    p.add_argument("--include-source", action="store_true", help="同时拷贝原图（默认仅 wallpaper PNG）")
    p.add_argument("--metadata-only", action="store_true", help="只写 manifest，不拷贝图片")
    p.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    return p.parse_args()


def slugify(text: str) -> str:
    raw = text.strip()
    ascii_part = re.sub(r"[^A-Za-z0-9]+", "-", raw).strip("-").lower()
    if len(re.sub(r"[^A-Za-z0-9]", "", raw)) >= 2:
        return (ascii_part or "pack")[:48]
    # CJK-heavy names → short stable ascii id (avoid ugly %XX URLs)
    import hashlib
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:10]
    return f"pack-{digest}"


def load_snapshot(path: Path) -> dict:
    if not path.is_file():
        raise SystemExit(f"找不到 snapshot：{path}")
    return json.loads(path.read_text(encoding="utf-8"))


def sidecar_path_for(image: Path) -> Path:
    name = image.name
    if ".wallpaper-" in name:
        stem = name.split(".wallpaper-", 1)[0]
    else:
        stem = image.stem
    return image.with_name(f"{stem}.prompt.json")


def channel_matches(channel: dict, needle: str) -> bool:
    needle = needle.strip().lower()
    if not needle:
        return False
    if str(channel.get("id", "")).lower() == needle:
        return True
    return needle in str(channel.get("name", "")).lower()


def select_records(snapshot: dict, args: argparse.Namespace) -> tuple[list[dict], list[dict]]:
    channels = snapshot.get("channels") or []
    records = snapshot.get("records") or []

    series_ids: set[str] | None = None
    if args.series:
        series_ids = set()
        for needle in args.series:
            matched = [c for c in channels if channel_matches(c, needle)]
            if not matched:
                raise SystemExit(f"找不到系列：{needle}")
            for c in matched:
                series_ids.add(str(c["id"]))

    selected: list[dict] = []
    for record in records:
        if record.get("trashedAt"):
            continue
        path = record.get("imagePath") or ""
        if not path or not Path(path).is_file():
            continue
        state = str(record.get("state") or "").lower()
        if state not in {"", "ready", "applied"}:
            continue
        if args.favorites and not record.get("isFavorite"):
            continue
        req = record.get("request") or {}
        sid = req.get("seriesID")
        if series_ids is not None:
            if not sid or str(sid) not in series_ids:
                continue
        tags = set(record.get("tags") or [])
        if args.tag and not set(args.tag).issubset(tags):
            continue
        selected.append(record)

    selected.sort(
        key=lambda r: str((r.get("request") or {}).get("createdAt") or r.get("updatedAt") or ""),
        reverse=True,
    )
    if args.limit and args.limit > 0:
        selected = selected[: args.limit]

    used_series = {
        str((r.get("request") or {}).get("seriesID"))
        for r in selected
        if (r.get("request") or {}).get("seriesID")
    }
    pack_channels = [c for c in channels if str(c.get("id")) in used_series]
    # If filtering by series but no images yet, still keep those channels.
    if series_ids is not None:
        pack_channels = [c for c in channels if str(c.get("id")) in series_ids]
    return selected, pack_channels


def slim_channel(channel: dict) -> dict:
    keep = [
        "id",
        "name",
        "essence",
        "mustInclude",
        "exclude",
        "palette",
        "variation",
        "coreKeywords",
        "variationAxes",
        "promptStrategy",
        "seedArtworkID",
    ]
    out = {k: channel.get(k) for k in keep if k in channel}
    # reference paths rewritten later if copied
    refs = channel.get("referenceImagePaths") or []
    if refs:
        out["referenceImagePaths"] = refs
    return out


def slim_record(record: dict, *, image_rel: str, sidecar_rel: str | None) -> dict:
    req = record.get("request") or {}
    return {
        "id": record.get("id"),
        "channelId": req.get("seriesID"),
        "image": image_rel,
        "sidecar": sidecar_rel,
        "tags": record.get("tags") or [],
        "tagSummary": record.get("tagSummary") or "",
        "isFavorite": bool(record.get("isFavorite")),
        "state": record.get("state"),
        "createdAt": req.get("createdAt"),
        "updatedAt": record.get("updatedAt"),
        "request": {
            "rawInput": req.get("rawInput") or "",
            "resolvedPrompt": req.get("resolvedPrompt") or "",
            "negativePrompt": req.get("negativePrompt") or "",
            "coreKeywords": req.get("coreKeywords") or "",
            "variationSeed": req.get("variationSeed"),
            "batchID": req.get("batchID"),
        },
    }


def main() -> int:
    args = parse_args()
    snapshot = load_snapshot(args.snapshot)
    records, channels = select_records(snapshot, args)
    if not records and not channels:
        raise SystemExit("没有可导出的作品（检查筛选条件）")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    default_name = args.name.strip() or (
        " · ".join(c.get("name") or "系列" for c in channels[:2]) if channels else "Musepaper 壁纸包"
    )
    pack_id = args.pack_id.strip() or f"{slugify(default_name)}-{stamp}"

    out_dir = args.out or (args.project_root / ".build" / "packs" / pack_id)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    art_dir = out_dir / "artworks"
    ref_dir = out_dir / "references"
    art_dir.mkdir(parents=True)
    ref_dir.mkdir(parents=True)

    total_bytes = 0
    artworks_out: list[dict] = []
    for record in records:
        src = Path(record["imagePath"])
        dest_name = src.name
        dest = art_dir / dest_name
        image_rel = f"artworks/{dest_name}"
        sidecar_rel = None
        if not args.metadata_only:
            shutil.copy2(src, dest)
            total_bytes += dest.stat().st_size
            side = sidecar_path_for(src)
            if side.is_file():
                side_dest = art_dir / side.name
                shutil.copy2(side, side_dest)
                sidecar_rel = f"artworks/{side.name}"
                total_bytes += side_dest.stat().st_size
            if args.include_source:
                # sibling original without .wallpaper-
                if ".wallpaper-" in src.name:
                    stem = src.name.split(".wallpaper-", 1)[0]
                    for cand in src.parent.glob(f"{stem}.*"):
                        if ".wallpaper-" in cand.name or cand.suffix == ".json":
                            continue
                        if cand.is_file():
                            shutil.copy2(cand, art_dir / cand.name)
                            total_bytes += cand.stat().st_size
        else:
            side = sidecar_path_for(src)
            if side.is_file():
                sidecar_rel = f"artworks/{side.name}"
        artworks_out.append(slim_record(record, image_rel=image_rel, sidecar_rel=sidecar_rel))

    # Copy channel reference images into pack and rewrite paths
    channels_out: list[dict] = []
    for channel in channels:
        slim = slim_channel(channel)
        refs = channel.get("referenceImagePaths") or []
        rewritten = []
        for idx, ref in enumerate(refs):
            src = Path(ref)
            if not src.is_file():
                continue
            name = f"{channel.get('id')}-{idx}{src.suffix.lower() or '.png'}"
            if not args.metadata_only:
                shutil.copy2(src, ref_dir / name)
                total_bytes += (ref_dir / name).stat().st_size
            rewritten.append(f"references/{name}")
        if rewritten:
            slim["referenceImagePaths"] = rewritten
        elif "referenceImagePaths" in slim:
            del slim["referenceImagePaths"]
        channels_out.append(slim)

    # Optional collections / playlists that only reference included artworks/channels
    artwork_ids = {str(a["id"]) for a in artworks_out}
    channel_ids = {str(c["id"]) for c in channels_out}
    collections = []
    for col in snapshot.get("smartCollections") or []:
        # Keep collection if its task filter intersects pack channels, or no task filter
        task_ids = set(str(x) for x in (col.get("taskIDs") or col.get("seriesIDs") or []))
        if task_ids and channel_ids and task_ids.isdisjoint(channel_ids):
            continue
        collections.append(col)
    playlists = []
    for pl in snapshot.get("playlists") or []:
        source = pl.get("source")
        source_id = str(pl.get("sourceID") or "")
        if source == "task" and source_id and source_id not in channel_ids:
            continue
        playlists.append(pl)

    digest = hashlib.sha1(
        json.dumps(
            {"artworks": [a["id"] for a in artworks_out], "channels": [c["id"] for c in channels_out]},
            ensure_ascii=False,
            sort_keys=True,
        ).encode("utf-8")
    ).hexdigest()[:12]

    manifest = {
        "schemaVersion": 1,
        "kind": "musepaper-wallpaper-pack",
        "packId": pack_id,
        "name": default_name,
        "version": stamp,
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "contentDigest": digest,
        "stats": {
            "artworkCount": len(artworks_out),
            "channelCount": len(channels_out),
            "bytes": total_bytes,
        },
        "filters": {
            "series": args.series,
            "tags": args.tag,
            "favorites": bool(args.favorites),
            "limit": args.limit or None,
            "metadataOnly": bool(args.metadata_only),
            "includeSource": bool(args.include_source),
        },
        "channels": channels_out,
        "artworks": artworks_out,
        "collections": collections,
        "playlists": playlists,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(json.dumps({
        "packId": pack_id,
        "out": str(out_dir),
        "artworks": len(artworks_out),
        "channels": len(channels_out),
        "bytes": total_bytes,
        "gb": round(total_bytes / (1024 ** 3), 3),
        "manifest": str(out_dir / "manifest.json"),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
