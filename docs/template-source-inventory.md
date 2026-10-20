# Template Source Inventory

Maintainer note. This distro is a source reference for extracting a clean
`openelis-distro-template` repository. The template repository should be created
fresh with `git init`; files from this repo should be copied deliberately after
classification, not by preserving this repo's git history.

## Generic Template Core

These files are broadly reusable after replacing country-specific defaults in
the new template repo only:

- `docker-compose.yml`
- `compose.letsencrypt.yaml`
- `.github/workflows/pr.yml`
- `.github/workflows/release.yml`
- `scripts/build-release-notes.sh`
- `scripts/build-tarball.sh`
- `scripts/check-release-pins.sh`
- `scripts/fix-config-permissions.sh`
- `scripts/generate-letsencrypt-certs.sh`
- `scripts/pin-versions.sh`
- `configs/configuration/backend/observation-history-types/environmental-observation-types.csv`
- `configs/configuration/backend/nce-categories/nce-categories.csv`
- `configs/configuration/backend/nce-types/nce-types.csv`
- `configs/configuration/backend/questionnaires/generic-sample-logbook-questionnaire.json`

Vendor analyzer types come with the Analyzer Bridge image. A distribution
lists only its own under `configs/analyzer-catalog`, which replaces them; a
template ships that folder empty with its README and
`scripts/sign-analyzer-profile.py`.

## Country Payload

These files are country production configuration and should stay in generated
country repos, not in the base template.

The catalog CSVs below carry the `png-` prefix because this is the Papua New
Guinea distro. The address hierarchy, phone validation and the CPHL test
catalog (pending CPHL review; see "Loading the PNG test catalog" in the
README) are PNG-specific.

- `configs/configuration/backend/address-hierarchy/png-levels.csv`
- `configs/configuration/backend/address-hierarchy/png-values.csv`
- `configs/configuration/backend/dictionaries/png-dictionary-entries.csv`
- `configs/configuration/backend/eqa-programs/png-eqa-programs.csv`
- `configs/configuration/backend/locales/png-locales.csv`
- `configs/configuration/backend/panels/png-panels.csv`
- `configs/configuration/backend/roles/png-lab-roles.csv`
- `configs/configuration/backend/sample-types/png-sample-types.csv`
- `configs/configuration/backend/site-information/png-site-information.csv`
- `configs/configuration/backend/test-results/png-test-results.csv`
- `configs/configuration/backend/test-sections/png-test-sections.csv`
- `configs/configuration/backend/tests/png-tests.csv`
- `configs/analyzer-catalog/` (the PNG analyzer types)
- `configs/menu/menu_config.json`
- `configs/odoo/odoo-test-product-mapping.csv`

## Runtime And Local Artifacts

Generated runtime state must not be copied into the template or committed back
to this country repo:

- `.env`
- `.env.letsencrypt`
- `.env.local`
- `.env.*.local`
- `compose.yaml`
- `compose.override.yaml`
- `compose.override.yml`
- `docker-compose.override.yml`
- `configs/database/data*/`
- `configs/logs/`
- `configs/letsencrypt/live/`
- `configs/letsencrypt/archive/`
- `configs/letsencrypt/renewal/`
- `configs/letsencrypt/accounts/`
- `configs/properties/TotalSystemConfiguration.properties`
- `configs/properties/ChangedSystemConfiguration.properties`
- any checksum or checksums properties files

The base template should ship `.env.example`, `.gitignore`, and empty placeholder
directories only where needed for Docker Compose path resolution.
