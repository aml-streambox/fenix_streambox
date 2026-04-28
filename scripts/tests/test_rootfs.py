#!/usr/bin/env python3
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.rootfs import configure_local_apt_feed, run_rootfs_depmod


class RootfsTests(unittest.TestCase):
    def test_run_rootfs_depmod_uses_rootfs_aware_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            fake_depmod = root / "depmod"
            log = root / "depmod.log"
            fake_depmod.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" > \"$DEPMOD_LOG\"\n",
                encoding="utf-8",
            )
            fake_depmod.chmod(0o755)
            rootfs = root / "rootfs"
            rootfs.mkdir()

            import os

            old_log = os.environ.get("DEPMOD_LOG")
            os.environ["DEPMOD_LOG"] = str(log)
            try:
                run_rootfs_depmod(rootfs=rootfs, kernel_version="5.15.137", depmod=str(fake_depmod))
            finally:
                if old_log is None:
                    os.environ.pop("DEPMOD_LOG", None)
                else:
                    os.environ["DEPMOD_LOG"] = old_log

            self.assertEqual(log.read_text(encoding="utf-8"), f"-b {rootfs} 5.15.137\n")

    def test_configure_local_apt_feed_writes_file_source(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            rootfs = root / "rootfs"
            rootfs.mkdir()
            feed = root / "feed"
            feed.mkdir()
            (feed / "Packages").write_text("", encoding="utf-8")

            source_file = configure_local_apt_feed(rootfs=rootfs, feed_root=feed)

            self.assertEqual(source_file, rootfs / "etc/apt/sources.list.d/fenix-local.list")
            self.assertEqual(source_file.read_text(encoding="utf-8"), f"deb [trusted=yes] {feed.resolve().as_uri()} ./\n")


if __name__ == "__main__":
    unittest.main()
