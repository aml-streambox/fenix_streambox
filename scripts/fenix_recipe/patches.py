from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
from typing import Any


@dataclass(frozen=True)
class PatchResult:
    source_dir: Path
    applied: list[Path]


class PatchError(RuntimeError):
    pass


def apply_recipe_patches(data: dict[str, Any], *, source_dir: Path, repo_root: Path, recipe_path: Path | None = None) -> PatchResult:
    applied: list[Path] = []
    for patch_entry in data.get("patches", []):
        patch_path = _resolve_patch_path(patch_entry, repo_root=repo_root, recipe_path=recipe_path)
        if not patch_path.is_file():
            raise PatchError(f"patch file does not exist: {patch_path}")
        _apply_patch(source_dir, patch_path.resolve())
        applied.append(patch_path)
    return PatchResult(source_dir=source_dir, applied=applied)


def _resolve_patch_path(path: str, *, repo_root: Path, recipe_path: Path | None) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    if recipe_path is not None:
        recipe_relative = recipe_path.parent / candidate
        if recipe_relative.exists():
            return recipe_relative
    return repo_root / candidate


def _apply_patch(source_dir: Path, patch_path: Path) -> None:
    if not source_dir.is_dir():
        raise PatchError(f"source directory does not exist: {source_dir}")

    command = ["patch", "--batch", "--forward", "-d", str(source_dir), "-p1", "-i", str(patch_path)]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise PatchError("required command not found: patch") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise PatchError(f"patch failed for {patch_path}: {detail}") from exc
