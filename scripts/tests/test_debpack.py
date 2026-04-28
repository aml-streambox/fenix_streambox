#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.debpack import build_deb_packages


class DebPackageTests(unittest.TestCase):
    def test_builds_rootless_deb_from_file_mapping(self) -> None:
        if shutil.which("dpkg-deb") is None:
            self.skipTest("dpkg-deb not available")

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
                        "runtime_depends": ["libc6"],
                        "files": [
                            {
                                "from": "dest/usr/bin/app",
                                "to": "/usr/bin/app",
                                "mode": "0755",
                            }
                        ],
                    }
                ],
            }

            packages = build_deb_packages(recipe, install_root=install_root, debs_root=root / "debs")
            extract_root = root / "extract"
            subprocess.run(["dpkg-deb", "-x", str(packages[0].path), str(extract_root)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            self.assertEqual(packages[0].package, "app")
            self.assertEqual((extract_root / "usr/bin/app").read_text(encoding="utf-8"), "app\n")

    def test_packages_kernel_modules_from_standard_extra_path(self) -> None:
        if shutil.which("dpkg-deb") is None:
            self.skipTest("dpkg-deb not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            install_root = root / "install"
            module = install_root / "lib/modules/5.15.137/extra/vfm-cap/vfm-cap.ko"
            module.parent.mkdir(parents=True)
            module.write_bytes(b"module")
            recipe = {
                "name": "vfm-cap",
                "version": "1.0",
                "build": {"class": "kernel-module"},
                "outputs": [
                    {
                        "package": "vfm-cap-modules",
                        "architecture": "arm64",
                        "description": "vfm-cap kernel module",
                        "files": [],
                    }
                ],
            }

            packages = build_deb_packages(recipe, install_root=install_root, debs_root=root / "debs")
            extract_root = root / "extract"
            subprocess.run(["dpkg-deb", "-x", str(packages[0].path), str(extract_root)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            self.assertEqual((extract_root / "lib/modules/5.15.137/extra/vfm-cap/vfm-cap.ko").read_bytes(), b"module")

    def test_packages_kernel_module_autoload_and_udev_metadata(self) -> None:
        if shutil.which("dpkg-deb") is None:
            self.skipTest("dpkg-deb not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            install_root = root / "install"
            module = install_root / "lib/modules/5.15.137/extra/vfm-cap/vfm-cap.ko"
            module.parent.mkdir(parents=True)
            module.write_bytes(b"module")
            rule = install_root / "dest/99-vfm-cap.rules"
            rule.parent.mkdir(parents=True)
            rule.write_text("SUBSYSTEM==\"video4linux\"\n", encoding="utf-8")
            recipe = {
                "name": "vfm-cap",
                "version": "1.0",
                "build": {"class": "kernel-module"},
                "outputs": [
                    {
                        "package": "vfm-cap-modules",
                        "architecture": "arm64",
                        "description": "vfm-cap kernel module",
                        "files": [],
                        "kernel_modules": [
                            {
                                "path": "/lib/modules/5.15.137/extra/vfm-cap/vfm-cap.ko",
                                "autoload": "vfm_cap",
                                "options": "debug=1",
                                "udev_rules": ["dest/99-vfm-cap.rules"],
                            }
                        ],
                    }
                ],
            }

            packages = build_deb_packages(recipe, install_root=install_root, debs_root=root / "debs")
            extract_root = root / "extract"
            subprocess.run(["dpkg-deb", "-x", str(packages[0].path), str(extract_root)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            self.assertEqual((extract_root / "etc/modules-load.d/vfm-cap-modules.conf").read_text(encoding="utf-8"), "vfm_cap\n")
            self.assertEqual((extract_root / "etc/modprobe.d/vfm-cap-modules.conf").read_text(encoding="utf-8"), "options vfm_cap debug=1\n")
            self.assertEqual((extract_root / "etc/udev/rules.d/99-vfm-cap.rules").read_text(encoding="utf-8"), "SUBSYSTEM==\"video4linux\"\n")


if __name__ == "__main__":
    unittest.main()
