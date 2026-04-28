#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.sources import fetch_recipe_source


def base_recipe(source: dict) -> dict:
    return {
        "schema": "fenix.recipe.v1",
        "name": "app",
        "version": "1.0",
        "summary": "app package",
        "license": "MIT",
        "source": source,
        "build": {"class": "make"},
        "dependencies": {"recipes": []},
        "outputs": [
            {
                "package": "app",
                "architecture": "arm64",
                "description": "app output",
                "files": [{"from": "dest/usr/bin/app", "to": "/usr/bin/app"}],
            }
        ],
    }


class SourceFetchTests(unittest.TestCase):
    def test_fetches_local_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            source = root / "src"
            source.mkdir()
            (source / "main.c").write_text("source\n", encoding="utf-8")

            result = fetch_recipe_source(base_recipe({"type": "local", "path": "src"}), fetch_root=root / "fetch", repo_root=root)

            self.assertEqual((result.source_dir / "main.c").read_text(encoding="utf-8"), "source\n")

    def test_fetches_and_extracts_tarball(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            payload = root / "payload"
            payload.mkdir()
            (payload / "file.txt").write_text("payload\n", encoding="utf-8")
            archive = root / "payload.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(payload / "file.txt", arcname="file.txt")

            result = fetch_recipe_source(
                base_recipe({"type": "tarball", "uri": str(archive), "sha256": sha256(archive)}),
                fetch_root=root / "fetch",
                repo_root=root,
            )

            self.assertEqual((result.source_dir / "file.txt").read_text(encoding="utf-8"), "payload\n")

    def test_fetches_vendor_blob(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            blob = root / "blob.deb"
            blob.write_bytes(b"blob")

            result = fetch_recipe_source(
                base_recipe({"type": "vendor-blob", "path": "blob.deb", "sha256": sha256(blob)}),
                fetch_root=root / "fetch",
                repo_root=root,
            )

            self.assertEqual((result.source_dir / "blob.deb").read_bytes(), b"blob")

    def test_fetches_git_revision(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git not available")

        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            repo = root / "repo"
            repo.mkdir()
            run_git(repo, "init")
            (repo / "main.c").write_text("git source\n", encoding="utf-8")
            run_git(repo, "add", "main.c")
            run_git(repo, "-c", "user.name=Fenix", "-c", "user.email=fenix@example.invalid", "commit", "-m", "initial")
            revision = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True, stdout=subprocess.PIPE, text=True).stdout.strip()

            result = fetch_recipe_source(
                base_recipe({"type": "git", "uri": str(repo), "revision": revision}),
                fetch_root=root / "fetch",
                repo_root=root,
            )

            self.assertEqual((result.source_dir / "main.c").read_text(encoding="utf-8"), "git source\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


if __name__ == "__main__":
    unittest.main()
