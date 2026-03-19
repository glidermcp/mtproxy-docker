#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

cf_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -fsSL \
      -X "$method" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4${path}" \
      --data "$data"
    return 0
  fi

  curl -fsSL \
    -X "$method" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4${path}"
}

json_get() {
  local expr="$1"

  python3 -c '
import json
import sys

expr = sys.argv[1]
data = json.load(sys.stdin)

parts = [part for part in expr.split(".") if part]
value = data

for part in parts:
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part)
        if value is None:
            break

if value is None:
    sys.exit(1)

if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
' "$expr"
}

load_local_env

require_command curl
require_command python3
require_env CLOUDFLARE_API_TOKEN
require_env CLOUDFLARE_ZONE_ID
require_env DNS_RECORD_CONTENT

DNS_RECORD_NAME="${DNS_RECORD_NAME:-life.wearbrands.vip}"
DNS_RECORD_TYPE="${DNS_RECORD_TYPE:-A}"
DNS_RECORD_TTL="${DNS_RECORD_TTL:-1}"
DNS_RECORD_PROXIED="${DNS_RECORD_PROXIED:-false}"

existing_response="$(
  cf_api GET \
    "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=${DNS_RECORD_TYPE}&name=${DNS_RECORD_NAME}"
)"

record_count="$(printf '%s' "$existing_response" | json_get "result_info.count" || printf '0\n')"

payload="$(cat <<EOF
{"type":"${DNS_RECORD_TYPE}","name":"${DNS_RECORD_NAME}","content":"${DNS_RECORD_CONTENT}","ttl":${DNS_RECORD_TTL},"proxied":${DNS_RECORD_PROXIED}}
EOF
)"

if [[ "$record_count" != "0" ]]; then
  record_id="$(printf '%s' "$existing_response" | json_get "result.0.id")"
  cf_api PUT "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}" "$payload" >/dev/null
  echo "Updated Cloudflare DNS record ${DNS_RECORD_NAME} -> ${DNS_RECORD_CONTENT}"
else
  cf_api POST "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" "$payload" >/dev/null
  echo "Created Cloudflare DNS record ${DNS_RECORD_NAME} -> ${DNS_RECORD_CONTENT}"
fi
