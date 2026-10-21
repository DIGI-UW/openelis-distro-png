# PNG candidate validation — 21 October 2026

Candidate: `c/optional-analyzer-mounts`, based on
`1de65a3d963901892d6d18277ebe1e8f1016972b`. This record belongs with the
candidate commit. Exact application/tool images are the digest references in
`docker-compose.yml`; publication preserves those references.

## Environments and boundaries

- Isolated Docker project `png-fresh-20261021` on OrbStack: empty database,
  security volumes and Bridge state; synthetic credentials and patients.
  Container names, network addressing and published ports were isolated from
  other local stacks. All published test ports were loopback-only.
- Clean Ubuntu 24.04.5 machine `png-distro-linux`: native ARM64 Docker daemon,
  native Linux storage, the pinned AMD64 application containers under emulation.
  Candidate source copied to `/opt/png-candidate`, independent empty state and
  synthetic credentials; online pulls followed by plain `docker compose up -d`.
- This is not performance qualification on production x86 hardware. An initial
  emulated x86 Ubuntu VM failed inside Docker/runc before application startup;
  it was replaced by the native-daemon environment above and deleted.
- A Java diagnostic signal terminated the first ARM-hosted Ubuntu application
  attempt under emulation. That interrupted attempt is not counted as a clean
  install pass. Its synthetic database, Bridge state and security volumes were
  discarded. The later installer-only rerun was superseded by the user request
  for raw Compose. The completed plain-Compose run started from empty state and
  did not use that diagnostic probe.
- No existing PNG server was accessed or modified. No migration, GitHub CI run,
  release publication or production deployment is represented by these checks.

## Baseline checks before the plain-Compose revision

| Check | Observed result |
|---|---|
| Focused Ubuntu tests | All 14 passed, including real mount/read-only probes, native permission denial, independent certificate generation, restart retention and fail-closed cases. |
| Host focused tests | 13 passed; the Linux-only permission test was skipped. After the final documentation/default-bind changes, 10 fast checks passed and 4 opt-in runtime checks were skipped. |
| Base startup without analyzer host files | Passed in the isolated stack. No `ANALYZER_HOST_MOUNT` or host drop directory was needed. |
| Administrator verification | Configured password HTTP 200; published default HTTP 401. Browser login passed with zero page errors. |
| Local HTTPS proxy | Login and workflow passed through the proxy with upstream certificate verification enabled. Browser automation accepted the local self-signed browser certificate; public CA issuance was not tested. |
| Live FHIR TLS | Metadata HTTP 200 with installation trust and client identity. Wrong hostname and unrelated trust failed the handshake, without an HTTP response. |
| Keys and encrypted stores | Independent clean generations differed; custom passwords worked; wrong password, unknown material and missing encryption secret failed without replacement. Final generator explicitly uses AES-256-CBC for PKCS12 key/certificate bags and SHA-256 MAC. |
| Secret logging | Generated passwords absent from recreated OpenELIS/FHIR startup logs after the logging fix. |
| PNG clinical workflow | Catalog initialized. Synthetic Glucose(Plasma) order accepted result 5.5, validation/release completed, and the PDF contained the accession, test and value. |
| Pairing | OpenELIS and Bridge paired successfully and reported certificate fingerprints. |
| Analyzer delivery | Thermo QuantStudio XLSX profile, manually mapped VIH-1 to the existing HIV VIRAL LOAD(Plasma) test. Value 1250 delivered on attempt 1 and appeared as one matched analyzer review row. |
| Analyzer file access | Synthetic file used the shared internal import volume, without a host mount. Connection probe succeeded and reported the directory non-writable to Bridge. |
| Unknown HTTP sender | Bridge returned HTTP 403: no active HTTP analyzer connection for that sender. Historical logs were not imported as authorization. |
| Full stack restart | Passed after removing/recreating containers and network without deleting volumes. Identical key/encryption hashes, pairing fingerprints, saved Glucose result and report; exactly one analyzer review row. Bridge logged file hash deduplication. |
| Earlier Ubuntu installer | Superseded by the requested plain-Compose startup revision before completion; not counted as an install pass. |
| Syntax and whitespace | Shell syntax checks and `git diff --check` passed. |

The first isolated startup took approximately 22 minutes under emulation. The
readiness grace period is 30 minutes and installer wait is 35 minutes; readiness
can succeed earlier. The first fixture predates the final PKCS12 algorithm
selection. Final generation was separately retested and is used by the clean
Ubuntu installation; its encrypted PKCS12 also passed a live, verified FHIR
metadata request (HTTP 200). Its existing identity was preserved, not silently replaced.

## Plain-Compose revision

The user requested `docker compose up -d` as the installation entry point.
The `certs` job now checks site credentials and prepares configuration permissions
before the database starts. `admin-init` sets the fresh password once;
`admin-verify` checks it through the live application before proxy startup.
They reuse already-pinned database and application images. The initializer
retains PostgreSQL's standard `pgcrypto` extension instead of removing it.

The built-in PostgreSQL account also now receives `ADMIN_PASSWORD` through
`POSTGRES_PASSWORD`; the earlier candidate left that account on its published
password. This fix applies to an empty database, not an existing deployment.

- Host suite: 17 tests ran, 16 passed, Linux-only permission test skipped.
- Full Linux suite: all 17 tests passed in 106.859 seconds, with no skips.
- Fresh plain-Compose boot: passed from empty Ubuntu state, without calling
  `scripts/install.sh` or `scripts/fix-config-permissions.sh`. Started at
  20:41:38 UTC and finished at 21:09:25 UTC (27 minutes 46 seconds under
  emulation). Initialization jobs exited 0 and the proxy became healthy.
- Default-credential negative startup: an isolated plain-Compose project refused
  the example administrator password; database, application and proxy never
  started. Its containers/network/volumes were then removed.
- PostgreSQL transport remains internal and unencrypted (`SHOW ssl` returned
  `off`); whole-database/file encryption is not claimed.
- Fresh database authentication: both `postgres` and `admin` accepted the
  configured password and rejected their published defaults over the Docker network.
- Fresh administrator: configured login HTTP 200, published default HTTP 401.
  Browser login passed with zero page errors; dashboard screenshot inspected.
- Repeated plain Compose startup: administrator password hash unchanged. A
  deliberately mismatched verification password blocked proxy startup without
  resetting the account; restoring the configured value restored proxy access.
- Secret logging: all service logs excluded the configured application, database
  and store passwords and the generated field-encryption secret.
- The earlier README review finding about plain Compose bypassing initialization
  is resolved by this requested behavior change; the command now owns the checks.

## Repeating the checks

For an empty target, follow the README installation steps: copy `.env.example`,
set unique passwords, then run `docker compose up -d`. No host permission or
installer script is needed. Run `scripts/set-admin-password.sh --check` afterwards.
Never use an existing installation's state for a fresh-install test.

After pulling the pinned Bridge and certgen images, run:

```sh
PNG_TEST_DOCKER_MOUNTS=1 PNG_TEST_SECURITY=1 python3 -m unittest discover -s tests -v
```

Pair the Bridge, create a synthetic order from the PNG catalog, enter and
validate a result, and inspect its patient report. For the bounded analyzer
path, configure the shipped `thermo-quantstudio` profile, map VIH-1 to the PNG
HIV viral-load test, and activate a FILE connection. A synthetic XLSX row with
`SampleName`, `TargetName`, `QuantityMean`, `CT` and `Task` columns used values
`<synthetic accession>`, `VIH-1`, `1250`, `27.2`, and `UNKNOWN`. Confirm one
matched review row. Restart without removing volumes and verify identity,
pairing, records and file deduplication.

Private local evidence is retained under `.local/fresh-install/` (ignored by
Git), including screenshots and synthetic PDFs. That directory also contains
session and configuration secrets; do not publish or archive it wholesale.

The final Ubuntu startup log and focused-test log are retained locally. The
validation machine is stopped with its state retained for inspection. The earlier
isolated host stack is also down, with its synthetic state retained. Browser
evidence is `.local/ubuntu-compose-login.png`. No secret-bearing evidence is
included in the source archive.

## Remaining operator acceptance

- Configure the real domain and complete Let's Encrypt issuance; validate
  browser trust from the intended client machines.
- Clinically review PNG tests, reference ranges, codes and instrument mappings.
  Catalog load and a synthetic result do not constitute clinical sign-off.
- Validate each actual instrument's transport and restrict the network listeners.
  Only the stated file profile and unknown HTTP sender rejection were tested.
- Migration must preserve or deliberately convert old encrypted fields and
  include all state in [the target contract](target-state.md). The existing
  backup script is not a complete migration package.

## Brief for the dev meeting

PNG now uses familiar Docker Compose startup, with optional analyzer file mounts,
private install-generated keys, verified internal service connections, a separate
stored-field encryption secret, and fixed image digests. Login, a synthetic
clinical report and one analyzer delivery have passed locally. Full restart also passed;
the new plain-Compose path also passed from an empty Ubuntu target, including
password initialization, browser login and safe repeated startup. No OE2 or Bridge
source changes were required. Public-domain HTTPS, clinical sign-off and actual
instrument checks remain deployment acceptance; offline packaging, broad
certificate rotation and migration automation remain deferred.
