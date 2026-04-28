from __future__ import annotations

from dataclasses import dataclass
import gzip
from pathlib import Path
import shutil
import subprocess


@dataclass(frozen=True)
class FeedResult:
    feed_root: Path
    packages: Path
    packages_gz: Path
    deb_count: int


class FeedError(RuntimeError):
    pass


def generate_local_feed(*, debs_root: Path, feed_root: Path, arch: str | None = None) -> FeedResult:
    debs = sorted(debs_root.glob("*.deb"))
    if not debs:
        raise FeedError(f"no debs found in {debs_root}")

    pool = feed_root / "pool"
    if pool.exists():
        shutil.rmtree(pool)
    pool.mkdir(parents=True, exist_ok=True)
    for deb in debs:
        shutil.copy2(deb, pool / deb.name)

    command = ["dpkg-scanpackages"]
    if arch:
        command.extend(["--arch", arch])
    command.append("pool")
    try:
        result = subprocess.run(command, check=True, cwd=feed_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError as exc:
        raise FeedError("required command not found: dpkg-scanpackages") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.decode("utf-8", errors="replace").strip() or exc.stdout.decode("utf-8", errors="replace").strip()
        raise FeedError(f"dpkg-scanpackages failed: {detail}") from exc

    packages = feed_root / "Packages"
    packages.write_bytes(result.stdout)
    packages_gz = feed_root / "Packages.gz"
    with gzip.GzipFile(filename=str(packages_gz), mode="wb", compresslevel=9, mtime=0) as compressed:
        compressed.write(result.stdout)
    return FeedResult(feed_root=feed_root, packages=packages, packages_gz=packages_gz, deb_count=len(debs))
