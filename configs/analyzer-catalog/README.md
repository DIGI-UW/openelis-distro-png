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

Each test entry carries a LOINC code (the profile format requires one), and
each coded answer a LOINC answer code (`value_codes`). OpenELIS pre-fills an
analyzer's mapping from them when an OpenELIS test, or one of its answers,
carries the same code. The PNG catalog gives its tests and answers these codes
(`loinc` in `tests/png-tests.csv`, `loincCode` in
`dictionaries/png-dictionary-entries.csv`):

| Instrument code | LOINC | OpenELIS test |
|---|---|---|
| `HIV-1_VL 2` | 20447-9 | Xpert HIV-1 VL Result |
| `HIV-1_QUAL 2 2` | 79380-2 | Xpert HIV-1 Qual Result |
| `MTB-RIF_ULTRA 2` | 85362-2 | Xpert MTB/RIF Ultra MTB Result |
| `MTB-XDR 2` | 38379-4 | Xpert MTB/XDR MTB Result |
| `MGIT_960_GND` | 543-9 | Mycobacterial Culture Result |
| `PLUSAEF`, `STDAEF` | 600-7 | Microbiology Culture Result |
| `ORGANISM` | 11475-1 | Microbiology Culture Identification |

`NEGATIVE` on the culture codes is "No growth" (LA21123-7). The GeneXpert's
ERROR, INVALID and NO RESULT, and the MALDI's "no peaks found", "no reliable
identification" and "not reliable identification" in place of an organism,
are run failures, held for review rather than saved as results. The Bridge matches these
exactly, so each is listed in the casings Bruker uses. The BD type declares
no run failures; a value outside its declared ones is held for review. Codes with no OpenELIS test or answer yet (BD
susceptibility results, MALDI `SCORE`, a culture `POSITIVE`, `IN PROGRESS`)
are mapped or left out in each analyzer's setup. `MTB-XDR 2` covers the MTB
detection result; the drug-resistance calls are not told apart yet.

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
