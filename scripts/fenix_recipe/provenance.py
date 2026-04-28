from __future__ import annotations

from typing import Any


def generate_provenance(recipes: list[dict[str, Any]], *, distro_packages: list[str]) -> dict[str, Any]:
    source_built: list[dict[str, Any]] = []
    vendor_blobs: list[dict[str, Any]] = []

    for recipe in sorted(recipes, key=lambda item: item["name"]):
        entry = {
            "recipe": recipe["name"],
            "version": recipe["version"],
            "source": recipe.get("source", {}),
            "packages": [output["package"] for output in recipe.get("outputs", [])],
        }
        if recipe.get("source", {}).get("type") == "vendor-blob" or recipe.get("build", {}).get("class") == "vendor-blob":
            entry["vendor_blob"] = recipe.get("vendor_blob", {})
            vendor_blobs.append(entry)
        else:
            source_built.append(entry)

    return {
        "source_built": source_built,
        "distro_provided": [{"package": package} for package in sorted(set(distro_packages))],
        "vendor_blobs": vendor_blobs,
    }
