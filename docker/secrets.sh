#!/usr/bin/env bash

declare -a CLIENT_SECRETS=()

normalize_client_secret() {
  local secret
  secret="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  if [[ "$secret" =~ ^dd([0-9a-f]{32})$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$secret" =~ ^[0-9a-f]{32}$ ]]; then
    printf '%s\n' "$secret"
    return 0
  fi

  die "Invalid MTProxy secret '$1'. Expected 32 hex digits, optionally prefixed with dd for padded client links."
}

append_client_secrets_from_value() {
  local input="$1"
  local separator_expression="$2"
  local secret

  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    CLIENT_SECRETS+=( "$(normalize_client_secret "$secret")" )
  done < <(printf '%s\n' "$input" | tr "$separator_expression" '\n')
}

append_client_secrets_from_file() {
  local secret

  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    CLIENT_SECRETS+=( "$(normalize_client_secret "$secret")" )
  done < <(tr ',[:space:]' '\n' < "$MTPROXY_SECRET_FILE")
}

write_client_secrets_file() {
  printf '%s\n' "${CLIENT_SECRETS[@]}" > "$MTPROXY_SECRET_FILE"
  chmod 0600 "$MTPROXY_SECRET_FILE"
}

generate_client_secret() {
  head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

load_client_secrets() {
  mkdir -p "$(dirname "$MTPROXY_SECRET_FILE")"

  CLIENT_SECRETS=()

  if [[ -n "${MTPROXY_SECRET:-}" ]]; then
    append_client_secrets_from_value "$MTPROXY_SECRET" ','
    write_client_secrets_file
    return 0
  fi

  if [[ -s "$MTPROXY_SECRET_FILE" ]]; then
    append_client_secrets_from_file
    if [[ "${#CLIENT_SECRETS[@]}" -gt 0 ]]; then
      return 0
    fi
  fi

  CLIENT_SECRETS=( "$(generate_client_secret)" )
  write_client_secrets_file
  echo "Generated and saved MTProxy client secret to $MTPROXY_SECRET_FILE."
}

require_client_secrets() {
  if [[ "${#CLIENT_SECRETS[@]}" -eq 0 ]]; then
    die "No valid MTProxy client secrets were provided."
  fi
}

print_proxy_links() {
  local secret
  local link_secret

  for secret in "${CLIENT_SECRETS[@]}"; do
    link_secret="$secret"

    if [[ "$MTPROXY_PADDED_LINKS" == "1" ]]; then
      link_secret="dd${secret}"
    fi

    echo "Add in Telegram: https://t.me/proxy?server=${MTPROXY_PUBLIC_HOST}&port=${MTPROXY_PORT}&secret=${link_secret}"
  done
}
