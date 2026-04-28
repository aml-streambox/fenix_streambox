#!/usr/bin/env python3
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.stamps import compute_phase_stamp, is_stamp_current, write_stamp


def recipe(source_path: str) -> dict:
    return {
        "schema": "fenix.recipe.v1",
        "name": "app",
        "version": "1.0",
        "summary": "app package",
        "license": "MIT",
        "source": {
            "type": "local",
            "path": source_path,
        },
        "patches": ["fix.patch"],
        "build": {
            "class": "make",
            "build_args": ["all"],
        },
        "dependencies": {
            "recipes": [],
        },
        "outputs": [
            {
                "package": "app",
                "architecture": "arm64",
                "description": "app output",
                "files": [
                    {
                        "from": "dest/usr/bin/app",
                        "to": "/usr/bin/app",
                    }
                ],
            }
        ],
    }


class RecipeStampTests(unittest.TestCase):
    def test_local_source_content_changes_fetch_stamp(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "main.c").write_text("one\n", encoding="utf-8")
            item = recipe("src")

            first = compute_phase_stamp(item, "fetch", repo_root=root)
            (source / "main.c").write_text("two\n", encoding="utf-8")
            second = compute_phase_stamp(item, "fetch", repo_root=root)

        self.assertNotEqual(first, second)

    def test_patch_content_changes_patch_stamp(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "main.c").write_text("one\n", encoding="utf-8")
            patch = root / "fix.patch"
            patch.write_text("patch one\n", encoding="utf-8")
            item = recipe("src")

            first = compute_phase_stamp(item, "patch", repo_root=root, recipe_path=root / "app.recipe.json")
            patch.write_text("patch two\n", encoding="utf-8")
            second = compute_phase_stamp(item, "patch", repo_root=root, recipe_path=root / "app.recipe.json")

        self.assertNotEqual(first, second)

    def test_stamp_store_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            build_root = Path(tempdir)
            digest = "a" * 64

            self.assertFalse(is_stamp_current(build_root, "app", "build", digest))
            write_stamp(build_root, "app", "build", digest)

            self.assertTrue(is_stamp_current(build_root, "app", "build", digest))


if __name__ == "__main__":
    unittest.main()
