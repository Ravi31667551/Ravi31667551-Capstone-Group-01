#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_root
load_m5_env

LOCAL_IP="$(detect_local_ip)"
if [[ "${LOCAL_IP}" == "${GR_BOOTSTRAP_NODE}" ]]; then
  echo "[ERROR] This is bootstrap node (${LOCAL_IP}). Use bootstrap-gr-primary.sh here."
  exit 1
fi

echo "[*] Setting GR recovery credentials on ${LOCAL_IP}..."
mysql_root_exec "
CHANGE REPLICATION SOURCE TO SOURCE_USER='${GR_RECOVERY_USER}', SOURCE_PASSWORD='${GR_RECOVERY_PASSWORD}' FOR CHANNEL 'group_replication_recovery';
"

echo "[*] Starting Group Replication join..."
mysql_root_exec "START GROUP_REPLICATION;"

echo "[✓] Join attempted. Current status:"
mysql_root_exec "SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;"
