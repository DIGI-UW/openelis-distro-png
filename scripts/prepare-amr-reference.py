#!/usr/bin/env python3
"""Install the distro-pinned AMR archive before OpenELIS starts; no R runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.parse
import urllib.request
import zipfile

MAX_BYTES = 32 * 1024 * 1024
FORMAT = "openelis-amr-reference/v1"


def read_pin(path):
    pin = json.loads(path.read_text())
    if set(pin) != {"format", "version", "url", "sha256"}:
        raise ValueError("AMR pin requires format, version, url and sha256")
    if pin["format"] != FORMAT or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", pin["version"]):
        raise ValueError("Unsupported AMR package format or version")
    if not re.fullmatch(r"[a-f0-9]{64}", pin["sha256"]):
        raise ValueError("AMR pin requires a SHA-256 from the reviewed release")
    expected = ("https://github.com/DIGI-UW/AMR/releases/download/openelis-reference-"
                + pin["version"] + "/amr-reference-" + pin["version"] + ".zip")
    if pin["url"] != expected:
        raise ValueError("AMR URL must identify the versioned DIGI-UW/AMR release asset")
    return pin


def verified(path, pin):
    if not path.is_file() or path.stat().st_size > MAX_BYTES:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest() == pin["sha256"]


def check_manifest(path, pin):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if sum(entry.file_size for entry in entries) > MAX_BYTES:
            raise ValueError("Expanded AMR package exceeds size limit")
        if archive.namelist().count("manifest.json") != 1:
            raise ValueError("AMR archive requires one manifest")
        manifest = json.loads(archive.read("manifest.json"))
    if (manifest.get("format") != pin["format"]
            or manifest.get("packageVersion") != pin["version"]
            or manifest.get("packageId") != "amr-reference-" + pin["version"]):
        raise ValueError("AMR manifest differs from the distro pin")


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise ValueError("AMR download refused a non-HTTPS redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, target):
    opener = urllib.request.build_opener(HTTPSRedirects())
    request = urllib.request.Request(url, headers={"User-Agent": "OpenELIS-PNG-reference-loader"})
    with opener.open(request, timeout=60) as response, target.open("wb") as output:
        size = 0
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_BYTES:
                raise ValueError("AMR archive exceeds size limit")
            output.write(chunk)
        output.flush()
        os.fsync(output.fileno())


def prepare(pin_path, destination, fetch=download):
    if not pin_path.exists():
        print("AMR reference package not configured: no distro pin")
        return None
    pin = read_pin(pin_path)
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / ("amr-reference-" + pin["version"] + "-" + pin["sha256"] + ".zip")
    if verified(target, pin):
        check_manifest(target, pin)
        print("AMR reference package verified in cache: " + pin["version"])
        return target
    fd, name = tempfile.mkstemp(prefix=".amr-download-", suffix=".part", dir=destination)
    os.close(fd)
    temporary = Path(name)
    try:
        fetch(pin["url"], temporary)
        if not verified(temporary, pin):
            raise ValueError("AMR download checksum differs from the distro pin; previous packages retained")
        check_manifest(temporary, pin)
        temporary.chmod(0o644)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    print("AMR reference package installed: " + pin["version"] + " sha256=" + pin["sha256"])
    return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    try:
        installed = prepare(args.pin, args.destination)
        if installed and os.environ.get("OE_CONFIGURATION_AUTOCREATE", "true").lower() != "true":
            print("AMR archive prepared but application import is DISABLED by OE_CONFIGURATION_AUTOCREATE")
    except Exception as error:
        parser.exit(1, "AMR package preparation failed: " + str(error) + "\n")
