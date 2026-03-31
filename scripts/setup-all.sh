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

PUBLIC_HOST="${PUBLIC_HOST:-mtproxy.example.com}"
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
repo="$(repo_slug)"

[[ -n "$server_ip" ]] || die "Failed to parse Public IPv4 from provisioning output"

gh variable set PROD_PUBLIC_HOST --repo "$repo" --body "$PUBLIC_HOST"
gh variable set PROD_DEPLOY_USER --repo "$repo" --body "$DEPLOY_USER"
gh secret set PROD_DEPLOY_SSH_PRIVATE_KEY --repo "$repo" < "$DEPLOY_SSH_PRIVATE_KEY_FILE"
gh secret set PROD_DEPLOY_SSH_PUBLIC_KEY --repo "$repo" < "$DEPLOY_SSH_PUBLIC_KEY_FILE"

cat <<EOF

GitHub secrets updated for ${repo}.

Bootstrap completed for ${server_ip}.

Next steps:
1. Add the remaining GitHub Actions secrets:
   HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, PROD_MTG_SECRET, GHCR_PULL_USERNAME, GHCR_PULL_TOKEN
2. Set any optional GitHub Actions variables if you want non-default Hetzner sizing:
   PROD_SERVER_NAME_PREFIX, PROD_SERVER_TYPE, PROD_SERVER_LOCATION, PROD_SERVER_IMAGE
3. Trigger the Provision Production workflow for future zero-touch rotations
4. Trigger the Deploy Production workflow for idempotent redeploys to ${PUBLIC_HOST}
EOF
