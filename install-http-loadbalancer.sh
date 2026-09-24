#!/usr/bin/env bash
# Install HAProxy in front of two Flask backends (final milestone — HTTP load balancing).
# Reads repo .env: BACKEND_HOST, BACKEND_HOST_2, BACKEND_PORT (default 5000).
# Listens on HAPROXY_FRONT_PORT (default 8080). Health check: GET /health
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
ROOT_ENV="${REPO_ROOT}/.env"

if [[ -f "${ROOT_ENV}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ROOT_ENV}"
  set +a
fi

BACKEND_PORT="${BACKEND_PORT:-5000}"
HAPROXY_FRONT_PORT="${HAPROXY_FRONT_PORT:-8080}"
HAPROXY_STATS_PORT="${HAPROXY_STATS_PORT:-8404}"

UP1="${BACKEND_HOST:-}"
UP2="${BACKEND_HOST_2:-${SECOND_BACKEND_HOST:-}}"

if [[ -z "${UP1}" || -z "${UP2}" ]]; then
  echo "[ERROR] Set BACKEND_HOST and BACKEND_HOST_2 (or SECOND_BACKEND_HOST) in ${ROOT_ENV}."
  echo "        Example: two ZeroTier IPs running the same Flask app on :${BACKEND_PORT}."
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[*] Re-running with sudo..."
  exec sudo env REPO_ROOT="$REPO_ROOT" bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y haproxy

CFG="/etc/haproxy/haproxy.cfg"
cp -a "${CFG}" "${CFG}.bak.$(date +%s)" 2>/dev/null || true

cat >"${CFG}" <<EOF
global
    log /dev/log local0
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend capstone_http
    bind *:${HAPROXY_FRONT_PORT}
    default_backend capstone_backends

backend capstone_backends
    balance roundrobin
    option httpchk GET /health
    http-check expect string healthy
    server be1 ${UP1}:${BACKEND_PORT} check inter 3s fall 3 rise 2
    server be2 ${UP2}:${BACKEND_PORT} check inter 3s fall 3 rise 2

listen stats
    bind *:${HAPROXY_STATS_PORT}
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
EOF

if haproxy -c -f "${CFG}"; then
  systemctl enable haproxy
  systemctl restart haproxy
  systemctl --no-pager --full status haproxy || true
else
  echo "[ERROR] haproxy config test failed."
  exit 1
fi

echo ""
echo "[✓] HAProxy front: http://THIS_HOST:${HAPROXY_FRONT_PORT}/  (proxies to /health on backends)"
echo "    Stats (bind all interfaces — restrict in production): http://THIS_HOST:${HAPROXY_STATS_PORT}/stats"
echo "    Upstreams: ${UP1}:${BACKEND_PORT} , ${UP2}:${BACKEND_PORT}"
