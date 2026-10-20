# PNG analyzer catalog

Analyzer Bridge profiles this distribution ships on top of the Bridge's own
(core) profiles. Each profile is a directory named by its profile id holding
one file per revision, `<revision>.json`, in the Bridge's catalog format
(`{"profile": ..., "publication": ...}`). Files are kept byte-for-byte as the
Bridge wrote them, so revision fingerprints, and the connections pinned to
them, stay valid. `manifest.json` lists each revision with its fingerprint and
the training-server connections that use it.

| Profile | Instrument |
|---|---|
| `site.49ab1f03-...` | BD EpiCenter (MGIT 960 / Phoenix M50 / BACTEC FX), ASTM |
| `site.2e526773-...` | Bruker MALDI Biotyper sirius, ASTM |
| `site.a295bd7e-...` | CPHL GeneXpert, ASTM, results only |

All three were authored at CPHL on the training server (September 2026) from
the core `genexpert-astm` profile, revision 4.

## How the Bridge loads them

The Bridge reads one shipped-catalog location today, and pointing it here would
replace the core profiles. Loading a distro directory alongside the core
catalog is tracked as an Analyzer Bridge change; this directory is wired into
`docker-compose.analyzers.yml` once that lands. A site migrated from an older
stack already holds these revisions in its Bridge state (`DATA_ROOT/bridge`).

## Updating

Never edit a revision in place: a changed file is a different revision. Add
`<revision+1>.json` exported from the Bridge and update `manifest.json`.
