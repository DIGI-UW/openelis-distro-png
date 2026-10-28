#!/usr/bin/env bash
# Resolve a proposed image set, then review and test the diff before committing.
# No arguments: validate existing pins without changing them.
# Usage: scripts/pin-versions.sh OE_TAG BRIDGE_TAG
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# == 0 ]]; then exec scripts/check-release-pins.sh; fi
if [[ $# != 2 ]]; then echo 'Usage: pin-versions.sh OE_TAG BRIDGE_TAG' >&2; exit 2; fi
python3 - "$1" "$2" <<'PY'
import pathlib, re, subprocess, sys
for tag in sys.argv[1:]:
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}',tag):
        sys.exit('Invalid image tag')
files=[pathlib.Path(n) for n in ('docker-compose.yml','docker-compose.analyzers.yml')]
original={p:p.read_text() for p in files}
refs=set(re.findall(r'^\s+image:\s+(\S+)', '\n'.join(original.values()), re.M))
replacements={}
for ref in sorted(refs):
    tagged=ref.split('@')[0]
    repo,tag=tagged.rsplit(':',1)
    if repo=='itechuw/openelis-analyzer-bridge': tag=sys.argv[2]
    elif repo in ('ghcr.io/digi-uw/openelis-global-2', 'ghcr.io/digi-uw/openelis-global-2-frontend'):
        # A combined candidate can later be replaced with a published OE release.
        repo = 'itechuw/' + repo.rsplit('/', 1)[1]
        tag = sys.argv[1]
    elif repo=='itechuw/openelis-global-2' or repo.startswith('itechuw/openelis-global-2-'):tag=sys.argv[1]
    else: continue  # certgen and autoheal are reviewed separately
    proposed=repo+':'+tag
    output=subprocess.check_output(['docker','buildx','imagetools','inspect',proposed],text=True)
    found=re.search(r'^Digest:\s+(sha256:[a-f0-9]{64})$',output,re.M)
    if not found:sys.exit('No registry digest for '+proposed)
    replacements[ref]=proposed+'@'+found[1]
# Resolve all references successfully before touching either file.
for p,text in original.items():
    for old,new in replacements.items():text=text.replace('image: '+old,'image: '+new)
    p.write_text(text)
print('Resolved immutable image set. Review both Compose files, update image provenance and validate before committing.')
PY
