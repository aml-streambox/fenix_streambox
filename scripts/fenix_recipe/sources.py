from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlretrieve


@dataclass(frozen=True)
class FetchResult:
    recipe_name: str
    source_type: str
    source_dir: Path


class FetchError(RuntimeError):
    pass


def fetch_recipe_source(data: dict[str, Any], *, fetch_root: Path, repo_root: Path, recipe_path: Path | None = None) -> FetchResult:
    source = data["source"]
    source_type = source["type"]
    recipe_name = data["name"]
    destination = fetch_root / recipe_name
    fetch_root.mkdir(parents=True, exist_ok=True)

    if source_type == "git":
        source_dir = _fetch_git(source, destination)
    elif source_type == "local":
        source_dir = _fetch_local(source, destination, repo_root=repo_root, recipe_path=recipe_path)
    elif source_type == "tarball":
        source_dir = _fetch_tarball(source, destination, fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe_path)
    elif source_type == "vendor-blob":
        source_dir = _fetch_vendor_blob(source, destination, fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe_path)
    else:
        raise FetchError(f"unsupported source type '{source_type}'")

    subdir = source.get("subdir")
    if subdir:
        source_dir = source_dir / subdir
        if not source_dir.exists():
            raise FetchError(f"source subdir '{subdir}' does not exist in {destination}")

    return FetchResult(recipe_name=recipe_name, source_type=source_type, source_dir=source_dir)


def _fetch_git(source: dict[str, Any], destination: Path) -> Path:
    uri = source["uri"]
    revision = source["revision"]

    if destination.exists() and not (destination / ".git").exists():
        shutil.rmtree(destination)

    if not destination.exists():
        _run(["git", "clone", "--no-checkout", uri, str(destination)])
    else:
        _run(["git", "-C", str(destination), "fetch", "--all", "--tags", "--prune"])

    _run(["git", "-C", str(destination), "checkout", "--force", revision])
    _run(["git", "-C", str(destination), "submodule", "update", "--init", "--recursive"])
    return destination


def _fetch_local(source: dict[str, Any], destination: Path, *, repo_root: Path, recipe_path: Path | None) -> Path:
    source_path = _resolve_source_path(source["path"], repo_root=repo_root, recipe_path=recipe_path)
    if not source_path.exists() and not source_path.is_symlink():
        raise FetchError(f"local source path does not exist: {source_path}")

    _replace_path(destination)
    if source_path.is_dir():
        shutil.copytree(source_path, destination, symlinks=True, ignore=shutil.ignore_patterns(".git"))
    else:
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination / source_path.name, follow_symlinks=False)
    return destination


def _fetch_tarball(source: dict[str, Any], destination: Path, *, fetch_root: Path, repo_root: Path, recipe_path: Path | None) -> Path:
    archive = _obtain_file(source["uri"], fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe_path)
    _verify_sha256(archive, source["sha256"])

    _replace_path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    _extract_tarball(archive, destination)
    return destination


def _fetch_vendor_blob(source: dict[str, Any], destination: Path, *, fetch_root: Path, repo_root: Path, recipe_path: Path | None) -> Path:
    if "path" in source:
        blob = _resolve_source_path(source["path"], repo_root=repo_root, recipe_path=recipe_path)
    else:
        blob = _obtain_file(source["uri"], fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe_path)
    _verify_sha256(blob, source["sha256"])

    _replace_path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(blob, destination / blob.name, follow_symlinks=False)
    return destination


def _obtain_file(uri: str, *, fetch_root: Path, repo_root: Path, recipe_path: Path | None) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme in ("", "file"):
        raw_path = parsed.path if parsed.scheme == "file" else uri
        source_path = _resolve_source_path(raw_path, repo_root=repo_root, recipe_path=recipe_path)
        if not source_path.is_file():
            raise FetchError(f"source file does not exist: {source_path}")
        return source_path

    downloads = fetch_root / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    name = Path(parsed.path).name
    if not name:
        raise FetchError(f"cannot determine filename for URI: {uri}")
    destination = downloads / name
    urlretrieve(uri, destination)
    return destination


def _resolve_source_path(path: str, *, repo_root: Path, recipe_path: Path | None) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate

    if recipe_path is not None:
        recipe_relative = recipe_path.parent / candidate
        if recipe_relative.exists() or recipe_relative.is_symlink():
            return recipe_relative

    return repo_root / candidate


def _extract_tarball(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:*") as tar:
        for member in tar.getmembers():
            target = destination / member.name
            try:
                target.resolve().relative_to(destination.resolve())
            except ValueError as exc:
                raise FetchError(f"tarball member escapes destination: {member.name}") from exc
        tar.extractall(destination)


def _verify_sha256(path: Path, expected: str) -> None:
    actual = _sha256(path)
    if actual.lower() != expected.lower():
        raise FetchError(f"sha256 mismatch for {path}: expected {expected}, got {actual}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _replace_path(path: Path) -> None:
    if path.exists() or path.is_symlink():
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()


def _run(command: list[str]) -> None:
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as exc:
        raise FetchError(f"required command not found: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise FetchError(f"command failed: {' '.join(command)}: {detail}") from exc
