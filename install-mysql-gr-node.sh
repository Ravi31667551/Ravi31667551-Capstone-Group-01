#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_root
load_m5_env

echo "[*] Installing MySQL server (if missing)..."
if ! command -v mysql >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
fi

echo "[*] Enabling and starting mysql service..."
systemctl enable mysql
systemctl restart mysql

echo "[*] Configuring root password..."
if mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_ROOT_CLIENT=(mysql -uroot -p"${MYSQL_ROOT_PASSWORD}")
elif mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_ROOT_CLIENT=(mysql -uroot)
elif mysql --protocol=socket -uroot -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_ROOT_CLIENT=(mysql --protocol=socket -uroot)
else
  echo "[ERROR] Unable to connect as root without password to initialize credentials." >&2
  echo "        Try: sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '...';\"" >&2
  exit 1
fi

"${MYSQL_ROOT_CLIENT[@]}" -e "SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" || true

"${MYSQL_ROOT_CLIENT[@]}" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

LOCAL_IP="$(detect_local_ip)"
CONF="/etc/mysql/mysql.conf.d/99-group-replication.cnf"

echo "[*] Writing ${CONF}..."
cat >"${CONF}" <<EOF
[mysqld]
bind-address = 0.0.0.0
port = ${MYSQL_PORT}
mysqlx_port = ${MYSQL_X_PORT}

server_id = $(echo "${LOCAL_IP}" | awk -F. '{print ($1*16777216)+($2*65536)+($3*256)+$4}')
report_host = ${LOCAL_IP}
report_port = ${MYSQL_PORT}

gtid_mode = ON
enforce_gtid_consistency = ON
log_bin = mysql-bin
log_replica_updates = ON
binlog_format = ROW
master_info_repository = TABLE
relay_log_info_repository = TABLE
relay_log_recovery = ON
skip_replica_start = ON
binlog_checksum = NONE

plugin_load_add = group_replication.so
group_replication_group_name = "${GR_GROUP_NAME}"
group_replication_start_on_boot = OFF
group_replication_local_address = "${LOCAL_IP}:${GR_LOCAL_ADDRESS_PORT}"
group_replication_group_seeds = "${GR_SEEDS}"
group_replication_bootstrap_group = OFF
group_replication_ip_allowlist = "${GR_IP_ALLOWLIST}"
group_replication_single_primary_mode = ${GR_SINGLE_PRIMARY_MODE}
group_replication_enforce_update_everywhere_checks = OFF
EOF

echo "[*] Restarting MySQL with GR config..."
systemctl restart mysql

echo "[*] Installing clone plugin used by GR distributed recovery..."
mysql_make_writable
mysql_root_exec "INSTALL PLUGIN clone SONAME 'mysql_clone.so';" || true

echo "[✓] Node prepared for Group Replication."
echo "    Next: run bootstrap-gr-primary.sh on node1, join-gr-node.sh on others."
