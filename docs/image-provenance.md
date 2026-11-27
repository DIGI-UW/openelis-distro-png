# PNG candidate image provenance

The default Compose files select immutable digests. The OpenELIS images are
upstream `develop` builds, not a tagged OpenELIS release.

| Component | Source evidence |
|---|---|
| OpenELIS backend, frontend, database and FHIR | `develop` commit `49e419777d7bc41b21fd6967cef44cad44fc52a2`; [publish run 45161913559](https://github.com/DIGI-UW/OpenELIS-Global-2/actions/runs/45161913559), which runs only after that commit's E2E checkpoint passes. Each digest matches the run's `published-image-*` artifacts. |
| Proxy | nginx with the merged analyzer baseline's configuration, `4b28fb46801fd7e76db87085aab765613e8c40a4`; [build 40164194759](https://github.com/DIGI-UW/OpenELIS-Global-2/actions/runs/40164194759). The proxy source is unchanged on `develop` since then. |
| Analyzer Bridge 3.5.0 | Released commit `82682a27be04ae387af1b349bc7d669f914d94cc`; [upstream release](https://github.com/DIGI-UW/openelis-analyzer-bridge/releases/tag/3.5.0). PNG profile checks execute classes extracted from the pinned image. |
| certgen and autoheal | Registry digests captured on 2026-10-25. certgen supplies tools only; its bundled stores are never mounted or copied. PNG generates private material under the installation's data directory. |

The complete references are in `docker-compose.yml` and
`docker-compose.analyzers.yml`. Release publication preserves these references.
`check-release-pins.sh` rejects floating references and temporary CI-cache images.
No source checkout or local WAR is required for installation.

The AMR reference package versions and digests remain in
`configs/configuration-packages`. Installing metadata does not activate a
standards edition or establish clinical acceptance. Lab-approved mappings and
physical-instrument acceptance remain separate from synthetic software tests.

## Published images

Each Docker Hub tag `sha-49e419777d7bc41b21fd6967cef44cad44fc52a2-45161913559` resolves to the pinned digest:

- Backend: `itechuw/openelis-global-2@sha256:20fbf2ea897c5530314be5cd0eeaf5feb4e42cc04591133eb6779d9a84e14209`
- Frontend: `itechuw/openelis-global-2-frontend@sha256:efc143443013300833ab5b986fc7691778966f0351627144aa4bd0048cdcd528`
- Database: `itechuw/openelis-global-2-database@sha256:c965f6e975057460a97b436b6efec48ff30542bfa0a1d8a07de045cbf840e59c`
- FHIR: `itechuw/openelis-global-2-fhir@sha256:d702b80cf8dfb48097f77cbd7f855604da86b0f496b29f204f1732c4939cf2bf`

## Reference package validation

Both metadata publishers are pinned to 2026.2. Their builds are reproducible,
and the receiving OpenELIS test passed all 1,581,576 source interpretation cases
(523,047 EUCAST and 1,058,529 CLSI). Producer tests passed for both; the
EUCAST-only clinical-context test is intentionally skipped for CLSI. The source
data revision is `5fc152ae947240b03dd1085fb4ff1bc0df3137a1`; the exporter is
`1379463d0feea33207f9422aa4aa88e5e29dac1f`. Publication revision `84f72a4` changes
only workflow time limits, leaving the exporter bytes unchanged.
