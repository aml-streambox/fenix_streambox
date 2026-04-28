# Vendor Blob Exceptions

This file tracks binary-only or prebuilt vendor packages that are allowed during migration but must not be treated as normal source recipes.

Each entry records the metadata expected by the new recipe model: origin, version/checksum, license/category, why source is unavailable, and replacement status.

## Confirmed Exceptions

### `dolby-ms12`

- Origin: Amlogic/Yocto Dolby MS12 release copied manually into `packages/dolby-ms12/sources`.
- Version: `1.0-amlogic-yocto` from `packages/dolby-ms12/package.mk`.
- Checksum: not currently declared because the package is assembled from a local manually copied source directory.
- License/category: proprietary vendor audio binary, `PKG_LICENSE="AMLOGIC"`.
- Reason source is unavailable: Dolby MS12 library, firmware, and OP-TEE trusted applications are distributed as prebuilt binaries.
- Replacement status: keep as a temporary exception; source replacement is unlikely unless vendor-provided source or redistributable open alternative becomes available.

## Prebuilt Vendor Packages Requiring Audit

These wrappers copy prebuilt debs or firmware archives and should be converted either to source recipes or explicit `vendor-blob` recipes once package contents and redistributability are confirmed.

### `mali-debs`

- Origin: `https://github.com/numbqq/mali-debs`, revision `79a60bb30229f742cc57307187b5a2c2929fc5a5`.
- Checksum: `24c1af846c28937e01064be603058c15b50cd9aa7e94cc2e186955e25a1106f7`.
- Current legacy behavior: `PKG_NEED_BUILD="NO"`; copies board/arch prebuilt GPU debs.
- License/category: legacy metadata says `GPL`, but GPU userspace blobs are likely vendor binary components and need license audit.
- Replacement status: audit first; keep prebuilt wrapper until Panfrost/open userspace replacement is selected per board/image.

### `optee_userspace_deb_aml`

- Origin: `https://github.com/numbqq/optee_userspace_deb_aml`, revision `e05c34b81f65fa10f534984a370001807fbd5c48`.
- Checksum: `06011c34c8ab5a55f69d9bbc2c4cbf6a3059f77f6f7d577112d5d77279c7f0c0`.
- Current legacy behavior: `PKG_NEED_BUILD="NO"`; copies board/arch prebuilt OP-TEE userspace debs.
- License/category: legacy metadata says `GPL`, but payload contents need license audit.
- Replacement status: tracked by `recipes/optee_userspace_deb_aml/optee_userspace_deb_aml.recipe.json`; keep as a temporary exception until OP-TEE source build wiring is available.

### `optee_video_firmware_deb_aml`

- Origin: `https://github.com/numbqq/optee_video_firmware_deb_aml`, revision `8f9e4b8db03a0bd61748417d0ba99ac3bde0a143`.
- Checksum: `ee374869fd01eeb055ab52f158ebc34bc37f02633c246a5d8f3d20207447278c`.
- Current legacy behavior: `PKG_NEED_BUILD="NO"`; copies board/arch prebuilt video firmware debs.
- License/category: legacy metadata says `GPL`, but firmware payloads need license audit.
- Replacement status: tracked by `recipes/optee_video_firmware_deb_aml/optee_video_firmware_deb_aml.recipe.json`; keep as a temporary firmware exception until payload contents and source availability are confirmed.

### Amlogic userspace prebuilt deb wrappers

The following packages are now represented by `vendor-blob` recipes because their upstream repositories contain distro/architecture deb payloads rather than source trees:

- `libion_deb_aml`: `recipes/libion_deb_aml/libion_deb_aml.recipe.json`
- `libge2d_deb_aml`: `recipes/libge2d_deb_aml/libge2d_deb_aml.recipe.json`
- `libmultienc_deb_aml`: `recipes/libmultienc_deb_aml/libmultienc_deb_aml.recipe.json`
- `libjpegenc_deb_aml`: `recipes/libjpegenc_deb_aml/libjpegenc_deb_aml.recipe.json`
- `libamvenc_deb_aml`: `recipes/libamvenc_deb_aml/libamvenc_deb_aml.recipe.json`
- `multimedia_debs_aml`: `recipes/multimedia_debs_aml/multimedia_debs_aml.recipe.json`
- `libadla_deb_aml`: `recipes/libadla_deb_aml/libadla_deb_aml.recipe.json`
- `meson-display-deb-aml`: `recipes/meson-display-deb-aml/meson-display-deb-aml.recipe.json`

These are not source migrations. They are explicit exceptions so provenance can distinguish binary payload wrappers from source-built recipes.

## Not Automatically Exceptions

Many legacy `PKG_NEED_BUILD="NO"` packages are distro package mirrors, host tools, or prebuilt wrapper archives. They should not all be marked proprietary by default. During migration, each package must become one of:

- normal source recipe,
- Debian/Ubuntu distro-provided package,
- explicit `vendor-blob` exception with required metadata.
