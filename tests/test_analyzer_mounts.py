"""Compose contract tests: resolve real files without touching a deployment."""

import importlib.util
import json
import os
import io
from contextlib import redirect_stdout
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mount_check", ROOT / "scripts/check-analyzer-mounts.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class AnalyzerMountTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="png-compose-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        for name in ("docker-compose.yml", "compose.analyzer-files.yaml", "compose.letsencrypt.yaml"):
            shutil.copyfile(ROOT / name, self.root / name)
        (self.root / "configs/database").mkdir(parents=True)
        (self.root / "configs/database/database.env").write_text("")
        shutil.copyfile(ROOT / ".env.example", self.root / ".env")
        # No local operator environment or secrets may influence the test model.
        self.env = {key: os.environ[key] for key in ("PATH", "HOME") if key in os.environ}

    def model(self, files=(), mount=None):
        if mount is not None:
            self.env["ANALYZER_HOST_MOUNT"] = mount
        command = ["docker", "compose", "--env-file", str(self.root / ".env"), "-f", "docker-compose.yml"]
        for name in files:
            command.extend(["-f", name])
        result = subprocess.run(command + ["config", "--format", "json"], cwd=self.root,
                                env=self.env, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_default_has_no_host_mount_and_preserves_network_and_internal_storage(self):
        model = self.model()
        self.assertEqual({}, check.analyzer_mounts(model, {}))
        bridge = model["services"]["openelis-analyzer-bridge"]
        self.assertIn(12001, [int(port["target"]) for port in bridge["ports"]])
        self.assertEqual("true", bridge["environment"]["BRIDGE_FILE_ENABLED"])
        for service in check.SERVICE_USERS:
            targets = [v["target"] for v in model["services"][service]["volumes"]]
            self.assertIn("/data/analyzer-imports", targets)
        self.assertFalse((self.root / "configs/analyzer-drops").exists())

    def test_security_volumes_never_copy_image_private_keys(self):
        for files in ((), ("compose.letsencrypt.yaml",)):
            model = self.model(files)
            for name, service in model["services"].items():
                for mount in service.get("volumes", []):
                    if mount.get("source") in {"key_trust-store-volume", "keys-vol", "certs-vol"}:
                        self.assertTrue(mount.get("volume", {}).get("nocopy"), (name, mount))
                        if name in {"oe.openelis.org", "fhir.openelis.org", "openelis-analyzer-bridge"}:
                            self.assertTrue(mount["read_only"])

    def test_optional_mount_merges_with_browser_https(self):
        for others in ((), ("compose.letsencrypt.yaml",)):
            with self.subTest(overlays=others):
                model = self.model((*others, "compose.analyzer-files.yaml"))
                mounts = check.analyzer_mounts(model, {})
                self.assertEqual(set(check.SERVICE_USERS), set(mounts))
                for mount in mounts.values():
                    self.assertEqual(str(self.root / "configs/analyzer-drops"), mount["source"])
                    self.assertTrue(mount["read_only"])
                    self.assertFalse(mount["bind"].get("create_host_path", False))

    def test_external_path_with_spaces_is_shared_at_same_container_path(self):
        source = str(self.root / "external share")
        mounts = check.analyzer_mounts(self.model(("compose.analyzer-files.yaml",), source), {})
        self.assertEqual({source}, {v["source"] for v in mounts.values()})

    def test_existing_mount_setting_without_overlay_is_actionable_failure(self):
        model = self.model(mount="/mnt")
        with self.assertRaisesRegex(check.CheckError, "Add compose.analyzer-files.yaml"):
            check.analyzer_mounts(model, {"ANALYZER_HOST_MOUNT": "/mnt"})

    def test_inconsistent_or_writable_mounts_are_rejected(self):
        for mutation in ("missing", "different", "writable", "auto-create"):
            with self.subTest(mutation=mutation):
                model = self.model(("compose.analyzer-files.yaml",))
                volumes = model["services"]["openelis-analyzer-bridge"]["volumes"]
                mount = next(v for v in volumes if v["target"] == check.TARGET)
                if mutation == "missing":
                    volumes.remove(mount)
                elif mutation == "different":
                    mount["source"] = "/other"
                elif mutation == "writable":
                    mount["read_only"] = False
                else:
                    mount["bind"]["create_host_path"] = True
                with self.assertRaises(check.CheckError):
                    check.analyzer_mounts(model, {})

    def check_fixture(self, files=(), mount=None):
        self.env["COMPOSE_FILE"] = ":".join(("docker-compose.yml", *files))
        if mount is not None:
            self.env["ANALYZER_HOST_MOUNT"] = mount
        with patch.object(check, "ROOT", self.root), patch.dict(os.environ, self.env, clear=True):
            with redirect_stdout(io.StringIO()) as output:
                check.check()
        return output.getvalue()

    def test_preflight_default_and_legacy_setting(self):
        self.assertIn("no analyzer host mount required", self.check_fixture())
        with self.assertRaisesRegex(check.CheckError, "Add compose.analyzer-files.yaml"):
            self.check_fixture(mount="/mnt")

    @unittest.skipUnless(os.environ.get("PNG_TEST_DOCKER_MOUNTS") == "1", "set PNG_TEST_DOCKER_MOUNTS=1 for disposable Docker probes")
    def test_daemon_mounts_for_both_users_and_rejects_missing_directory(self):
        source = self.root / "analyzer files"
        source.mkdir(mode=0o755)
        (source / "synthetic-result.txt").write_text("synthetic test only\n")
        output = self.check_fixture(("compose.analyzer-files.yaml",), str(source))
        self.assertIn("user 8443 (read-only)", output)
        self.assertIn("user 9257 (read-only)", output)
        self.assertEqual("synthetic test only\n", (source / "synthetic-result.txt").read_text())
        with self.assertRaisesRegex(check.CheckError, "Docker mount/read probe"):
            self.check_fixture(("compose.analyzer-files.yaml",), str(self.root / "missing"))
        self.assertFalse((self.root / "missing").exists())
        model = self.model(("compose.analyzer-files.yaml",), str(source))
        bridge = model["services"]["openelis-analyzer-bridge"]
        # Prove read-only enforcement even for root, using synthetic files only.
        with self.assertRaises(check.CheckError):
            check.run([
                "docker", "run", "--rm", "--pull=never", "--network=none",
                "--read-only", "--user", "0", "--entrypoint", "/bin/sh",
                "--platform", bridge["platform"], "--mount",
                f"type=bind,src={source},dst={check.TARGET},readonly",
                bridge["image"], "-c", "touch /data/analyzer-drops/write-probe",
            ], "Read-only write probe")
        self.assertFalse((source / "write-probe").exists())

    @unittest.skipUnless(os.environ.get("PNG_TEST_DOCKER_MOUNTS") == "1" and sys.platform == "linux", "permission-denial probe requires a native Linux Docker host")
    def test_daemon_rejects_unreadable_directory(self):
        # macOS shared filesystems can virtualize POSIX permissions; validate
        # Linux permission denial on the supported production platform instead.
        source = self.root / "unreadable"
        source.mkdir(mode=0o000)
        try:
            with self.assertRaisesRegex(check.CheckError, "Docker mount/read probe"):
                self.check_fixture(("compose.analyzer-files.yaml",), str(source))
        finally:
            source.chmod(0o755)

    def test_compose_error_does_not_echo_credentials(self):
        result = subprocess.CompletedProcess([], 1, "password=private-test-value", "private-test-value")
        with patch.object(check.subprocess, "run", return_value=result):
            with self.assertRaises(check.CheckError) as error:
                check.run(["docker", "compose", "config"], "Resolving Compose")
        self.assertNotIn("private-test-value", str(error.exception))


if __name__ == "__main__":
    unittest.main()
