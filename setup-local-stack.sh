#!/usr/bin/env bash
# Install MySQL + RabbitMQ on this machine and seed capstone_db (Ubuntu/Debian).
# Run:  bash scripts/setup-local-stack.sh
# Requires sudo for apt and system services.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="capstone_db"
DB_USER="it490"
DB_PASS="${LOCAL_DB_PASSWORD:-localdev490}"
RMQ_USER="group1"
RMQ_PASS="${LOCAL_RMQ_PASSWORD:-12345}"

if [[ ! -f /etc/os-release ]]; then
  echo "This script targets Debian/Ubuntu. Install MySQL and RabbitMQ manually on other OSes."
  exit 1
fi

echo "==> Installing packages (mysql-server, rabbitmq-server) ..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y mysql-server rabbitmq-server

echo "==> Enabling services ..."
sudo systemctl enable --now mysql rabbitmq-server

echo "==> Creating MySQL database and user (${DB_USER}) ..."
sudo mysql -e "
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
"

echo "==> Applying schema (database/db_setup.sql) ..."
sudo mysql < "${ROOT}/database/db_setup.sql"

echo "==> RabbitMQ user ${RMQ_USER} ..."
if sudo rabbitmqctl list_users 2>/dev/null | grep -q "^${RMQ_USER}\\b"; then
  sudo rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
else
  sudo rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}"
fi
sudo rabbitmqctl set_permissions -p / "${RMQ_USER}" ".*" ".*" ".*"

echo ""
echo "Done. Match these in your .env (see .env.local.example):"
echo "  DB_USER=${DB_USER}  DB_PASSWORD=${DB_PASS}  DB_NAME=${DB_NAME}"
echo "  RABBITMQ_USER=${RMQ_USER}  RABBITMQ_PASS=${RMQ_PASS}  RABBITMQ_HOST=127.0.0.1"
echo ""
echo "Next:  cp .env.local.example .env"
echo "Then start backend (source .env; backend/run.sh or your unit) and PHP frontend."
