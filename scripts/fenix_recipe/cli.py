from __future__ import annotations

import argparse
import json
from pathlib import Path

from .build_classes import BuildError, build_recipe, load_kernel_metadata
from .debpack import DebPackageError, build_deb_packages
from .feeds import FeedError, generate_local_feed
from .graph import load_recipes, topological_order
from .package_groups import load_package_groups, select_package_groups
from .patches import PatchError, apply_recipe_patches
from .provenance import generate_provenance
from .rootfs import RootfsError, configure_local_apt_feed, run_rootfs_depmod
from .sources import FetchError, fetch_recipe_source
from .stamps import PHASES, compute_phase_stamp
from .systemd import SystemdError, enable_recipe_services
from .sysroots import SysrootError, check_native_tools, stage_recipe_sysroot_exports
from .validator import validate_recipe_file


def _default_recipe_paths(repo_root: Path) -> list[Path]:
    recipes_dir = repo_root / "recipes"
    if not recipes_dir.exists():
        return []
    return sorted(recipes_dir.glob("**/*.recipe.json"))


def _default_package_group_paths(repo_root: Path) -> list[Path]:
    groups_dir = repo_root / "recipes" / "package-groups"
    if not groups_dir.exists():
        return []
    return sorted(groups_dir.glob("*.package-group.json"))


def _cmd_validate(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    had_errors = False
    for path in paths:
        errors = validate_recipe_file(path)
        if errors:
            had_errors = True
            for error in errors:
                print(f"{path}: {error.location}: {error.message}")
        elif args.verbose:
            print(f"{path}: ok")

    return 1 if had_errors else 0


def _cmd_order(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, load_issues = load_recipes(paths)
    if load_issues:
        for issue in load_issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    ordered, graph_issues = topological_order(recipes)
    if graph_issues:
        for issue in graph_issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    for recipe in ordered:
        if args.with_paths:
            print(f"{recipe.name}\t{recipe.path}")
        else:
            print(recipe.name)
    return 0


def _cmd_stamp(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    for recipe in (recipes[name] for name in sorted(recipes)):
        digest = compute_phase_stamp(recipe.data, args.phase, repo_root=repo_root, recipe_path=recipe.path)
        print(f"{recipe.name}\t{args.phase}\t{digest}")
    return 0


def _cmd_group_select(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_package_group_paths(repo_root)

    if not paths:
        print("No package group files found.")
        return 0

    groups, load_issues = load_package_groups(paths)
    if load_issues:
        for path, issue in load_issues:
            print(f"{path}: {issue.location}: {issue.message}")
        return 1

    selection, selection_issues = select_package_groups(
        groups,
        board=args.board,
        distribution=args.distribution,
        release=args.release,
        image_type=args.image_type,
        install_type=args.install_type,
    )
    if selection_issues:
        for issue in selection_issues:
            print(f"<package-groups>: {issue.location}: {issue.message}")
        return 1

    if args.show_groups:
        for group in selection.groups:
            print(f"group\t{group.name}")
    for recipe in selection.recipes:
        print(f"recipe\t{recipe}")
    for package in selection.distro_packages:
        print(f"distro\t{package}")
    return 0


def _cmd_fetch(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    fetch_root = Path(args.fetch_root)
    for recipe in (recipes[name] for name in sorted(recipes)):
        try:
            result = fetch_recipe_source(recipe.data, fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe.path)
        except FetchError as exc:
            print(f"{recipe.path}: $.source: {exc}")
            return 1
        print(f"{result.recipe_name}\t{result.source_type}\t{result.source_dir}")
    return 0


def _cmd_patch(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    fetch_root = Path(args.fetch_root)
    for recipe in (recipes[name] for name in sorted(recipes)):
        try:
            result = fetch_recipe_source(recipe.data, fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe.path)
            patch_result = apply_recipe_patches(recipe.data, source_dir=result.source_dir, repo_root=repo_root, recipe_path=recipe.path)
        except (FetchError, PatchError) as exc:
            print(f"{recipe.path}: $.patches: {exc}")
            return 1
        print(f"{recipe.name}\t{len(patch_result.applied)}\t{patch_result.source_dir}")
    return 0


def _cmd_stage_sysroot(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    package_root = Path(args.package_root)
    sysroot = Path(args.sysroot)
    for recipe in (recipes[name] for name in sorted(recipes)):
        missing_tools = check_native_tools(recipe.data)
        if missing_tools:
            print(f"{recipe.path}: $.dependencies.native_tools: missing native tools: {', '.join(missing_tools)}")
            return 1
        try:
            result = stage_recipe_sysroot_exports(recipe.data, package_root=package_root, sysroot=sysroot)
        except SysrootError as exc:
            print(f"{recipe.path}: $.outputs[].sysroot_exports: {exc}")
            return 1
        print(f"{recipe.name}\t{len(result.staged)}\t{sysroot}")
    return 0


def _cmd_build(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    ordered, graph_issues = topological_order(recipes)
    if graph_issues:
        for issue in graph_issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    fetch_root = Path(args.fetch_root)
    install_base = Path(args.install_root)
    target_sysroot = Path(args.sysroot) if args.sysroot else None
    try:
        kernel_metadata = load_kernel_metadata(Path(args.kernel_metadata)) if args.kernel_metadata else None
    except BuildError as exc:
        print(f"{args.kernel_metadata}: $: {exc}")
        return 1
    for recipe in ordered:
        try:
            fetch_result = fetch_recipe_source(recipe.data, fetch_root=fetch_root, repo_root=repo_root, recipe_path=recipe.path)
            patch_result = apply_recipe_patches(recipe.data, source_dir=fetch_result.source_dir, repo_root=repo_root, recipe_path=recipe.path)
            build_result = build_recipe(
                recipe.data,
                source_dir=patch_result.source_dir,
                install_root=install_base / recipe.name,
                build_root=Path(args.build_root),
                target_sysroot=target_sysroot,
                kernel_metadata=kernel_metadata,
                jobs=args.jobs,
            )
        except (FetchError, PatchError, BuildError) as exc:
            print(f"{recipe.path}: $.build: {exc}")
            return 1
        print(f"{build_result.recipe_name}\t{build_result.build_class}\t{build_result.install_root}")
    return 0


def _cmd_package(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    install_base = Path(args.install_root)
    debs_root = Path(args.debs_root)
    for recipe in (recipes[name] for name in sorted(recipes)):
        try:
            packages = build_deb_packages(recipe.data, install_root=install_base / recipe.name, debs_root=debs_root)
        except DebPackageError as exc:
            print(f"{recipe.path}: $.outputs: {exc}")
            return 1
        for package in packages:
            print(f"{recipe.name}\t{package.package}\t{package.path}")
    return 0


def _cmd_enable_services(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    if not paths:
        print("No recipe files found.")
        return 0

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    rootfs = Path(args.rootfs)
    for recipe in (recipes[name] for name in sorted(recipes)):
        try:
            enabled = enable_recipe_services(recipe.data, rootfs=rootfs)
        except SystemdError as exc:
            print(f"{recipe.path}: $.outputs[].services: {exc}")
            return 1
        for service in enabled:
            for link in service.symlinks:
                print(f"{recipe.name}\t{service.unit}\t{link}")
    return 0


def _cmd_depmod(args: argparse.Namespace) -> int:
    try:
        run_rootfs_depmod(rootfs=Path(args.rootfs), kernel_version=args.kernel_version)
    except RootfsError as exc:
        print(f"{args.rootfs}: {exc}")
        return 1
    print(f"depmod\t{args.kernel_version}\t{args.rootfs}")
    return 0


def _cmd_generate_feed(args: argparse.Namespace) -> int:
    try:
        result = generate_local_feed(debs_root=Path(args.debs_root), feed_root=Path(args.feed_root), arch=args.arch)
    except FeedError as exc:
        print(f"{args.debs_root}: {exc}")
        return 1
    print(f"feed\t{result.deb_count}\t{result.feed_root}")
    return 0


def _cmd_configure_feed(args: argparse.Namespace) -> int:
    try:
        source_file = configure_local_apt_feed(rootfs=Path(args.rootfs), feed_root=Path(args.feed_root), name=args.name)
    except RootfsError as exc:
        print(f"{args.rootfs}: {exc}")
        return 1
    print(f"apt-source\t{source_file}")
    return 0


def _cmd_provenance(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[2]
    paths = [Path(p) for p in args.paths] if args.paths else _default_recipe_paths(repo_root)

    recipes, issues = load_recipes(paths)
    if issues:
        for issue in issues:
            prefix = str(issue.path) if issue.path is not None else "<recipes>"
            print(f"{prefix}: {issue.location}: {issue.message}")
        return 1

    provenance = generate_provenance([recipe.data for recipe in recipes.values()], distro_packages=args.distro_package)
    encoded = json.dumps(provenance, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fenix rootless recipe tooling")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="validate recipe metadata")
    validate.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    validate.add_argument("-v", "--verbose", action="store_true", help="print valid files too")
    validate.set_defaults(func=_cmd_validate)

    order = subparsers.add_parser("order", help="print recipe build order")
    order.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    order.add_argument("--with-paths", action="store_true", help="print recipe paths next to names")
    order.set_defaults(func=_cmd_order)

    stamp = subparsers.add_parser("stamp", help="print deterministic phase stamps")
    stamp.add_argument("phase", choices=PHASES, help="recipe phase to stamp")
    stamp.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    stamp.set_defaults(func=_cmd_stamp)

    group_select = subparsers.add_parser("group-select", help="select package groups for a board image")
    group_select.add_argument("--board", required=True, help="Fenix board name, for example TVPRO")
    group_select.add_argument("--distribution", required=True, help="distribution name, for example Ubuntu")
    group_select.add_argument("--release", required=True, help="distribution release, for example noble")
    group_select.add_argument("--image-type", required=True, help="Fenix image type, for example server")
    group_select.add_argument("--install-type", required=True, help="Fenix install type, for example EMMC")
    group_select.add_argument("--show-groups", action="store_true", help="print selected package group names")
    group_select.add_argument("paths", nargs="*", help="package group files; defaults to recipes/package-groups/*.package-group.json")
    group_select.set_defaults(func=_cmd_group_select)

    fetch = subparsers.add_parser("fetch", help="fetch recipe sources")
    fetch.add_argument("--fetch-root", default="build/rootless/sources", help="source fetch output directory")
    fetch.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    fetch.set_defaults(func=_cmd_fetch)

    patch = subparsers.add_parser("patch", help="fetch sources and apply recipe patches")
    patch.add_argument("--fetch-root", default="build/rootless/sources", help="source fetch output directory")
    patch.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    patch.set_defaults(func=_cmd_patch)

    stage_sysroot = subparsers.add_parser("stage-sysroot", help="stage recipe sysroot exports")
    stage_sysroot.add_argument("--package-root", required=True, help="package install staging root")
    stage_sysroot.add_argument("--sysroot", default="build/rootless/sysroots/target", help="target sysroot directory")
    stage_sysroot.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    stage_sysroot.set_defaults(func=_cmd_stage_sysroot)

    build = subparsers.add_parser("build", help="fetch, patch, and build recipes")
    build.add_argument("--fetch-root", default="build/rootless/sources", help="source fetch output directory")
    build.add_argument("--build-root", default="build/rootless/build", help="out-of-source build base directory")
    build.add_argument("--install-root", default="build/rootless/install", help="package install staging base directory")
    build.add_argument("--sysroot", help="target sysroot directory")
    build.add_argument("--kernel-metadata", help="kernel build metadata JSON for kernel-module recipes")
    build.add_argument("-j", "--jobs", type=int, help="parallel make jobs")
    build.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    build.set_defaults(func=_cmd_build)

    package = subparsers.add_parser("package", help="build debs from recipe install staging roots")
    package.add_argument("--install-root", default="build/rootless/install", help="package install staging base directory")
    package.add_argument("--debs-root", default="build/rootless/debs", help="deb output directory")
    package.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    package.set_defaults(func=_cmd_package)

    enable_services = subparsers.add_parser("enable-services", help="enable recipe systemd units in a rootfs")
    enable_services.add_argument("--rootfs", required=True, help="rootfs directory")
    enable_services.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    enable_services.set_defaults(func=_cmd_enable_services)

    depmod = subparsers.add_parser("depmod-rootfs", help="run host-side depmod for a rootfs")
    depmod.add_argument("--rootfs", required=True, help="rootfs directory")
    depmod.add_argument("--kernel-version", required=True, help="kernel version under /lib/modules")
    depmod.set_defaults(func=_cmd_depmod)

    feed = subparsers.add_parser("generate-feed", help="generate a local apt package feed")
    feed.add_argument("--debs-root", default="build/rootless/debs", help="directory containing built debs")
    feed.add_argument("--feed-root", default="build/rootless/feed", help="feed output directory")
    feed.add_argument("--arch", help="optional package architecture filter")
    feed.set_defaults(func=_cmd_generate_feed)

    configure_feed = subparsers.add_parser("configure-feed", help="add local feed apt source to a rootfs")
    configure_feed.add_argument("--rootfs", required=True, help="rootfs directory")
    configure_feed.add_argument("--feed-root", required=True, help="local feed directory")
    configure_feed.add_argument("--name", default="fenix-local", help="apt source list name")
    configure_feed.set_defaults(func=_cmd_configure_feed)

    provenance = subparsers.add_parser("provenance", help="generate package provenance JSON")
    provenance.add_argument("--distro-package", action="append", default=[], help="distro-provided package name; repeatable")
    provenance.add_argument("--output", help="write JSON to file instead of stdout")
    provenance.add_argument("paths", nargs="*", help="recipe JSON files; defaults to recipes/**/*.recipe.json")
    provenance.set_defaults(func=_cmd_provenance)

    args = parser.parse_args(argv)
    return args.func(args)
