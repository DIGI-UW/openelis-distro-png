"""Deployment pins must survive beyond the temporary build-cache lifetime."""
import pathlib
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleasePinsTest(unittest.TestCase):
    def check_pin(self, reference):
        with tempfile.TemporaryDirectory() as directory:
            compose = pathlib.Path(directory) / 'compose.yaml'
            compose.write_text('services:\n  app:\n    image: ' + reference + '\n')
            return subprocess.run(
                [str(ROOT / 'scripts/check-release-pins.sh'), str(compose)],
                capture_output=True, text=True,
            )

    def test_durable_digest_passes(self):
        self.assertEqual(0, self.check_pin('ghcr.io/digi-uw/openelis-global-2:png-candidate@sha256:' + 'a' * 64).returncode)

    def test_floating_tag_is_rejected(self):
        result = self.check_pin('itechuw/openelis-global-2:develop')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('immutable digest', result.stderr)

    def test_temporary_cache_is_rejected_even_with_a_digest(self):
        result = self.check_pin('ghcr.io/digi-uw/openelis-global-2/e2e-cache/app@sha256:' + 'a' * 64)
        self.assertNotEqual(0, result.returncode)
        self.assertIn('temporary CI-cache', result.stderr)


class ReleaseUpdateTest(unittest.TestCase):
    def test_release_replaces_both_candidate_images_and_updates_bridge_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'scripts').mkdir()
            shutil.copy(ROOT / 'scripts/pin-versions.sh', root / 'scripts/pin-versions.sh')
            (root / 'docker-compose.yml').write_text(
                'services:\n  backend:\n    image: ghcr.io/digi-uw/openelis-global-2:png-candidate@sha256:' + 'a' * 64 +
                '\n  frontend:\n    image: ghcr.io/digi-uw/openelis-global-2-frontend:png-candidate@sha256:' + 'a' * 64 + '\n')
            (root / 'docker-compose.analyzers.yml').write_text(
                'services:\n  bridge:\n    image: itechuw/openelis-analyzer-bridge:3.5.0@sha256:' + 'a' * 64 + '\n')
            docker = root / 'docker'
            docker.write_text('#!/bin/sh\nprintf "Digest: sha256:' + 'b' * 64 + '\\n"\n')
            docker.chmod(0o755)
            result = subprocess.run([str(root / 'scripts/pin-versions.sh'), '4.0.0', '3.6.0'],
                                    env={**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH']},
                                    capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            core = (root / 'docker-compose.yml').read_text()
            self.assertIn('itechuw/openelis-global-2:4.0.0@sha256:' + 'b' * 64, core)
            self.assertIn('itechuw/openelis-global-2-frontend:4.0.0@sha256:' + 'b' * 64, core)
            self.assertNotIn('png-candidate', core)
            self.assertIn('itechuw/openelis-analyzer-bridge:3.6.0@sha256:' + 'b' * 64,
                          (root / 'docker-compose.analyzers.yml').read_text())
