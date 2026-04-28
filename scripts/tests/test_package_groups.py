#!/usr/bin/env python3
from pathlib import Path
import json
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.package_groups import load_package_groups, select_package_groups, validate_package_group


def group(name: str, *, recipes: list[str], include: list[str] | None = None, board: str = "TVPRO") -> dict:
    return {
        "schema": "fenix.package-group.v1",
        "name": name,
        "selectors": {
            "boards": [board],
            "distributions": ["Ubuntu"],
            "releases": ["noble"],
            "image_types": ["server"],
            "install_types": ["EMMC"],
        },
        "include": include or [],
        "recipes": recipes,
        "distro_packages": ["openssh-server"],
    }


class PackageGroupTests(unittest.TestCase):
    def test_valid_group(self) -> None:
        self.assertEqual(validate_package_group(group("tvpro-server", recipes=["libvfmcap"])), [])

    def test_selector_filters_by_board(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            paths = self._write_groups(Path(tempdir), [group("tvpro-server", recipes=["libvfmcap"]), group("vim4-server", recipes=["other"], board="VIM4")])

            groups, load_issues = load_package_groups(paths)
            selection, selection_issues = select_package_groups(groups, board="TVPRO", distribution="Ubuntu", release="noble", image_type="server", install_type="EMMC")

        self.assertEqual(load_issues, [])
        self.assertEqual(selection_issues, [])
        self.assertEqual([item.name for item in selection.groups], ["tvpro-server"])
        self.assertEqual(selection.recipes, ["libvfmcap"])
        self.assertEqual(selection.distro_packages, ["openssh-server"])

    def test_includes_are_resolved_before_child_group(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            paths = self._write_groups(Path(tempdir), [group("base", recipes=["libvfmcap"]), group("apps", recipes=["gst-plugin-vfmcap"], include=["base"])])

            groups, load_issues = load_package_groups(paths)
            selection, selection_issues = select_package_groups(groups, board="TVPRO", distribution="Ubuntu", release="noble", image_type="server", install_type="EMMC")

        self.assertEqual(load_issues, [])
        self.assertEqual(selection_issues, [])
        self.assertEqual(selection.recipes, ["libvfmcap", "gst-plugin-vfmcap"])

    def _write_groups(self, directory: Path, groups: list[dict]) -> list[Path]:
        paths: list[Path] = []
        for item in groups:
            path = directory / f"{item['name']}.package-group.json"
            path.write_text(json.dumps(item), encoding="utf-8")
            paths.append(path)
        return paths


if __name__ == "__main__":
    unittest.main()
