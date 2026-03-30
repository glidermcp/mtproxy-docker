#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

require_command docker

CONFIG_FILE="${1:-./mtg.toml}"
MTG_IMAGE="${MTG_IMAGE:-ghcr.io/glidermcp/mtproxy-docker:latest}"
PUBLIC_HOST="${PUBLIC_HOST:-}"
PUBLIC_IPV4="${PUBLIC_IPV4:-}"

[[ -f "$CONFIG_FILE" ]] || die "Missing mtg config file: $CONFIG_FILE"

config_dir="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
config_name="$(basename "$CONFIG_FILE")"

access_output="$(
  docker run --rm \
    -v "${config_dir}/${config_name}:/config.toml:ro" \
    "$MTG_IMAGE" access --hex /config.toml
)"

secret="$(
  printf '%s\n' "$access_output" | awk -F'"' '/"hex":/ { print $4; exit }'
)"
bind_to="$(
  awk -F'"' '/^[[:space:]]*bind-to[[:space:]]*=/ { print $2; exit }' "$CONFIG_FILE"
)"
config_public_ipv4="$(
  awk -F'"' '/^[[:space:]]*public-ipv4[[:space:]]*=/ { print $2; exit }' "$CONFIG_FILE"
)"
port="${bind_to##*:}"

[[ -n "$secret" ]] || die "Failed to parse normalized secret from mtg access output"
[[ -n "$port" ]] || die "Failed to parse bind-to port from $CONFIG_FILE"

if [[ -z "$PUBLIC_IPV4" ]]; then
  PUBLIC_IPV4="$config_public_ipv4"
fi

if [[ -n "$PUBLIC_IPV4" ]]; then
  printf 'Direct IP link: https://t.me/proxy?server=%s&port=%s&secret=%s\n' \
    "$PUBLIC_IPV4" "$port" "$secret"
fi

if [[ -n "$PUBLIC_HOST" ]]; then
  printf 'Hostname link: https://t.me/proxy?server=%s&port=%s&secret=%s\n' \
    "$PUBLIC_HOST" "$port" "$secret"
fi

if [[ -z "$PUBLIC_IPV4" && -z "$PUBLIC_HOST" ]]; then
  printf 'Hex secret: %s\n' "$secret"
  echo "Set PUBLIC_IPV4 and/or PUBLIC_HOST to print ready-made Telegram links."
fi
