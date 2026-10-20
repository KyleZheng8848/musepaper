#!/usr/bin/env python3
"""只根据 OSS 现状重新生成并上传 index.html（不动安装包和 latest.json）。"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from importlib.machinery import SourceFileLoader

pub = SourceFileLoader("publish_release", str(ROOT / "scripts" / "publish-release.py")).load_module()
OssClient = pub.OssClient
generate_index = pub.generate_index
remote_versioned_files = pub.remote_versioned_files
resolve_oss_config = pub.resolve_oss_config
snapshot_catalog = pub.snapshot_catalog


def main() -> int:
    release_dir = ROOT / "release"
    manifest_path = release_dir / "latest.json"
    if not manifest_path.is_file():
        raise SystemExit("缺少 release/latest.json")

    cfg = resolve_oss_config(ROOT, require_credentials=True)
    base_url = cfg["baseUrl"]
    prefix = cfg["keyPrefix"]
    icon_url = base_url + "assets/icon.png"
    catalog_local = snapshot_catalog(base_url + "packs/catalog.json", release_dir / "packs.catalog.json")

    oss = OssClient(cfg)
    shot_local = ROOT / "assets" / "screenshots" / "ui-main.png"
    if shot_local.is_file():
        oss.put_file(shot_local, prefix + "assets/screenshots/ui-main.png")
    extra_files = remote_versioned_files(oss, prefix)
    index_local = release_dir / "index.html"
    generate_index(
        manifest_path,
        release_dir,
        base_url,
        index_local,
        extra_files=extra_files,
        catalog_path=catalog_local,
        icon_url=icon_url,
    )
    oss.put_file(index_local, prefix + "index.html")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    print(f"[refresh-download-page] 已上传 {base_url}index.html（{manifest.get('version')}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
