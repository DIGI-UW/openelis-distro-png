# PNG candidate image provenance

The default Compose files retain exact Docker Hub digests. The readable
`develop` label cannot change the bytes selected by a digest.

| Component | Source evidence |
|---|---|
| OpenELIS backend, frontend, database, FHIR and proxy | Commit `4b28fb46801fd7e76db87085aab765613e8c40a4`; [build 40164194759](https://github.com/DIGI-UW/OpenELIS-Global-2/actions/runs/40164194759). Each Docker Hub digest exactly matches this build's `e2e-image-map` artifact. |
| Analyzer Bridge 3.5.0 | Released commit `82682a27be04ae387af1b349bc7d669f914d94cc`; [upstream release](https://github.com/DIGI-UW/openelis-analyzer-bridge/releases/tag/3.5.0). PNG profile checks execute classes extracted from the pinned image. |
| certgen and autoheal | Registry digests captured on 2026-10-25. certgen supplies tools only; its bundled stores are never mounted or copied. PNG generates private material under the installation's data directory. |

The complete references are in `docker-compose.yml` and
`docker-compose.analyzers.yml`. Release publication preserves these references.
No source checkout, local WAR or CI-cache image is required for the default target.

`compose.amr.yaml` remains a separate, older testing candidate. It predates the
merged analyzer changes and uses temporary CI-cache references. It is not part
of this provenance claim or a combined PNG release. AMR configuration and
reference-package pins remain preserved in the repository.
