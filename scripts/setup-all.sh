#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

load_local_env

require_command gh
require_command git
require_command ssh-keygen
require_command ssh-keyscan

first_existing_admin_key() {
  local candidate

  for candidate in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

PUBLIC_HOST="${PUBLIC_HOST:-life.wearbrands.vip}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_SSH_PRIVATE_KEY_FILE="${DEPLOY_SSH_PRIVATE_KEY_FILE:-${HOME}/.ssh/mtproxy-actions}"
DEPLOY_SSH_PUBLIC_KEY_FILE="${DEPLOY_SSH_PUBLIC_KEY_FILE:-${DEPLOY_SSH_PRIVATE_KEY_FILE}.pub}"
ADMIN_SSH_PUBLIC_KEY_FILE="${ADMIN_SSH_PUBLIC_KEY_FILE:-$(first_existing_admin_key || true)}"

ensure_deploy_key() {
  if [[ -f "$DEPLOY_SSH_PRIVATE_KEY_FILE" && -f "$DEPLOY_SSH_PUBLIC_KEY_FILE" ]]; then
    return 0
  fi

  ssh-keygen -t ed25519 -f "$DEPLOY_SSH_PRIVATE_KEY_FILE" -C gh-mtproxy-actions -N "" >/dev/null
}

repo_slug() {
  git remote get-url origin \
    | sed -E 's#(git@github.com:|https://github.com/)##' \
    | sed -E 's#\.git$##'
}

ensure_deploy_key

[[ -f "$ADMIN_SSH_PUBLIC_KEY_FILE" ]] || die "Missing admin SSH public key: $ADMIN_SSH_PUBLIC_KEY_FILE"

provision_output="$(
  ADMIN_SSH_PUBLIC_KEY_FILE="$ADMIN_SSH_PUBLIC_KEY_FILE" \
  DEPLOY_SSH_PUBLIC_KEY_FILE="$DEPLOY_SSH_PUBLIC_KEY_FILE" \
  PUBLIC_HOST="$PUBLIC_HOST" \
  "${SCRIPT_DIR}/provision-hetzner.sh"
)"

printf '%s\n' "$provision_output"

server_ip="$(printf '%s\n' "$provision_output" | awk -F': ' '/^Public IPv4:/ {print $2}')"
host_fingerprint="$(printf '%s\n' "$provision_output" | awk -F'=' '/PROD_HOST_FINGERPRINT=/ {print $2}')"
repo="$(repo_slug)"

[[ -n "$server_ip" ]] || die "Failed to parse Public IPv4 from provisioning output"

DNS_RECORD_CONTENT="$server_ip" "${SCRIPT_DIR}/upsert-cloudflare-dns.sh"

gh secret set PROD_HOST --repo "$repo" --body "$server_ip"
gh secret set PROD_USER --repo "$repo" --body "$DEPLOY_USER"
gh secret set PROD_PORT --repo "$repo" --body "22"
gh secret set PROD_SSH_KEY --repo "$repo" < "$DEPLOY_SSH_PRIVATE_KEY_FILE"

if [[ -n "$host_fingerprint" && "$host_fingerprint" != "<run ssh-keyscan later and add the ed25519 SHA256 fingerprint>" ]]; then
  gh secret set PROD_HOST_FINGERPRINT --repo "$repo" --body "$host_fingerprint"
fi

cat <<EOF

GitHub secrets updated for ${repo}.

Remaining manual step:
1. SSH to ${server_ip} with your personal key
2. Edit /opt/mtproxy/mtproxy.env with the real MTProxy values
3. Trigger the Deploy Production workflow in GitHub Actions
EOF
