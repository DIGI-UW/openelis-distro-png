# PNG target installation plan

Updated: 21 October 2026  
Status: implemented and validated locally on `c/optional-analyzer-mounts`.
The original isolated workflow/restart checks and the requested plain-Compose
fresh Ubuntu startup, browser login and repeated-startup checks passed.
Not published or deployed to the existing PNG server.

## Objective and boundary

Deliver a small, reproducible, online PNG distribution that can be installed
from scratch, tested, and handed over as the target for the existing training
installation. The user will handle migration from
`training.jdhealthsolutions-openelis.com`. We do not need access to that server
to build this target. No source-server inspection, migration execution or cutover
is part of this work.

The target is one Ubuntu Server host using published Docker images, the PNG
configuration and catalog, the web application, database, FHIR service, frontend,
proxy and analyzer Bridge already present in the distro. Keep their existing
interfaces; do not introduce a new deployment framework or make PNG the delivery
vehicle for the full upstream certificate remediation.

Installation requires internet access to pull the selected images. A source
archive is a convenient delivery format, not an offline installer.

## Keep in this delivery

| Item | Bounded outcome |
|---|---|
| Simple startup | Follow one documented online installation path on a clean Ubuntu host; no source builds or development mounts. |
| Optional analyzer host files | Default setup requires neither `ANALYZER_HOST_MOUNT` nor an analyzer drop folder. File-based instruments opt into a shared read-only folder. Preserve internal import storage and Bridge state. |
| PNG configuration | Load the included catalog, address hierarchy and configuration successfully; expose errors clearly. Loading the catalog does not replace its clinical review. |
| Working services | Confirm application readiness, login, browser access, internal FHIR access and a bounded synthetic analyzer result path. Do not certify every analyzer model or protocol. |
| Minimum security for the fresh target | Verify a non-default administrator password, generate private identity material on the installation rather than reuse image-bundled keys, verify peer identity through trust/hostname checks or explicit certificate pinning on the connections this target uses, and use a separate installation-specific secret for stored sensitive fields. Retain browser HTTPS. This is a bounded fresh-install requirement, not a universal upgrade/rotation framework. |
| Fixed release candidate | Select a compatible published image set and record exact digests, including certgen, so the tested target can be reproduced. Align release claims with what the tooling actually does. No general release-platform redesign. |
| Persistent state and handoff | Document the target's database, configuration, volumes, permissions and startup order. Verify restart retains synthetic data and configured state. The user chooses how to bring the old site's state into this target. |

## Delivery steps

### 1. Finish the startup change

- Keep `compose.analyzer-files.yaml` as an explicit opt-in file.
- Keep the focused mount check and regression tests. They catch the reported
  Docker mount failure and give existing file-based installations an actionable
  message when a mount setting lacks its optional Compose file.
- Keep installation instructions short: copy the example environment, set site
  passwords, prepare configuration permissions automatically, enable file mounts only if needed, and run
  `docker compose up -d`. Compose sets and verifies the fresh administrator.
- Retain the current Bridge state initializer and shared internal import volume.
  Removing a host file mount must not disable unrelated Bridge functionality.

**Done locally:** base Compose no longer mounts an analyzer host directory; the
example leaves the setting unset. The opt-in mounts are read-only in both
services and refuse automatic host-directory creation. Added preflight,
installation/upgrade instructions, ignored runtime result folders and automated
checks. The security work below now also generates private install-time keys,
separates the encryption secret and enables verified service connections.

**Evidence:** all 17 focused tests passed on Ubuntu, including native Linux
permission denial and independent certificate generation. Browser login,
a synthetic clinical report, Bridge pairing and a synthetic QuantStudio delivery
passed in the isolated stack. See the [validation record](validation-2026-10-21.md)
for exact checks, environment limits and remaining acceptance.

### 2. Choose and test the target release

- Record distro revision, image digests and the installation instructions used.
  Implemented locally: every base image has an immutable digest, including
  certgen. Publication verifies the committed candidate and does not resolve
  mutable tags again.
- Review the selected images' initialization behavior. Do not accidentally add
  rotation or encrypted-field migration of existing data by selecting an image
  containing those changes. Fresh-install generation is required; existing-data
  transformations must be identified explicitly for the user-owned migration.
- Install on a clean supported Linux host with empty application state and
  synthetic test data. Do not reuse development volumes as fresh-install proof.
- Verify the acceptance checks below and fix actual blockers in the distro or
  select a compatible upstream fix. Do not require completion of the entire
  upstream Bridge/OpenELIS PR stack unless the chosen target needs it.

### 3. Deliver the tested target and state handoff

Provide the exact release candidate, online install instructions, concise test
results and a state inventory. The inventory describes where the target expects:

- the application database and the FHIR data stored by this configuration;
- `.env`, site properties, PNG configuration and analyzer settings;
- Bridge state and pending deliveries, shared import files and optional host
  analyzer files;
- internal certificate/key stores, browser certificates and any encryption
  material required by the selected images;
- container ownership/permissions and initialization order.

Document which state is initialized on a new installation and which must be
retained when restoring an existing installation. This is a target contract,
not a migration script or a promise that an old site's data is compatible.
Migration rehearsal, source backup, data conversion, restore, rollback and
cutover are user-owned and outside this delivery.

## Fresh-install acceptance

| Check | Pass evidence |
|---|---|
| Clean online startup | Exact candidate installs on a clean Ubuntu host using the documented commands; initialization jobs exit successfully and required services become ready. |
| No analyzer host files | Base configuration starts with no analyzer host directory or mount setting. |
| Optional analyzer files | Enabling the optional file exposes the same directory read-only in both services; missing or inaccessible sources fail clearly. |
| Credentials and browser access | Configured administrator login works and the published default is rejected; browser HTTPS works through the documented proxy configuration. |
| Fresh-target security | Private identity material is generated locally and persists across restart; independent clean installs have different keys. Required internal clients verify trust and hostnames or authenticate a deliberately pinned peer certificate. Tests reject unrelated certificates and, where hostname verification applies, wrong hostnames. Stored-field encryption uses a separate installation-specific secret. Selected images and release artifacts do not provide the private identity used by the target. |
| PNG catalog and basic workflow | Catalog loading completes; create a synthetic order, enter a result and view the resulting report. Catalog sign-off remains separate. |
| FHIR and Bridge | Internal FHIR communication works; a synthetic analyzer message follows the selected supported path into the expected result/review state. Record exactly which path was tested. |
| Restart persistence | Restart the stack and confirm synthetic records, relevant settings and Bridge state persist. |
| Reproducibility and handoff | Candidate revision/digests, commands, test results, known limitations and persistent-state inventory are retained without secrets or real patient data. |

Docker Desktop checks are useful for reproducing the reported `/mnt` issue.
They are not a requirement to support macOS as a PNG production platform or a
substitute for the Linux fresh-install test. Standby and offline combinations
are excluded from the acceptance matrix.

## Explicitly deferred

| Work | Why it is outside this PNG delivery |
|---|---|
| Offline image bundles, registries, import scripts and disconnected testing | Explicitly out of scope; this target installs online. |
| Broad certificate migration/lifecycle framework | Automatic replacement of every historical bundled-key variant, customer-certificate ownership detection, rotation automation and general lifecycle tooling remain upstream work. Generating and using private keys for this fresh PNG target stays in scope. |
| Existing-data re-encryption | Old-password detection, encrypted-column rewriting, migration counters and historical compatibility are outside the fresh-target work. A separate installation-specific encryption secret stays in scope; transferring existing encrypted data requires the matching old secret or an explicit conversion in the user-owned migration. |
| Broader identity architecture | Separate identities for every service, expanded mutual authentication and support for every external trust arrangement are deferred. Correct peer identity verification on the connections used by this PNG target stays in scope. |
| High availability | Standby promotion, failover, offsite replication and snapshot refresh are not target acceptance requirements. Existing optional files remain untouched; no new functionality or qualification is added. |
| New-site cloning and key regeneration | Cross-site identity handling and data transformation are separate lifecycle work. |
| Migration and recovery tooling | Automated source discovery, backup redesign, migration rehearsals, restore automation and cutover/rollback execution are user-owned for this move. |
| Broad analyzer expansion | New instrument protocols, host queries returning orders, every analyzer model and the entire upstream harness roadmap are outside the bounded synthetic delivery test. |
| Shared distro blueprint | Extracting a generic template, porting to other countries and publishing a universal lifecycle contract can follow a successful PNG target. |

## Implementation status

Implemented locally in the distro only:

- Optional analyzer host-file overlay and mount preflight.
- Private install-generated certificate/key stores, with Docker image seeding
  disabled and fail-closed handling of unknown or incomplete security volumes.
- Independent random encryption secret, retained across restart.
- Verified Bridge forwarding, corrected forwarding URL, production Bridge
  profile, proxy upstream verification and localhost-only management ports.
- Suppression of password-bearing Tomcat startup argument logs in both Java
  services, verified in the running fixture.
- Plain Compose startup prepares permissions, sets the administrator once and
  verifies it before starting the proxy. A retained initialization marker prevents
  password resets on ordinary restarts. Administrator checks fail on network errors.
- Both PostgreSQL privileged accounts use the configured site password on a fresh
  database. The published built-in PostgreSQL password is no longer retained.
- Immutable image pins and release publication that preserves the tested bytes.
- [Persistent state and security contract](target-state.md).

Focused tests have verified distinct keys for independent installations,
restart retention, custom store passwords, wrong-password and missing-secret
failure, hostname rejection and optional host-mount behavior. All 17 focused
tests passed on Ubuntu. Login, a synthetic clinical report, one analyzer delivery
and full restart persistence passed on the initial candidate. The subsequent
plain-Compose startup flow passed from empty Ubuntu state, including browser
login and repeated startup without resetting the administrator password.
No upstream repository has been changed for this implementation. No source
server has been inspected or modified.

The current [backup script](../scripts/backup.sh) captures the database and
configuration tree but does not capture named certificate/key volumes or the
shared import volume. It also forces the base Compose file rather than honoring
all selected overlays. Do not present it as a complete migration package; record
these limitations in the target handoff. No backup or migration has been run.

## Reported startup issue and baseline

The supplied log shows Docker denying a bind mount of `/mnt`, before Bridge
startup completed. At PNG main `1de65a3d963901892d6d18277ebe1e8f1016972b`,
the example environment selected `/mnt` and both services mounted it. The local
startup change removes that requirement from the base configuration.

The log also names `oe-init` and `autoheal-oe`, which are absent from the inspected
base file. It therefore does not establish the source server's exact setup.
Investigating that setup is not needed for the clean target and belongs to the
user's migration work. No live source settings, passwords or keys were inspected.

## Short dev-meeting brief

PNG is scoped to a lean online installation target: a fixed image set, the PNG
configuration, optional analyzer file mounts and a proven fresh-install path.
We will hand over the tested target and its persistent-state requirements; the
user will migrate the existing training server. Minimum fresh-install security
stays in scope: private install-generated keys, verified service connections and
a separate encryption secret. Offline packaging, universal certificate upgrades
and rotation, old-data re-encryption, standby/failover, migration automation and a
generic country blueprint are deferred. The baseline is implemented locally;
the remaining acceptance and deployment gates are recorded in the
[validation record](validation-2026-10-21.md).
