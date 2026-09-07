import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


BUILDER = Path(__file__).resolve().parents[1] / "build_deterministic_tar.py"


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "manifest.json").write_text(json.dumps({
            "packages": [{"file": "test.apk"}]
        }))
        for name in ("a1625-tool", "a1625-zram-enable"):
            (self.source / name).write_text("#!/bin/sh\nexit 0\n")

    def tearDown(self):
        self.temp.cleanup()

    def apk(self, members):
        with tarfile.open(self.source / "test.apk", "w:gz") as archive:
            for name, kind, link in members:
                entry = tarfile.TarInfo(name)
                entry.type = kind
                entry.linkname = link
                data = b"test\n" if kind == tarfile.REGTYPE else b""
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data) if data else None)

    def build(self, name="output.gz"):
        return subprocess.run([sys.executable, str(BUILDER), str(self.source),
                               str(self.root / name)], capture_output=True)

    def test_reproducible_and_excludes_stale_files(self):
        self.apk([("usr/bin/test", tarfile.REGTYPE, "")])
        (self.source / "stale.apk").write_bytes(b"not a valid package")
        self.assertEqual(self.build("one.gz").returncode, 0)
        self.assertEqual(self.build("two.gz").returncode, 0)
        self.assertEqual(hashlib.sha256((self.root / "one.gz").read_bytes()).digest(),
                         hashlib.sha256((self.root / "two.gz").read_bytes()).digest())
        with tarfile.open(self.root / "one.gz", "r:gz") as archive:
            self.assertNotIn("stale.apk", archive.getnames())

    def test_rejects_parent_path(self):
        self.apk([("../outside", tarfile.REGTYPE, "")])
        self.assertNotEqual(self.build().returncode, 0)

    def test_rejects_device_node(self):
        self.apk([("dev/device", tarfile.BLKTYPE, "")])
        self.assertNotEqual(self.build().returncode, 0)

    def test_rejects_entry_beneath_link(self):
        self.apk([("usr/bin/alias", tarfile.SYMTYPE, "../lib"),
                  ("usr/bin/alias/escape", tarfile.REGTYPE, "")])
        self.assertNotEqual(self.build().returncode, 0)


if __name__ == "__main__":
    unittest.main()
