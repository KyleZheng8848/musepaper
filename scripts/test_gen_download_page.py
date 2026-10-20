#!/usr/bin/env python3
"""Contract tests for the CPET-shaped Musepaper download page."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from importlib.machinery import SourceFileLoader

ROOT = Path(__file__).resolve().parents[1]
gen = SourceFileLoader("gen_download_page", str(ROOT / "scripts" / "gen-download-page.py")).load_module()


class DownloadPageTests(unittest.TestCase):
    def test_history_sorts_newest_first_and_skips_zip(self) -> None:
        files = {
            "Musepaper-0.5.1-arm64.dmg": 2_000_000,
            "Musepaper-0.5.1-arm64.zip": 1_800_000,
            "Musepaper-0.5.10-arm64.dmg": 2_100_000,
            "Musepaper-0.5.9-x64.dmg": 2_200_000,
        }
        history = gen.history_entries(files, base_url="https://ex/Musepaper/")
        self.assertEqual([h["version"] for h in history], ["0.5.10", "0.5.9", "0.5.1"])
        self.assertEqual(history[2]["files"][0]["label"], "Apple Silicon")
        self.assertTrue(all("zip" not in f["url"] for h in history for f in h["files"]))

    def test_featured_packs_skip_tiny_test_packs(self) -> None:
        packs = gen.featured_packs(
            {
                "packs": [
                    {"name": "试传", "stats": {"artworkCount": 3, "bytes": 10}},
                    {"name": "孤独宇宙", "stats": {"artworkCount": 40, "bytes": 557_662_404}},
                ]
            }
        )
        self.assertEqual([p["name"] for p in packs], ["孤独宇宙"])

    def test_page_uses_stable_links_and_cpet_sections(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            release = Path(raw)
            (release / "Musepaper-latest-arm64.dmg").write_bytes(b"x" * 2_000_000)
            (release / "Musepaper-0.5.59-arm64.dmg").write_bytes(b"x" * 2_000_000)
            (release / "Musepaper-0.5.58-arm64.dmg").write_bytes(b"y" * 1_900_000)
            html = gen.render_from_inputs(
                {
                    "version": "0.5.59",
                    "build": "202609161736",
                    "date": "2026-09-16",
                    "highlights": ["Agent Prompt 只留主题和格式"],
                    "artifacts": {
                        "arm64": {
                            "dmg": "Musepaper-0.5.59-arm64.dmg",
                            "latestDmg": "Musepaper-latest-arm64.dmg",
                            "latestZip": "Musepaper-latest-arm64.zip",
                        }
                    },
                },
                base_url="https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/",
                packs_catalog_url="https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/packs/catalog.json",
                release_dir=release,
                catalog={
                    "packs": [
                        {"name": "孤独宇宙", "stats": {"artworkCount": 40, "bytes": 557_662_404}, "createdAt": "2026-08-26"}
                    ]
                },
                icon_url="https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/assets/icon.png",
            )
        self.assertIn("Musepaper-latest-arm64.dmg", html)
        self.assertIn("免挂载 zip", html)
        self.assertIn("安装并打开.command", html)
        self.assertRegex(html, r"不要(?:直接)?双击 Musepaper\.app")
        self.assertIn("SofunAI", html)
        self.assertIn("0.5.59 更新了什么", html)
        self.assertIn("全部版本", html)
        self.assertIn("孤独宇宙", html)
        self.assertIn("assets/icon.png", html)
        self.assertIn("上面的下载链接固定不变", html)
        self.assertIn('class="now">最新', html)
        self.assertNotIn("不要整批女人", html)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
