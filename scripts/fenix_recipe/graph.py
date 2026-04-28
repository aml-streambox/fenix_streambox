from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .validator import ValidationIssue, validate_recipe_file


@dataclass(frozen=True)
class Recipe:
    name: str
    path: Path
    data: dict[str, Any]


@dataclass(frozen=True)
class RecipeIssue:
    path: Path | None
    location: str
    message: str


def load_recipes(paths: list[Path]) -> tuple[dict[str, Recipe], list[RecipeIssue]]:
    recipes: dict[str, Recipe] = {}
    issues: list[RecipeIssue] = []

    for path in paths:
        validation_issues = validate_recipe_file(path)
        if validation_issues:
            issues.extend(_convert_validation_issues(path, validation_issues))
            continue

        data = _load_valid_json(path)
        name = data["name"]
        if name in recipes:
            issues.append(RecipeIssue(path, "$.name", f"duplicate recipe name '{name}', already defined in {recipes[name].path}"))
            continue
        recipes[name] = Recipe(name=name, path=path, data=data)

    return recipes, issues


def topological_order(recipes: dict[str, Recipe]) -> tuple[list[Recipe], list[RecipeIssue]]:
    ordered: list[Recipe] = []
    issues: list[RecipeIssue] = []
    state: dict[str, str] = {}
    stack: list[str] = []

    def visit(name: str) -> None:
        current_state = state.get(name)
        if current_state == "done":
            return
        if current_state == "visiting":
            cycle_start = stack.index(name) if name in stack else 0
            cycle = stack[cycle_start:] + [name]
            issues.append(RecipeIssue(recipes[name].path, "$.dependencies.recipes", "dependency cycle: " + " -> ".join(cycle)))
            return

        recipe = recipes[name]
        state[name] = "visiting"
        stack.append(name)
        for dependency in recipe.data.get("dependencies", {}).get("recipes", []):
            if dependency not in recipes:
                issues.append(RecipeIssue(recipe.path, "$.dependencies.recipes", f"unknown recipe dependency '{dependency}'"))
                continue
            visit(dependency)
        stack.pop()
        state[name] = "done"
        ordered.append(recipe)

    for name in sorted(recipes):
        visit(name)

    if issues:
        return [], issues
    return ordered, []


def _convert_validation_issues(path: Path, issues: list[ValidationIssue]) -> list[RecipeIssue]:
    return [RecipeIssue(path, issue.location, issue.message) for issue in issues]


def _load_valid_json(path: Path) -> dict[str, Any]:
    import json

    with path.open("r", encoding="utf-8") as recipe_file:
        data = json.load(recipe_file)
    return data
