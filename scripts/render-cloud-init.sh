#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

TEMPLATE_FILE="${1:-${ROOT_DIR}/deploy/cloud-init.yaml}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
AUTHORIZED_KEYS_FILE="${AUTHORIZED_KEYS_FILE:-}"

[[ -f "$TEMPLATE_FILE" ]] || die "Missing cloud-init template: $TEMPLATE_FILE"
[[ -n "$AUTHORIZED_KEYS_FILE" ]] || die "AUTHORIZED_KEYS_FILE is required"
[[ -f "$AUTHORIZED_KEYS_FILE" ]] || die "Missing authorized keys file: $AUTHORIZED_KEYS_FILE"

python3 - "$TEMPLATE_FILE" "$DEPLOY_USER" "$AUTHORIZED_KEYS_FILE" <<'PY'
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
deploy_user = sys.argv[2]
keys_path = pathlib.Path(sys.argv[3])

template = template_path.read_text()
keys = [line.strip() for line in keys_path.read_text().splitlines() if line.strip()]

if not keys:
    raise SystemExit("AUTHORIZED_KEYS_FILE did not contain any SSH public keys")

keys_block = "\n      - ".join(keys)

rendered = template.replace("__DEPLOY_USER__", deploy_user)
rendered = rendered.replace("__DEPLOY_SSH_AUTHORIZED_KEYS__", keys_block)

sys.stdout.write(rendered)
PY
