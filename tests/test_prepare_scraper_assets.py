from pathlib import Path
import importlib.util
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parent
if (ROOT / ".github/scripts/prepare-scraper-assets.py").exists():
    SCRIPT = ROOT / ".github/scripts/prepare-scraper-assets.py"
else:
    SCRIPT = ROOT / "prepare-scraper-assets.py"
spec = importlib.util.spec_from_file_location("prepare_scraper_assets", SCRIPT)
prepare_assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_assets)


class PrepareScraperAssetsTests(unittest.TestCase):
    def test_jpeg_conversion_and_logo_limit(self):
        with tempfile.TemporaryDirectory() as tmp:
            assets = Path(tmp)
            for stem in ("screenshot", "box2d", "fanart"):
                Image.new("RGB", (64, 48), "navy").save(assets / f"{stem}.png")
            Image.new("RGBA", (1800, 900), (10, 20, 30, 100)).save(assets / "logo.png")

            prepare_assets.prepare(assets)

            for stem in ("screenshot", "box2d", "fanart"):
                self.assertFalse((assets / f"{stem}.png").exists())
                with Image.open(assets / f"{stem}.jpg") as image:
                    self.assertEqual(image.format, "JPEG")
                    self.assertEqual(image.size, (64, 48))
            with Image.open(assets / "logo.png") as logo:
                self.assertEqual(logo.format, "PNG")
                self.assertEqual(logo.size, (1200, 600))
                self.assertEqual(logo.mode, "RGBA")


if __name__ == "__main__":
    unittest.main()
