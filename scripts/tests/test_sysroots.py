#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.sysroots import check_native_tools, extract_deb_to_sysroot, stage_recipe_sysroot_exports


class SysrootTests(unittest.TestCase):
    def test_stages_recipe_sysroot_exports(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            package_root = root / "pkg"
            header = package_root / "dest/usr/include/app.h"
            header.parent.mkdir(parents=True)
            header.write_text("header\n", encoding="utf-8")
            recipe = {
                "outputs": [
                    {
                        "sysroot_exports": [
                            {
                                "from": "dest/usr/include/app.h",
                                "to": "/usr/include/app.h",
                            }
                        ]
                    }
                ]
            }

            result = stage_recipe_sysroot_exports(recipe, package_root=package_root, sysroot=root / "sysroot")

            self.assertEqual(len(result.staged), 1)
            self.assertEqual((root / "sysroot/usr/include/app.h").read_text(encoding="utf-8"), "header\n")

    def test_checks_native_tools(self) -> None:
        recipe = {"dependencies": {"native_tools": ["sh", "definitely-missing-fenix-tool"]}}

        self.assertEqual(check_native_tools(recipe), ["definitely-missing-fenix-tool"])

    def test_extracts_deb_to_sysroot(self) -> None:
        if shutil.which("dpkg-deb") is None:
            self.skipTest("dpkg-deb not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            pkg = root / "pkg"
            control = pkg / "DEBIAN/control"
            control.parent.mkdir(parents=True)
            control.write_text(
                "Package: libapp-dev\n"
                "Version: 1.0\n"
                "Architecture: arm64\n"
                "Maintainer: Fenix <fenix@example.invalid>\n"
                "Description: test dev package\n",
                encoding="utf-8",
            )
            header = pkg / "usr/include/app.h"
            header.parent.mkdir(parents=True)
            header.write_text("deb header\n", encoding="utf-8")
            deb = root / "libapp-dev.deb"
            subprocess.run(["dpkg-deb", "--root-owner-group", "-b", str(pkg), str(deb)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            extract_deb_to_sysroot(deb, sysroot=root / "sysroot")

            self.assertEqual((root / "sysroot/usr/include/app.h").read_text(encoding="utf-8"), "deb header\n")


if __name__ == "__main__":
    unittest.main()
