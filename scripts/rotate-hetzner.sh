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

repo_slug() {
  git remote get-url origin \
    | sed -E 's#(git@github.com:|https://github.com/)##' \
    | sed -E 's#\.git$##'
}

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_SSH_PRIVATE_KEY_FILE="${DEPLOY_SSH_PRIVATE_KEY_FILE:-${HOME}/.ssh/mtproxy-actions}"
DEPLOY_SSH_PUBLIC_KEY_FILE="${DEPLOY_SSH_PUBLIC_KEY_FILE:-${DEPLOY_SSH_PRIVATE_KEY_FILE}.pub}"
ADMIN_SSH_PUBLIC_KEY_FILE="${ADMIN_SSH_PUBLIC_KEY_FILE:-$(first_existing_admin_key || true)}"
SERVER_NAME="${SERVER_NAME:-mtg-$(date -u +%Y%m%d%H%M%S)}"

[[ -f "$ADMIN_SSH_PUBLIC_KEY_FILE" ]] || die "Missing admin SSH public key: $ADMIN_SSH_PUBLIC_KEY_FILE"
[[ -f "$DEPLOY_SSH_PUBLIC_KEY_FILE" ]] || die "Missing deploy SSH public key: $DEPLOY_SSH_PUBLIC_KEY_FILE"

provision_output="$(
  ADMIN_SSH_PUBLIC_KEY_FILE="$ADMIN_SSH_PUBLIC_KEY_FILE" \
  DEPLOY_SSH_PUBLIC_KEY_FILE="$DEPLOY_SSH_PUBLIC_KEY_FILE" \
  SERVER_NAME="$SERVER_NAME" \
  "${SCRIPT_DIR}/provision-hetzner.sh"
)"

printf '%s\n' "$provision_output"

server_ip="$(printf '%s\n' "$provision_output" | awk -F': ' '/^Public IPv4:/ {print $2}')"
host_fingerprint="$(printf '%s\n' "$provision_output" | awk -F'=' '/PROD_HOST_FINGERPRINT=/ {print $2}')"
repo="$(repo_slug)"

[[ -n "$server_ip" ]] || die "Failed to parse Public IPv4 from provisioning output"

gh secret set PROD_HOST --repo "$repo" --body "$server_ip"
gh secret set PROD_USER --repo "$repo" --body "$DEPLOY_USER"
gh secret set PROD_PORT --repo "$repo" --body "22"
gh secret set PROD_SSH_KEY --repo "$repo" < "$DEPLOY_SSH_PRIVATE_KEY_FILE"

if [[ -n "$host_fingerprint" && "$host_fingerprint" != "<run ssh-keyscan later and add the ed25519 SHA256 fingerprint>" ]]; then
  gh secret set PROD_HOST_FINGERPRINT --repo "$repo" --body "$host_fingerprint"
fi

cat <<EOF

GitHub deploy target rotated to ${SERVER_NAME} (${server_ip}).

Next steps:
1. Copy / create /opt/mtproxy/mtg.toml on ${server_ip}
2. Validate direct-IP access with:
   PUBLIC_IPV4=${server_ip} ${SCRIPT_DIR}/print-access-links.sh /opt/mtproxy/mtg.toml
3. Repoint DNS when you are satisfied:
   DNS_RECORD_CONTENT=${server_ip} ${SCRIPT_DIR}/upsert-cloudflare-dns.sh
4. Trigger the Deploy Production workflow in GitHub Actions
5. Remove the old Hetzner host only after the new one is working
EOF
