"""Compatibility rules for DXVK-NVAPI releases."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "toolbox/helpers"))
import dxvk_compat


class DxvkNvapiCompatibilityTests(unittest.TestCase):
    def test_dxvk_21_is_hard_minimum_from_nvapi_061(self):
        self.assertEqual(dxvk_compat.evaluate("2.0", "3.0.1", "0.6.0"),
                         (True, []))
        self.assertEqual(dxvk_compat.evaluate("2.0", "3.0.1", "0.6.1"),
                         (False, []))
        self.assertEqual(dxvk_compat.evaluate("2.1", "3.0.1", "0.6.1"),
                         (True, []))

    def test_optional_features_are_reported_without_blocking_nvapi(self):
        compatible, limitations = dxvk_compat.evaluate("2.2", "2.10", "0.9.2")
        self.assertTrue(compatible)
        self.assertEqual(limitations, ["hdr", "reflex", "optical-flow", "shader-extensions"])

    def test_latest_known_requirements_have_no_limitations(self):
        self.assertEqual(dxvk_compat.evaluate("2.3", "3.0.1", "0.9.2"),
                         (True, []))

    def test_invalid_versions_are_rejected(self):
        with self.assertRaises(ValueError):
            dxvk_compat.evaluate("latest", "3.0.1", "0.9.2")



class DxvkNvapiPickerTests(unittest.TestCase):
    def run_picker(self, dxvk, vkd3d, releases):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as home:
            script = (
                "source toolbox/modules/dxvk-manager.sh\n"
                "dxvk_release_catalog() { printf '%s\\n' " +
                " ".join("'" + release.replace("'", "'\\''") + "'" for release in releases) +
                "; }\n"
                "menu_select() { printf '1'; }\n"
                "i18n() { printf '%s' \"$1\"; }\n"
                "msgbox() { printf 'MSG:%s\\n' \"$2\" >&2; }\n"
                "dxvk_choose_release test nvapi title '" + dxvk + "' '" + vkd3d + "'"
            )
            env = dict(os.environ, WT_ROOT=str(root), WT_HOME=home)
            return subprocess.run(["bash", "-c", script], cwd=root, env=env,
                                  capture_output=True, text=True)

    def test_picker_hides_nvapi_releases_incompatible_with_dxvk(self):
        result = self.run_picker("2.0", "3.0.1", [
            "v0.9.2\thttps://example.invalid/new\tsha256:new",
            "v0.6.0\thttps://example.invalid/old\tsha256:old",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("v0.6.0\t"), result.stdout)
        self.assertNotIn("v0.9.2", result.stdout)

    def test_picker_reports_when_no_nvapi_release_matches(self):
        result = self.run_picker("2.0", "3.0.1", [
            "v0.9.2\thttps://example.invalid/new\tsha256:new",
            "v0.6.1\thttps://example.invalid/old\tsha256:old",
        ])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dxvk_nvapi_no_compatible_release", result.stderr)

    def test_picker_keeps_partial_feature_support_selectable_and_warns(self):
        result = self.run_picker("2.2", "2.10", [
            "v0.9.2\thttps://example.invalid/new\tsha256:new",
            "v0.6.1\thttps://example.invalid/old\tsha256:old",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("v0.9.2\t"), result.stdout)
        self.assertIn("dxvk_nvapi_hdr_limited", result.stderr)
        self.assertIn("dxvk_nvapi_reflex_limited", result.stderr)
        self.assertIn("dxvk_nvapi_optical_flow_limited", result.stderr)
        self.assertIn("dxvk_nvapi_shader_extensions_limited", result.stderr)


if __name__ == "__main__":
    unittest.main()
