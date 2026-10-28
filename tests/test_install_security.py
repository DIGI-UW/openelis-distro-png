"""Real key generation in task-owned Docker volumes; opt in with PNG_TEST_SECURITY=1."""
import os
import secrets
from pathlib import Path
import subprocess
import unittest
import uuid
from test_analyzer_target import compose

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get("PNG_TEST_SECURITY") == "1", "set PNG_TEST_SECURITY=1 for real certificate tests")
class InstallSecurityTest(unittest.TestCase):
    def setUp(self):
        self.image = compose()["init"]["image"]
        self.volumes = []
        self.store_password = secrets.token_hex(16)  # Disposable test credential.
        self.trust_password = secrets.token_hex(16)  # Disposable test credential.

    def tearDown(self):
        for name in self.volumes:
            subprocess.run(["docker", "volume", "rm", name], check=True, capture_output=True)

    def volume(self):
        name = "png-security-" + uuid.uuid4().hex
        subprocess.run(["docker", "volume", "create", name], check=True, capture_output=True)
        self.volumes.append(name)
        return name

    def run_script(self, volume, command="/scripts/init-security.sh", password=None, succeeds=True):
        r = subprocess.run(["docker", "run", "--rm", "--network", "none", "--platform", "linux/amd64", "--user", "0:0",
            "--entrypoint", "sh", "-e", "KEYSTORE_PW=" + (password or self.store_password), "-e", "TRUSTSTORE_PW=" + self.trust_password,
            "--mount", "type=volume,src=" + volume + ",dst=/data,volume-nocopy",
            "--mount", "type=bind,src=" + str(ROOT / "scripts") + ",dst=/scripts,readonly",
            self.image, "-c", command], capture_output=True, text=True, timeout=120)
        if succeeds:
            self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        else:
            self.assertNotEqual(0, r.returncode)
        return r.stdout

    def fingerprint(self, volume):
        return self.run_script(volume, "sha256sum /data/tls/stores/keystore /data/tls/stores/encryption.key")

    def test_independent_keys_restart_retention_and_wrong_password(self):
        a, b = self.volume(), self.volume()
        self.run_script(a)
        self.run_script(b)
        before = self.fingerprint(a)
        self.assertNotEqual(before, self.fingerprint(b))
        self.run_script(a)
        self.assertEqual(before, self.fingerprint(a))
        self.run_script(a, password=secrets.token_hex(16), succeeds=False)  # Deliberately wrong test credential.
        self.assertEqual(before, self.fingerprint(a))
        self.run_script(a, "openssl verify -CAfile /data/tls/stores/internal.crt -verify_hostname fhir.openelis.org /data/tls/stores/internal.crt")
        self.run_script(a, "openssl verify -CAfile /data/tls/stores/internal.crt -verify_hostname wrong.invalid /data/tls/stores/internal.crt", succeeds=False)
        mode = self.run_script(a, "stat -c '%a %u' /data/tls/stores/encryption.key").strip()
        self.assertEqual("400 8443", mode)

    def test_unknown_or_partial_state_never_generates_replacement(self):
        a = self.volume()
        self.run_script(a, "mkdir -p /data/tls/stores; echo existing > /data/tls/stores/keystore")
        self.run_script(a, succeeds=False)
        self.assertEqual("existing", self.run_script(a, "cat /data/tls/stores/keystore").strip())
        b = self.volume()
        self.run_script(b)
        before = self.run_script(b, "sha256sum /data/tls/stores/keystore")
        self.run_script(b, "rm /data/tls/stores/encryption.key")
        self.run_script(b, succeeds=False)
        self.assertEqual(before, self.run_script(b, "sha256sum /data/tls/stores/keystore"))
        self.run_script(b, "test ! -e /data/tls/stores/encryption.key")

    def test_existing_database_without_keys_is_not_treated_as_fresh(self):
        a = self.volume()
        self.run_script(a, "mkdir -p /data/db; echo 14 > /data/db/PG_VERSION")
        self.run_script(a, succeeds=False)
        self.run_script(a, "test ! -e /data/tls/stores/encryption.key; test ! -e /data/tls/keys/apache-selfsigned.key")

    def test_readable_but_unrelated_truststore_is_rejected(self):
        a = self.volume()
        self.run_script(a)
        before = self.fingerprint(a)
        self.run_script(a, "mkdir -p /other; PNG_DATA_ROOT=/other /scripts/init-security.sh; cp /other/tls/stores/truststore /data/tls/stores/truststore")
        self.run_script(a, succeeds=False)
        self.assertEqual(before, self.fingerprint(a))
