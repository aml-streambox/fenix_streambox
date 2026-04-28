# Package Groups

Package group manifests select rootless recipe names for a board, release, image type, and install type.

Files should use the `*.package-group.json` suffix and schema `fenix.package-group.v1`.

Example:

```json
{
  "schema": "fenix.package-group.v1",
  "name": "tvpro-server-core",
  "selectors": {
    "boards": ["TVPRO"],
    "distributions": ["Ubuntu"],
    "releases": ["noble"],
    "image_types": ["server"],
    "install_types": ["EMMC"]
  },
  "include": [],
  "recipes": ["libvfmcap"],
  "distro_packages": ["openssh-server"]
}
```

Keep this directory focused on package selection. Recipe build details belong in `*.recipe.json` files.
