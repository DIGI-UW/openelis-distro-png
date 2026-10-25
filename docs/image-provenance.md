# PNG candidate image provenance

The default Compose files select immutable digests. The application contains
AMR on top of the merged analyzer baseline; no separate AMR overlay is needed.
This is a testing candidate, not an upstream OpenELIS release.

| Component | Source evidence |
|---|---|
| OpenELIS backend and frontend | Combined AMR/analyzer commit `908d3ce33567fe8dd55f4d35ffa69502d6a502be`; [PR #4819](https://github.com/DIGI-UW/OpenELIS-Global-2/pull/4819); [build 40208167298](https://github.com/DIGI-UW/OpenELIS-Global-2/actions/runs/40208167298). The build's merge tree `3940362b8d4ee14800a437a8ba0c25926fd5cf48` exactly matches the pushed source tree. |
| Database, FHIR and proxy | Merged analyzer baseline `4b28fb46801fd7e76db87085aab765613e8c40a4`; [build 40164194759](https://github.com/DIGI-UW/OpenELIS-Global-2/actions/runs/40164194759). Their source directories are unchanged by the AMR stack. Each Docker Hub digest matches this build's image map. |
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

## Published candidate

The backend and frontend were copied to durable public packages without changing
their manifest digests, then pulled using an empty Docker credential directory:

- Backend: `ghcr.io/digi-uw/openelis-global-2:png-amr-908d3ce335@sha256:68a690ee056da168cd84780c86abe38a293aaa1ab513f43bbf30a9416522fdf7`
- Frontend: `ghcr.io/digi-uw/openelis-global-2-frontend:png-amr-908d3ce335@sha256:c5a0e1627aa64d22ffea2a23f9dea21a1cf8340682ee6de55186cd793fdef843`

All sixteen local CI jobs passed on the source revision above. All twelve PRs
in stack #4674 have the backend, frontend, end-to-end and submodule-pin checks
passing. These images remain a testing candidate until the upstream release.

## Reference package validation

Both metadata publishers are pinned to 2026.2. Their builds are reproducible,
and the receiving OpenELIS test passed all 1,581,576 source interpretation cases
(523,047 EUCAST and 1,058,529 CLSI). Producer tests passed for both; the
EUCAST-only clinical-context test is intentionally skipped for CLSI. The source
data revision is `5fc152ae947240b03dd1085fb4ff1bc0df3137a1`; the exporter is
`1379463d0feea33207f9422aa4aa88e5e29dac1f`. Publication revision `84f72a4` changes
only workflow time limits, leaving the exporter bytes unchanged.
