#!/usr/bin/env python3
from pathlib import Path
import sys
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.provenance import generate_provenance


class ProvenanceTests(unittest.TestCase):
    def test_classifies_source_distro_and_vendor_packages(self) -> None:
        source_recipe = {
            "name": "app",
            "version": "1.0",
            "source": {"type": "git", "uri": "https://example.invalid/app.git", "revision": "abc"},
            "build": {"class": "make"},
            "outputs": [{"package": "app"}],
        }
        vendor_recipe = {
            "name": "blob",
            "version": "1.0",
            "source": {"type": "vendor-blob", "uri": "https://example.invalid/blob.deb", "sha256": "0" * 64},
            "build": {"class": "vendor-blob"},
            "vendor_blob": {"origin": "vendor"},
            "outputs": [{"package": "blob"}],
        }

        provenance = generate_provenance([vendor_recipe, source_recipe], distro_packages=["openssh-server"])

        self.assertEqual(provenance["source_built"][0]["recipe"], "app")
        self.assertEqual(provenance["vendor_blobs"][0]["recipe"], "blob")
        self.assertEqual(provenance["distro_provided"], [{"package": "openssh-server"}])


if __name__ == "__main__":
    unittest.main()
