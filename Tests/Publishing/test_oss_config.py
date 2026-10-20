"""Publishing configuration must not borrow credentials from another project."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts/lib/oss_client.py"
SPEC = importlib.util.spec_from_file_location("oss_client", MODULE_PATH)
oss_client = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oss_client)


class OSSConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "musepaper"
        (self.root / "Packaging").mkdir(parents=True)
        (self.root / "Packaging/oss.json").write_text(json.dumps({
            "ossTarget": "oss://example-bucket/Musepaper/",
            "ossEndpoint": "oss-cn-hangzhou.aliyuncs.com",
            "downloadBaseUrl": "https://downloads.example.test/Musepaper/",
        }))
        self.environ = patch.dict(os.environ, {}, clear=True)
        self.environ.start()
        self.addCleanup(self.environ.stop)

    def test_neighbor_credentials_are_never_loaded(self):
        neighbor = self.root.parent / "cursor-pet"
        neighbor.mkdir()
        (neighbor / ".env.local").write_text(
            "OSS_ACCESS_KEY_ID=neighbor-id\nOSS_ACCESS_KEY_SECRET=neighbor-secret\n"
        )
        with self.assertRaisesRegex(SystemExit, "缺少 OSS 密钥"):
            oss_client.resolve_oss_config(self.root)
        self.assertNotIn("OSS_ACCESS_KEY_ID", os.environ)
        self.assertNotIn("OSS_ACCESS_KEY_SECRET", os.environ)

    def test_project_credentials_are_loaded(self):
        (self.root / ".env.local").write_text(
            "OSS_ACCESS_KEY_ID=project-id\nOSS_ACCESS_KEY_SECRET=project-secret\n"
        )
        cfg = oss_client.resolve_oss_config(self.root)
        self.assertEqual(cfg["accessKeyId"], "project-id")
        self.assertEqual(cfg["accessKeySecret"], "project-secret")

    def test_environment_overrides_project_file_and_target(self):
        (self.root / ".env.local").write_text(
            "OSS_ACCESS_KEY_ID=file-id\nOSS_ACCESS_KEY_SECRET=file-secret\n"
        )
        os.environ.update({
            "OSS_ACCESS_KEY_ID": "env-id",
            "OSS_ACCESS_KEY_SECRET": "env-secret",
            "MUSEPAPER_OSS_TARGET": "oss://fork-bucket/releases",
            "MUSEPAPER_OSS_ENDPOINT": "oss-cn-beijing.aliyuncs.com",
            "MUSEPAPER_DOWNLOAD_BASE_URL": "https://fork.example.test/releases",
        })
        cfg = oss_client.resolve_oss_config(self.root)
        self.assertEqual(cfg["accessKeyId"], "env-id")
        self.assertEqual(cfg["accessKeySecret"], "env-secret")
        self.assertEqual(cfg["bucket"], "fork-bucket")
        self.assertEqual(cfg["keyPrefix"], "releases/")
        self.assertEqual(cfg["endpoint"], "oss-cn-beijing.aliyuncs.com")
        self.assertEqual(cfg["baseUrl"], "https://fork.example.test/releases/")

    def test_public_config_can_be_read_without_credentials(self):
        cfg = oss_client.resolve_oss_config(self.root, require_credentials=False)
        self.assertEqual(cfg["accessKeyId"], "")
        self.assertEqual(cfg["accessKeySecret"], "")


if __name__ == "__main__":
    unittest.main()
