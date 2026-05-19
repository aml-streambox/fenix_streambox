from __future__ import annotations

from dataclasses import dataclass
import os
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any


@dataclass(frozen=True)
class BuildResult:
    recipe_name: str
    build_class: str
    source_dir: Path
    install_root: Path


class BuildError(RuntimeError):
    pass


def build_recipe(
    data: dict[str, Any],
    *,
    source_dir: Path,
    install_root: Path,
    build_root: Path | None = None,
    target_sysroot: Path | None = None,
    kernel_metadata: dict[str, Any] | None = None,
    jobs: int | None = None,
) -> BuildResult:
    build = data["build"]
    build_class = build["class"]
    if build_class == "make":
        _build_make(data, source_dir=source_dir, install_root=install_root, target_sysroot=target_sysroot, jobs=jobs)
    elif build_class == "cmake":
        if build_root is None:
            build_root = source_dir / ".fenix-build"
        _build_cmake(data, source_dir=source_dir, build_dir=build_root / data["name"], install_root=install_root, target_sysroot=target_sysroot, jobs=jobs)
    elif build_class == "meson":
        if build_root is None:
            build_root = source_dir / ".fenix-build"
        _build_meson(data, source_dir=source_dir, build_dir=build_root / data["name"], install_root=install_root, target_sysroot=target_sysroot, jobs=jobs)
    elif build_class == "autotools":
        _build_autotools(data, source_dir=source_dir, install_root=install_root, target_sysroot=target_sysroot, jobs=jobs)
    elif build_class == "cargo":
        if build_root is None:
            build_root = source_dir / ".fenix-build"
        _build_cargo(data, source_dir=source_dir, build_dir=build_root / data["name"], install_root=install_root, target_sysroot=target_sysroot, jobs=jobs)
    elif build_class == "kernel-module":
        if kernel_metadata is None:
            raise BuildError("kernel-module build requires kernel metadata")
        _build_kernel_module(data, source_dir=source_dir, install_root=install_root, kernel_metadata=kernel_metadata, jobs=jobs)
    elif build_class == "vendor-blob":
        install_root.mkdir(parents=True, exist_ok=True)
    else:
        raise BuildError(f"unsupported build class '{build_class}'")

    return BuildResult(recipe_name=data["name"], build_class=build_class, source_dir=source_dir, install_root=install_root)


def _build_make(data: dict[str, Any], *, source_dir: Path, install_root: Path, target_sysroot: Path | None, jobs: int | None) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")

    install_root.mkdir(parents=True, exist_ok=True)
    _prepare_legacy_make_dirs(install_root)
    build = data["build"]
    env = _build_env(build, target_sysroot=target_sysroot)
    _set_make_install_env(env, source_dir=source_dir, install_root=install_root, target_sysroot=target_sysroot)
    common_args = list(build.get("build_args", []))

    build_command = ["make", "-C", str(source_dir)]
    if jobs is not None and jobs > 0:
        build_command.append(f"-j{jobs}")
    build_command.extend(build.get("targets", []))
    build_command.extend(common_args)
    _run(build_command, env=env)

    install_target = build.get("install_target", "install")
    if install_target:
        install_command = ["make", "-C", str(source_dir), f"DESTDIR={install_root}", install_target]
        install_command.extend(build.get("install_args", []))
        _run(install_command, env=env)


def _build_cmake(
    data: dict[str, Any],
    *,
    source_dir: Path,
    build_dir: Path,
    install_root: Path,
    target_sysroot: Path | None,
    jobs: int | None,
) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")
    if target_sysroot is not None:
        target_sysroot = target_sysroot.resolve()

    build = data["build"]
    build_dir.mkdir(parents=True, exist_ok=True)
    install_root.mkdir(parents=True, exist_ok=True)
    env = _build_env(build, target_sysroot=target_sysroot)

    configure_command = ["cmake", "-S", str(source_dir), "-B", str(build_dir), "-DCMAKE_INSTALL_PREFIX=/usr"]
    if target_sysroot is not None and not any(arg.startswith("-DCMAKE_FIND_ROOT_PATH=") for arg in build.get("configure_args", [])):
        configure_command.append(f"-DCMAKE_FIND_ROOT_PATH={target_sysroot}")
        configure_command.append(f"-DCMAKE_PREFIX_PATH={target_sysroot / 'usr'}")
    if target_sysroot is not None and not any(arg.startswith("-DCMAKE_C_FLAGS=") for arg in build.get("configure_args", [])):
        configure_command.append(f"-DCMAKE_C_FLAGS=-I{target_sysroot / 'usr/include'}")
    if target_sysroot is not None and not any(arg.startswith("-DCMAKE_CXX_FLAGS=") for arg in build.get("configure_args", [])):
        configure_command.append(f"-DCMAKE_CXX_FLAGS=-I{target_sysroot / 'usr/include'}")
    if target_sysroot is not None and not any(arg.startswith("-DCMAKE_SHARED_LINKER_FLAGS=") for arg in build.get("configure_args", [])):
        configure_command.append(f"-DCMAKE_SHARED_LINKER_FLAGS=-L{target_sysroot / 'usr/lib'}")
    if target_sysroot is not None and not any(arg.startswith("-DCMAKE_EXE_LINKER_FLAGS=") for arg in build.get("configure_args", [])):
        configure_command.append(f"-DCMAKE_EXE_LINKER_FLAGS=-L{target_sysroot / 'usr/lib'}")
    configure_command.extend(build.get("configure_args", []))
    _run(configure_command, env=env)

    build_command = ["cmake", "--build", str(build_dir)]
    if jobs is not None and jobs > 0:
        build_command.extend(["--parallel", str(jobs)])
    targets = build.get("targets", [])
    if targets:
        build_command.append("--target")
        build_command.extend(targets)
    build_command.extend(build.get("build_args", []))
    _run(build_command, env=env)

    if build.get("install_target", "install"):
        install_env = env.copy()
        install_env["DESTDIR"] = str(install_root)
        install_command = ["cmake", "--install", str(build_dir)]
        install_command.extend(build.get("install_args", []))
        _run(install_command, env=install_env)


def _build_meson(
    data: dict[str, Any],
    *,
    source_dir: Path,
    build_dir: Path,
    install_root: Path,
    target_sysroot: Path | None,
    jobs: int | None,
) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")

    build = data["build"]
    build_dir.parent.mkdir(parents=True, exist_ok=True)
    install_root.mkdir(parents=True, exist_ok=True)
    env = _build_env(build, target_sysroot=target_sysroot)

    if (build_dir / "build.ninja").exists():
        setup_command = ["meson", "setup", "--reconfigure", str(build_dir)]
    else:
        setup_command = ["meson", "setup", str(build_dir), str(source_dir), "--prefix=/usr"]
    setup_command.extend(build.get("configure_args", []))
    _run(setup_command, env=env)

    compile_command = ["meson", "compile", "-C", str(build_dir)]
    if jobs is not None and jobs > 0:
        compile_command.extend(["-j", str(jobs)])
    compile_command.extend(build.get("targets", []))
    compile_command.extend(build.get("build_args", []))
    _run(compile_command, env=env)

    if build.get("install_target", "install"):
        install_env = env.copy()
        install_env["DESTDIR"] = str(install_root)
        install_command = ["meson", "install", "-C", str(build_dir), "--no-rebuild"]
        install_command.extend(build.get("install_args", []))
        _run(install_command, env=install_env)


def _build_autotools(
    data: dict[str, Any],
    *,
    source_dir: Path,
    install_root: Path,
    target_sysroot: Path | None,
    jobs: int | None,
) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")

    source_dir = source_dir.resolve()
    install_root = install_root.resolve()
    install_root.mkdir(parents=True, exist_ok=True)
    _prepare_legacy_make_dirs(install_root)
    build = data["build"]
    env = _build_env(build, target_sysroot=target_sysroot)
    _set_make_install_env(env, source_dir=source_dir, install_root=install_root, target_sysroot=target_sysroot)

    configure_script = source_dir / "configure"
    if not configure_script.is_file():
        _run(["autoreconf", "-fi"], env=env, cwd=source_dir)
    if not configure_script.is_file():
        raise BuildError(f"configure script was not generated: {configure_script}")

    configure_args = build.get("configure_args", [])
    configure_command = [str(configure_script)]
    if not any(arg.startswith("--prefix=") for arg in configure_args):
        configure_command.append("--prefix=/usr")
    cross_compile = env.get("CROSS_COMPILE")
    if cross_compile and not any(arg.startswith("--host=") for arg in configure_args):
        configure_command.append(f"--host={cross_compile.rstrip('-')}")
    configure_command.extend(configure_args)
    _run(configure_command, env=env, cwd=source_dir)

    build_command = ["make", "-C", str(source_dir)]
    if jobs is not None and jobs > 0:
        build_command.append(f"-j{jobs}")
    build_command.extend(build.get("targets", []))
    build_command.extend(build.get("build_args", []))
    _run(build_command, env=env)

    install_target = build.get("install_target", "install")
    if install_target:
        install_command = ["make", "-C", str(source_dir), f"DESTDIR={install_root}", install_target]
        install_command.extend(build.get("install_args", []))
        _run(install_command, env=env)


def _build_cargo(
    data: dict[str, Any],
    *,
    source_dir: Path,
    build_dir: Path,
    install_root: Path,
    target_sysroot: Path | None,
    jobs: int | None,
) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")
    if not (source_dir / "Cargo.toml").is_file():
        raise BuildError(f"Cargo.toml does not exist: {source_dir / 'Cargo.toml'}")

    build = data["build"]
    build_dir.mkdir(parents=True, exist_ok=True)
    install_root.mkdir(parents=True, exist_ok=True)
    env = _build_env(build, target_sysroot=target_sysroot)
    env["CARGO_TARGET_DIR"] = str(build_dir)

    cargo_common = _cargo_common_args(build)
    build_command = ["cargo", "build", "--manifest-path", str(source_dir / "Cargo.toml")]
    if jobs is not None and jobs > 0:
        build_command.extend(["-j", str(jobs)])
    build_command.extend(cargo_common)
    build_command.extend(build.get("build_args", []))
    _run(build_command, env=env)

    if build.get("install_target", "install"):
        install_command = ["cargo", "install", "--path", str(source_dir), "--root", str(install_root / "usr"), "--no-track"]
        install_command.extend(cargo_common)
        install_command.extend(build.get("install_args", []))
        _run(install_command, env=env)


def _cargo_common_args(build: dict[str, Any]) -> list[str]:
    args: list[str] = []
    if build.get("offline", False):
        args.append("--offline")
    if build.get("locked", False):
        args.append("--locked")
    return args


def _build_kernel_module(
    data: dict[str, Any],
    *,
    source_dir: Path,
    install_root: Path,
    kernel_metadata: dict[str, Any],
    jobs: int | None,
) -> None:
    if not source_dir.is_dir():
        raise BuildError(f"source directory does not exist: {source_dir}")

    source_dir = source_dir.resolve()
    install_root = install_root.resolve()
    build = data["build"]
    env = _build_env(build, target_sysroot=None)
    kernel_build_dir = Path(kernel_metadata["build_dir"]).resolve()
    architecture = kernel_metadata["architecture"]
    cross_compile = kernel_metadata["cross_compile"]
    kernel_version = kernel_metadata["kernel_version"]
    package_name = data["name"]

    clean_command = [
        "make",
        "-C",
        str(kernel_build_dir),
        f"M={source_dir}",
        f"ARCH={architecture}",
        f"CROSS_COMPILE={cross_compile}",
        "clean",
    ]
    _run(clean_command, env=env)

    modules_command = [
        "make",
        "-C",
        str(kernel_build_dir),
        f"M={source_dir}",
        f"ARCH={architecture}",
        f"CROSS_COMPILE={cross_compile}",
    ]
    if jobs is not None and jobs > 0:
        modules_command.append(f"-j{jobs}")
    modules_command.append("modules")
    modules_command.extend(build.get("build_args", []))
    _run(modules_command, env=env)

    install_root.mkdir(parents=True, exist_ok=True)
    install_command = [
        "make",
        "-C",
        str(kernel_build_dir),
        f"M={source_dir}",
        f"ARCH={architecture}",
        f"CROSS_COMPILE={cross_compile}",
        f"INSTALL_MOD_PATH={install_root}",
        f"INSTALL_MOD_DIR=extra/{package_name}",
        "DEPMOD=echo",
        "modules_install",
    ]
    install_command.extend(build.get("install_args", []))
    _run(install_command, env=env)

    modules_dir = install_root / "lib/modules" / kernel_version / "extra" / package_name
    modules_dir.mkdir(parents=True, exist_ok=True)
    _stage_kernel_module_metadata_files(data, source_dir=source_dir, install_root=install_root)


def _stage_kernel_module_metadata_files(data: dict[str, Any], *, source_dir: Path, install_root: Path) -> None:
    for output in data.get("outputs", []):
        for module in output.get("kernel_modules", []):
            for rule in module.get("udev_rules", []):
                staged_rule = install_root / rule
                if staged_rule.is_file():
                    continue
                source_rule = source_dir / rule
                if not source_rule.is_file():
                    continue
                staged_rule.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_rule, staged_rule)


def load_kernel_metadata(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as metadata_file:
            metadata = json.load(metadata_file)
    except OSError as exc:
        raise BuildError(f"cannot read kernel metadata: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise BuildError(f"invalid kernel metadata JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}") from exc

    required = ["schema", "kernel_version", "architecture", "build_dir", "cross_compile"]
    for key in required:
        if key not in metadata:
            raise BuildError(f"kernel metadata missing required field '{key}'")
    if metadata["schema"] != "fenix.kernel-build.v1":
        raise BuildError("kernel metadata schema must be 'fenix.kernel-build.v1'")
    return metadata


def _build_env(build: dict[str, Any], *, target_sysroot: Path | None) -> dict[str, str]:
    env = os.environ.copy()
    env.update({key: _expand_env_value(value) for key, value in build.get("env", {}).items()})
    if target_sysroot is not None:
        target_sysroot = target_sysroot.resolve()
        env.setdefault("SYSROOT", str(target_sysroot))
        env.setdefault("PKG_CONFIG_SYSROOT_DIR", str(target_sysroot))
        env.setdefault("PKG_CONFIG_LIBDIR", str(target_sysroot / "usr/lib/pkgconfig") + ":" + str(target_sysroot / "usr/share/pkgconfig"))
        env.setdefault("CPPFLAGS", f"-I{target_sysroot / 'usr/include'}")
        env.setdefault("LDFLAGS", f"-L{target_sysroot / 'usr/lib'}")
    env.setdefault("PKG_CONFIG", "pkg-config")
    cross_compile = env.get("CROSS_COMPILE")
    if cross_compile:
        env.setdefault("CC", cross_compile + "gcc")
        env.setdefault("CXX", cross_compile + "g++")
        env.setdefault("STRIP", cross_compile + "strip")
    return env


def _expand_env_value(value: str) -> str:
    return value.replace("{repo_root}", str(Path(__file__).resolve().parents[2]))


def _prepare_legacy_make_dirs(install_root: Path) -> None:
    for relative in ("usr/bin", "usr/lib", "usr/lib/gstreamer-1.0", "usr/include", "etc/init.d", "lib/systemd/system"):
        (install_root / relative).mkdir(parents=True, exist_ok=True)


def _set_make_install_env(env: dict[str, str], *, source_dir: Path, install_root: Path, target_sysroot: Path | None) -> None:
    source_dir = source_dir.resolve()
    install_root = install_root.resolve()
    staging_dir = (install_root / ".fenix-staging").resolve()
    staging_dir.mkdir(parents=True, exist_ok=True)
    if target_sysroot is not None and target_sysroot.exists():
        shutil.copytree(target_sysroot.resolve(), staging_dir, dirs_exist_ok=True)
    for relative in ("usr/bin", "usr/lib", "usr/include"):
        (staging_dir / relative).mkdir(parents=True, exist_ok=True)

    env.setdefault("DESTDIR", str(install_root))
    env.setdefault("TARGET_DIR", str(install_root))
    env.setdefault("STAGING_DIR", str(staging_dir))
    env.setdefault("OUT_DIR", str(source_dir))
    env.setdefault("AML_BUILD_DIR", str(source_dir))
    env.setdefault("LIBLOG_SRC_DIR", str(source_dir))

    cross_compile = env.get("CROSS_COMPILE")
    if cross_compile:
        env.setdefault("CC", cross_compile + "gcc")
        env.setdefault("CXX", cross_compile + "g++")
        env.setdefault("STRIP", cross_compile + "strip")


def _run(command: list[str], *, env: dict[str, str], cwd: Path | None = None) -> None:
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, cwd=cwd)
    except FileNotFoundError as exc:
        raise BuildError(f"required command not found: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip()
        raise BuildError(f"command failed: {' '.join(command)}: {detail}") from exc
