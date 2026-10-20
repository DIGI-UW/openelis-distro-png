#!/usr/bin/env python3
"""Recompute an analyzer profile's catalog fingerprints in place.

The Analyzer Bridge refuses a shipped profile whose `catalog.recognitionFingerprint`
or `catalog.revisionFingerprint` does not match its content. Run this after
editing a profile under configs/analyzer-catalog (and after raising
`catalog.revision`):

    python3 scripts/sign-analyzer-profile.py configs/analyzer-catalog/<type>/<revision>.json

With --check it only reports whether the fingerprints match.

Fingerprints are SHA-256 over RFC 8785 canonical JSON, as the Bridge's
ProfileFingerprintService computes them. Profiles hold only strings,
integers, booleans and nulls; a float is refused rather than risk a
canonical-number mismatch.
"""
import copy
import hashlib
import json
import sys


def _no_floats(value):
    if isinstance(value, float):
        raise SystemExit("profile contains a float (%r); use an integer or a string" % value)
    if isinstance(value, dict):
        for item in value.values():
            _no_floats(item)
    elif isinstance(value, list):
        for item in value:
            _no_floats(item)


def fingerprint(value):
    _no_floats(value)
    canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def sign(profile):
    catalog = profile["catalog"]
    recognition = copy.deepcopy(profile["controlResultRecognition"])
    recognition.pop("recognitionFingerprint", None)
    catalog["recognitionFingerprint"] = fingerprint(recognition)
    unsigned = copy.deepcopy(profile)
    unsigned["catalog"].pop("revisionFingerprint", None)
    catalog["revisionFingerprint"] = fingerprint(unsigned)


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    if not paths:
        raise SystemExit(__doc__)
    status = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            profile = json.load(f)
        before = dict(profile["catalog"])
        sign(profile)
        changed = before != profile["catalog"]
        if check:
            print("%s: %s" % (path, "MISMATCH" if changed else "ok"))
            status |= changed
            continue
        with open(path, "w", encoding="utf-8") as f:
            json.dump(profile, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("%s: %s" % (path, "signed" if changed else "unchanged"))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
