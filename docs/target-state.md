# PNG target state

This is the fresh online, single-host target. It does not migrate the training
server. Set site passwords in `.env`, then run `docker compose up -d`. Compose
prepares configuration permissions, generates keys and initializes the
administrator once. The proxy waits for successful live password verification.
No separate installer command is required.

## Security material

The `certs` initialization job uses the published certgen image as a tool image.
Every security volume disables Docker's automatic image-file copy. On an empty
installation the job creates a new private key, service certificate, encrypted
Java stores and a separate random stored-field encryption secret. Image-bundled
keys are not the target's identity. No generated private material belongs in
Git, release archives or test reports. The separate secret protects fields that
the application encrypts; it does not encrypt the whole database or its files.
PostgreSQL transport TLS is not enabled in this single-host target (`SHOW ssl`
returned `off`); its port is not published outside the Docker network.

The internal certificate covers `oe.openelis.org`, `fhir.openelis.org`,
`bridge.openelis.org`, `localhost` and `127.0.0.1`. The three Java services share
this installation's identity; separate identities for all services are deferred.
The proxy verifies its OpenELIS upstream against the generated public certificate.
Bridge forwarding disables the insecure TLS option and uses the installation
truststore. Pair the Bridge through OpenELIS before receiving results; the
published application also uses certificate fingerprints for paired peers.
Fingerprint verification and hostname verification are different mechanisms;
a deliberately pinned peer is authenticated by its exact certificate.

The public browser certificate is separate. Configure Let's Encrypt using the
existing overlay after initial startup. Changing that browser certificate does
not change internal trust or stored-field encryption. The internal certificate
expires after 825 days. Planned replacement is required before expiry; automatic
rotation is outside this delivery. The initializer fails if it has expired.

Store passwords remain configurable through `SSL_KEYSTORE_PASSWORD` and
`SSL_TRUSTSTORE_PASSWORD`. Configure them before installation and retain them;
editing them later does not re-encrypt the existing stores. If existing unknown
material, a partial initialization or a missing encryption secret is detected,
startup stops. It never silently replaces keys needed to read existing data.

## Persistent state contract

| State | Target location | Requirement |
|---|---|---|
| OpenELIS and local FHIR data | `DB_VOLUME_MOUNT`, default `configs/database/data` | Retain the complete database state; FHIR uses the same PostgreSQL database in this configuration. |
| Site configuration and credentials | `.env`, `configs/properties`, `configs/configuration`, analyzer configuration | Keep permissions and site choices; protect `.env`. Configuration checksums live with the catalog. |
| Internal identity and encryption secret | Compose volume `key_trust-store-volume` | Retain **with the database**. Includes `keystore`, `client_facing_keystore`, `truststore`, `internal.crt`, `encryption.key`, `png-initialized`. Do not regenerate during restore. |
| Browser key and certificates, internal proxy trust | `keys-vol`, `certs-vol`; `configs/letsencrypt` when enabled | Keep all three together. Let's Encrypt overlay can place symlinks in the named volumes. |
| Bridge state, pairings and pending results | `BRIDGE_STATE_HOST_DIR`, default `configs/bridge-state` | Retain consistently; SQLite may have active WAL files. Owner UID/GID 9257 by default. |
| Administrator initialization marker | Compose volume `installation-state` | Retain with the database. Prevents ordinary startup from resetting an initialized administrator; mismatched credentials fail verification. |
| Internal analyzer imports | Compose volume `analyzer-imports` | Retain any pending files. This remains present even without a host file mount. |
| Optional instrument files | `ANALYZER_HOST_MOUNT`, only with `compose.analyzer-files.yaml` | Same existing directory mounted read-only into both services; owner must allow required service access. |
| Search index | Compose volume `lucene_index-vol` | Retain or explicitly plan a supported rebuild. |
| Logs and plugins | `configs/logs`, `configs/plugins` | Retain according to operational needs; logs may contain sensitive clinical information. |

Compose prefixes volume names with its project name. Record the actual project
name and resolved mount locations. The initializer owns raw private keys as
root; the encryption secret is owned by UID 8443 with mode 0400. OpenELIS and
FHIR use that same UID and share the store volume; this is not isolation of the
secret from the FHIR service.
Java stores are mounted read-only into the three Java services and the
short-lived administrator verification job. Bridge state ownership is initialized before the Bridge starts.
The security/preparation job must succeed before the database starts. Java
services wait for their dependencies; administrator initialization waits for
application readiness, and the proxy waits for administrator verification. The
standard PostgreSQL `pgcrypto` extension is retained for password hashing. Both
PostgreSQL privileged accounts use the configured `ADMIN_PASSWORD` on a fresh
database; existing database passwords are not rotated by changing `.env`.

Old encrypted data requires its original encryption secret or an explicit
conversion. This target does not discover that secret or re-encrypt old data.
Changing from the old shared password to this target's random secret without
conversion can make those fields unreadable. Migration and rehearsal are owned
by the operator.

The existing backup script is **not a complete migration package**: it omits
named security/import volumes, forces the base Compose file, and copies live
Bridge SQLite files without coordinating a consistent snapshot. No source-server
backup, restore or cutover is performed by this work.

## Instrument addresses

A configured analyzer connection is the authority for allowed senders. Existing
logs can suggest addresses for operator review; a previous connection does not
automatically make a sender trusted. Incoming HTTP analyzer traffic is checked
against active connection addresses in the Bridge. TCP behavior must be checked
for the selected transport. Keep instrument listeners restricted to the lab
network; the distro does not create or discover site firewall rules.

The Bridge HTTPS listener is local-only by default. HTTP instruments can opt
into a lab-network interface with `BRIDGE_HTTPS_BIND_ADDRESS`; configure their
active connection addresses and firewall access as well. ASTM traffic on port
12000 is not encrypted by these service certificates and belongs on the protected
instrument network. Internal Bridge-to-OpenELIS traffic uses HTTPS.
