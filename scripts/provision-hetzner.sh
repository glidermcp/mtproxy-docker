#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

CLOUD_INIT_TEMPLATE="${ROOT_DIR}/deploy/cloud-init.yaml"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

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

SERVER_NAME="${SERVER_NAME:-mtproxy-prod}"
SERVER_TYPE="${SERVER_TYPE:-cx23}"
SERVER_LOCATION="${SERVER_LOCATION:-hel1}"
SERVER_IMAGE="${SERVER_IMAGE:-ubuntu-24.04}"
PUBLIC_HOST="${PUBLIC_HOST:-life.wearbrands.vip}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
ADMIN_SSH_KEY_NAME="${ADMIN_SSH_KEY_NAME:-mtproxy-admin}"
ADMIN_SSH_PUBLIC_KEY_FILE="${ADMIN_SSH_PUBLIC_KEY_FILE:-$(first_existing_admin_key || true)}"
DEPLOY_SSH_PUBLIC_KEY_FILE="${DEPLOY_SSH_PUBLIC_KEY_FILE:-${HOME}/.ssh/mtproxy-actions.pub}"

[[ -f "$CLOUD_INIT_TEMPLATE" ]] || die "Missing cloud-init template: $CLOUD_INIT_TEMPLATE"
[[ -f "$ADMIN_SSH_PUBLIC_KEY_FILE" ]] || die "Missing admin SSH public key: $ADMIN_SSH_PUBLIC_KEY_FILE"
[[ -f "$DEPLOY_SSH_PUBLIC_KEY_FILE" ]] || die "Missing deploy SSH public key: $DEPLOY_SSH_PUBLIC_KEY_FILE"

hcloud context list >/dev/null 2>&1 || die "Hetzner CLI is not authenticated. Run 'hcloud context create mtproxy' first."

if ! hcloud ssh-key describe "$ADMIN_SSH_KEY_NAME" >/dev/null 2>&1; then
  echo "Creating Hetzner SSH key ${ADMIN_SSH_KEY_NAME} from ${ADMIN_SSH_PUBLIC_KEY_FILE}"
  hcloud ssh-key create \
    --name "$ADMIN_SSH_KEY_NAME" \
    --public-key-from-file "$ADMIN_SSH_PUBLIC_KEY_FILE" >/dev/null
fi

tmp_user_data="$(mktemp)"
trap 'rm -f "$tmp_user_data"' EXIT

admin_public_key="$(tr -d '\n' < "$ADMIN_SSH_PUBLIC_KEY_FILE")"
deploy_public_key="$(tr -d '\n' < "$DEPLOY_SSH_PUBLIC_KEY_FILE")"
escaped_user="$(escape_sed_replacement "$DEPLOY_USER")"
escaped_admin_key="$(escape_sed_replacement "$admin_public_key")"
escaped_key="$(escape_sed_replacement "$deploy_public_key")"

sed \
  -e "s/__DEPLOY_USER__/${escaped_user}/g" \
  -e "s/__ADMIN_SSH_PUBLIC_KEY__/${escaped_admin_key}/g" \
  -e "s/__DEPLOY_SSH_PUBLIC_KEY__/${escaped_key}/g" \
  "$CLOUD_INIT_TEMPLATE" > "$tmp_user_data"

if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  echo "Hetzner server ${SERVER_NAME} already exists, skipping creation."
else
  echo "Creating Hetzner server ${SERVER_NAME} (${SERVER_TYPE}, ${SERVER_IMAGE}, ${SERVER_LOCATION})"
  hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --location "$SERVER_LOCATION" \
    --image "$SERVER_IMAGE" \
    --ssh-key "$ADMIN_SSH_KEY_NAME" \
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
2. Edit /opt/mtproxy/mtproxy.env on the server and set real MTProxy values
3. Add GitHub Actions secrets:
   PROD_HOST=${server_ip}
   PROD_USER=${DEPLOY_USER}
   PROD_PORT=22
EOF

if [[ -n "$fingerprint" ]]; then
  cat <<EOF
   PROD_HOST_FINGERPRINT=${fingerprint}
EOF
else
  cat <<'EOF'
   PROD_HOST_FINGERPRINT=<run ssh-keyscan later and add the ed25519 SHA256 fingerprint>
EOF
fi

cat <<'EOF'
4. Paste the private contents of your deploy key into PROD_SSH_KEY
EOF
