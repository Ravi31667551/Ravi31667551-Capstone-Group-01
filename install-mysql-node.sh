#!/usr/bin/env bash
# Configure this machine as MySQL PRIMARY or REPLICA.
# Usage:
#   PRIMARY (Ravi):    sudo bash install-mysql-node.sh primary
#   REPLICA (Rishu):   sudo bash install-mysql-node.sh replica 2
#   REPLICA (Bhavna):  sudo bash install-mysql-node.sh replica 3
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/cluster.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[!] Copy cluster.env.example to cluster.env first."
  exit 1
fi
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

ROLE="${1:-}"
SID="${2:-}"

if [[ "$ROLE" != "primary" && "$ROLE" != "replica" ]]; then
  echo "Usage: sudo $0 primary | replica <server-id>"
  exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
  echo "[*] Installing mysql-server..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
fi

CONF="/etc/mysql/mysql.conf.d/99-capstone-cluster.cnf"
if [[ "$ROLE" == "primary" ]]; then
  cat >"$CONF" <<EOF
[mysqld]
server-id = 1
bind-address = 0.0.0.0
log_bin = /var/log/mysql/mysql-bin.log
binlog_do_db = ${MYSQL_DB_NAME}
EOF
  echo "[✓] Wrote $CONF (primary). Restarting MySQL..."
  systemctl restart mysql
  echo ""
  echo "=== Run on PRIMARY as MySQL root (create replicator + show position) ==="
  echo "sudo mysql <<'SQL'"
  echo "CREATE USER '${MYSQL_REPLICATOR_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_REPLICATOR_PASSWORD}';"
  echo "GRANT REPLICATION SLAVE ON *.* TO '${MYSQL_REPLICATOR_USER}'@'%';"
  echo "FLUSH PRIVILEGES;"
  echo "SHOW MASTER STATUS\\G"
  echo "SQL"
  echo ""
  echo "Update MYSQL_MASTER_LOG_FILE and MYSQL_MASTER_LOG_POS in cluster.env, then run replicas."
elif [[ "$ROLE" == "replica" ]]; then
  [[ -n "$SID" ]] || { echo "Usage: sudo $0 replica <server-id>"; exit 1; }
  cat >"$CONF" <<EOF
[mysqld]
server-id = ${SID}
bind-address = 0.0.0.0
relay-log = /var/log/mysql/mysql-relay-bin.log
EOF
  echo "[✓] Wrote $CONF (replica server-id=$SID). Restarting MySQL..."
  systemctl restart mysql
  echo ""
  echo "=== Run as root to attach to primary (${MYSQL_PRIMARY_IP}) ==="
  echo "sudo mysql <<'SQL'"
  echo "STOP SLAVE;"
  echo "RESET SLAVE ALL;"
  echo "CHANGE MASTER TO"
  echo "  MASTER_HOST='${MYSQL_PRIMARY_IP}',"
  echo "  MASTER_USER='${MYSQL_REPLICATOR_USER}',"
  echo "  MASTER_PASSWORD='${MYSQL_REPLICATOR_PASSWORD}',"
  echo "  MASTER_LOG_FILE='${MYSQL_MASTER_LOG_FILE}',"
  echo "  MASTER_LOG_POS=${MYSQL_MASTER_LOG_POS};"
  echo "START SLAVE;"
  echo "SQL"
  echo ""
  echo "Then: sudo mysql -e \"SHOW SLAVE STATUS\\G\" | grep -E 'Slave_IO_Running|Slave_SQL_Running|Last_IO_Error'"
fi
