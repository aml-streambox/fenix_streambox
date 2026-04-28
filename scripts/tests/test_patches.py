#!/usr/bin/env python3
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.patches import apply_recipe_patches


class PatchTests(unittest.TestCase):
    def test_applies_package_local_patch(self) -> None:
        if shutil.which("patch") is None:
            self.skipTest("patch not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "hello.txt").write_text("hello\n", encoding="utf-8")
            patch = root / "fix.patch"
            patch.write_text(
                "--- a/hello.txt\n"
                "+++ b/hello.txt\n"
                "@@ -1 +1 @@\n"
                "-hello\n"
                "+hello patched\n",
                encoding="utf-8",
            )
            recipe = {"patches": ["fix.patch"]}

            result = apply_recipe_patches(recipe, source_dir=source, repo_root=root, recipe_path=root / "app.recipe.json")

            self.assertEqual(result.applied, [patch])
            self.assertEqual((source / "hello.txt").read_text(encoding="utf-8"), "hello patched\n")


if __name__ == "__main__":
    unittest.main()
