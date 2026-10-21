"""Exercise real certgen tools against disposable, initially empty volumes."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pins', ROOT / 'scripts/pin-images.py')
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)


class PinTests(unittest.TestCase):
    def test_all_images_including_certgen_resolved_and_duplicates_share_digest(self):
        calls = []
        def resolve(ref):
            calls.append(ref)
            return 'sha256:' + 'a' * 64
        text = '    image: itechuw/certgen:main\n    image: itechuw/openelis-analyzer-bridge:develop\n    image: itechuw/openelis-analyzer-bridge:develop\n'
        result = pins.pin(text, resolve, bridge='3.0.2')
        self.assertEqual(calls, ['itechuw/certgen:main', 'itechuw/openelis-analyzer-bridge:3.0.2'])
        self.assertEqual(result.count('@sha256:'), 3)

    def test_invalid_resolution_fails_instead_of_producing_partial_pins(self):
        with self.assertRaises(ValueError):
            pins.pin('    image: example:main\n', lambda _: 'not-a-digest')


@unittest.skipUnless(os.getenv('PNG_TEST_SECURITY') == '1', 'set PNG_TEST_SECURITY=1 for disposable certificate tests')
class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.image = re.search(r'image: (itechuw/certgen:\S+)', (ROOT / 'docker-compose.yml').read_text())[1]
        self.volumes = []

    def tearDown(self):
        for volume in self.volumes:
            self.docker('volume', 'rm', volume)

    def docker(self, *args, ok=True):
        result = subprocess.run(['docker', *args], capture_output=True, text=True, timeout=120)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def fresh(self):
        volumes = ['png-security-test-' + uuid.uuid4().hex for _ in range(3)]
        for volume in volumes:
            self.docker('volume', 'create', volume)
            self.volumes.append(volume)
        return volumes

    def run_image(self, volumes, script=None, password='TestStore42', ok=True):
        args = ['run', '--rm', '--network', 'none', '--platform', 'linux/amd64',
                '-e', 'KEYSTORE_PW=' + password, '-e', 'TRUSTSTORE_PW=OtherStore42',
                '--entrypoint', '/bin/sh']
        for volume, target in zip(volumes, ['/etc/openelis-global', '/etc/ssl/private', '/etc/ssl/certs']):
            args += ['--mount', f'type=volume,src={volume},dst={target},volume-nocopy']
        args += ['--mount', f'type=bind,src={ROOT / "scripts/init-security.sh"},dst=/init-security.sh,readonly', self.image]
        args += ['-c', script] if script else ['/init-security.sh']
        return self.docker(*args, ok=ok)

    def fingerprint(self, volumes):
        return self.run_image(volumes, 'sha256sum /etc/openelis-global/keystore /etc/openelis-global/encryption.key').stdout

    def test_independent_installs_restart_and_custom_password(self):
        first, second = self.fresh(), self.fresh()
        self.run_image(first)
        self.run_image(second)
        before = self.fingerprint(first)
        self.assertNotEqual(before, self.fingerprint(second))
        self.run_image(first)
        self.assertEqual(before, self.fingerprint(first))
        # The exact leaf is trusted only under its declared service names.
        self.run_image(first, 'openssl verify -CAfile /etc/openelis-global/internal.crt -verify_hostname oe.openelis.org /etc/openelis-global/internal.crt')
        denied = self.run_image(first, 'openssl verify -CAfile /etc/openelis-global/internal.crt -verify_hostname wrong.example /etc/openelis-global/internal.crt', ok=False)
        self.assertNotEqual(denied.returncode, 0)
        unrelated = self.run_image(first, 'openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj /CN=unrelated -keyout /tmp/other.key -out /tmp/other.crt >/dev/null 2>&1 && openssl verify -CAfile /tmp/other.crt /etc/openelis-global/internal.crt', ok=False)
        self.assertNotEqual(unrelated.returncode, 0)
        mode = self.run_image(first, "stat -c '%a %u' /etc/openelis-global/encryption.key").stdout.strip()
        self.assertEqual(mode, '400 8443')
        failed = self.run_image(first, password='WrongStore42', ok=False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(before, self.fingerprint(first))

    def test_unknown_material_and_partial_state_fail_without_replacement(self):
        volumes = self.fresh()
        self.run_image(volumes, 'echo existing > /etc/openelis-global/keystore')
        self.assertNotEqual(self.run_image(volumes, ok=False).returncode, 0)
        self.assertEqual(self.run_image(volumes, 'cat /etc/openelis-global/keystore').stdout.strip(), 'existing')
        volumes = self.fresh()
        self.run_image(volumes)
        self.run_image(volumes, 'rm /etc/openelis-global/encryption.key')
        self.assertNotEqual(self.run_image(volumes, ok=False).returncode, 0)
        self.run_image(volumes, 'test ! -e /etc/openelis-global/encryption.key')
