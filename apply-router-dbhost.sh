#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_root
load_m5_env

ENVF="${BACKEND_ENV_FILE}"
if [[ ! -f "${ENVF}" ]]; then
  echo "[ERROR] Backend env file not found: ${ENVF}"
  exit 1
fi

echo "[*] Updating backend DB settings in ${ENVF}..."
if rg -q "^DB_HOST=" "${ENVF}"; then
  sed -i "s/^DB_HOST=.*/DB_HOST=${MYSQL_NODE1_IP}/" "${ENVF}"
else
  echo "DB_HOST=${MYSQL_NODE1_IP}" >> "${ENVF}"
fi

if rg -q "^DB_PORT=" "${ENVF}"; then
  sed -i "s/^DB_PORT=.*/DB_PORT=${ROUTER_RW_PORT}/" "${ENVF}"
else
  echo "DB_PORT=${ROUTER_RW_PORT}" >> "${ENVF}"
fi

echo "[*] Restarting backend service (${BACKEND_SYSTEMD_UNIT})..."
systemctl restart "${BACKEND_SYSTEMD_UNIT}"

echo "[✓] Backend now points to Router RW endpoint."
echo "    DB_HOST=${MYSQL_NODE1_IP}"
echo "    DB_PORT=${ROUTER_RW_PORT}"
systemctl --no-pager status "${BACKEND_SYSTEMD_UNIT}" || true
