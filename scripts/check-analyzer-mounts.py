#!/usr/bin/env python3
"""Check optional analyzer mounts without starting the deployment or printing secrets."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = "/data/analyzer-drops"
SERVICE_USERS = {"oe.openelis.org": "8443", "openelis-analyzer-bridge": "9257"}


class CheckError(Exception):
    pass


def run(command, description):
    try:
        result = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True, timeout=120
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CheckError(f"{description}: command unavailable or timed out.") from error
    if result.returncode:
        # Compose diagnostics can contain interpolated credentials. Never echo
        # the command output or full model, including on failure.
        raise CheckError(f"{description} failed (exit {result.returncode}).")
    return result.stdout


def analyzer_mounts(model, environment):
    """Require the same, read-only, explicitly prepared source in both services."""
    mounts = {}
    for service in SERVICE_USERS:
        if service not in model["services"]:
            raise CheckError(f"Expected service {service} is missing; check selected Compose files.")
        matches = [
            volume for volume in model["services"][service].get("volumes", [])
            if volume["target"] == TARGET
        ]
        if matches:
            mounts[service] = matches[0]
    if not mounts:
        if environment.get("ANALYZER_HOST_MOUNT"):
            raise CheckError(
                "ANALYZER_HOST_MOUNT is set but no analyzer directory is mounted. "
                "Add compose.analyzer-files.yaml to COMPOSE_FILE for file-based analyzers, "
                "or remove the obsolete setting if no instruments use it."
            )
        return mounts
    if len(mounts) != len(SERVICE_USERS):
        raise CheckError("Both OpenELIS and Bridge must mount the analyzer directory.")
    sources = set()
    for service, mount in mounts.items():
        if mount["type"] != "bind" or not mount.get("read_only"):
            raise CheckError(f"{service}: analyzer directory must be a read-only host bind mount.")
        if mount.get("bind", {}).get("create_host_path", False):
            raise CheckError(
                f"{service}: automatic host-directory creation is enabled. "
                "Use compose.analyzer-files.yaml to fail on missing shares."
            )
        sources.add(mount["source"])
    if len(sources) != 1:
        raise CheckError("OpenELIS and Bridge use different analyzer source directories.")
    return mounts


def check():
    context = run(["docker", "context", "show"], "Reading Docker context").strip()
    print(f"Docker context: {context} (DOCKER_HOST/DOCKER_CONTEXT overrides also apply)")
    model = json.loads(run(
        ["docker", "compose", "config", "--format", "json"],
        "Resolving Compose configuration; check COMPOSE_FILE, local overrides and .env",
    ))
    environment = dict(
        line.split("=", 1)
        for line in run(
            ["docker", "compose", "config", "--environment"],
            "Reading Compose interpolation settings",
        ).splitlines() if "=" in line
    )
    mounts = analyzer_mounts(model, environment)
    if not mounts:
        print("OK: no analyzer host mount required. Network connections and internal storage remain configured.")
        return
    bridge_image = model["services"]["openelis-analyzer-bridge"]["image"]
    for service, mount in mounts.items():
        source = mount["source"]
        if "," in source or "\n" in source:
            raise CheckError("Analyzer source contains a comma or newline; choose a path without these characters.")
        user = model["services"][service].get("user", SERVICE_USERS[service])
        command = [
            "docker", "run", "--rm", "--pull=never", "--network=none",
            "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
            "--user", str(user), "--entrypoint", "/bin/sh",
            "--mount", f"type=bind,src={source},dst={TARGET},readonly",
        ]
        platform = model["services"]["openelis-analyzer-bridge"].get("platform")
        if platform:
            command.extend(["--platform", platform])
        command.extend([
            bridge_image, "-c", 'test -d "$1" && test -r "$1" && test -x "$1"',
            "check-analyzer-directory", TARGET,
        ])
        try:
            run(command, f"Docker mount/read probe for {service}")
        except CheckError as error:
            raise CheckError(
                f"{error} Check Docker availability, pull the configured Bridge image, "
                f"and ensure {source} exists on the Docker host and is readable/traversable "
                f"by user {user}. On Docker Desktop, allow that directory in File Sharing; "
                "sudo cannot bypass it. Do not replace a missing external share with an empty directory."
            ) from error
        print(f"OK: {service} can mount and read {source} as user {user} (read-only).")
    print("Mount checks passed. Instrument workflows and application readiness still need verification.")


def main():
    try:
        check()
    except (CheckError, ValueError, KeyError) as error:
        # JSON/model errors should not expose configuration values either.
        message = str(error) if isinstance(error, CheckError) else "Unexpected Compose output; check Docker Compose version."
        print(f"ERROR: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
