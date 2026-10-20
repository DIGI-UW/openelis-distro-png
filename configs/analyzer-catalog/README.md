# PNG analyzer catalog

The analyzer types (Analyzer Bridge profiles) this distribution offers on
Admin > Analyzer types. The Bridge loads every `<type>/<revision>.json` here
**in place of its built-in types** (`BRIDGE_PROFILECATALOG_SHIPPEDPATTERN` in
`docker-compose.analyzers.yml`), so a PNG site is offered only these. Types a
site creates itself are kept in the Bridge's state (`DATA_ROOT/bridge`) and
appear alongside them.

| Type | Name on Admin > Analyzer types | Instrument |
|---|---|---|
| `png-cepheid-genexpert-astm` | Cepheid GeneXpert (PNG, ASTM results) | GeneXpert, results upload only |
| `png-bd-epicenter-astm` | BD EpiCenter (PNG, ASTM) | BD EpiCenter: MGIT 960, Phoenix M50, BACTEC FX |
| `png-bruker-maldi-astm` | Bruker MALDI Biotyper (PNG, ASTM) | MALDI Biotyper sirius, MBT Compass IVD |

They were built at CPHL on the training server in September 2026 and checked
against the messages those instruments sent. The GeneXpert type also carries
the `HIV-1_QUAL 2 2` and `MTB-XDR 2` assays the CPHL GeneXpert reports.

## Test codes and OpenELIS tests

Each test entry carries a LOINC code (the profile format requires one).
OpenELIS pre-fills an analyzer's mapping from it only when the OpenELIS test
has the same LOINC code; otherwise each code is mapped once per analyzer in
its setup. `MTB-XDR 2` covers the MTB detection result; the drug-resistance
calls are not told apart yet.

## Changing a type

The Bridge refuses a file whose fingerprints do not match its content, and
analyzers stay pinned to the revision they were set up on.

1. Copy the latest `<type>/<n>.json` to `<type>/<n+1>.json`, edit the copy and
   set its `catalog.revision` to `n+1`. Keep the old file: analyzers on it are
   offered the new revision and move when someone accepts it.
2. Recompute the fingerprints:
   `python3 scripts/sign-analyzer-profile.py configs/analyzer-catalog/<type>/<n+1>.json`
3. `docker compose up -d openelis-analyzer-bridge` and check the type on
   Admin > Analyzer types. `docker compose logs openelis-analyzer-bridge`
   names any file it set aside.
