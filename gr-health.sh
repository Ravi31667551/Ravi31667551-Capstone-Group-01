#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

load_m5_env

echo "============================================================"
echo "  Group Replication Health ($(date))"
echo "============================================================"

echo "[*] Member state and role:"
mysql_root_exec "
SELECT
  MEMBER_HOST,
  MEMBER_PORT,
  MEMBER_STATE,
  MEMBER_ROLE
FROM performance_schema.replication_group_members
ORDER BY MEMBER_HOST;
"

echo
echo "[*] Primary count check:"
mysql_root_exec "
SELECT COUNT(*) AS primary_count
FROM performance_schema.replication_group_members
WHERE MEMBER_ROLE='PRIMARY';
"

echo
echo "[*] Group-wide settings:"
mysql_root_exec "
SHOW VARIABLES WHERE Variable_name IN (
  'group_replication_single_primary_mode',
  'group_replication_start_on_boot'
);
"
