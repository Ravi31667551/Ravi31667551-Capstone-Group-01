#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_root
load_m5_env

LOCAL_IP="$(detect_local_ip)"
ROUTER_INSTALL_NODE="${ROUTER_INSTALL_NODE:-${MYSQL_NODE1_IP}}"
if [[ "${LOCAL_IP}" != "${ROUTER_INSTALL_NODE}" ]]; then
  echo "[ERROR] Router placement chosen on ${ROUTER_INSTALL_NODE}, but local IP is ${LOCAL_IP}."
  exit 1
fi

echo "[*] Installing mysql-router package..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-router

ROUTER_DIR="/etc/mysqlrouter"
CONF="${ROUTER_DIR}/mysqlrouter.conf"
mkdir -p "${ROUTER_DIR}"

echo "[*] Writing static router config for Group Replication..."
cat >"${CONF}" <<EOF
[DEFAULT]
name = milestone5-gr-router
logging_folder = /var/log/mysqlrouter
runtime_folder = /var/run/mysqlrouter
data_folder = /var/lib/mysqlrouter

[logger]
level = INFO

[routing:rw]
bind_address = ${ROUTER_BIND_ADDRESS}
bind_port = ${ROUTER_RW_PORT}
destinations = ${MYSQL_NODE1_IP}:${MYSQL_PORT},${MYSQL_NODE2_IP}:${MYSQL_PORT},${MYSQL_NODE3_IP}:${MYSQL_PORT}
routing_strategy = first-available
mode = read-write
protocol = classic

[routing:ro]
bind_address = ${ROUTER_BIND_ADDRESS}
bind_port = ${ROUTER_RO_PORT}
destinations = ${MYSQL_NODE1_IP}:${MYSQL_PORT},${MYSQL_NODE2_IP}:${MYSQL_PORT},${MYSQL_NODE3_IP}:${MYSQL_PORT}
routing_strategy = round-robin
mode = read-only
protocol = classic
EOF

echo "[*] Enabling and restarting mysqlrouter..."
ROUTER_SERVICE=""
if systemctl list-unit-files --type=service | awk '{print $1}' | grep -qx "mysqlrouter.service"; then
  ROUTER_SERVICE="mysqlrouter.service"
elif systemctl list-unit-files --type=service | awk '{print $1}' | grep -qx "mysql-router.service"; then
  ROUTER_SERVICE="mysql-router.service"
fi

if [[ -n "${ROUTER_SERVICE}" ]]; then
  systemctl enable "${ROUTER_SERVICE}"
  systemctl restart "${ROUTER_SERVICE}"
else
  echo "[WARN] Could not find mysqlrouter systemd unit (mysqlrouter.service or mysql-router.service)."
  echo "       Verify package installation and service name on this distro."
fi

echo "[✓] mysqlrouter is configured."
echo "    RW endpoint: ${ROUTER_BIND_ADDRESS}:${ROUTER_RW_PORT}"
echo "    RO endpoint: ${ROUTER_BIND_ADDRESS}:${ROUTER_RO_PORT}"
if [[ -n "${ROUTER_SERVICE}" ]]; then
  systemctl --no-pager status "${ROUTER_SERVICE}" || true
fi
