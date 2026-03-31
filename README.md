# mtproxy-docker

Docker packaging and Hetzner deployment automation for [`mtg`](https://github.com/9seconds/mtg).

The repo name stays the same for continuity, but the runtime is now `mtg`, not
the official Telegram MTProxy server. The main reasons for the switch are
stronger FakeTLS behavior and a cleaner disposable-host recovery story when a
public IPv4 gets blocked.

## What This Repo Does

1. Builds and publishes a pinned `mtg` image to GHCR.
2. Ships a native `mtg.toml` example instead of env-driven MTProxy flags.
3. Provisions a plain Hetzner host with Docker and a locked-down deploy user.
4. Supports both direct-IP Telegram links and hostname-based links.
5. Treats IP rotation as a normal recovery action.

## Quick Start

1. Generate a FakeTLS secret for a front domain you want to use:

   ```bash
   scripts/generate-mtg-secret.sh storage.googleapis.com
   ```

   The helper emits an `ee...` hex secret so you can paste it directly into
   `mtg.toml`.

2. Copy the example config and replace the placeholder secret:

   ```bash
   cp deploy/mtg.toml.example ./mtg.toml
   ```

3. Create `compose.yml`:

   ```yaml
   services:
     mtg:
       image: ghcr.io/glidermcp/mtproxy-docker:latest
       container_name: mtg
       restart: unless-stopped
       ports:
         - "443:443/tcp"
       volumes:
         - ./mtg.toml:/config.toml:ro
   ```

4. Start the proxy:

   ```bash
   docker compose up -d
   ```

5. Print Telegram access links:

   ```bash
   PUBLIC_IPV4=203.0.113.10 scripts/print-access-links.sh ./mtg.toml
   PUBLIC_IPV4=203.0.113.10 PUBLIC_HOST=mtproxy.example.com \
     scripts/print-access-links.sh ./mtg.toml
   ```

If `public-ipv4` is already set in `mtg.toml`, you can omit `PUBLIC_IPV4`.

## Runtime Config

This repo now uses a native `mtg` config file. Start from
[deploy/mtg.toml.example](./deploy/mtg.toml.example).

Important fields:

1. `secret`
   Generate it with `scripts/generate-mtg-secret.sh <front-domain>`.
2. `bind-to`
   Usually `0.0.0.0:443`.
3. `prefer-ip`
   Defaults to `prefer-ipv4` in the example for simple Hetzner deployments.
4. `public-ipv4`
   Optional for the server, but recommended if you want local helper scripts to
   emit a direct-IP Telegram link without extra env vars.

Operational rules:

1. `mtg` only supports FakeTLS mode here.
2. Sponsored placement / adtag support is intentionally gone.
3. The front domain is an explicit operator choice and can change on future
   rotations.
4. Direct-IP links are the primary recovery path. Stable DNS is optional.

## Hetzner Deployment

This repo keeps the simple production layout under `/opt/mtproxy`:

1. `compose.yml`
2. `mtg.toml`
3. `.env` for the selected `MTG_IMAGE` tag

## GitHub Actions Zero-Touch Provisioning

The repo now supports a fully GitHub-managed production path for servers that
have not been prepared manually.

Required GitHub Actions secrets:

1. `HCLOUD_TOKEN`
2. `CLOUDFLARE_API_TOKEN`
3. `CLOUDFLARE_ZONE_ID`
4. `PROD_MTG_SECRET`
5. `PROD_DEPLOY_SSH_PRIVATE_KEY`
6. `PROD_DEPLOY_SSH_PUBLIC_KEY`
7. `GHCR_PULL_USERNAME`
8. `GHCR_PULL_TOKEN`

Required GitHub Actions variables:

1. `PROD_PUBLIC_HOST`
2. `PROD_DEPLOY_USER`
3. `PROD_SERVER_NAME_PREFIX`
4. `PROD_SERVER_TYPE`
5. `PROD_SERVER_LOCATION`
6. `PROD_SERVER_IMAGE`

Automation entry points:

1. `Build Docker Image` publishes the image tag to GHCR.
2. `Provision Production` creates a new Hetzner host, installs config, deploys
   the container, updates DNS, and can remove the old host.
3. `Deploy Production` redeploys the current production hostname without manual
   SSH prep and can optionally rotate the billed Primary IPv4 on the same
   Hetzner server.

How the zero-touch path works:

1. `Provision Production` creates a fresh Hetzner host with the GitHub-managed
   deploy key already installed through cloud-init.
2. The workflow renders `/opt/mtproxy/mtg.toml` from `PROD_MTG_SECRET`, pushes
   `compose.yml`, logs the host into GHCR, starts `mtg`, and only then updates
   Cloudflare DNS.
3. `Deploy Production` uses the current `PROD_PUBLIC_HOST`, fetches the live SSH
   host key at runtime, rewrites `mtg.toml` from secrets, and redeploys without
   any manual SSH bootstrap.
4. If `Deploy Production` is run with `rotate_public_ip=true`, the workflow
   keeps the same `PROD_MTG_SECRET`, powers the server off, swaps its billed
   Primary IPv4, powers the server back on, redeploys to the new IPv4, checks
   SSH plus TCP/443 reachability, updates DNS, and only then deletes the old
   Primary IPv4.

## Rotation / Ban Recovery

The intended recovery path is either a fresh Hetzner host with a fresh IPv4 or
an in-place Primary IPv4 rotation on the current server.

Preferred automated path:

1. Run `Provision Production` when you want a fresh host and fresh IP.
2. Run `Deploy Production` when you want to redeploy the current active host.
3. Run `Deploy Production` with `rotate_public_ip=true` when you want to keep
   the same server, preserve the current MTG secret, leave IPv6 untouched, and
   rotate only the billed Primary IPv4.

Legacy local path:

```bash
scripts/rotate-hetzner.sh
```

Recommended recovery order:

1. Choose either fresh-host provisioning or in-place Primary IPv4 rotation.
2. Validate direct-IP Telegram access.
3. Repoint DNS if you want to keep a stable hostname.
4. Remove the old Hetzner resource only after the new path works.

## Cloudflare Notes

Cloudflare is used for DNS only.

1. Keep the MTG hostname in DNS-only mode.
2. Do not put an HTTP proxy, Tunnel, or orange-cloud record in front of the
   Telegram TCP endpoint.
3. `scripts/upsert-cloudflare-dns.sh` is still the helper for A-record updates.

## GitHub Actions Deployment

Remote host expectations:

1. Docker is installed.
2. The deploy user from `PROD_DEPLOY_USER` is present and has the GitHub-managed
   public key in `authorized_keys`.
3. `/opt/mtproxy` exists and is writable by the deploy user.
4. `/opt/mtproxy/.env` is managed by the deploy workflow and stores
   `MTG_IMAGE=...`.

`Deploy Production` inputs:

1. `image_tag`
   GHCR image tag to deploy. Defaults to `latest`.
2. `rotate_public_ip`
   Defaults to `false`. When set to `true`, the workflow rotates the billed
   Hetzner Primary IPv4 on the current server, keeps `PROD_MTG_SECRET`
   unchanged, leaves IPv6 untouched, and updates DNS only after the new IPv4 is
   reachable.

## Censorship Resistance

The runtime migration is complete, but there is still operator work around
front-domain choice and fast host replacement. See
[docs/censorship-resistance.md](./docs/censorship-resistance.md).
