#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_root
load_m5_env

LOCAL_IP="$(detect_local_ip)"
if [[ "${LOCAL_IP}" != "${GR_BOOTSTRAP_NODE}" ]]; then
  echo "[ERROR] This host (${LOCAL_IP}) is not GR_BOOTSTRAP_NODE (${GR_BOOTSTRAP_NODE})."
  echo "        Run this script on node1/bootstrap node."
  exit 1
fi

mysql_make_writable

echo "[*] Creating app DB/user + GR recovery user..."
mysql_root_exec "
CREATE DATABASE IF NOT EXISTS \`${MYSQL_APP_DB}\`;
CREATE USER IF NOT EXISTS '${MYSQL_APP_USER}'@'%' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_APP_DB}\`.* TO '${MYSQL_APP_USER}'@'%';

CREATE USER IF NOT EXISTS '${GR_RECOVERY_USER}'@'%' IDENTIFIED BY '${GR_RECOVERY_PASSWORD}';
GRANT REPLICATION SLAVE, CONNECTION_ADMIN, BACKUP_ADMIN, CLONE_ADMIN ON *.* TO '${GR_RECOVERY_USER}'@'%';
FLUSH PRIVILEGES;
"

echo "[*] Configuring GR recovery channel credentials..."
mysql_root_exec "
CHANGE REPLICATION SOURCE TO SOURCE_USER='${GR_RECOVERY_USER}', SOURCE_PASSWORD='${GR_RECOVERY_PASSWORD}' FOR CHANNEL 'group_replication_recovery';
"

echo "[*] Bootstrapping Group Replication on primary..."
mysql_root_exec "SET GLOBAL group_replication_bootstrap_group=ON;"
mysql_root_exec "START GROUP_REPLICATION;"
mysql_root_exec "SET GLOBAL group_replication_bootstrap_group=OFF;"

echo "[✓] Primary bootstrapped. Current GR members:"
mysql_root_exec "SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;"
