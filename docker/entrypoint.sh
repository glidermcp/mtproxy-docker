#!/usr/bin/env bash

set -euo pipefail

. /env.sh
declare -i PROXY_STARTUP_TIMEOUT_SECONDS=30
declare -a NAT_INFO_ARGS=()

die() {
  echo "$1" >&2
  exit 1
}

. /secrets.sh

require_public_host() {
  if [[ -z "$MTPROXY_PUBLIC_HOST" ]]; then
    die "MTPROXY_PUBLIC_HOST is required"
  fi
}

detect_nat_private_ip() {
  local detected_ips

  detected_ips="$(hostname -i 2>/dev/null || true)"
  printf '%s\n' "${detected_ips%% *}"
}

configure_nat_info() {
  local private_ip

  if [[ -z "$MTPROXY_NAT_PUBLIC_IP" ]]; then
    return 0
  fi

  private_ip="$(detect_nat_private_ip)"

  NAT_INFO_ARGS=(
    --nat-info "$private_ip":"$MTPROXY_NAT_PUBLIC_IP"
  )

  echo "Using MTProxy NAT info: ${private_ip} -> ${MTPROXY_NAT_PUBLIC_IP}."
}

telegram_files_present() {
  [[ -s "$PROXY_SECRET_FILE" && -s "$PROXY_CONFIG_FILE" ]]
}

ensure_telegram_files() {
  mkdir -p "$DATA_DIR"

  if telegram_files_present; then
    return 0
  fi

  if [[ "$MTPROXY_AUTO_UPDATE_TELEGRAM_FILES" == "1" ]]; then
    if /tg-config-updater.sh || telegram_files_present; then
      return 0
    fi

    die "Failed to download Telegram proxy files and no local copies exist."
  fi

  die "Missing required ${PROXY_SECRET_FILE} or ${PROXY_CONFIG_FILE}."
}

start_proxy() {
  local args=(
    -p "$MTPROXY_STATS_PORT"
    -H "$MTPROXY_PORT"
    --aes-pwd "$PROXY_SECRET_FILE" "$PROXY_CONFIG_FILE"
    -M "$MTPROXY_WORKERS"
    -u nobody
  )
  local secret

  for secret in "${CLIENT_SECRETS[@]}"; do
    args+=( -S "$secret" )
  done

  if [[ -n "${MTPROXY_TAG:-}" ]]; then
    args+=( -P "$MTPROXY_TAG" )
  fi

  if [[ "${#NAT_INFO_ARGS[@]}" -gt 0 ]]; then
    args+=( "${NAT_INFO_ARGS[@]}" )
  fi

  /mtproto-proxy "${args[@]}" &
  proxy_pid="$!"
}

# Probe a listening TCP socket by opening /dev/tcp/host/port
# and then closing it.
proxy_port_open() {
  if { exec 3<>"/dev/tcp/127.0.0.1/${MTPROXY_PORT}"; } 2>/dev/null; then
    exec 3<&-
    exec 3>&-
    return 0
  fi

  return 1
}

wait_for_proxy() {
  for ((attempt = 1; attempt <= PROXY_STARTUP_TIMEOUT_SECONDS; attempt++)); do
    if ! kill -0 "$proxy_pid" 2>/dev/null; then
      wait "$proxy_pid"
      exit $?
    fi

    if proxy_port_open; then
      echo "MTProxy is reachable on ${MTPROXY_PORT}."
      print_proxy_links
      return 0
    fi

    sleep 1
  done

  echo "MTProxy did not open port ${MTPROXY_PORT}" \
       " within ${PROXY_STARTUP_TIMEOUT_SECONDS}s." >&2
  return 1
}

require_public_host
configure_nat_info
ensure_telegram_files

load_client_secrets
require_client_secrets
start_proxy
wait_for_proxy

wait "$proxy_pid"
