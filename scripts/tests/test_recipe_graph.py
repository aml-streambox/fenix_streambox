#!/usr/bin/env python3
from pathlib import Path
import json
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.graph import load_recipes, topological_order


def recipe(name: str, deps: list[str] | None = None) -> dict:
    return {
        "schema": "fenix.recipe.v1",
        "name": name,
        "version": "1.0",
        "summary": f"{name} package",
        "license": "MIT",
        "source": {
            "type": "local",
            "path": f"packages/{name}",
        },
        "build": {
            "class": "make",
        },
        "dependencies": {
            "recipes": deps or [],
        },
        "outputs": [
            {
                "package": name,
                "architecture": "arm64",
                "description": f"{name} output",
                "files": [
                    {
                        "from": "dest/usr/bin/tool",
                        "to": "/usr/bin/tool",
                    }
                ],
            }
        ],
    }


class RecipeGraphTests(unittest.TestCase):
    def test_topological_order_places_dependencies_first(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            paths = self._write_recipes(Path(tempdir), [recipe("app", ["lib"]), recipe("lib")])

            recipes, load_issues = load_recipes(paths)
            ordered, graph_issues = topological_order(recipes)

        self.assertEqual(load_issues, [])
        self.assertEqual(graph_issues, [])
        self.assertEqual([item.name for item in ordered], ["lib", "app"])

    def test_missing_dependency_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            paths = self._write_recipes(Path(tempdir), [recipe("app", ["missing-lib"])])

            recipes, load_issues = load_recipes(paths)
            ordered, graph_issues = topological_order(recipes)

        self.assertEqual(load_issues, [])
        self.assertEqual(ordered, [])
        self.assertTrue(any("missing-lib" in issue.message for issue in graph_issues))

    def test_cycle_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            paths = self._write_recipes(Path(tempdir), [recipe("app", ["lib"]), recipe("lib", ["app"])])

            recipes, load_issues = load_recipes(paths)
            ordered, graph_issues = topological_order(recipes)

        self.assertEqual(load_issues, [])
        self.assertEqual(ordered, [])
        self.assertTrue(any("dependency cycle" in issue.message for issue in graph_issues))

    def _write_recipes(self, directory: Path, recipes: list[dict]) -> list[Path]:
        paths: list[Path] = []
        for item in recipes:
            path = directory / f"{item['name']}.recipe.json"
            path.write_text(json.dumps(item), encoding="utf-8")
            paths.append(path)
        return paths


if __name__ == "__main__":
    unittest.main()
