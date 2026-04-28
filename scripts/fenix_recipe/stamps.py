from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


PHASES = ("fetch", "patch", "build", "install", "package")
_PHASE_INDEX = {phase: index for index, phase in enumerate(PHASES)}


def compute_phase_stamp(data: dict[str, Any], phase: str, *, repo_root: Path, recipe_path: Path | None = None) -> str:
    if phase not in _PHASE_INDEX:
        raise ValueError(f"unknown phase '{phase}'")

    material = _phase_material(data, phase, repo_root=repo_root, recipe_path=recipe_path)
    encoded = json.dumps(material, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def stamp_file(build_root: Path, recipe_name: str, phase: str) -> Path:
    return build_root / "stamps" / "recipes" / recipe_name / f"{phase}.stamp"


def is_stamp_current(build_root: Path, recipe_name: str, phase: str, digest: str) -> bool:
    path = stamp_file(build_root, recipe_name, phase)
    try:
        return path.read_text(encoding="utf-8").strip() == digest
    except FileNotFoundError:
        return False


def write_stamp(build_root: Path, recipe_name: str, phase: str, digest: str) -> None:
    path = stamp_file(build_root, recipe_name, phase)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(digest + "\n", encoding="utf-8")


def _phase_material(data: dict[str, Any], phase: str, *, repo_root: Path, recipe_path: Path | None) -> dict[str, Any]:
    material: dict[str, Any] = {
        "stamp_schema": 1,
        "phase": phase,
        "recipe": {
            "schema": data.get("schema"),
            "name": data.get("name"),
            "version": data.get("version"),
            "license": data.get("license"),
        },
        "source": _source_material(data.get("source", {}), repo_root=repo_root),
    }

    if _includes(phase, "patch"):
        material["patches"] = _patch_materials(data.get("patches", []), repo_root=repo_root, recipe_path=recipe_path)

    if _includes(phase, "build"):
        material["build"] = data.get("build", {})
        material["dependencies"] = data.get("dependencies", {})

    if _includes(phase, "install"):
        material["install_outputs"] = _output_subset(data.get("outputs", []), include_package_metadata=False)

    if _includes(phase, "package"):
        material["outputs"] = data.get("outputs", [])
        material["vendor_blob"] = data.get("vendor_blob")
        material["metadata"] = data.get("metadata", {})

    return material


def _includes(phase: str, required_phase: str) -> bool:
    return _PHASE_INDEX[phase] >= _PHASE_INDEX[required_phase]


def _source_material(source: dict[str, Any], *, repo_root: Path) -> dict[str, Any]:
    source_type = source.get("type")
    material = dict(source)

    if source_type == "local" and isinstance(source.get("path"), str):
        path = Path(source["path"])
        source_path = path if path.is_absolute() else repo_root / path
        material["content"] = _path_digest(source_path)

    return material


def _patch_materials(patches: list[str], *, repo_root: Path, recipe_path: Path | None) -> list[dict[str, Any]]:
    base_dir = recipe_path.parent if recipe_path is not None else repo_root
    materials: list[dict[str, Any]] = []
    for patch in patches:
        path = Path(patch)
        patch_path = path if path.is_absolute() else base_dir / path
        materials.append({"path": patch, "content": _path_digest(patch_path)})
    return materials


def _output_subset(outputs: list[dict[str, Any]], *, include_package_metadata: bool) -> list[dict[str, Any]]:
    subset: list[dict[str, Any]] = []
    for output in outputs:
        item = {
            "package": output.get("package"),
            "files": output.get("files", []),
            "sysroot_exports": output.get("sysroot_exports", []),
            "services": output.get("services", []),
            "kernel_modules": output.get("kernel_modules", []),
        }
        if include_package_metadata:
            item.update(output)
        subset.append(item)
    return subset


def _path_digest(path: Path) -> dict[str, Any]:
    if not path.exists() and not path.is_symlink():
        return {"exists": False}
    if path.is_symlink():
        return {"exists": True, "type": "symlink", "target": str(path.readlink())}
    if path.is_file():
        return {"exists": True, "type": "file", "sha256": _file_digest(path)}
    if path.is_dir():
        entries: list[dict[str, Any]] = []
        for child in sorted(path.rglob("*")):
            relative = child.relative_to(path).as_posix()
            if ".git" in child.relative_to(path).parts:
                continue
            if child.is_symlink():
                entries.append({"path": relative, "type": "symlink", "target": str(child.readlink())})
            elif child.is_file():
                entries.append({"path": relative, "type": "file", "sha256": _file_digest(child)})
            elif child.is_dir():
                entries.append({"path": relative, "type": "dir"})
        return {"exists": True, "type": "dir", "entries": entries}
    return {"exists": True, "type": "other"}


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
