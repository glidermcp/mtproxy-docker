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

Provisioning prerequisites:

1. `hcloud`
2. `gh`
3. `ssh-keyscan`
4. `ssh-keygen`

Bootstrap a deploy key once:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/mtproxy-actions -C gh-mtproxy-actions -N ""
```

Authenticate Hetzner:

```bash
hcloud context create mtproxy
hcloud context use mtproxy
```

Initial setup:

```bash
DEPLOY_SSH_PUBLIC_KEY_FILE=~/.ssh/mtproxy-actions.pub scripts/setup-all.sh
```

That script provisions the host and updates GitHub deploy secrets. After it
finishes:

1. SSH to the server.
2. Edit `/opt/mtproxy/mtg.toml`.
3. Validate direct-IP access with `PUBLIC_IPV4=<server-ip> scripts/print-access-links.sh`.
4. Update DNS if you want a stable hostname.
5. Trigger the Deploy Production workflow.

## Rotation / Ban Recovery

The intended recovery path is a fresh Hetzner host with a fresh IPv4.

Use:

```bash
scripts/rotate-hetzner.sh
```

What it does:

1. Creates a new Hetzner server with a unique default name.
2. Updates `PROD_HOST`, `PROD_PORT`, `PROD_USER`, and `PROD_HOST_FINGERPRINT`.
3. Leaves DNS cutover as a separate explicit step so you can validate first.

Recommended recovery order:

1. Provision the new host.
2. Create or copy `/opt/mtproxy/mtg.toml`.
3. Validate direct-IP Telegram access.
4. Repoint DNS if you want to keep a stable hostname.
5. Deploy to the new host via GitHub Actions.
6. Remove the old Hetzner host only after the new one works.

## Cloudflare Notes

Cloudflare is used for DNS only.

1. Keep the MTG hostname in DNS-only mode.
2. Do not put an HTTP proxy, Tunnel, or orange-cloud record in front of the
   Telegram TCP endpoint.
3. `scripts/upsert-cloudflare-dns.sh` is still the helper for A-record updates.

## GitHub Actions Deployment

Required repository secrets:

1. `PROD_HOST`
2. `PROD_USER`
3. `PROD_PORT`
4. `PROD_SSH_KEY`
5. `PROD_HOST_FINGERPRINT`

Remote host expectations:

1. Docker is installed.
2. `/opt/mtproxy/mtg.toml` already exists.
3. The remote user can run `docker compose`.
4. `/opt/mtproxy/.env` is managed by the deploy workflow and stores
   `MTG_IMAGE=...`.

## Censorship Resistance

The runtime migration is complete, but there is still operator work around
front-domain choice and fast host replacement. See
[docs/censorship-resistance.md](./docs/censorship-resistance.md).
