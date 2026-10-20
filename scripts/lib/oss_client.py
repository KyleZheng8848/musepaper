#!/usr/bin/env python3
"""Minimal Aliyun OSS V1 client (stdlib only). Secrets never printed."""

from __future__ import annotations

import base64
import hmac
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from email.utils import formatdate
from hashlib import sha1
from pathlib import Path
from typing import Callable

MIME = {
    ".dmg": "application/x-apple-diskimage",
    ".zip": "application/zip",
    ".json": "application/json",
    ".html": "text/html; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".txt": "text/plain; charset=utf-8",
}

_ENV_PREFIX = "MUSEPAPER"


def load_env_local(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        key, value = s.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        os.environ.setdefault(key, value)


def _env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value and value.strip():
            return value.strip()
    return default


def resolve_oss_config(project_root: Path, *, require_credentials: bool = True) -> dict:
    """Load this project's Packaging/oss.json, .env.local and environment overrides."""
    project_root = Path(project_root).resolve()
    load_env_local(project_root / ".env.local")
    cfg_path = project_root / "Packaging" / "oss.json"
    if not cfg_path.is_file():
        raise SystemExit(f"缺少 {cfg_path}")
    raw = json.loads(cfg_path.read_text(encoding="utf-8"))

    target = _env(f"{_ENV_PREFIX}_OSS_TARGET", "OSS_TARGET", default=str(raw.get("ossTarget") or ""))
    endpoint = _env(f"{_ENV_PREFIX}_OSS_ENDPOINT", "OSS_ENDPOINT", default=str(raw.get("ossEndpoint") or ""))
    base_url = _env(
        f"{_ENV_PREFIX}_DOWNLOAD_BASE_URL",
        "DOWNLOAD_BASE_URL",
        default=str(raw.get("downloadBaseUrl") or ""),
    )
    packs_prefix = str(raw.get("packsPrefix") or "packs/")
    if packs_prefix and not packs_prefix.endswith("/"):
        packs_prefix += "/"

    match = re.match(r"^oss://([^/]+)/?(.*)$", target)
    if not match:
        raise SystemExit(
            '缺少上传目标。Packaging/oss.json 设 "ossTarget": "oss://<bucket>/<前缀>/"，'
            f'或环境变量 {_ENV_PREFIX}_OSS_TARGET。'
        )
    bucket, key_prefix = match.group(1), match.group(2)
    if key_prefix and not key_prefix.endswith("/"):
        key_prefix += "/"
    if not endpoint:
        raise SystemExit(f"缺少 OSS endpoint（Packaging/oss.json 或 {_ENV_PREFIX}_OSS_ENDPOINT）")
    if not base_url:
        raise SystemExit(f"缺少 downloadBaseUrl（Packaging/oss.json 或 {_ENV_PREFIX}_DOWNLOAD_BASE_URL）")
    if not base_url.endswith("/"):
        base_url += "/"

    access_key_id = _env("OSS_ACCESS_KEY_ID")
    access_key_secret = _env("OSS_ACCESS_KEY_SECRET")
    if require_credentials and (not access_key_id or not access_key_secret):
        raise SystemExit(
            "缺少 OSS 密钥。写进项目根 .env.local（已 gitignore）：\n"
            "  OSS_ACCESS_KEY_ID=...\n"
            "  OSS_ACCESS_KEY_SECRET=...\n"
        )

    keep = int(raw.get("keepPacks") or 30)
    return {
        "bucket": bucket,
        "keyPrefix": key_prefix,
        "endpoint": endpoint,
        "baseUrl": base_url,
        "packsPrefix": packs_prefix,
        "accessKeyId": access_key_id,
        "accessKeySecret": access_key_secret,
        "keepPacks": keep if keep > 0 else 30,
    }


def _content_type(name: str) -> str:
    ext = Path(name).suffix.lower()
    return MIME.get(ext) or "application/octet-stream"


def _is_transient(err: BaseException) -> bool:
    text = f"{type(err).__name__} {err}"
    return bool(
        re.search(
            r"ECONNRESET|EPIPE|ETIMEDOUT|ECONNREFUSED|EAI_AGAIN|ENOTFOUND|socket hang up|"
            r"RequestTimeout|InternalError|ServiceUnavailable|SlowDown|\b5\d\d\b|timed out",
            text,
            re.I,
        )
    )


def _sign(*, secret: str, method: str, content_type: str, date: str, oss_headers: dict, resource: str) -> str:
    canon = "".join(
        f"{k.lower()}:{oss_headers[k]}\n"
        for k in sorted(oss_headers, key=lambda x: x.lower())
    )
    raw = "\n".join([method, "", content_type, date, f"{canon}{resource}"])
    digest = hmac.new(secret.encode("utf-8"), raw.encode("utf-8"), sha1).digest()
    return base64.b64encode(digest).decode("ascii")


class OssClient:
    def __init__(self, cfg: dict):
        self.bucket = cfg["bucket"]
        self.endpoint = cfg["endpoint"]
        self.ak = cfg["accessKeyId"]
        self.sk = cfg["accessKeySecret"]
        self.host = f"{self.bucket}.{self.endpoint}"
        self.on_retry: Callable | None = None

    def public_url(self, key: str) -> str:
        parts = "/".join(urllib.parse.quote(p, safe="") for p in key.split("/"))
        return f"https://{self.host}/{parts}"

    def _send(
        self,
        *,
        method: str,
        key: str,
        query: str = "",
        headers: dict | None = None,
        body: bytes | None = None,
        body_path: Path | None = None,
        oss_headers: dict | None = None,
    ) -> tuple[int, str]:
        headers = dict(headers or {})
        oss_headers = dict(oss_headers or {})
        date = formatdate(usegmt=True)
        content_type = headers.get("Content-Type", "")
        resource = f"/{self.bucket}/{key}"
        signature = _sign(
            secret=self.sk,
            method=method,
            content_type=content_type,
            date=date,
            oss_headers=oss_headers,
            resource=resource,
        )
        path = "/" + "/".join(urllib.parse.quote(p, safe="") for p in key.split("/")) + query
        req_headers = {
            **headers,
            **oss_headers,
            "Date": date,
            "Authorization": f"OSS {self.ak}:{signature}",
            "Host": self.host,
        }
        data = body
        if body_path is not None:
            data = body_path.read_bytes()
            req_headers["Content-Length"] = str(len(data))
        request = urllib.request.Request(
            f"https://{self.host}{path}",
            data=data if method in {"PUT", "POST"} else None,
            headers=req_headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=600) as resp:
                text = resp.read().decode("utf-8", errors="replace")
                return resp.status, text
        except urllib.error.HTTPError as err:
            text = err.read().decode("utf-8", errors="replace")
            code = re.search(r"<Code>([^<]+)</Code>", text)
            msg = re.search(r"<Message>([^<]+)</Message>", text)
            detail = (code.group(1) if code else str(err.code)) + " —— " + (
                msg.group(1) if msg else text[:200]
            )
            raise RuntimeError(f"OSS {method} {key or '/'} 失败：{detail}") from err

    def put_file(
        self,
        local_path: Path,
        key: str,
        *,
        acl: str = "public-read",
        retries: int = 4,
    ) -> dict:
        local_path = Path(local_path)
        size = local_path.stat().st_size
        content_type = _content_type(local_path.name)
        last_err: BaseException | None = None
        for attempt in range(1, retries + 2):
            try:
                self._send(
                    method="PUT",
                    key=key,
                    headers={"Content-Type": content_type},
                    body_path=local_path,
                    oss_headers={"x-oss-object-acl": acl} if acl else {},
                )
                return {"size": size, "url": self.public_url(key)}
            except BaseException as err:
                last_err = err
                if attempt > retries or not _is_transient(err):
                    raise
                wait_ms = min(2000 * attempt, 10_000)
                if self.on_retry:
                    self.on_retry({"key": key, "attempt": attempt, "waitMs": wait_ms, "error": err})
                time.sleep(wait_ms / 1000)
        raise last_err  # type: ignore[misc]

    def put_bytes(
        self,
        data: bytes,
        key: str,
        *,
        content_type: str = "application/octet-stream",
        acl: str = "public-read",
    ) -> dict:
        self._send(
            method="PUT",
            key=key,
            headers={"Content-Type": content_type, "Content-Length": str(len(data))},
            body=data,
            oss_headers={"x-oss-object-acl": acl} if acl else {},
        )
        return {"size": len(data), "url": self.public_url(key)}

    def list(self, prefix: str) -> list[dict]:
        items: list[dict] = []
        marker = ""
        while True:
            query = f"?prefix={urllib.parse.quote(prefix)}&max-keys=1000"
            if marker:
                query += f"&marker={urllib.parse.quote(marker)}"
            _, text = self._send(method="GET", key="", query=query)
            for block in re.findall(r"<Contents>([\s\S]*?)</Contents>", text):
                key = re.search(r"<Key>([^<]+)</Key>", block)
                if not key:
                    continue
                size = re.search(r"<Size>(\d+)</Size>", block)
                modified = re.search(r"<LastModified>([^<]+)</LastModified>", block)
                items.append(
                    {
                        "key": key.group(1),
                        "size": int(size.group(1)) if size else 0,
                        "lastModified": modified.group(1) if modified else "",
                    }
                )
            if "<IsTruncated>true</IsTruncated>" not in text:
                break
            if not items:
                break
            marker = items[-1]["key"]
        return items

    def head_size(self, key: str) -> int | None:
        try:
            date = formatdate(usegmt=True)
            resource = f"/{self.bucket}/{key}"
            signature = _sign(
                secret=self.sk,
                method="HEAD",
                content_type="",
                date=date,
                oss_headers={},
                resource=resource,
            )
            path = "/" + "/".join(urllib.parse.quote(p, safe="") for p in key.split("/"))
            request = urllib.request.Request(
                f"https://{self.host}{path}",
                headers={
                    "Date": date,
                    "Authorization": f"OSS {self.ak}:{signature}",
                    "Host": self.host,
                },
                method="HEAD",
            )
            with urllib.request.urlopen(request, timeout=60) as resp:
                length = resp.headers.get("Content-Length")
                return int(length) if length else 0
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None
            return None
        except Exception:
            return None
