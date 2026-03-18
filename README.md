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
          # REQUIRED: your server's public IP/host
          MTPROXY_PUBLIC_HOST: "133.7.69.67"
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

If you want a domain name, point a DNS-only A record at the Hetzner IPv4. If
you use a hostname in `MTPROXY_PUBLIC_HOST`, set `MTPROXY_NAT_PUBLIC_IP` too.

## Cloudflare Notes

Cloudflare is fine for DNS, but not as the default traffic path for this
project:

1. Normal Cloudflare orange-cloud proxying is HTTP/HTTPS-oriented, not a
   general MTProxy TCP passthrough.
2. Cloudflare Tunnel public hostnames are not a fit for normal Telegram
   clients.
3. Cloudflare Spectrum supports arbitrary TCP, but that is an Enterprise-tier
   product.

For most deployments, use Hetzner for the actual proxy host and optionally use
Cloudflare in DNS-only mode.

## GitHub Actions Deploy

This repo already builds and publishes the image to GHCR. It now also supports
manual production deploys over SSH.

Required GitHub Actions secrets:

1. `PROD_HOST`
2. `PROD_USER`
3. `PROD_SSH_KEY`
4. `PROD_PORT` (optional, defaults to `22`)

Remote host expectations:

1. Docker and Docker Compose are installed.
2. `/opt/mtproxy/mtproxy.env` already exists.
3. The remote user can run `docker compose`.

To deploy, run the `Deploy Production` workflow and set `image_tag` if you want
something other than `latest`.

## Environment variables

#### `MTPROXY_PUBLIC_HOST` (required)
Public IP or hostname Telegram clients use to connect.

#### `MTPROXY_SECRET` (recommended)
One or more client secrets, separated by commas.

If none are set, one client secret is generated automatically and stored in
`/data/mtproxy-secret`.

If you want clients to use random padding, prefix the secret(s) with `dd`.

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

#### `MTPROXY_SPONSORED_TAG`
Proxy tag from `@MTProxybot` for sponsored placement (`-P` argument).

There is no separate upstream "sponsored channel" server setting. MTProxy uses
the bot-issued proxy tag.

#### `MTPROXY_AUTO_UPDATE_TELEGRAM_FILES` (default `1`)
Download `/data/telegram-proxy-secret` and `/data/telegram-proxy-config` at
container startup. Set to `0` to manage these files manually.

#### `MTPROXY_SECRET_FILE` (default `/data/mtproxy-secret`)
Persistent path for generated/provided client secret data. The file may contain
one secret or multiple secrets separated by commas, spaces, or newlines.

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

<!-- Links -->
[tg-docker-outdated]: https://github.com/TelegramMessenger/MTProxy#:~:text=the%20image%20is%20outdated
