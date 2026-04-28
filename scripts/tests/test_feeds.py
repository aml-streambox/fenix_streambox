#!/usr/bin/env python3
from pathlib import Path
import gzip
import shutil
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.debpack import build_deb_packages
from fenix_recipe.feeds import generate_local_feed


class FeedTests(unittest.TestCase):
    def test_generates_packages_metadata_from_debs(self) -> None:
        if shutil.which("dpkg-deb") is None or shutil.which("dpkg-scanpackages") is None:
            self.skipTest("dpkg-deb or dpkg-scanpackages not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            install_root = root / "install"
            binary = install_root / "dest/usr/bin/app"
            binary.parent.mkdir(parents=True)
            binary.write_text("app\n", encoding="utf-8")
            recipe = {
                "name": "app",
                "version": "1.0",
                "outputs": [
                    {
                        "package": "app",
                        "architecture": "arm64",
                        "description": "test app",
                        "files": [{"from": "dest/usr/bin/app", "to": "/usr/bin/app"}],
                    }
                ],
            }
            build_deb_packages(recipe, install_root=install_root, debs_root=root / "debs")

            result = generate_local_feed(debs_root=root / "debs", feed_root=root / "feed", arch="arm64")

            packages = result.packages.read_text(encoding="utf-8")
            with gzip.open(result.packages_gz, "rt", encoding="utf-8") as compressed:
                packages_gz = compressed.read()
            self.assertIn("Package: app", packages)
            self.assertEqual(packages, packages_gz)
            self.assertEqual(result.deb_count, 1)


if __name__ == "__main__":
    unittest.main()
