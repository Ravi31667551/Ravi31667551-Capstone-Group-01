#!/usr/bin/env bash
set -euo pipefail

M5_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M5_ENV="${M5_DIR}/cluster.env"

load_m5_env() {
  local env_file=""
  if [[ -f "${M5_ENV}" ]]; then
    env_file="${M5_ENV}"
  else
    echo "[ERROR] Missing env file (repo root):" >&2
    echo "        ${M5_ENV}" >&2
    echo "        Copy cluster.env.example to cluster.env and fill values." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a; source "${env_file}"; set +a
}

mysql_root_exec() {
  local sql="$1"
  MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -uroot -e "${sql}"
}

mysql_make_writable() {
  mysql_root_exec "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" || true
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] Run with sudo/root." >&2
    exit 1
  fi
}

detect_local_ip() {
  local ip
  for ip in $(hostname -I); do
    if [[ "${ip}" == "${GR_BOOTSTRAP_NODE:-}" ]] \
      || [[ "${ip}" == "${MYSQL_NODE1_IP:-}" ]] \
      || [[ "${ip}" == "${MYSQL_NODE2_IP:-}" ]] \
      || [[ "${ip}" == "${MYSQL_NODE3_IP:-}" ]]; then
      echo "${ip}"
      return 0
    fi
  done

  # Fallback: first non-loopback address if no configured node IP matched.
  for ip in $(hostname -I); do
    if [[ "${ip}" != "127.0.0.1" ]]; then
      echo "${ip}"
      return 0
    fi
  done

  return 1
}
