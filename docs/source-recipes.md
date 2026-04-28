# Fenix Source Recipes

Fenix remains the image build system. The existing `packages/<name>/package.mk` flow stays available during migration.

The new recipe flow is for custom Fenix software that should build from source outside the target rootfs, produce debs, and enter rootfs assembly through a local apt feed.

## Compatibility

- Existing `package.mk` packages still build through `build_package` and board scripts.
- Rootfs and image assembly may continue using existing Fenix sudo/chroot/qemu/loop behavior.
- New custom packages should use `recipes/**/*.recipe.json` when practical.
- During rootfs assembly, `build_package` refuses to run so custom source compilation cannot move back into rootfs hooks.

## Common Commands

Validate recipe metadata:

```sh
make recipe-lint
```

Show recipe build order:

```sh
scripts/fenix-recipe order
```

Build a local feed from already built recipe debs:

```sh
scripts/fenix-recipe generate-feed --debs-root build/rootless/debs --feed-root build/rootless/feed --arch arm64
```

Generate provenance JSON:

```sh
scripts/fenix-recipe provenance --output build/rootless/provenance.json
```

## Rootfs Feed Integration

Enable local feed consumption in the existing Fenix rootfs assembly with environment variables:

```sh
FENIX_CUSTOM_FEED_ENABLE=yes \
FENIX_CUSTOM_FEED_PACKAGES="vfm-cap-modules" \
FENIX_CUSTOM_RECIPE_FILES="recipes/vfm-cap/vfm-cap.recipe.json" \
make
```

Variables:

- `FENIX_CUSTOM_FEED_ENABLE`: set to `yes` to copy the feed into the target rootfs and run `apt-get update` in the existing chroot flow.
- `FENIX_CUSTOM_FEED_DIR`: host-side feed directory, default `build/rootless/feed`.
- `FENIX_CUSTOM_FEED_ROOTFS_DIR`: target-side feed directory, default `/opt/fenix/local-feed`.
- `FENIX_CUSTOM_FEED_PACKAGES`: packages to install from the local feed.
- `FENIX_CUSTOM_RECIPE_FILES`: recipe files whose enabled systemd services should be linked directly in the rootfs after package installation.

## Recipe Files

Recipe files use JSON and should be named `*.recipe.json`.

Required fields:

- `schema`: currently `fenix.recipe.v1`.
- `name`: recipe name used by dependencies and package groups.
- `version`: package version.
- `source`: git, tarball, local path, or vendor-blob input.
- `build`: build class and build arguments.
- `dependencies`: recipe, distro development, and native-tool dependencies.
- `outputs`: deb package payload metadata.

Supported build classes:

- `make`
- `cmake`
- `meson`
- `cargo`
- `kernel-module`
- `vendor-blob`

## Kernel Modules

Kernel-module recipes consume kernel build metadata with schema `fenix.kernel-build.v1`. Modules are staged under:

```text
/lib/modules/<kernel-version>/extra/<recipe>/
```

Module dependency metadata is generated once during rootfs post-processing with host-side `depmod -b <rootfs> <kernel-version>`.

## Vendor Blobs

Binary-only custom packages must use explicit `vendor_blob` metadata. This keeps temporary proprietary exceptions visible in provenance output.

Current legacy exceptions and packages requiring audit are tracked in `recipes/vendor-blob-exceptions.md`.
