#!/usr/bin/env python3
from pathlib import Path
import sys
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.validator import validate_recipe


VALID_RECIPE = {
    "schema": "fenix.recipe.v1",
    "name": "libvfmcap",
    "version": "0.1.0",
    "summary": "VFM capture helper library",
    "license": "MIT",
    "source": {
        "type": "git",
        "uri": "https://example.invalid/libvfmcap.git",
        "revision": "deadbeef",
    },
    "build": {
        "class": "cmake",
        "configure_args": ["-DENABLE_TESTS=OFF"],
    },
    "dependencies": {
        "recipes": [],
        "distro_dev": ["libdrm-dev"],
        "native_tools": ["cmake"],
    },
    "outputs": [
        {
            "package": "libvfmcap1",
            "architecture": "arm64",
            "description": "VFM capture runtime library",
            "runtime_depends": ["libc6"],
            "files": [
                {
                    "from": "dest/usr/lib/libvfmcap.so.1",
                    "to": "/usr/lib/libvfmcap.so.1",
                }
            ],
            "sysroot_exports": [
                {
                    "from": "dest/usr/include/vfmcap",
                    "to": "/usr/include/vfmcap",
                }
            ],
        }
    ],
}


class RecipeValidatorTests(unittest.TestCase):
    def test_valid_recipe(self) -> None:
        self.assertEqual(validate_recipe(VALID_RECIPE), [])

    def test_vendor_blob_requires_exception_metadata(self) -> None:
        recipe = dict(VALID_RECIPE)
        recipe["source"] = {
            "type": "vendor-blob",
            "uri": "https://example.invalid/blob.deb",
            "sha256": "0" * 64,
        }

        issues = validate_recipe(recipe)

        self.assertTrue(any(issue.location == "$" and "vendor_blob" in issue.message for issue in issues))

    def test_reports_nested_file_mapping_error(self) -> None:
        recipe = dict(VALID_RECIPE)
        recipe["outputs"] = [dict(VALID_RECIPE["outputs"][0])]
        recipe["outputs"][0]["files"] = [{"from": "dest/file", "to": "relative/path"}]

        issues = validate_recipe(recipe)

        self.assertTrue(any(issue.location == "$.outputs[0].files[0].to" for issue in issues))


if __name__ == "__main__":
    unittest.main()
