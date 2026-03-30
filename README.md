# mtproxy-docker

Minimal Docker image for MTProxy with automatic builds.

## Why

1. The official Docker image for MTProxy is incredibly outdated. Telegram itself
   [advises against using it][tg-docker-outdated].

1. There are no other similar repos that wouldn't weird me out and also fit all
   of my requirements.

1. Convenience and ease of setup. Your grandma could do it. Unrestricted
   messaging for everyone.

1. No extra bullshit or questionable additions to MTProxy that weren't properly
   tested and verified.

## Quick start

This guide assumes that you're performing the steps on a Linux machine.

1. Install Docker:

    ```bash
    bash <(curl -sSL https://get.docker.com)
    ```

2. Create a working directory for `mtproxy-docker` and go there:

    ```bash
    mkdir mtproxy && cd mtproxy
    ```

3. Create a `compose.yml` file with `nano` (or any other editor):
    ```bash
    nano compose.yml
    ```

4. Copy and paste this config into `compose.yml`:
    ```yml
    services:
      mtproxy:
        image: ghcr.io/glidermcp/mtproxy-docker:latest
        container_name: mtproxy
        restart: unless-stopped
        ports:
          - "443:443/tcp"
        volumes:
          - ./data:/data
        environment:
          # REQUIRED: public hostname clients will use
          MTPROXY_PUBLIC_HOST: "mtproxy.example.com"
          # REQUIRED when using a hostname instead of a raw IPv4
          MTPROXY_NAT_PUBLIC_IP: "203.0.113.10"
          # RECOMMENDED: point at the mounted host secret file
          MTPROXY_SECRET_FILE: "/data/mtproxy-secret"
    ```

    Note: if you're using a hostname for `MTPROXY_PUBLIC_HOST` rather than
    an IPv4 address, you need to set `MTPROXY_NAT_PUBLIC_IP` with your
    server's IPv4 address.

    Additionally, set other [environment variables](#environment-variables).

5. Start the Docker container:
    ```bash
    docker compose up -d
    ```

6. Detached container doesn't print container logs, so get the proxy link from
   the container logs:
    ```bash
    docker compose logs mtproxy
    ```

7. Copy the proxy link. Enjoy unrestricted access to Telegram and share your
   proxy with a friend.

## Host On Hetzner

Hetzner Cloud is the practical default for public MTProxy hosting: you get a
normal VM with a public IPv4, standard Docker support, and no L4 proxy product
requirements in front of your traffic.

1. Create a small Hetzner Cloud VM with a public IPv4.
2. Open inbound TCP `22` and `443` in the Hetzner firewall.
3. Install Docker and Compose on the server.
4. Copy [deploy/compose.yml](./deploy/compose.yml) to `/opt/mtproxy/compose.yml`.
5. Copy [deploy/mtproxy.env.example](./deploy/mtproxy.env.example) to
   `/opt/mtproxy/mtproxy.env` and fill in your real values.
6. Start the service:
   ```bash
   cd /opt/mtproxy
   docker compose up -d
   ```

Recommended production profile for this repo:

1. Run MTProxy on Hetzner.
2. Point `mtproxy.example.com` to the Hetzner IPv4 with a DNS-only A record.
3. Keep client traffic on TCP `443`.
4. Use a raw 32-hex server secret and let the printed client link add the
   `dd` padding prefix.
5. If you want sponsorship, configure your public channel or group in `@MTProxybot`
   and paste the returned tag into `MTPROXY_SPONSORED_TAG`.

If you use a hostname in `MTPROXY_PUBLIC_HOST`, set `MTPROXY_NAT_PUBLIC_IP`
too.

### Automated Local Provisioning

This repo now includes local helper scripts for the one-time infrastructure
setup:

1. [scripts/provision-hetzner.sh](./scripts/provision-hetzner.sh) creates the
   Hetzner server with cloud-init bootstrap, Docker, `/opt/mtproxy`, and a
   dedicated `deploy` user.
2. [scripts/upsert-cloudflare-dns.sh](./scripts/upsert-cloudflare-dns.sh)
   creates or updates the DNS-only Cloudflare record for
   your chosen hostname.

Provisioning prerequisites on your machine:

1. `hcloud`
2. `curl`
3. `python3`
4. Your personal SSH public key for manual admin access
5. A separate deploy SSH keypair for GitHub Actions

You can keep local infrastructure credentials in a repo-ignored
[.env.local.example](./.env.local.example) style file named `.env.local`.
The helper scripts automatically load it.

Recommended deploy key generation:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/mtproxy-actions -C gh-mtproxy-actions -N ""
```

Recommended one-time provisioning flow:

1. Create a Hetzner Cloud API token and store it locally with:
   ```bash
   hcloud context create mtproxy
   hcloud context use mtproxy
   ```
2. Create a Cloudflare API token with DNS edit permission for your zone, such
   as `example.com`, and export `CLOUDFLARE_API_TOKEN`.
3. Export your Cloudflare zone id as `CLOUDFLARE_ZONE_ID`.
4. Run the Hetzner provisioning script:
   ```bash
   ADMIN_SSH_PUBLIC_KEY_FILE=~/.ssh/id_rsa.pub \
   DEPLOY_SSH_PUBLIC_KEY_FILE=~/.ssh/mtproxy-actions.pub \
   ./scripts/provision-hetzner.sh
   ```
5. Run the Cloudflare DNS script with the IPv4 printed by the Hetzner script:
   ```bash
   CLOUDFLARE_API_TOKEN=... \
   CLOUDFLARE_ZONE_ID=... \
   DNS_RECORD_CONTENT=203.0.113.10 \
   ./scripts/upsert-cloudflare-dns.sh
   ```
6. SSH to the server with your personal key and replace the placeholder values
   in `/opt/mtproxy/mtproxy.env`.
7. Create `/opt/mtproxy/data/mtproxy-secret` with one raw 32-hex secret per line
   so the secret stays out of container env metadata:
   ```bash
   install -d -m 0755 /opt/mtproxy/data
   printf '%s\n' '0123456789abcdef0123456789abcdef' > /opt/mtproxy/data/mtproxy-secret
   chmod 600 /opt/mtproxy/data/mtproxy-secret
   ```

New servers are hardened during bootstrap:

1. your personal admin key and the GitHub deploy key are both installed on
   `deploy`
2. SSH logins are restricted to `deploy`
3. password auth is disabled
4. direct root SSH is disabled

If you want the shortest path, put your Cloudflare values in `.env.local` and
run:

```bash
./scripts/setup-all.sh
```

That script:

1. Generates the GitHub Actions deploy key if it does not exist yet
2. Provisions the Hetzner server
3. Creates or updates the Cloudflare DNS record
4. Writes the required GitHub Actions secrets via `gh secret set`

If your admin key is `~/.ssh/id_ed25519.pub`, point `ADMIN_SSH_PUBLIC_KEY_FILE`
there instead. `scripts/setup-all.sh` will auto-detect `id_ed25519.pub` first
and then fall back to `id_rsa.pub`.

## Cloudflare Notes

Cloudflare is supported only for DNS in this setup.

1. Set your MTProxy hostname, such as `mtproxy.example.com`, to DNS-only. Do
   not orange-cloud this record.
2. Cloudflare Containers are not a fit for MTProxy because they do not expose a
   direct public MTProto TCP endpoint that Telegram clients can use.
3. Cloudflare Tunnel public hostnames are not a fit for normal Telegram
   clients.
4. Cloudflare Spectrum supports arbitrary TCP, but that is an Enterprise-tier
   product.

For this repo, use Hetzner for the actual proxy host and Cloudflare only in
DNS-only mode.

## GitHub Actions Deploy

This repo already builds and publishes the image to GHCR. It now also supports
manual production deploys over SSH.

Required GitHub Actions secrets:

1. `PROD_HOST`
2. `PROD_USER`
3. `PROD_SSH_KEY`
4. `PROD_PORT` (optional, defaults to `22`)
5. `PROD_HOST_FINGERPRINT`

Recommended values:

1. `PROD_USER=deploy`
2. `PROD_PORT=22`
3. `PROD_SSH_KEY` should contain the private contents of the dedicated
   `~/.ssh/mtproxy-actions` key
4. `PROD_HOST_FINGERPRINT` should be the server's ed25519 SHA256 fingerprint

Remote host expectations:

1. Docker and Docker Compose are installed.
2. `/opt/mtproxy/mtproxy.env` already exists.
3. The remote user can run `docker compose`.
4. `/opt/mtproxy/.env` is managed by the deploy workflow to persist the selected
   `MTPROXY_IMAGE` tag across later `docker compose up -d` runs.
5. Your chosen MTProxy hostname already resolves to the Hetzner host in
   DNS-only mode.
6. SSH is key-only and restricted to `deploy`.

SSH hardening policy:

1. `PermitRootLogin no`
2. `PasswordAuthentication no`
3. `KbdInteractiveAuthentication no`
4. `PubkeyAuthentication yes`
5. `AllowUsers deploy`

If you ever lock yourself out, use the Hetzner web console as the break-glass
recovery path.

To deploy, run the `Deploy Production` workflow and set `image_tag` if you want
something other than `latest`.

The workflow writes the resolved `ghcr.io/...` image tag into
`/opt/mtproxy/.env`, so the host stays pinned to that image until a later
deploy updates it.

The provisioning script prints the values you should copy into the GitHub
secrets after server creation.

## Environment variables

#### `MTPROXY_PUBLIC_HOST` (required)
Public IP or hostname Telegram clients use to connect.

#### `MTPROXY_SECRET` (fallback only)
One or more MTProxy server secrets, separated by commas.

This works, but it exposes the secret in container env metadata. Prefer
`MTPROXY_SECRET_FILE` for production.

If none are set, one client secret is generated automatically and stored in
`/data/mtproxy-secret`.

Each secret must be 32 hex digits. The repo also accepts `dd` + 32 hex digits
as input for compatibility, but it strips the `dd` prefix before starting the
server because upstream `mtproto-proxy` expects raw 32-hex secrets.

For a public deployment on a hostname such as `mtproxy.example.com`, padded
client links are the
recommended default and are printed automatically.

You can generate a plain secret manually:

```bash
head -c 16 /dev/urandom | xxd -ps
```

### Optional variables

#### `MTPROXY_PORT` (default `443`)
MTProxy client port inside the container. It must match the container-side port
in your Compose `ports:` entries.

#### `MTPROXY_STATS_PORT` (default `8888`)
Local MTProxy stats port.

#### `MTPROXY_WORKERS` (default `1`)
Number of worker processes.

#### `MTPROXY_PADDED_LINKS` (default `1`)
When set to `1`, printed Telegram proxy links use `dd<secret>` for random
padding support.

The server still uses the raw 32-hex secret internally.

#### `MTPROXY_SPONSORED_TAG`
Proxy tag from `@MTProxybot` for sponsored placement (`-P` argument).

There is no separate upstream "sponsored channel" server setting. MTProxy uses
the bot-issued proxy tag.

If you want sponsored placement, configure your public channel or group in
`@MTProxybot` first, then copy the returned proxy tag into
`MTPROXY_SPONSORED_TAG`.

#### `MTPROXY_AUTO_UPDATE_TELEGRAM_FILES` (default `1`)
Download `/data/telegram-proxy-secret` and `/data/telegram-proxy-config` at
container startup. Set to `0` to manage these files manually.

#### `MTPROXY_SECRET_FILE` (default `/data/mtproxy-secret`)
Persistent path for generated/provided client secret data. The file may contain
one secret or multiple secrets separated by commas, spaces, or newlines.

This is the recommended production path because the secret stays in a mounted
host file instead of appearing in the container environment.

Note: `MTPROXY_SECRET` takes precedence over `MTPROXY_SECRET_FILE` if both are
defined.

#### `MTPROXY_NAT_PUBLIC_IP`
Public IPv4 address to pass to `mtproto-proxy --nat-info`.

Used when the container runs behind Docker bridge/NAT instead of
`network_mode: host`.

Defaults to `MTPROXY_PUBLIC_HOST`. If `MTPROXY_PUBLIC_HOST` is a hostname
rather than an IPv4 address, you have to set `MTPROXY_NAT_PUBLIC_IP` or disable
NAT info.

#### `MTPROXY_NAT_DISABLE` (default `0`)
Disable passing `--nat-info` to `mtproto-proxy`. May be useful if you prefer
using `network_mode: host`.

## Follow-Up Research

This repo keeps the official MTProxy runtime for now. If you want stronger
censorship resistance than the official server can offer, see
[docs/censorship-resistance.md](./docs/censorship-resistance.md) for the
follow-up evaluation track.

<!-- Links -->
[tg-docker-outdated]: https://github.com/TelegramMessenger/MTProxy#:~:text=the%20image%20is%20outdated
