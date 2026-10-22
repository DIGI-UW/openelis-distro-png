# Pinned metadata packages

Metadata can be released independently of OpenELIS and selected by a deployment.
Place one JSON pin per package here. There are no active pins yet: the AMR
candidate has not yet passed publication validation. `compose.amr.yaml` pins
the receiving application candidate for local testing.

Each pin has exactly four string fields: `id`, `version`, `url` and `sha256`.
Use a GHCR URL `oci://ghcr.io/<owner>/<package>@sha256:<manifest digest>`
or an immutable HTTPS release URL, plus the ZIP SHA-256. No credentials belong
in a pin. GHCR packages must have exactly one `application/zip` layer; the
manifest digest, layer digest and ZIP checksum are all verified before installation.
Private packages use `CONFIGURATION_REGISTRY_USERNAME` and
`CONFIGURATION_REGISTRY_TOKEN` from the deployment environment, never the pin.
The token needs read access to the selected package. `id` and `version` must match the release manifest. The installer is
publisher-independent; multiple laboratory catalogs can use the same pattern.

## Release layout

The archive contains a root `manifest.json`:

```json
{
  "format": "openelis-configuration/v1",
  "packageId": "catalog-name",
  "packageVersion": "1.0",
  "files": {
    "configuration/backend/dictionaries/catalog.csv": {
      "sha256": "<SHA-256 of this file>",
      "bytes": 123
    }
  }
}
```

The illustration is a schema example, not a usable pin or valid release.
Every payload must appear in the manifest inventory with its real size/hash.
Configuration files use `configuration/backend/<domain>/<filename>`; existing
CSV, JSON, XML or properties domains can be supplied. Additional provenance,
coverage and attribution files belong under `evidence/`. A package cannot add a
new application domain by itself: select a compatible OE2 image containing its
handler. Archive paths, duplicate entries and symlinks are checked before writes.

## Normal startup and updates

`docker compose up -d` runs the existing initializer before application startup.
`prepare-configuration-packages.py` reads every pin, verifies a cached archive or
downloads it, then installs verified files into `configs/configuration/backend/`.
The application uses that existing mount and its normal configuration loader.
No archive parser, R runtime or package-specific import process runs in OE2.

Installed names are `pkg--<id>--<version>--<filename>` within their domain.
This prefix is reserved for downloaded packages and ignored by Git. Existing
site files are left in place. Conflicting or locally edited package files cause
an actionable failure rather than an overwrite. Source CSVs must reconcile
existing IDs and preserve local database choices through their domain handlers.

Unchanged startup reuses the checksum-verified cache without network access.
New versions retain older archives/files for history. Failed downloads leave
previous versions intact; a failed file installation removes files created by
that attempt. Preparation failure prevents a new application container starting.
This is a startup adapter, not a live update transaction for an already running
application. Review pin changes, recreate through normal deployment procedures,
and inspect the application's import report. HTTP health alone proves no import.

`OE_CONFIGURATION_AUTOCREATE=false` is respected and explicitly reported:
installing files does not mean records were imported. New AMR breakpoint editions
load inactive; activation is a separate laboratory decision. Keep old referenced
editions when upgrading. Removing a pin does not delete installed files or data.

The independent AMR exporter targets EUCAST and CLSI 2025/2026 in separate
packages. CLSI-derived packages must remain restricted. Each artifact reports
its supported and blocked interpretation contexts.
Application image pins, a published package pin and actual local distro workflow
validation remain required before testing-server acceptance.
