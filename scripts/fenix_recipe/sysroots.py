from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
from typing import Any


@dataclass(frozen=True)
class SysrootStageResult:
    staged: list[Path]


class SysrootError(RuntimeError):
    pass


def check_native_tools(data: dict[str, Any]) -> list[str]:
    missing: list[str] = []
    for tool in data.get("dependencies", {}).get("native_tools", []):
        if shutil.which(tool) is None:
            missing.append(tool)
    return missing


def stage_recipe_sysroot_exports(data: dict[str, Any], *, package_root: Path, sysroot: Path) -> SysrootStageResult:
    staged: list[Path] = []
    for output in data.get("outputs", []):
        for export in output.get("sysroot_exports", []):
            source = package_root / export["from"].lstrip("/")
            destination = sysroot / export["to"].lstrip("/")
            if not source.exists() and not source.is_symlink():
                raise SysrootError(f"sysroot export source does not exist: {source}")
            _copy_path(source, destination)
            staged.append(destination)
    return SysrootStageResult(staged=staged)


def extract_deb_to_sysroot(deb_path: Path, *, sysroot: Path) -> SysrootStageResult:
    if not deb_path.is_file():
        raise SysrootError(f"deb does not exist: {deb_path}")
    sysroot.mkdir(parents=True, exist_ok=True)
    command = ["dpkg-deb", "-x", str(deb_path), str(sysroot)]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise SysrootError("required command not found: dpkg-deb") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise SysrootError(f"failed to extract {deb_path}: {detail}") from exc
    return SysrootStageResult(staged=[sysroot])


def _copy_path(source: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        if destination.is_dir() and not destination.is_symlink():
            shutil.rmtree(destination)
        else:
            destination.unlink()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(source.readlink())
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)
