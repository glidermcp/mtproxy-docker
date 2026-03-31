#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

MTG_SECRET="${MTG_SECRET:-${PROD_MTG_SECRET:-}}"
PUBLIC_IPV4="${PUBLIC_IPV4:-}"
MTG_BIND_TO="${MTG_BIND_TO:-0.0.0.0:443}"
MTG_PREFER_IP="${MTG_PREFER_IP:-prefer-ipv4}"
MTG_CONCURRENCY="${MTG_CONCURRENCY:-8192}"

[[ -n "$MTG_SECRET" ]] || die "MTG_SECRET is required"

cat <<EOF
secret = "${MTG_SECRET}"
bind-to = "${MTG_BIND_TO}"
prefer-ip = "${MTG_PREFER_IP}"
concurrency = ${MTG_CONCURRENCY}
EOF

if [[ -n "$PUBLIC_IPV4" ]]; then
  printf 'public-ipv4 = "%s"\n' "$PUBLIC_IPV4"
fi
