#!/usr/bin/env bash
# Append team hostnames to /etc/hosts so RabbitMQ and SSH use short names.
# Run on EVERY machine that participates in clustering:
#   sudo bash milestone4/add-cluster-hosts.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/cluster.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[!] Copy cluster.env.example to cluster.env and edit IPs first."
  exit 1
fi
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

MARKER="# Capstone-Group-01 milestone4 cluster hosts"
if grep -qF "$MARKER" /etc/hosts 2>/dev/null; then
  echo "[!] Cluster hosts block already present in /etc/hosts. Remove it manually to re-add."
  exit 0
fi

{
  echo ""
  echo "$MARKER"
  echo "${RMQ_NODE1_IP}    ${RMQ_NODE1_HOST}"
  echo "${RMQ_NODE2_IP}    ${RMQ_NODE2_HOST}"
  if [[ -n "${RMQ_NODE3_IP:-}" ]]; then
    echo "${RMQ_NODE3_IP}    ${RMQ_NODE3_HOST}"
  fi
  echo "${MYSQL_PRIMARY_IP}    ${MYSQL_PRIMARY_HOST}"
  echo "${MYSQL_REPLICA_RISHU_IP}    mysql2-rishu"
  echo "${MYSQL_REPLICA_BHAVNA_IP}    mysql3-bhavna"
} >> /etc/hosts

echo "[✓] Added cluster hostnames to /etc/hosts. Verify: getent hosts ${RMQ_CLUSTER_SEED}"
