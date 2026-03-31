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
PUBLIC_HOST="${PUBLIC_HOST:-mtproxy.example.com}"
DEPLOY_SSH_PRIVATE_KEY_FILE="${DEPLOY_SSH_PRIVATE_KEY_FILE:-${HOME}/.ssh/mtproxy-actions}"
DEPLOY_SSH_PUBLIC_KEY_FILE="${DEPLOY_SSH_PUBLIC_KEY_FILE:-${DEPLOY_SSH_PRIVATE_KEY_FILE}.pub}"
ADMIN_SSH_PUBLIC_KEY_FILE="${ADMIN_SSH_PUBLIC_KEY_FILE:-$(first_existing_admin_key || true)}"
SERVER_NAME="${SERVER_NAME:-mtg-$(date -u +%Y%m%d%H%M%S)}"

[[ -f "$ADMIN_SSH_PUBLIC_KEY_FILE" ]] || die "Missing admin SSH public key: $ADMIN_SSH_PUBLIC_KEY_FILE"
[[ -f "$DEPLOY_SSH_PUBLIC_KEY_FILE" ]] || die "Missing deploy SSH public key: $DEPLOY_SSH_PUBLIC_KEY_FILE"

provision_output="$(
  ADMIN_SSH_PUBLIC_KEY_FILE="$ADMIN_SSH_PUBLIC_KEY_FILE" \
  DEPLOY_SSH_PUBLIC_KEY_FILE="$DEPLOY_SSH_PUBLIC_KEY_FILE" \
  PUBLIC_HOST="$PUBLIC_HOST" \
  SERVER_NAME="$SERVER_NAME" \
  "${SCRIPT_DIR}/provision-hetzner.sh"
)"

printf '%s\n' "$provision_output"

server_ip="$(printf '%s\n' "$provision_output" | awk -F': ' '/^Public IPv4:/ {print $2}')"
host_fingerprint="$(printf '%s\n' "$provision_output" | awk -F': ' '/^   Captured SSH host fingerprint:/ {print $2}')"
repo="$(repo_slug)"

[[ -n "$server_ip" ]] || die "Failed to parse Public IPv4 from provisioning output"
[[ -n "$host_fingerprint" ]] || die "Failed to capture a new SSH host fingerprint for ${server_ip}. Refusing to rotate without SSH verification."
[[ "$host_fingerprint" != "<run ssh-keyscan later if you want to verify manually>" ]] || die "Hetzner provisioning did not return a usable SSH fingerprint for ${server_ip}. Refusing to rotate until the new host is reachable over SSH."

gh variable set PROD_PUBLIC_HOST --repo "$repo" --body "$PUBLIC_HOST"
gh variable set PROD_DEPLOY_USER --repo "$repo" --body "$DEPLOY_USER"
gh secret set PROD_DEPLOY_SSH_PRIVATE_KEY --repo "$repo" < "$DEPLOY_SSH_PRIVATE_KEY_FILE"
gh secret set PROD_DEPLOY_SSH_PUBLIC_KEY --repo "$repo" < "$DEPLOY_SSH_PUBLIC_KEY_FILE"

cat <<EOF

GitHub deploy target rotated to ${SERVER_NAME} (${server_ip}).

Next steps:
1. Trigger the Provision Production workflow when you want GitHub Actions to take over future zero-touch rotations
2. Repoint DNS when you are satisfied:
   DNS_RECORD_CONTENT=${server_ip} ${SCRIPT_DIR}/upsert-cloudflare-dns.sh
3. Trigger the Deploy Production workflow in GitHub Actions
4. Remove the old Hetzner host only after the new one is working
EOF
