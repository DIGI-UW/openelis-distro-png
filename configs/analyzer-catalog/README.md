# PNG analyzer catalog

The analyzer types (Analyzer Bridge profiles) this distribution offers on
Admin > Analyzer types. The Bridge loads every `<type>/<revision>.json` here
**in place of its built-in types** (`BRIDGE_PROFILE_CATALOG_SHIPPED_PATTERN` in
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

Tests with a known terminology hint carry a LOINC code, and
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
susceptibility results, a culture `POSITIVE`, `IN PROGRESS`)
are mapped or left out in each analyzer's setup. `MTB-XDR 2` covers the MTB
detection result; the drug-resistance calls are not told apart yet.

## Current contract and limits

These files use the current schema and explicitly declare where each ASTM
result's code, value, unit, status and timestamps are read. The Bridge computes
catalog fingerprints itself. There is no signing script or operator hash gate.
The PNG types expose TCP/IP and results upload only. The connection role is
separate: a Bridge client can connect to an instrument without sending orders.

MALDI `SCORE` has no PNG destination test. Its previous organism-identification
LOINC hint was incorrect and has been removed. It remains an unconfigured raw
value for review; it is not an organism answer or an imported numeric score.
BD susceptibility codes and unconfigured culture answers also need explicit
lab-approved mappings. `MTB-XDR 2` does not distinguish resistance calls yet.
Do not map them speculatively or interpret a software test as clinical approval.

`scripts/check-analyzer-profiles.sh` loads only these three types into the
released Bridge and exercises nine synthetic result cases. It checks normal
and control results, GeneXpert/MALDI failed runs, FHIR absence-of-result markers,
and preservation of an unmapped MALDI score. These fixtures describe the PNG
profile contract; they are not captured vendor messages or instrument certification.

## Changing a type

1. Copy the latest `<type>/<n>.json` to `<type>/<n+1>.json`, edit it and increment
   `catalog.revision`. Retain old revisions for saved connections.
2. Run `scripts/check-analyzer-profiles.sh` and extend the result fixtures for
   changes in how messages are read.
3. Restart the Bridge, inspect its catalog warnings and review the new type in
   OpenELIS. Existing connections adopt a new revision explicitly.

The initial PNG revision is still an unreleased candidate. The acceptance
boundary is a fresh installation; upgrading a site already using an earlier
copy of these profiles requires its own revision/adoption review.
