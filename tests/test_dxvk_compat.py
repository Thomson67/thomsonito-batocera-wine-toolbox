"""Compatibility rules for DXVK-NVAPI releases."""
import sys
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


if __name__ == "__main__":
    unittest.main()
