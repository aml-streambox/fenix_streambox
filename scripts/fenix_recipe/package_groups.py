from __future__ import annotations

from dataclasses import dataclass
import json
from json import JSONDecodeError
from pathlib import Path
import re
from typing import Any

from .validator import ValidationIssue


GROUP_SCHEMA = "fenix.package-group.v1"
GROUP_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9+._-]*$")
GROUP_KEYS = {"schema", "name", "selectors", "include", "recipes", "distro_packages", "notes"}
SELECTOR_KEYS = {"boards", "distributions", "releases", "image_types", "install_types"}


@dataclass(frozen=True)
class PackageGroup:
    name: str
    path: Path
    data: dict[str, Any]


@dataclass(frozen=True)
class Selection:
    groups: list[PackageGroup]
    recipes: list[str]
    distro_packages: list[str]


def validate_package_group_file(path: Path) -> list[ValidationIssue]:
    try:
        with path.open("r", encoding="utf-8") as group_file:
            data = json.load(group_file)
    except FileNotFoundError:
        return [ValidationIssue("$", "file does not exist")]
    except JSONDecodeError as exc:
        return [ValidationIssue("$", f"invalid JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}")]
    except OSError as exc:
        return [ValidationIssue("$", f"cannot read file: {exc}")]

    return validate_package_group(data)


def validate_package_group(data: Any) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    if not isinstance(data, dict):
        return [ValidationIssue("$", "package group must be a JSON object")]

    _check_required(data, ["schema", "name", "selectors", "recipes"], "$", issues)
    _check_unknown(data, GROUP_KEYS, "$", issues)
    _check_literal(data, "schema", GROUP_SCHEMA, "$.schema", issues)
    _check_string(data, "name", "$.name", issues, pattern=GROUP_NAME_RE)
    _check_string_list(data, "include", "$.include", issues, required=False)
    _check_string_list(data, "recipes", "$.recipes", issues)
    _check_string_list(data, "distro_packages", "$.distro_packages", issues, required=False)
    _check_string(data, "notes", "$.notes", issues, required=False)

    selectors = _check_object(data, "selectors", "$.selectors", issues)
    if selectors is not None:
        _check_unknown(selectors, SELECTOR_KEYS, "$.selectors", issues)
        for key in sorted(SELECTOR_KEYS):
            _check_string_list(selectors, key, f"$.selectors.{key}", issues, required=False)

    return issues


def load_package_groups(paths: list[Path]) -> tuple[dict[str, PackageGroup], list[tuple[Path, ValidationIssue]]]:
    groups: dict[str, PackageGroup] = {}
    issues: list[tuple[Path, ValidationIssue]] = []

    for path in paths:
        validation_issues = validate_package_group_file(path)
        if validation_issues:
            issues.extend((path, issue) for issue in validation_issues)
            continue

        with path.open("r", encoding="utf-8") as group_file:
            data = json.load(group_file)
        name = data["name"]
        if name in groups:
            issues.append((path, ValidationIssue("$.name", f"duplicate package group name '{name}', already defined in {groups[name].path}")))
            continue
        groups[name] = PackageGroup(name=name, path=path, data=data)

    return groups, issues


def select_package_groups(
    groups: dict[str, PackageGroup],
    *,
    board: str,
    distribution: str,
    release: str,
    image_type: str,
    install_type: str,
) -> tuple[Selection, list[ValidationIssue]]:
    selected = [
        group
        for group in groups.values()
        if _matches(group.data.get("selectors", {}), board=board, distribution=distribution, release=release, image_type=image_type, install_type=install_type)
    ]
    selected = sorted(selected, key=lambda group: group.name)

    ordered_groups: list[PackageGroup] = []
    recipes: list[str] = []
    distro_packages: list[str] = []
    issues: list[ValidationIssue] = []
    visited: set[str] = set()
    stack: list[str] = []

    def add_group(group: PackageGroup) -> None:
        if group.name in visited:
            return
        if group.name in stack:
            cycle = stack[stack.index(group.name):] + [group.name]
            issues.append(ValidationIssue("$.include", "package group include cycle: " + " -> ".join(cycle)))
            return
        stack.append(group.name)
        for included in group.data.get("include", []):
            if included not in groups:
                issues.append(ValidationIssue("$.include", f"unknown package group include '{included}'"))
                continue
            add_group(groups[included])
        stack.pop()
        visited.add(group.name)
        ordered_groups.append(group)
        recipes.extend(_append_unique(recipes, group.data.get("recipes", [])))
        distro_packages.extend(_append_unique(distro_packages, group.data.get("distro_packages", [])))

    for group in selected:
        add_group(group)

    return Selection(groups=ordered_groups, recipes=recipes, distro_packages=distro_packages), issues


def _matches(selectors: dict[str, Any], *, board: str, distribution: str, release: str, image_type: str, install_type: str) -> bool:
    return all(
        (
            _matches_one(selectors.get("boards", []), board),
            _matches_one(selectors.get("distributions", []), distribution),
            _matches_one(selectors.get("releases", []), release),
            _matches_one(selectors.get("image_types", []), image_type),
            _matches_one(selectors.get("install_types", []), install_type),
        )
    )


def _matches_one(values: list[str], actual: str) -> bool:
    return not values or "*" in values or actual in values


def _append_unique(existing: list[str], values: list[str]) -> list[str]:
    added: list[str] = []
    seen = set(existing)
    for value in values:
        if value not in seen:
            added.append(value)
            seen.add(value)
    return added


def _check_required(data: dict[str, Any], keys: list[str], location: str, issues: list[ValidationIssue]) -> None:
    for key in keys:
        if key not in data:
            issues.append(ValidationIssue(location, f"missing required field '{key}'"))


def _check_unknown(data: dict[str, Any], allowed: set[str], location: str, issues: list[ValidationIssue]) -> None:
    for key in sorted(set(data) - allowed):
        issues.append(ValidationIssue(f"{location}.{key}", "unknown field"))


def _check_literal(data: dict[str, Any], key: str, expected: str, location: str, issues: list[ValidationIssue]) -> None:
    if key in data and data[key] != expected:
        issues.append(ValidationIssue(location, f"must be '{expected}'"))


def _check_string(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
    pattern: re.Pattern[str] | None = None,
) -> str | None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, str):
        issues.append(ValidationIssue(location, "must be a string"))
        return None
    if not value:
        issues.append(ValidationIssue(location, "must not be empty"))
    if pattern is not None and not pattern.match(value):
        issues.append(ValidationIssue(location, "has invalid format"))
    return value


def _check_object(data: dict[str, Any], key: str, location: str, issues: list[ValidationIssue]) -> dict[str, Any] | None:
    if key not in data:
        issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, dict):
        issues.append(ValidationIssue(location, "must be an object"))
        return None
    return value


def _check_string_list(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
) -> None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return
    value = data[key]
    if not isinstance(value, list):
        issues.append(ValidationIssue(location, "must be an array"))
        return
    for index, item in enumerate(value):
        if not isinstance(item, str):
            issues.append(ValidationIssue(f"{location}[{index}]", "must be a string"))
        elif not item:
            issues.append(ValidationIssue(f"{location}[{index}]", "must not be empty"))
