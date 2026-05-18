from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
from typing import Any


@dataclass(frozen=True)
class DebPackage:
    package: str
    path: Path


class DebPackageError(RuntimeError):
    pass


def build_deb_packages(data: dict[str, Any], *, install_root: Path, debs_root: Path) -> list[DebPackage]:
    debs_root.mkdir(parents=True, exist_ok=True)
    work_root = debs_root / ".work" / data["name"]
    if work_root.exists():
        shutil.rmtree(work_root)
    work_root.mkdir(parents=True)

    built: list[DebPackage] = []
    for output in data.get("outputs", []):
        package_root = work_root / output["package"]
        _populate_package_root(data, output, install_root=install_root, package_root=package_root)
        deb_path = debs_root / f"{output['package']}_{data['version']}_{output['architecture']}.deb"
        _build_deb(package_root, deb_path)
        built.append(DebPackage(package=output["package"], path=deb_path))
    return built


def _populate_package_root(data: dict[str, Any], output: dict[str, Any], *, install_root: Path, package_root: Path) -> None:
    debian_dir = package_root / "DEBIAN"
    debian_dir.mkdir(parents=True, exist_ok=True)
    _write_control(data, output, debian_dir / "control")

    if data.get("build", {}).get("class") == "kernel-module":
        _copy_kernel_module_payload(data, install_root=install_root, package_root=package_root)
        _write_kernel_module_postinst(debian_dir / "postinst")
    _write_kernel_module_metadata(output, install_root=install_root, package_root=package_root)

    for mapping in output.get("files", []):
        source = install_root / mapping["from"]
        destination = package_root / mapping["to"].lstrip("/")
        if not source.exists() and not source.is_symlink():
            raise DebPackageError(f"package file source does not exist: {source}")
        _copy_path(source, destination)
        if "mode" in mapping and not destination.is_symlink():
            destination.chmod(int(mapping["mode"], 8))


def _copy_kernel_module_payload(data: dict[str, Any], *, install_root: Path, package_root: Path) -> None:
    module_roots = sorted((install_root / "lib/modules").glob(f"*/extra/{data['name']}"))
    if not module_roots:
        raise DebPackageError(f"no staged kernel modules found under {install_root / 'lib/modules'}")
    for module_root in module_roots:
        relative = module_root.relative_to(install_root)
        _copy_path(module_root, package_root / relative)


def _write_kernel_module_metadata(output: dict[str, Any], *, install_root: Path, package_root: Path) -> None:
    autoload: list[str] = []
    options: list[str] = []
    for module in output.get("kernel_modules", []):
        module_name = module.get("autoload")
        if module_name:
            autoload.append(module_name)
            if module.get("options"):
                options.append(f"options {module_name} {module['options']}")
        for rule in module.get("udev_rules", []):
            source = install_root / rule
            if not source.is_file():
                raise DebPackageError(f"udev rule source does not exist: {source}")
            _copy_path(source, package_root / "etc/udev/rules.d" / source.name)

    if autoload:
        modules_load = package_root / "etc/modules-load.d" / f"{output['package']}.conf"
        modules_load.parent.mkdir(parents=True, exist_ok=True)
        modules_load.write_text("\n".join(autoload) + "\n", encoding="utf-8")
    if options:
        modprobe = package_root / "etc/modprobe.d" / f"{output['package']}.conf"
        modprobe.parent.mkdir(parents=True, exist_ok=True)
        modprobe.write_text("\n".join(options) + "\n", encoding="utf-8")


def _write_kernel_module_postinst(path: Path) -> None:
    path.write_text(
        "#!/bin/sh\n"
        "set -e\n"
        "if command -v depmod >/dev/null 2>&1; then\n"
        "\tdepmod -a || true\n"
        "fi\n"
        "\n"
        "exit 0\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def _write_control(data: dict[str, Any], output: dict[str, Any], path: Path) -> None:
    depends = ", ".join(output.get("runtime_depends", []))
    lines = [
        f"Package: {output['package']}",
        f"Version: {data['version']}",
        f"Architecture: {output['architecture']}",
        f"Maintainer: Fenix <fenix@example.invalid>",
        f"Section: {output.get('section', 'misc')}",
        f"Priority: {output.get('priority', 'optional')}",
    ]
    if depends:
        lines.append(f"Depends: {depends}")
    lines.extend(["Description: " + output["description"], ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def _build_deb(package_root: Path, deb_path: Path) -> None:
    command = ["dpkg-deb", "--root-owner-group", "-b", str(package_root), str(deb_path)]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise DebPackageError("required command not found: dpkg-deb") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise DebPackageError(f"dpkg-deb failed for {package_root}: {detail}") from exc


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
