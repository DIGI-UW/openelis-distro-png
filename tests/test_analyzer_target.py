"""Test the resolved fresh target rather than individual YAML text fragments."""
import json
import os
import secrets
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENV = {**os.environ, **{name: "Png9!" + secrets.token_hex(16)
    for name in ("OE_DB_PASSWORD", "ADMIN_PASSWORD", "OE_ADMIN_PASSWORD")}}


def compose(*extra):
    result = subprocess.run(["docker", "compose", "--env-file", str(ROOT / ".env.example"),
        "-f", "docker-compose.yml", "-f", "docker-compose.analyzers.yml", *extra,
        "config", "--format", "json"], cwd=ROOT, env=ENV, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)["services"]


class AnalyzerTargetTest(unittest.TestCase):
    def test_tcp_target_has_no_host_drop_mount_or_file_watcher(self):
        services = compose()
        bridge = services["openelis-analyzer-bridge"]
        self.assertEqual("false", bridge["environment"]["BRIDGE_FILE_ENABLED"])
        for service in services.values():
            self.assertNotIn("/data/analyzer-drops", [v["target"] for v in service.get("volumes", [])])
        listener = next(p for p in bridge["ports"] if p["target"] == 12001)
        self.assertEqual("127.0.0.1", listener["host_ip"])
        self.assertEqual("127.0.0.1/32", bridge["environment"]["BRIDGE_LISTENERS_ALLOWED_SOURCES"])

    def test_file_overlay_only_exposes_files_to_bridge_and_refuses_directory_creation(self):
        from unittest.mock import patch
        with patch.dict(ENV, ANALYZER_HOST_MOUNT="/tmp/png-existing-test-input"):
            services = compose("-f", "compose.analyzer-files.yaml")
        bridge = services["openelis-analyzer-bridge"]
        self.assertEqual("true", bridge["environment"]["BRIDGE_FILE_ENABLED"])
        mount = next(v for v in bridge["volumes"] if v["target"] == "/data/analyzer-drops")
        self.assertTrue(mount["read_only"])
        self.assertFalse(mount["bind"].get("create_host_path", False))
        self.assertNotIn("/data/analyzer-drops", [v["target"] for v in services["oe.openelis.org"]["volumes"]])

    def test_live_admin_verification_precedes_proxy_and_database_waits_for_init(self):
        services = compose()
        self.assertEqual("service_completed_successfully", services["proxy"]["depends_on"]["verify-admin"]["condition"])
        self.assertEqual("service_completed_successfully", services["db.openelis.org"]["depends_on"]["init"]["condition"])
        self.assertEqual(ENV["ADMIN_PASSWORD"], services["db.openelis.org"]["environment"]["POSTGRES_PASSWORD"])
        self.assertNotIn("OE_ENCRYPTION_PASSWORD", services["oe.openelis.org"]["environment"])
        bridge = services["openelis-analyzer-bridge"]["environment"]
        self.assertNotIn("trustStorePassword", bridge["JDK_JAVA_OPTIONS"])
        self.assertEqual("PKCS12", bridge["BRIDGE_TRUSTSTORE_TYPE"])

    def test_letsencrypt_retains_internal_trust(self):
        proxy = compose("-f", "compose.letsencrypt.yaml")["proxy"]
        self.assertIn("/etc/nginx/png-internal.crt", [v["target"] for v in proxy["volumes"]])
