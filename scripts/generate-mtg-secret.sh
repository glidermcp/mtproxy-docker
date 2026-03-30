#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
. "${SCRIPT_DIR}/lib.sh"

require_command docker

FRONT_DOMAIN="${1:-${FRONT_DOMAIN:-}}"
MTG_IMAGE="${MTG_IMAGE:-ghcr.io/glidermcp/mtproxy-docker:latest}"

[[ -n "$FRONT_DOMAIN" ]] || die "Usage: $0 <front-domain>"

docker run --rm "$MTG_IMAGE" generate-secret --hex "$FRONT_DOMAIN"
