from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class EnabledService:
    unit: str
    symlinks: list[Path]


class SystemdError(RuntimeError):
    pass


def enabled_services(data: dict[str, Any]) -> list[str]:
    units: list[str] = []
    seen: set[str] = set()
    for output in data.get("outputs", []):
        for service in output.get("services", []):
            unit = service["unit"]
            if service.get("enable", False) and unit not in seen:
                units.append(unit)
                seen.add(unit)
    return units


def enable_recipe_services(data: dict[str, Any], *, rootfs: Path) -> list[EnabledService]:
    enabled: list[EnabledService] = []
    for unit in enabled_services(data):
        unit_path = _find_unit(rootfs, unit)
        install_targets = _read_install_targets(unit_path)
        if not install_targets:
            raise SystemdError(f"enabled unit has no [Install] WantedBy/RequiredBy targets: {unit}")
        symlinks = [_create_install_symlink(rootfs, unit_path, target, relation) for relation, target in install_targets]
        enabled.append(EnabledService(unit=unit, symlinks=symlinks))
    return enabled


def _find_unit(rootfs: Path, unit: str) -> Path:
    candidates = [
        rootfs / "etc/systemd/system" / unit,
        rootfs / "lib/systemd/system" / unit,
        rootfs / "usr/lib/systemd/system" / unit,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemdError(f"systemd unit not found in rootfs: {unit}")


def _read_install_targets(unit_path: Path) -> list[tuple[str, str]]:
    in_install = False
    targets: list[tuple[str, str]] = []
    for raw_line in unit_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_install = line == "[Install]"
            continue
        if not in_install or "=" not in line:
            continue
        key, value = line.split("=", 1)
        relation = {"WantedBy": "wants", "RequiredBy": "requires"}.get(key)
        if relation is None:
            continue
        for target in value.split():
            targets.append((relation, target))
    return targets


def _create_install_symlink(rootfs: Path, unit_path: Path, target: str, relation: str) -> Path:
    wants_dir = rootfs / "etc/systemd/system" / f"{target}.{relation}"
    wants_dir.mkdir(parents=True, exist_ok=True)
    link = wants_dir / unit_path.name
    if link.exists() or link.is_symlink():
        link.unlink()
    link.symlink_to("/" + unit_path.relative_to(rootfs).as_posix())
    return link
