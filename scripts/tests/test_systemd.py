#!/usr/bin/env python3
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fenix_recipe.systemd import enable_recipe_services, enabled_services


class SystemdHelperTests(unittest.TestCase):
    def test_enabled_services_are_collected(self) -> None:
        recipe = {
            "outputs": [
                {
                    "services": [
                        {"unit": "app.service", "enable": True},
                        {"unit": "debug.service", "enable": False},
                    ]
                }
            ]
        }

        self.assertEqual(enabled_services(recipe), ["app.service"])

    def test_enable_service_creates_wantedby_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            rootfs = Path(tempdir)
            unit = rootfs / "lib/systemd/system/app.service"
            unit.parent.mkdir(parents=True)
            unit.write_text(
                "[Unit]\n"
                "Description=App\n"
                "[Service]\n"
                "ExecStart=/usr/bin/app\n"
                "[Install]\n"
                "WantedBy=multi-user.target\n",
                encoding="utf-8",
            )
            recipe = {"outputs": [{"services": [{"unit": "app.service", "enable": True}]}]}

            result = enable_recipe_services(recipe, rootfs=rootfs)

            link = rootfs / "etc/systemd/system/multi-user.target.wants/app.service"
            self.assertEqual(result[0].symlinks, [link])
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.readlink(), Path("/lib/systemd/system/app.service"))


if __name__ == "__main__":
    unittest.main()
