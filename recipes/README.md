# Fenix Rootless Recipes

This directory contains metadata for the new rootless source-build flow.

Recipe files use JSON so the first implementation can parse them with Python's standard library. A recipe file should be named `*.recipe.json` and should declare `"schema": "fenix.recipe.v1"`.

## Recipe Model

Each recipe describes one custom Fenix source unit and the deb packages it produces.

Required top-level fields:

- `schema`: schema identifier, currently `fenix.recipe.v1`.
- `name`: stable recipe name used by dependencies and package groups.
- `version`: upstream or Fenix package version.
- `summary`: short human-readable description.
- `license`: SPDX identifier or explicit license label.
- `source`: git, tarball, local path, or vendor-blob input.
- `build`: build class and build arguments.
- `dependencies`: build-time dependency metadata.
- `outputs`: deb packages produced by the recipe.

## Source Types

- `git`: requires `uri` and `revision`; optional `sha256` for exported archives.
- `tarball`: requires `uri` and `sha256`.
- `local`: requires `path`, relative to the Fenix checkout unless absolute.
- `vendor-blob`: requires `uri` or `path`, `sha256`, and `vendor_blob` exception metadata.

## Build Classes

Supported class names are defined up front even if implementation lands incrementally:

- `make`
- `cmake`
- `meson`
- `autotools`
- `cargo`
- `kernel-module`
- `vendor-blob`

Custom packages must build outside the rootfs. `vendor-blob` is only for explicit temporary binary exceptions.

Cargo recipes may set `build.offline` and `build.locked` to control `cargo --offline` and `cargo --locked`. Vendored Cargo dependencies should be declared through the source tree's `.cargo/config.toml` and built with `offline: true`.

## Dependencies

`dependencies.recipes` lists other Fenix recipe names and drives graph ordering.

`dependencies.distro_dev` lists target-architecture Debian/Ubuntu development packages that should be extracted or staged into the target sysroot.

`dependencies.native_tools` lists host tools or future native recipes required to run the build.

Runtime dependencies belong to each output package as `runtime_depends` because split packages may differ.

## Outputs

Each entry in `outputs` describes one deb package:

- `package`: Debian package name.
- `architecture`: Debian architecture such as `arm64` or `all`.
- `description`: package description.
- `runtime_depends`: Debian dependency strings.
- `files`: payload mapping from install staging paths into package paths.
- `sysroot_exports`: headers, libraries, pkg-config files, or tools exported to dependent recipe sysroots.
- `services`: systemd units shipped by the package and whether rootfs assembly should enable them.
- `kernel_modules`: `.ko` files and optional autoload metadata for kernel-module recipes.

For `kernel_modules`, `autoload` creates `/etc/modules-load.d/<package>.conf`, `options` creates `/etc/modprobe.d/<package>.conf`, and `udev_rules` lists rule files from the install staging root to copy into `/etc/udev/rules.d/`.

## Vendor Blob Exceptions

Binary-only packages are not normal source recipes. A recipe with `source.type` or `build.class` set to `vendor-blob` must include `vendor_blob` metadata with origin, version, checksum, license category, reason source is unavailable, and replacement status.

The intent is to make every binary exception visible and temporary.

## Schema

The machine-readable schema is in `schema/recipe-v1.schema.json`. The first validator may implement checks directly in Python rather than requiring an external JSON Schema package.

## Package Groups

Package group manifests live under `package-groups/` and use `"schema": "fenix.package-group.v1"`.

A package group selects custom recipe names for a board/release/image combination. Selectors are arrays; an empty or omitted selector means the group applies to all values for that dimension.

Selector fields:

- `boards`: Fenix board names such as `TVPRO` or `VIM4`.
- `distributions`: distro names such as `Ubuntu`.
- `releases`: distro release names such as `noble` or `jammy`.
- `image_types`: Fenix image types such as `server`, `minimal`, or `gnome`.
- `install_types`: Fenix install types such as `EMMC` or `SD-USB`.

Group fields:

- `include`: other package group names to include first.
- `recipes`: custom Fenix recipe names to build from source.
- `distro_packages`: Debian/Ubuntu package names to keep distro-provided.

Package groups intentionally reference recipe names, not `package.mk` names. During migration they can be added before every referenced recipe exists, but final image builds should fail when selected recipe names cannot be resolved.

The initial T7 package groups include `t7-kernel-modules` for source-built out-of-tree modules, `t7-aml-source-app-stack` for migrated Amlogic source-built app dependencies, and `t7-aml-legacy-binary-stack` for Amlogic prebuilt deb wrappers that are tracked as `vendor-blob` exceptions.

Migrated Amlogic app-stack recipes currently cover `android-liblog`, `android-binder`, `aml-avsync`, `aml-audio-utils`, `aml-audio-hal`, `aml-audio-service`, and `aml-tvserver-streambox`. `aml-audio-utils` still needs Boost headers staged in the target sysroot; during migration those headers can come from `packages/libboost1.83-dev/sources/usr/include/boost` until distro development package extraction is wired into the recipe runner. `libexpat1` is source-built as a temporary sysroot provider for `aml-audio-hal` for the same reason.

## Fenix Rootfs Feed Integration

The existing Fenix rootfs flow can consume debs built by these recipes through a local apt feed.

Generate the feed with:

```sh
scripts/fenix-recipe generate-feed --debs-root build/rootless/debs --feed-root build/rootless/feed --arch arm64
```

Then enable feed consumption during normal Fenix rootfs assembly with environment variables:

- `FENIX_CUSTOM_FEED_ENABLE=yes`: copy the local feed into the target rootfs and run `apt-get update` in the existing chroot flow.
- `FENIX_CUSTOM_FEED_DIR=...`: host-side feed directory, default `build/rootless/feed`.
- `FENIX_CUSTOM_FEED_ROOTFS_DIR=...`: target rootfs feed directory, default `/opt/fenix/local-feed`.
- `FENIX_CUSTOM_FEED_PACKAGES="pkg1 pkg2"`: packages to install from the local feed.
- `FENIX_CUSTOM_RECIPE_FILES="recipes/pkg/pkg.recipe.json ..."`: recipe metadata files whose `services` entries should be enabled directly in the rootfs after package installation.

This keeps sudo/chroot rootfs assembly in Fenix while moving custom source compilation and deb creation outside the rootfs.

During rootfs assembly Fenix exports `FENIX_ROOTFS_ASSEMBLY_ACTIVE=yes`; `build_package` refuses to run in that mode. Board hooks may still apply rootfs configuration through existing Fenix mechanisms, but custom source compilation must happen before rootfs assembly.

## Kernel Build Metadata

Out-of-tree kernel module recipes consume kernel build metadata rather than guessing paths from board scripts.

The kernel build step should write a JSON file using `"schema": "fenix.kernel-build.v1"` with:

- `kernel_version`: installed module version such as `5.15.137`.
- `architecture`: kernel architecture, normally `arm64`.
- `source_dir`: kernel source tree.
- `build_dir`: configured kernel build tree used for module builds.
- `modules_dir`: staged module directory for the selected kernel.
- `headers_dir`: exported header directory, if separate.
- `module_symvers`: path to `Module.symvers`.
- `config`: path to the kernel `.config`.
- `image`: path to the built kernel image.
- `dtbs`: paths to built DTBs.
- `cross_compile`: cross compiler prefix such as `aarch64-none-linux-gnu-`.

The machine-readable schema is `schema/kernel-build-v1.schema.json`.
