# Let's Encrypt (public hostnames)

This distro serves the UI at `/` and the API at `/api/` through the `proxy` service.
For public hostnames, use HTTP-01 with the optional compose overlay and helper script.
The proxy config is hostname-agnostic; the certificate lineage and SAN list are driven by
compose env vars.

## Prerequisites

- DNS `A` (or equivalent) for each requested hostname → this host’s public IP.
- **TCP 80** reachable from the internet (Let’s Encrypt validation).
- Base stack already mounts `./configs/nginx/certbot` for the ACME webroot (`docker-compose.yml`).
- If you added the certbot mount after the proxy was first created, **recreate** the proxy so the mount appears inside the container:  
  `docker compose -f docker-compose.yml up -d --force-recreate proxy`  
  (Otherwise `/var/www/certbot` is missing in the container and validation returns 404 or redirects.)

## Bring-up

1. Start the stack (proxy must be running):

   ```bash
   docker compose -f docker-compose.yml up -d
   ```

2. **Quota-safe check** (recommended before real issuance):

   ```bash
   ./scripts/generate-letsencrypt-certs.sh --dry-run
   ```

   The script reads the `LETSENCRYPT_*` block from `.env` — the same place
   `.env.example` tells you to fill it in — so nothing needs exporting. A
   value already exported in your shell still wins, for ad-hoc overrides:

   ```bash
   LETSENCRYPT_EMAIL='you@example.com' ./scripts/generate-letsencrypt-certs.sh --dry-run
   ```

   `--dry-run` exercises ACME without consuming Let’s Encrypt **production** issuance quota.

3. Issue or update the real certificate:

   ```bash
   ./scripts/generate-letsencrypt-certs.sh
   ```

4. Recreate the proxy with the Let’s Encrypt overlay so nginx can read
   `/etc/letsencrypt/live/$LETSENCRYPT_CERT_NAME/` and symlink into the paths nginx uses
   (the lineage directory is selected by `LETSENCRYPT_CERT_NAME`, falling back to
   `LETSENCRYPT_PRIMARY_DOMAIN` then the legacy `LETSENCRYPT_DOMAIN`):

   ```bash
   docker compose -f docker-compose.yml -f compose.letsencrypt.yaml up -d --force-recreate proxy
   ```

   Set the variables below in `.env` before running the script; both the
   overlay and the script read them from there.

## Environment variables

All of these are read from `.env` (or the environment, which takes
precedence).

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `LETSENCRYPT_EMAIL` | Yes (for `certbot`) | — | ACME account / notices |
| `LETSENCRYPT_DOMAINS` | Yes | — | Comma- or space-separated SAN list |
| `LETSENCRYPT_PRIMARY_DOMAIN` | No | first entry in `LETSENCRYPT_DOMAINS` | Default cert lineage / primary hostname |
| `LETSENCRYPT_CERT_NAME` | No | `LETSENCRYPT_PRIMARY_DOMAIN` | Explicit lineage name under `configs/letsencrypt/live/` |
| `LETSENCRYPT_DOMAIN` | Legacy | — | Backward-compatible single-domain fallback |
| `LETSENCRYPT_STAGING` | No | `false` | First-time `certonly` only: use `--staging` (untrusted chain) |

There is no built-in hostname default. It used to fall back to another
project's test host, so an unconfigured run requested a certificate for
somebody else's site and spent this host's ACME
quota doing it. The script now stops with an error instead.

Example for two names on one certificate, in `.env`:

```dotenv
LETSENCRYPT_EMAIL=ops@health.gov.pg
LETSENCRYPT_DOMAINS=lab.health.gov.pg,lab-test.health.gov.pg
LETSENCRYPT_PRIMARY_DOMAIN=lab.health.gov.pg
LETSENCRYPT_CERT_NAME=lab.health.gov.pg
```

```bash
./scripts/generate-letsencrypt-certs.sh
```

## Renewal

When a certificate already exists under `configs/letsencrypt/live/<cert-name>/`, the script renews it
when the requested SAN list matches, or expands the lineage when the requested SAN list changes.
Use `./scripts/generate-letsencrypt-certs.sh --dry-run` to test renewal without production quota impact.

## Wildcard DNS

A DNS wildcard (e.g. `*.health.gov.pg`) does **not** replace a public certificate for
that name; wildcard issuance requires DNS-01 and is out of scope for this HTTP-01 flow.

## Verification checklist

After issuance and `docker compose ... --force-recreate proxy` with `compose.letsencrypt.yaml`:

```bash
curl -I "http://lab.health.gov.pg"
curl -I "http://lab-test.health.gov.pg"
curl -v "https://lab.health.gov.pg/"
curl -v "https://lab-test.health.gov.pg/"
curl -sSf -X POST \
  'https://lab.health.gov.pg/api/OpenELIS-Global/ValidateLogin?apiCall=true' \
  --data-urlencode 'loginName=admin' \
  --data-urlencode "password=${OE_ADMIN_PASSWORD}"
```

Use the site's own `OE_ADMIN_PASSWORD`, not `adminADMIN!` — on a correctly
deployed site `./scripts/set-admin-password.sh` has already made the default
invalid.

Expect HTTP→HTTPS redirect, a trusted certificate chain in the browser (no `-k`), and a successful login
response. On the same machine without public DNS, continue using `https://localhost/` with `-k`.
