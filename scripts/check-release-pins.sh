#!/usr/bin/env bash
# Every published target must retain the exact images that were tested.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$@" <<'PYCODE'
import pathlib,re,sys
files=sys.argv[1:] or ['docker-compose.yml','docker-compose.analyzers.yml']
errors=[]
for name in files:
    refs=re.findall(r'^\s+image:\s+(\S+)',pathlib.Path(name).read_text(),re.M)
    if not refs: errors.append(name+': no images found')
    for ref in refs:
        if '/e2e-cache/' in ref:errors.append(name+': temporary CI-cache image cannot be a deployment pin: '+ref)
        if not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}',ref):errors.append(name+': image requires an immutable digest: '+ref)
if errors:sys.exit('\n'.join(errors))
print('All target images have immutable digests.')
PYCODE
