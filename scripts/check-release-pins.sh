#!/usr/bin/env bash
# Every image, including certgen, must be pinned. Tags remain readable labels.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT/docker-compose.yml" <<'PY'
import re
import sys
from pathlib import Path
refs = re.findall(r'^\s+image:\s+(\S+)', Path(sys.argv[1]).read_text(), re.M)
if not refs or any(not re.fullmatch(r'[^@]+@sha256:[0-9a-f]{64}', ref) for ref in refs):
    sys.exit('FAIL: every image requires a digest; run scripts/pin-versions.sh')
print('OK: all base images have immutable digest pins.')
PY
