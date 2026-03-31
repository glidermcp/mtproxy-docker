#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

CLOUD_INIT_TEMPLATE="${ROOT_DIR}/deploy/cloud-init.yaml"

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

wait_for_ssh_fingerprint() {
  local host="$1"
  local attempt
  local fingerprint

  for attempt in {1..30}; do
    fingerprint="$(
      ssh-keyscan -t ed25519 "$host" 2>/dev/null \
        | ssh-keygen -lf - 2>/dev/null \
        | awk '{print $2}' \
        | head -n 1
    )"

    if [[ -n "$fingerprint" ]]; then
      printf '%s\n' "$fingerprint"
      return 0
    fi

    sleep 2
  done

  return 1
}

load_local_env

require_command hcloud
require_command ssh-keyscan
require_command ssh-keygen
require_command python3

SERVER_NAME="${SERVER_NAME:-mtg-prod}"
SERVER_TYPE="${SERVER_TYPE:-cx23}"
SERVER_LOCATION="${SERVER_LOCATION:-hel1}"
SERVER_IMAGE="${SERVER_IMAGE:-ubuntu-24.04}"
PUBLIC_HOST="${PUBLIC_HOST:-mtproxy.example.com}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
ADMIN_SSH_PUBLIC_KEY_FILE="${ADMIN_SSH_PUBLIC_KEY_FILE:-$(first_existing_admin_key || true)}"
DEPLOY_SSH_PUBLIC_KEY_FILE="${DEPLOY_SSH_PUBLIC_KEY_FILE:-${HOME}/.ssh/mtproxy-actions.pub}"

[[ -f "$CLOUD_INIT_TEMPLATE" ]] || die "Missing cloud-init template: $CLOUD_INIT_TEMPLATE"
[[ -f "$DEPLOY_SSH_PUBLIC_KEY_FILE" ]] || die "Missing deploy SSH public key: $DEPLOY_SSH_PUBLIC_KEY_FILE"

hcloud context list >/dev/null 2>&1 || die "Hetzner CLI is not authenticated. Run 'hcloud context create mtproxy' first."

tmp_user_data="$(mktemp)"
tmp_authorized_keys="$(mktemp)"
trap 'rm -f "$tmp_user_data" "$tmp_authorized_keys"' EXIT

if [[ -f "$ADMIN_SSH_PUBLIC_KEY_FILE" ]]; then
  cat "$ADMIN_SSH_PUBLIC_KEY_FILE" >> "$tmp_authorized_keys"
fi
cat "$DEPLOY_SSH_PUBLIC_KEY_FILE" >> "$tmp_authorized_keys"
awk '!seen[$0]++' "$tmp_authorized_keys" > "${tmp_authorized_keys}.dedup"
mv "${tmp_authorized_keys}.dedup" "$tmp_authorized_keys"

AUTHORIZED_KEYS_FILE="$tmp_authorized_keys" \
DEPLOY_USER="$DEPLOY_USER" \
"${SCRIPT_DIR}/render-cloud-init.sh" "$CLOUD_INIT_TEMPLATE" > "$tmp_user_data"

if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  echo "Hetzner server ${SERVER_NAME} already exists, skipping creation."
else
  echo "Creating Hetzner server ${SERVER_NAME} (${SERVER_TYPE}, ${SERVER_IMAGE}, ${SERVER_LOCATION})"
  hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --location "$SERVER_LOCATION" \
    --image "$SERVER_IMAGE" \
    --user-data-from-file "$tmp_user_data"
fi

server_ip="$(hcloud server ip "$SERVER_NAME")"
[[ -n "$server_ip" ]] || die "Failed to resolve IPv4 for ${SERVER_NAME}"

fingerprint="$(wait_for_ssh_fingerprint "$server_ip" || true)"

cat <<EOF
Hetzner server ready.

Server name: ${SERVER_NAME}
Server type: ${SERVER_TYPE}
Server location: ${SERVER_LOCATION}
Public IPv4: ${server_ip}
Public hostname: ${PUBLIC_HOST}
Deploy user: ${DEPLOY_USER}

Next steps:
1. Run scripts/upsert-cloudflare-dns.sh with DNS_RECORD_CONTENT=${server_ip}
2. Store your deploy key and production config in GitHub Actions:
   PROD_DEPLOY_SSH_PRIVATE_KEY=<private deploy key contents>
   PROD_DEPLOY_SSH_PUBLIC_KEY=<public deploy key contents>
   PROD_MTG_SECRET=<mtg FakeTLS secret>
3. Set GitHub Actions variables:
   PROD_PUBLIC_HOST=${PUBLIC_HOST}
   PROD_DEPLOY_USER=${DEPLOY_USER}
EOF

if [[ -n "$fingerprint" ]]; then
  cat <<EOF
   Captured SSH host fingerprint: ${fingerprint}
EOF
else
  cat <<'EOF'
   Captured SSH host fingerprint: <run ssh-keyscan later if you want to verify manually>
EOF
fi

cat <<'EOF'
4. Trigger the Deploy Production workflow after DNS points at the new host
EOF
