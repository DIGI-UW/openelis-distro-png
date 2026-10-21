#!/usr/bin/env python3
"""Resolve every base image before atomically updating the deployment file."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE = re.compile(r'^(\s+image:\s+)(\S+)(.*)$', re.MULTILINE)
DIGEST = re.compile(r'sha256:[0-9a-f]{64}')


def pin(text, resolver, oe=None, bridge=None):
    resolved = {}
    for match in IMAGE.finditer(text):
        original = match[2]
        ref = original.split('@')[0]
        repo = ref.rsplit(':', 1)[0]
        tag = bridge if repo == 'itechuw/openelis-analyzer-bridge' else (
            oe if repo.startswith('itechuw/openelis-global-2') else None)
        if tag:
            if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', tag):
                raise ValueError('Invalid image tag')
            ref = f'{repo}:{tag}'
        if ref not in resolved:
            digest = resolver(ref)
            if not DIGEST.fullmatch(digest):
                raise ValueError(f'Invalid registry digest for {ref}')
            resolved[ref] = f'{ref}@{digest}'
        resolved[original] = resolved[ref]
    if not resolved:
        raise ValueError('No images found')
    return IMAGE.sub(lambda m: m[1] + resolved[m[2]] + m[3], text)


def resolve(ref):
    result = subprocess.run(['docker', 'buildx', 'imagetools', 'inspect', ref,
                             '--format', '{{json .Manifest}}'],
                            check=True, text=True, capture_output=True, timeout=120)
    return json.loads(result.stdout)['digest']


if __name__ == '__main__':
    path = ROOT / 'docker-compose.yml'
    try:
        updated = pin(path.read_text(), resolve, *sys.argv[1:])
        temp = path.with_suffix('.yml.tmp')
        temp.write_text(updated)
        temp.replace(path)
    except (ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit(f'Image resolution failed; Compose was not changed: {type(exc).__name__}')
    print('All base images pinned to registry digests. Review docker-compose.yml.')
