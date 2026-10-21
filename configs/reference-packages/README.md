# AMR reference release pin

This directory holds the distribution's `amr.json` pin, not the reference data.
Normal `docker compose up -d` runs the existing initializer, which downloads the
versioned asset, verifies its SHA-256 and manifest, and atomically installs it
under `DATA_ROOT/webapp/reference-packages`. OpenELIS loads that directory through
its configuration loader. A valid cached archive needs no network on restart.

The release pin has four fields: `format` (`openelis-amr-reference/v1`), `version`,
`url` (the versioned DIGI-UW/AMR GitHub release asset), and `sha256` (the reviewed
archive checksum). The version and checksum must come from the published release;
never use `latest`, a branch URL, or a placeholder checksum.

**Current integration status:** no release pin is committed yet. The AMR reference
package and receiving OpenELIS application are still under review. Without
`amr.json`, initialization explicitly reports that AMR references are unconfigured.
Do not treat this as a configured AMR installation. Add the real pin together with
compatible application image digests after those artifacts are published.

A bad download or checksum fails initialization and prevents the dependent webapp
from starting. Previous verified archives remain on disk. New package versions
create inactive editions; import never substitutes for laboratory activation.
`OE_CONFIGURATION_AUTOCREATE=false` is honored: archives may be prepared, but
OpenELIS will not import them. Enable loading for the AMR acceptance environment.
Confirm application import success as well as container health.

To upgrade, review the new release and coverage, update the pin and compatible
image digests in the distribution, back up site data, and use normal startup.
Retain the previous archives and database backup. Do not edit an archive or reuse
a package version for changed content. No manual file copying or browser upload
is part of installation.
