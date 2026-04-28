from __future__ import annotations

from pathlib import Path
import subprocess


class RootfsError(RuntimeError):
    pass


def run_rootfs_depmod(*, rootfs: Path, kernel_version: str, depmod: str = "depmod") -> None:
    if not rootfs.is_dir():
        raise RootfsError(f"rootfs directory does not exist: {rootfs}")
    if not kernel_version:
        raise RootfsError("kernel version must not be empty")
    command = [depmod, "-b", str(rootfs), kernel_version]
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise RootfsError(f"required command not found: {depmod}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise RootfsError(f"depmod failed for {kernel_version}: {detail}") from exc


def configure_local_apt_feed(*, rootfs: Path, feed_root: Path, name: str = "fenix-local") -> Path:
    if not rootfs.is_dir():
        raise RootfsError(f"rootfs directory does not exist: {rootfs}")
    if not feed_root.is_dir():
        raise RootfsError(f"feed directory does not exist: {feed_root}")
    if not (feed_root / "Packages").is_file() and not (feed_root / "Packages.gz").is_file():
        raise RootfsError(f"feed directory lacks Packages metadata: {feed_root}")

    sources_dir = rootfs / "etc/apt/sources.list.d"
    sources_dir.mkdir(parents=True, exist_ok=True)
    source_file = sources_dir / f"{name}.list"
    source_file.write_text(f"deb [trusted=yes] {feed_root.resolve().as_uri()} ./\n", encoding="utf-8")
    return source_file
