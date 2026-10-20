#!/usr/bin/env python3
"""HTTP-check that Musepaper OSS surface matches local release/latest.json."""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from lib.oss_client import resolve_oss_config  # noqa: E402


def head_or_get(url: str) -> tuple[int, int | None]:
    """Return (status, content-length or None). Prefer HEAD, fall back to GET range."""
    for method in ("HEAD", "GET"):
        req = urllib.request.Request(url, method=method)
        if method == "GET":
            req.add_header("Range", "bytes=0-0")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                length = resp.headers.get("Content-Length")
                # For Range responses Content-Range may be present
                if method == "GET" and resp.headers.get("Content-Range"):
                    # bytes 0-0/12345
                    cr = resp.headers.get("Content-Range", "")
                    if "/" in cr:
                        try:
                            return resp.status, int(cr.split("/")[-1])
                        except ValueError:
                            pass
                return resp.status, int(length) if length else None
        except urllib.error.HTTPError as err:
            if method == "HEAD" and err.code in {403, 405}:
                continue
            return err.code, None
        except Exception:
            return 0, None
    return 0, None


def main() -> int:
    local = json.loads((ROOT / "release" / "latest.json").read_text(encoding="utf-8"))
    cfg = resolve_oss_config(ROOT, require_credentials=False)
    base = cfg["baseUrl"]
    errors = 0

    def fail(msg: str) -> None:
        nonlocal errors
        print(f"FAIL  {msg}", file=sys.stderr)
        errors += 1

    def ok(msg: str) -> None:
        print(f"OK    {msg}")

    # index + latest.json
    for name in ("index.html", "latest.json"):
        url = base + name
        status, _ = head_or_get(url)
        if status not in {200, 206}:
            fail(f"{url} → HTTP {status}")
        else:
            ok(f"{name} HTTP {status}")

    remote_manifest = None
    try:
        with urllib.request.urlopen(base + "latest.json", timeout=60) as resp:
            remote_manifest = json.loads(resp.read().decode("utf-8"))
    except Exception as err:
        fail(f"无法读取远端 latest.json：{err}")

    if remote_manifest:
        for field in ("version", "build"):
            lv = str(local.get(field, ""))
            rv = str(remote_manifest.get(field, ""))
            if lv != rv:
                fail(f"latest.json {field}: local={lv} remote={rv}")
            else:
                ok(f"latest.json {field}={lv}")

        arts = remote_manifest.get("artifacts") or {}
        for tag in local.get("architectures") or []:
            block = arts.get(tag) or {}
            for key in ("dmg", "zip", "latestDmg", "latestZip"):
                name = block.get(key)
                if not name:
                    # also accept only dmg/zip
                    continue
                local_path = ROOT / "release" / name
                url = base + name
                status, remote_size = head_or_get(url)
                if status not in {200, 206}:
                    fail(f"{tag} {key} {url} → HTTP {status}")
                    continue
                if local_path.is_file() and remote_size is not None:
                    local_size = local_path.stat().st_size
                    if local_size != remote_size:
                        fail(f"{name} size local={local_size} remote={remote_size}")
                    else:
                        ok(f"{name} HTTP {status} size={remote_size}")
                else:
                    ok(f"{name} HTTP {status}")

    packs_url = base + "packs/catalog.json"
    status, _ = head_or_get(packs_url)
    if status not in {200, 206}:
        fail(f"packs/catalog.json → HTTP {status}")
    else:
        ok(f"packs/catalog.json HTTP {status}")

    print("")
    if errors:
        print(f"verify-published 失败（{errors}）— 禁止宣称 OSS 已同步", file=sys.stderr)
        return 1
    print(f"verify-published OK · {local.get('version')} · {base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
