"""Downloader behavior with synthetic archives and no network or application DB."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/prepare-amr-reference.py"
spec = importlib.util.spec_from_file_location("prepare_amr", SCRIPT)
amr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(amr)


class ReferencePreparationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pin = self.root / "amr.json"
        self.destination = self.root / "packages"
        self.content = self.archive("2026.1")
        self.write_pin("2026.1", self.content)
        self.fetch = Mock(side_effect=lambda url, path: path.write_bytes(self.content))

    def archive(self, version):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as package:
            package.writestr("manifest.json", json.dumps({"format": amr.FORMAT,
                "packageVersion": version, "packageId": "amr-reference-" + version}))
        return stream.getvalue()

    def write_pin(self, version, content):
        self.pin.write_text(json.dumps({"format": amr.FORMAT, "version": version,
            "url": "https://github.com/DIGI-UW/AMR/releases/download/openelis-reference-"
                   + version + "/amr-reference-" + version + ".zip",
            "sha256": hashlib.sha256(content).hexdigest()}))

    def test_first_start_installs_verified_archive(self):
        installed = amr.prepare(self.pin, self.destination, self.fetch)
        self.assertEqual(self.content, installed.read_bytes())
        self.assertEqual([installed], list(self.destination.iterdir()))
        self.assertEqual(0o644, installed.stat().st_mode & 0o777)
        self.fetch.assert_called_once()

    def test_restart_uses_verified_cache_offline(self):
        installed = amr.prepare(self.pin, self.destination, self.fetch)
        offline = Mock(side_effect=OSError("offline"))
        self.assertEqual(installed, amr.prepare(self.pin, self.destination, offline))
        offline.assert_not_called()

    def test_corrupt_cache_is_replaced_only_after_verified_download(self):
        installed = amr.prepare(self.pin, self.destination, self.fetch)
        installed.write_bytes(b"corrupt")
        self.assertEqual(installed, amr.prepare(self.pin, self.destination, self.fetch))
        self.assertEqual(self.content, installed.read_bytes())

    def test_bad_download_leaves_previous_version_and_no_partial_file(self):
        installed = amr.prepare(self.pin, self.destination, self.fetch)
        self.write_pin("2026.2", self.archive("2026.2"))
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            amr.prepare(self.pin, self.destination, self.fetch)
        self.assertEqual([installed], list(self.destination.iterdir()))
        self.assertEqual(self.content, installed.read_bytes())

    def test_interruption_is_cleaned_up_and_retry_succeeds(self):
        def interrupted(url, path):
            path.write_bytes(b"partial")
            raise OSError("interrupted")
        with self.assertRaisesRegex(OSError, "interrupted"):
            amr.prepare(self.pin, self.destination, interrupted)
        self.assertEqual([], list(self.destination.iterdir()))
        self.assertEqual(self.content, amr.prepare(self.pin, self.destination, self.fetch).read_bytes())

    def test_upgrade_retains_previous_verified_archive(self):
        previous = amr.prepare(self.pin, self.destination, self.fetch)
        self.content = self.archive("2026.2")
        self.write_pin("2026.2", self.content)
        current = amr.prepare(self.pin, self.destination, self.fetch)
        self.assertNotEqual(previous, current)
        self.assertTrue(previous.is_file())
        self.assertEqual(self.content, current.read_bytes())
        self.assertEqual(2, len(list(self.destination.iterdir())))

    def test_manifest_must_match_pin_even_when_checksum_matches(self):
        self.write_pin("2026.2", self.content)
        with self.assertRaisesRegex(ValueError, "manifest differs"):
            amr.prepare(self.pin, self.destination, self.fetch)
        self.assertEqual([], list(self.destination.iterdir()))

    def test_moving_release_url_is_rejected_before_network(self):
        pin = json.loads(self.pin.read_text())
        pin["url"] = "https://github.com/DIGI-UW/AMR/releases/latest/download/amr.zip"
        self.pin.write_text(json.dumps(pin))
        with self.assertRaisesRegex(ValueError, "versioned"):
            amr.prepare(self.pin, self.destination, self.fetch)
        self.fetch.assert_not_called()

    def test_no_pin_preserves_existing_non_amr_deployment(self):
        self.pin.unlink()
        self.assertIsNone(amr.prepare(self.pin, self.destination, self.fetch))
        self.fetch.assert_not_called()
        self.assertFalse(self.destination.exists())

    def test_non_https_redirect_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "non-HTTPS"):
            amr.HTTPSRedirects().redirect_request(None, None, 302, "", {}, "http://example.com/package.zip")


if __name__ == "__main__":
    unittest.main()
