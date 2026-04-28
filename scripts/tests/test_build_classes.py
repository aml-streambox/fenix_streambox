#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.build_classes import build_recipe


class MakeBuildClassTests(unittest.TestCase):
    def test_make_build_installs_to_destdir(self) -> None:
        if shutil.which("make") is None:
            self.skipTest("make not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "Makefile").write_text(
                "all:\n"
                "\tprintf 'built\\n' > app\n"
                "install:\n"
                "\tmkdir -p $(DESTDIR)/usr/bin\n"
                "\tcp app $(DESTDIR)/usr/bin/app\n",
                encoding="utf-8",
            )
            recipe = {
                "name": "app",
                "build": {
                    "class": "make",
                },
            }

            result = build_recipe(recipe, source_dir=source, install_root=root / "install")

            self.assertEqual(result.recipe_name, "app")
            self.assertEqual((root / "install/usr/bin/app").read_text(encoding="utf-8"), "built\n")

    def test_make_build_passes_env(self) -> None:
        if shutil.which("make") is None:
            self.skipTest("make not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "Makefile").write_text(
                "all:\n"
                "\tprintf '%s\\n' \"$$CUSTOM_VALUE\" > app\n"
                "install:\n"
                "\tmkdir -p $(DESTDIR)/usr/bin\n"
                "\tcp app $(DESTDIR)/usr/bin/app\n",
                encoding="utf-8",
            )
            recipe = {
                "name": "app",
                "build": {
                    "class": "make",
                    "env": {"CUSTOM_VALUE": "from-env"},
                },
            }

            build_recipe(recipe, source_dir=source, install_root=root / "install")

            self.assertEqual((root / "install/usr/bin/app").read_text(encoding="utf-8"), "from-env\n")

    def test_make_build_provides_legacy_install_env(self) -> None:
        if shutil.which("make") is None:
            self.skipTest("make not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "Makefile").write_text(
                "all:\n"
                "\tmkdir -p $(OUT_DIR)\n"
                "\tprintf 'built\\n' > $(OUT_DIR)/app\n"
                "install:\n"
                "\tcp $(OUT_DIR)/app $(TARGET_DIR)/usr/bin/app\n"
                "\tprintf 'header\\n' > $(STAGING_DIR)/usr/include/app.h\n",
                encoding="utf-8",
            )
            recipe = {"name": "app", "build": {"class": "make"}}

            build_recipe(recipe, source_dir=source, install_root=root / "install")

            self.assertEqual((root / "install/usr/bin/app").read_text(encoding="utf-8"), "built\n")
            self.assertEqual((root / "install/.fenix-staging/usr/include/app.h").read_text(encoding="utf-8"), "header\n")


class CMakeBuildClassTests(unittest.TestCase):
    def test_cmake_build_installs_to_destdir(self) -> None:
        if shutil.which("cmake") is None:
            self.skipTest("cmake not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "CMakeLists.txt").write_text(
                "cmake_minimum_required(VERSION 3.16)\n"
                "project(App NONE)\n"
                "file(WRITE ${CMAKE_BINARY_DIR}/app \"cmake built\\n\")\n"
                "install(FILES ${CMAKE_BINARY_DIR}/app DESTINATION bin)\n",
                encoding="utf-8",
            )
            recipe = {
                "name": "app",
                "build": {
                    "class": "cmake",
                },
            }

            result = build_recipe(recipe, source_dir=source, build_root=root / "build", install_root=root / "install")

            self.assertEqual(result.build_class, "cmake")
            self.assertEqual((root / "install/usr/bin/app").read_text(encoding="utf-8"), "cmake built\n")


class MesonBuildClassTests(unittest.TestCase):
    def test_meson_build_installs_to_destdir(self) -> None:
        if shutil.which("meson") is None:
            self.skipTest("meson not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "meson.build").write_text(
                "project('app')\n"
                "install_data('app.txt', install_dir : 'bin', rename : 'app')\n",
                encoding="utf-8",
            )
            (source / "app.txt").write_text("meson built\n", encoding="utf-8")
            recipe = {
                "name": "app",
                "build": {
                    "class": "meson",
                },
            }

            result = build_recipe(recipe, source_dir=source, build_root=root / "build", install_root=root / "install")

            self.assertEqual(result.build_class, "meson")
            self.assertEqual((root / "install/usr/bin/app").read_text(encoding="utf-8"), "meson built\n")


class CargoBuildClassTests(unittest.TestCase):
    def test_cargo_build_installs_to_root(self) -> None:
        if shutil.which("cargo") is None:
            self.skipTest("cargo not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            (source / "src").mkdir(parents=True)
            (source / "Cargo.toml").write_text(
                "[package]\n"
                "name = \"app\"\n"
                "version = \"0.1.0\"\n"
                "edition = \"2021\"\n",
                encoding="utf-8",
            )
            (source / "Cargo.lock").write_text(
                "# This file is automatically @generated by Cargo.\n"
                "version = 3\n"
                "\n"
                "[[package]]\n"
                "name = \"app\"\n"
                "version = \"0.1.0\"\n",
                encoding="utf-8",
            )
            (source / "src/main.rs").write_text(
                "fn main() { println!(\"cargo built\"); }\n",
                encoding="utf-8",
            )
            recipe = {
                "name": "app",
                "build": {
                    "class": "cargo",
                    "offline": True,
                    "locked": True,
                },
            }

            result = build_recipe(recipe, source_dir=source, build_root=root / "build", install_root=root / "install")

            self.assertEqual(result.build_class, "cargo")
            self.assertTrue((root / "install/usr/bin/app").is_file())


class KernelModuleBuildClassTests(unittest.TestCase):
    def test_kernel_module_build_runs_kernel_make_flow(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "module"
            source.mkdir()
            kernel_build = root / "kernel-build"
            kernel_build.mkdir()
            fake_bin = root / "bin"
            fake_bin.mkdir()
            log = root / "make.log"
            fake_make = fake_bin / "make"
            fake_make.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$MAKE_LOG\"\n",
                encoding="utf-8",
            )
            fake_make.chmod(0o755)
            recipe = {
                "name": "vfm-cap",
                "build": {
                    "class": "kernel-module",
                    "env": {
                        "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                        "MAKE_LOG": str(log),
                    },
                },
            }
            metadata = {
                "schema": "fenix.kernel-build.v1",
                "kernel_version": "5.15.137",
                "architecture": "arm64",
                "build_dir": str(kernel_build),
                "cross_compile": "aarch64-none-linux-gnu-",
            }

            result = build_recipe(recipe, source_dir=source, install_root=root / "install", kernel_metadata=metadata)

            logged = log.read_text(encoding="utf-8")
            self.assertEqual(result.build_class, "kernel-module")
            self.assertIn(f"-C {kernel_build} M={source} ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- modules", logged)
            self.assertIn("INSTALL_MOD_PATH=" + str(root / "install"), logged)
            self.assertIn("INSTALL_MOD_DIR=extra/vfm-cap", logged)
            self.assertTrue((root / "install/lib/modules/5.15.137/extra/vfm-cap").is_dir())

    def test_kernel_module_requires_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "module"
            source.mkdir()
            recipe = {"name": "vfm-cap", "build": {"class": "kernel-module"}}

            with self.assertRaisesRegex(Exception, "kernel metadata"):
                build_recipe(recipe, source_dir=source, install_root=root / "install")


class VendorBlobBuildClassTests(unittest.TestCase):
    def test_vendor_blob_build_is_noop(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "blob"
            source.mkdir()
            recipe = {"name": "vendor-lib", "build": {"class": "vendor-blob"}}

            result = build_recipe(recipe, source_dir=source, install_root=root / "install")

            self.assertEqual(result.build_class, "vendor-blob")
            self.assertTrue((root / "install").is_dir())


if __name__ == "__main__":
    unittest.main()
