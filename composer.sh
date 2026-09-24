#!/bin/bash
set -euo pipefail

# =========================
# IT490 Composer Script - Group 01
# Start/Stop/Status services across team VMs using SSH key auth
#
# Team roles (4 teammates):
#   Dhayasagar – PHP frontend (Ubuntu)            (PHP :7012)  ZT 10.67.151.148  hostname dhayasubuntuserver
#   Dhayasagar – RabbitMQ cluster node (AWS)      (AMQP :5672) ZT 10.67.151.133  hostname ip-172-31-39-85
#   Rishu      – Frontend + Backend (Flask)       (PHP :7012 + Python :5000 → MySQL + RabbitMQ)
#   Bhavna     – RabbitMQ                         (AMQP :5672)
#   Ravi       – MySQL server                     (MySQL :3306)
#
# Dhaya SSH public keys (install on machines that must accept team logins; never commit private keys):
#   Ubuntu FE:  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK0hO5jBK8uPFe7dtz4+OWSlgvzNc63hgYO6rA/wxTIE dk67@njit.edu
#   Cloud RMQ:  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCWMvFmv1S9cWbgrsMPotOcmoEpQE+4n3HUVPh7H9FI it490-DhayasagarKesavan
# =========================

# Default key for most teammates; optional FRONTEND_SSH_KEY / RABBITMQ_DHAYA_SSH_KEY in .env if Dhaya's hosts use another identity (.pem).
SSH_KEY="${SSH_KEY:-$HOME/.ssh/master_composer}"
SSH_BASE_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=4 -o ConnectionAttempts=1 -o ServerAliveInterval=2 -o ServerAliveCountMax=1"

_composer_ssh_identity_for() {
  local svc="${1:-}"
  if [[ "$svc" == "frontend" && -n "${FRONTEND_SSH_KEY:-}" && -f "${FRONTEND_SSH_KEY/#\~/$HOME}" ]]; then
    echo "${FRONTEND_SSH_KEY/#\~/$HOME}"
  elif [[ "$svc" == "rabbitmq_dhaya" && -n "${RABBITMQ_DHAYA_SSH_KEY:-}" && -f "${RABBITMQ_DHAYA_SSH_KEY/#\~/$HOME}" ]]; then
    echo "${RABBITMQ_DHAYA_SSH_KEY/#\~/$HOME}"
  else
    echo "$SSH_KEY"
  fi
}

# Usage: composer_ssh <service_key> ...normal ssh args...
composer_ssh() {
  local svc="$1"
  shift
  local idf
  idf="$(_composer_ssh_identity_for "$svc")"
  ssh -i "$idf" $SSH_BASE_OPTS "$@"
}

# =========================
# ZeroTier IPs — fill in after teammates share theirs
# =========================
declare -A SERVERS=(
  ["frontend"]="10.67.151.148"    # Dhayasagar – Ubuntu PHP FE       :7012 (ZT) dhayasubuntuserver
  ["rabbitmq_dhaya"]="10.67.151.133" # Dhayasagar – cloud VM RabbitMQ  :5672 (ZT) ip-172-31-39-85
  ["frontendbe"]="10.67.151.212"  # Rishu      – FE + backend app    :7012 :5000
  ["rabbitmq"]="10.67.151.114"    # Bhavna     – RabbitMQ            :5672
  ["mysql"]="10.67.151.166"       # Ravi       – MySQL server        :3306
)

# =========================
# Linux usernames
# =========================
declare -A USERS=(
  ["frontend"]="dhayak23"         # Dhayasagar Ubuntu (repo under /home/dhayak23/...)
  ["rabbitmq_dhaya"]="ubuntu"     # Dhayasagar cloud VM
  ["frontendbe"]="vboxuser"       # Rishu
  ["rabbitmq"]="bhavnasahai3"     # Bhavna
  ["mysql"]="ravi"                # Ravi (MySQL host)
)

# =========================
# Repo paths — exact clone location on each machine
# =========================
declare -A REPO_PATHS=(
  ["frontend"]="/home/dhayak23/Desktop/Capstone-Group-01"    # Dhayasagar Ubuntu → frontend/…
  ["rabbitmq_dhaya"]="/home/ubuntu"                            # Dhaya cloud VM home (add /Capstone-Group-01 if cloned)
  ["frontendbe"]="/home/vboxuser/Desktop/Capstone-Group-01"  # Rishu
  ["rabbitmq"]="/home/bhavnasahai3/Capstone-Group-01"        # Bhavna
  ["mysql"]="/home/ravi/Desktop/Capstone-Group-01"           # Ravi (DB server)
)
# Default fallback
REPO_PATH="${REPO_PATH:-$HOME/Desktop/Capstone-Group-01}"

# =========================
# Repo .env — same file as backend/frontend (optional). Overrides SERVERS/USERS below.
# =========================
COMPOSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_ENV="${COMPOSER_DIR}/.env"
if [[ -f "$ROOT_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_ENV"
  set +a
fi
# Team IPs / Linux users (.env.example: *_HOST, *_USER, RABBITMQ_HOST, DB_HOST, …)
[[ -n "${FRONTEND_HOST:-}" ]] && SERVERS[frontend]="$FRONTEND_HOST"
[[ -n "${BACKEND_HOST:-}" ]] && SERVERS[frontendbe]="$BACKEND_HOST"
[[ -n "${MESSAGING_HOST:-}" ]] && SERVERS[rabbitmq]="$MESSAGING_HOST"
[[ -n "${RABBITMQ_HOST:-}" ]] && SERVERS[rabbitmq]="$RABBITMQ_HOST"
[[ -n "${DATABASE_HOST:-}" ]] && SERVERS[mysql]="$DATABASE_HOST"
if [[ -n "${DB_HOST:-}" && "$DB_HOST" != "localhost" && "$DB_HOST" != "127.0.0.1" ]]; then
  SERVERS[mysql]="$DB_HOST"
fi
[[ -n "${FRONTEND_USER:-}" ]] && USERS[frontend]="$FRONTEND_USER"
[[ -n "${RABBITMQ_DHAYA_HOST:-}" ]] && SERVERS[rabbitmq_dhaya]="$RABBITMQ_DHAYA_HOST"
[[ -n "${RABBITMQ_DHAYA_USER:-}" ]] && USERS[rabbitmq_dhaya]="$RABBITMQ_DHAYA_USER"
[[ -n "${BACKEND_USER:-}" ]] && USERS[frontendbe]="$BACKEND_USER"
[[ -n "${MESSAGING_USER:-}" ]] && USERS[rabbitmq]="$MESSAGING_USER"
[[ -n "${DATABASE_USER:-}" ]] && USERS[mysql]="$DATABASE_USER"
BACKEND_PORT="${BACKEND_PORT:-5000}"

# =========================
# MySQL write failover (file-based — no InnoDB Router required)
# milestone4/mysql_nodes.env  — optional overrides for 3 MySQL IPs
# milestone4/active_mysql.env — DB_WRITE_HOST = which node backend uses
# =========================
MYSQL_NODES_ENV="${COMPOSER_DIR}/milestone4/mysql_nodes.env"
ACTIVE_MYSQL_ENV="${COMPOSER_DIR}/milestone4/active_mysql.env"
ACTIVE_FRONTEND_ENV="${COMPOSER_DIR}/milestone4/active_frontend.env"
ACTIVE_BACKEND_ENV="${COMPOSER_DIR}/milestone4/active_backend.env"
ACTIVE_RABBITMQ_ENV="${COMPOSER_DIR}/milestone4/active_rabbitmq.env"
MYSQL_NODE_RAVI="${SERVERS[mysql]}"
MYSQL_NODE_RISHU="${SERVERS[frontendbe]}"
MYSQL_NODE_BHAVNA="${SERVERS[rabbitmq]}"
if [[ -f "$MYSQL_NODES_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$MYSQL_NODES_ENV"
  set +a
fi

get_active_db_write_host() {
  if [[ -f "$ACTIVE_MYSQL_ENV" ]] && grep -q '^DB_WRITE_HOST=' "$ACTIVE_MYSQL_ENV" 2>/dev/null; then
    grep '^DB_WRITE_HOST=' "$ACTIVE_MYSQL_ENV" | tail -1 | cut -d= -f2- | tr -d '\r' | xargs
  else
    echo "${SERVERS[mysql]}"
  fi
}

select_mysql_write_node() {
  mkdir -p "${COMPOSER_DIR}/milestone4"
  echo ""
  echo "Pick MySQL node for BACKEND WRITES (updates milestone4/active_mysql.env):"
  echo "1) Ravi    (${MYSQL_NODE_RAVI})"
  echo "2) Bhavna  (${MYSQL_NODE_BHAVNA})"
  echo "3) Rishu   (${MYSQL_NODE_RISHU})"
  read -r -p "Choice: " _dbch
  local pick=""
  case "$_dbch" in
    1) pick="$MYSQL_NODE_RAVI" ;;
    2) pick="$MYSQL_NODE_BHAVNA" ;;
    3) pick="$MYSQL_NODE_RISHU" ;;
    *) echo "Invalid choice"; return 1 ;;
  esac
  printf '%s\n' "# Updated by composer.sh — backend DB_HOST target" >"$ACTIVE_MYSQL_ENV"
  printf '%s\n' "DB_WRITE_HOST=${pick}" >>"$ACTIVE_MYSQL_ENV"
  echo "[✓] DB_WRITE_HOST=${pick}  →  ${ACTIVE_MYSQL_ENV}"
  echo "    Run menu 9 to push DB_HOST to Rishu's .env and restart Flask backend."
}

apply_db_host_to_rishu() {
  local dbh ip user rpath
  dbh="$(get_active_db_write_host)"
  ip="${SERVERS[frontendbe]}"
  user="${USERS[frontendbe]}"
  rpath="${REPO_PATHS[frontendbe]}"
  echo "[frontendbe] Apply DB_HOST=${dbh} on Rishu (${user}@${ip})"
  local remote_cmd
  remote_cmd="
    set -e
    RPATH='${rpath}'
    DBW='${dbh}'
    ENVF=\"\$RPATH/.env\"
    if [ ! -d \"\$RPATH\" ]; then echo '[ERROR] Repo not found: '\$RPATH; exit 1; fi
    touch \"\$ENVF\"
    if grep -q '^DB_HOST=' \"\$ENVF\"; then
      sed -i \"s/^DB_HOST=.*/DB_HOST=\${DBW}/\" \"\$ENVF\"
    else
      echo \"DB_HOST=\${DBW}\" >> \"\$ENVF\"
    fi
    echo \"[✓] .env DB_HOST=\$(grep ^DB_HOST= \"\$ENVF\" | tail -1)\"
    pkill -f 'python app.py' 2>/dev/null || true
    sleep 2
    set -o allexport
    source \"\$ENVF\"
    set +o allexport
    cd \"\$RPATH/backend\"
    [ ! -d venv ] && python3 -m venv venv
    source venv/bin/activate
    pip install -q -r requirements.txt 2>/dev/null || true
    export PYTHONUNBUFFERED=1
    nohup python app.py >/tmp/frontendbe_py.log 2>&1 </dev/null &
    sleep 3
    if ss -lntp 2>/dev/null | grep -q ':5000'; then
      echo '[✓] Backend restarted on :5000'
    else
      echo '[!] Backend may have failed — tail -f /tmp/frontendbe_py.log'
    fi
  "
  if [[ -n "$LOCAL_ZT_IP" && "$LOCAL_ZT_IP" == "$ip" ]]; then
    bash -l <<< "$remote_cmd" || true
  else
    composer_ssh "frontendbe" "$user@$ip" bash -l <<< "$remote_cmd" || true
  fi
}

show_active_mysql_summary() {
  echo ""
  echo "── Active MySQL for app writes ──"
  echo "  DB_WRITE_HOST (file): $(get_active_db_write_host)"
  echo "  Config file: ${ACTIVE_MYSQL_ENV}"
  echo ""
}

# Active targets for connectivity / team demos (milestone4/active_*.env).
get_active_frontend_host() {
  if [[ -f "$ACTIVE_FRONTEND_ENV" ]] && grep -q '^ACTIVE_FRONTEND_HOST=' "$ACTIVE_FRONTEND_ENV" 2>/dev/null; then
    grep '^ACTIVE_FRONTEND_HOST=' "$ACTIVE_FRONTEND_ENV" | tail -1 | cut -d= -f2- | tr -d '\r' | xargs
  else
    echo "${SERVERS[frontend]}"
  fi
}

get_active_backend_host() {
  if [[ -f "$ACTIVE_BACKEND_ENV" ]] && grep -q '^ACTIVE_BACKEND_HOST=' "$ACTIVE_BACKEND_ENV" 2>/dev/null; then
    grep '^ACTIVE_BACKEND_HOST=' "$ACTIVE_BACKEND_ENV" | tail -1 | cut -d= -f2- | tr -d '\r' | xargs
  else
    echo "${SERVERS[frontendbe]}"
  fi
}

get_active_rabbitmq_host() {
  if [[ -f "$ACTIVE_RABBITMQ_ENV" ]] && grep -q '^ACTIVE_RABBITMQ_HOST=' "$ACTIVE_RABBITMQ_ENV" 2>/dev/null; then
    grep '^ACTIVE_RABBITMQ_HOST=' "$ACTIVE_RABBITMQ_ENV" | tail -1 | cut -d= -f2- | tr -d '\r' | xargs
  else
    echo "${SERVERS[rabbitmq]}"
  fi
}

select_active_frontend_node() {
  mkdir -p "${COMPOSER_DIR}/milestone4"
  echo ""
  echo "Pick ACTIVE FRONTEND host (PHP :7012) — writes milestone4/active_frontend.env:"
  echo "1) Dhayasagar  (${SERVERS[frontend]})"
  echo "2) Rishu       (${SERVERS[frontendbe]})"
  echo "3) Ravi        (${SERVERS[mysql]})"
  read -r -p "Choice: " _ch
  local pick=""
  case "$_ch" in
    1) pick="${SERVERS[frontend]}" ;;
    2) pick="${SERVERS[frontendbe]}" ;;
    3) pick="${SERVERS[mysql]}" ;;
    *) echo "Invalid choice"; return 1 ;;
  esac
  printf '%s\n' "# Active frontend for composer connectivity (menu 7)" >"$ACTIVE_FRONTEND_ENV"
  printf '%s\n' "ACTIVE_FRONTEND_HOST=${pick}" >>"$ACTIVE_FRONTEND_ENV"
  echo "[✓] ACTIVE_FRONTEND_HOST=${pick}  →  ${ACTIVE_FRONTEND_ENV}"
}

select_active_backend_node() {
  mkdir -p "${COMPOSER_DIR}/milestone4"
  echo ""
  echo "Pick ACTIVE BACKEND host (Flask :${BACKEND_PORT}) — writes milestone4/active_backend.env:"
  echo "1) Rishu       (${SERVERS[frontendbe]})"
  echo "2) Dhayasagar  (${SERVERS[frontend]})"
  echo "3) Ravi        (${SERVERS[mysql]})"
  read -r -p "Choice: " _ch
  local pick=""
  case "$_ch" in
    1) pick="${SERVERS[frontendbe]}" ;;
    2) pick="${SERVERS[frontend]}" ;;
    3) pick="${SERVERS[mysql]}" ;;
    *) echo "Invalid choice"; return 1 ;;
  esac
  printf '%s\n' "# Active backend for composer connectivity (menu 7)" >"$ACTIVE_BACKEND_ENV"
  printf '%s\n' "ACTIVE_BACKEND_HOST=${pick}" >>"$ACTIVE_BACKEND_ENV"
  echo "[✓] ACTIVE_BACKEND_HOST=${pick}  →  ${ACTIVE_BACKEND_ENV}"
}

select_active_rabbitmq_node() {
  mkdir -p "${COMPOSER_DIR}/milestone4"
  echo ""
  echo "Pick ACTIVE RABBITMQ broker (:5672) — writes milestone4/active_rabbitmq.env:"
  echo "1) Bhavna  (${SERVERS[rabbitmq]})"
  echo "2) Dhayasagar cloud (${SERVERS[rabbitmq_dhaya]})"
  echo "3) Ravi    (${SERVERS[mysql]})"
  read -r -p "Choice: " _ch
  local pick=""
  case "$_ch" in
    1) pick="${SERVERS[rabbitmq]}" ;;
    2) pick="${SERVERS[rabbitmq_dhaya]}" ;;
    3) pick="${SERVERS[mysql]}" ;;
    *) echo "Invalid choice"; return 1 ;;
  esac
  printf '%s\n' "# Active RabbitMQ for composer connectivity (menu 7)" >"$ACTIVE_RABBITMQ_ENV"
  printf '%s\n' "ACTIVE_RABBITMQ_HOST=${pick}" >>"$ACTIVE_RABBITMQ_ENV"
  echo "[✓] ACTIVE_RABBITMQ_HOST=${pick}  →  ${ACTIVE_RABBITMQ_ENV}"
}

# Run ON Bhavna's VM (via SSH): stop replication + allow writes when Ravi's MySQL is down.
promote_bhavna_mysql_failover() {
  local ip user script_path
  ip="${SERVERS[rabbitmq]}"
  user="${USERS[rabbitmq]}"
  script_path="${COMPOSER_DIR}/mysql-promote-replica-writable.sh"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  MySQL FAILOVER — Bhavna replica → writable"
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Use when Ravi (primary) MySQL is DOWN and registrations must save on Bhavna."
  echo "  Remote: ${user}@${ip}  (MySQL must be installed there as replica of Ravi.)"
  echo ""
  echo "  This will: STOP REPLICA, RESET REPLICA, turn off read_only."
  echo "  Then run HERE: 8) pick Bhavna (choice 2) → 9) push DB_HOST to Rishu + restart Flask."
  echo ""
  local _y=""
  if [[ "${COMPOSER_ASSUME_YES:-}" == "1" ]]; then
    _y=y
  else
    read -r -p "Run promote script on Bhavna via SSH? [y/N]: " _y
  fi
  if [[ "$_y" != [yY] ]]; then
    echo "Cancelled. Bhavna can run locally: sudo bash ${COMPOSER_DIR}/mysql-promote-replica-writable.sh"
    return 0
  fi
  if [[ ! -f "$script_path" ]]; then
    echo "[ERROR] Missing ${script_path}"
    return 1
  fi
  echo "[*] Piping script to ${user}@${ip} ..."
  if composer_ssh "rabbitmq" "$user@$ip" "sudo bash -s" <"$script_path"; then
    echo ""
    echo "[✓] Promote completed on remote host."
    echo "    Next: menu 8 → choice 2) Bhavna (${MYSQL_NODE_BHAVNA}), then menu 9."
  else
    echo ""
    echo "[!] SSH/sudo failed. On Bhavna's machine run:"
    echo "    sudo bash ${COMPOSER_DIR}/mysql-promote-replica-writable.sh"
    return 1
  fi
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
}

show_gr_health() {
  local script="${COMPOSER_DIR}/gr-health.sh"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Group Replication health (cluster.env)"
  echo "═══════════════════════════════════════════════════════════════════"
  if [[ ! -f "$script" ]]; then
    echo "[ERROR] Missing script: ${script}"
    return 1
  fi
  bash "$script" || true
}

apply_router_dbhost_local() {
  local script="${COMPOSER_DIR}/apply-router-dbhost.sh"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Apply backend DB_HOST/DB_PORT to MySQL Router (local)"
  echo "═══════════════════════════════════════════════════════════════════"
  if [[ ! -f "$script" ]]; then
    echo "[ERROR] Missing script: ${script}"
    return 1
  fi
  if [[ $EUID -ne 0 ]]; then
    echo "[*] apply-router-dbhost.sh needs sudo. Re-running with sudo..."
    sudo bash "$script" || true
  else
    bash "$script" || true
  fi
}

# =========================
# Start commands
# =========================
declare -A START_COMMANDS=(

  # Dhayasagar – PHP frontend only
  ["frontend"]="
    RPATH='${REPO_PATHS[frontend]}'
    if [ ! -d \"\$RPATH\" ]; then echo '[ERROR] Repo not found at '\"\$RPATH\"' on this machine'; exit 1; fi
    if [ \"\${COMPOSER_SKIP_PHP_DEPS:-0}\" != \"1\" ] && [ -f \"\$RPATH/scripts/install-php-deps.sh\" ] && command -v composer >/dev/null 2>&1; then
      echo '[*] install-php-deps.sh (PHP Composer root + frontend)...'
      bash \"\$RPATH/scripts/install-php-deps.sh\" || echo '[!] install-php-deps failed — check composer / network'
    fi
    cd \"\$RPATH/frontend\"
    pkill -f 'php -S 0.0.0.0:7012' 2>/dev/null || true
    nohup php -S 0.0.0.0:7012 Welcome.php >/tmp/frontend.log 2>&1 </dev/null &
    echo 'Frontend started'
  "

  # Rishu – PHP + Flask backend (consumers → MySQL on Ravi, RabbitMQ on Bhavna)
  ["frontendbe"]="
    RPATH='${REPO_PATHS[frontendbe]}'
    if [ ! -d \"\$RPATH\" ]; then echo '[ERROR] Repo not found at '\"\$RPATH\"' — update REPO_PATHS[frontendbe] in composer.sh'; exit 1; fi
    if [ -f \"\$RPATH/.env\" ]; then
      set -o allexport; source \"\$RPATH/.env\"; set +o allexport
    fi
    if [ \"\${COMPOSER_SKIP_PHP_DEPS:-0}\" != \"1\" ] && [ -f \"\$RPATH/scripts/install-php-deps.sh\" ] && command -v composer >/dev/null 2>&1; then
      echo '[*] install-php-deps.sh (PHP Composer root + frontend)...'
      bash \"\$RPATH/scripts/install-php-deps.sh\" || echo '[!] install-php-deps failed — check composer / network'
    fi
    cd \"\$RPATH/frontend\"
    pkill -f 'php -S 0.0.0.0:7012' 2>/dev/null || true
    nohup php -S 0.0.0.0:7012 Welcome.php >/tmp/frontendbe_php.log 2>&1 </dev/null &
    cd \"\$RPATH/backend\"
    [ ! -d venv ] && python3 -m venv venv
    source venv/bin/activate
    pip install -q -r requirements.txt 2>/dev/null || true
    pkill -f 'python app.py' 2>/dev/null || true
    nohup python app.py >/tmp/frontendbe_py.log 2>&1 </dev/null &
    echo 'Frontend+Backend-FE started'
  "

  # Bhavna – RabbitMQ broker
  ["rabbitmq"]="sudo -n systemctl start rabbitmq-server && echo 'RabbitMQ started'"

  # Dhayasagar – cloud VM RabbitMQ (cluster with Bhavna)
  ["rabbitmq_dhaya"]="sudo -n systemctl start rabbitmq-server && echo 'RabbitMQ (Dhaya cloud) started'"

  # Ravi – MySQL server
  ["mysql"]="
    sudo -n systemctl start mysql 2>/dev/null ||
    sudo -n systemctl start mysqld 2>/dev/null || true
    echo 'MySQL start attempted'
  "
)

# =========================
# Stop commands  (verify service actually stopped after running)
# =========================
declare -A STOP_COMMANDS=(
  ["frontend"]="
    pkill -f 'php -S 0.0.0.0:7012' 2>/dev/null || true
    sleep 1
    if ss -lntp 2>/dev/null | grep -q ':7012'; then
      echo '  [!] Frontend  (Dhayasagar) : STILL RUNNING — could not stop'
    else
      echo '  [✓] Frontend  (Dhayasagar) : STOPPED'
    fi
  "
  ["frontendbe"]="
    pkill -f 'php -S 0.0.0.0:7012' 2>/dev/null || true
    pkill -f 'python app.py' 2>/dev/null || true
    sleep 1
    if ss -lntp 2>/dev/null | grep -q ':7012'; then
      echo '  [!] Frontend  (Rishu)  : STILL RUNNING on :7012'
    else
      echo '  [✓] Frontend  (Rishu)  : STOPPED'
    fi
    if ss -lntp 2>/dev/null | grep -q ':5000'; then
      echo '  [!] Backend-FE(Rishu)  : STILL RUNNING on :5000'
    else
      echo '  [✓] Backend-FE(Rishu)  : STOPPED'
    fi
  "
  ["rabbitmq"]="
    if sudo -n systemctl stop rabbitmq-server 2>/dev/null; then
      sleep 1
      STATUS=\$(systemctl is-active rabbitmq-server 2>/dev/null || echo 'unknown')
      if [ \"\$STATUS\" = 'active' ]; then
        echo '  [!] RabbitMQ  (Bhavna) : STILL RUNNING'
      else
        echo '  [✓] RabbitMQ  (Bhavna) : STOPPED'
      fi
    else
      echo '  [!] RabbitMQ  (Bhavna) : STOP FAILED — sudo passwordless not configured'
      echo '       Run on Bhavna machine: sudo systemctl stop rabbitmq-server'
    fi
  "
  ["rabbitmq_dhaya"]="
    if sudo -n systemctl stop rabbitmq-server 2>/dev/null; then
      sleep 1
      STATUS=\$(systemctl is-active rabbitmq-server 2>/dev/null || echo 'unknown')
      if [ \"\$STATUS\" = 'active' ]; then
        echo '  [!] RabbitMQ  (Dhaya cloud) : STILL RUNNING'
      else
        echo '  [✓] RabbitMQ  (Dhaya cloud) : STOPPED'
      fi
    else
      echo '  [!] RabbitMQ  (Dhaya cloud) : STOP FAILED — sudo passwordless not configured'
      echo '       Run on Dhaya cloud VM: sudo systemctl stop rabbitmq-server'
    fi
  "
  ["mysql"]="
    if sudo -n systemctl stop mysql 2>/dev/null || sudo -n systemctl stop mysqld 2>/dev/null; then
      sleep 1
      STATUS=\$(systemctl is-active mysql 2>/dev/null || systemctl is-active mysqld 2>/dev/null || echo 'unknown')
      if [ \"\$STATUS\" = 'active' ]; then
        echo '  [!] MySQL     (Ravi)   : STILL RUNNING'
      else
        echo '  [✓] MySQL     (Ravi)   : STOPPED'
      fi
    else
      echo '  [!] MySQL     (Ravi)   : STOP FAILED — sudo passwordless not configured'
      echo '       Run on Ravi machine: sudo systemctl stop mysql'
    fi
  "
)

# =========================
# Status commands  (no sudo needed — uses systemctl is-active + port check)
# =========================
declare -A STATUS_COMMANDS=(
  ["frontend"]="
    if ss -lntp 2>/dev/null | grep -q ':7012'; then
      echo '  [✓] Frontend  (Dhayasagar) : RUNNING  on port 7012'
    else
      echo '  [✗] Frontend  (Dhayasagar) : STOPPED'
    fi
  "
  ["frontendbe"]="
    if ss -lntp 2>/dev/null | grep -q ':7012'; then
      echo '  [✓] Frontend  (Rishu)  : RUNNING  on port 7012'
    else
      echo '  [✗] Frontend  (Rishu)  : STOPPED'
    fi
    if ss -lntp 2>/dev/null | grep -q ':5000'; then
      echo '  [✓] Backend-FE(Rishu)  : RUNNING  on port 5000'
    else
      echo '  [✗] Backend-FE(Rishu)  : STOPPED'
    fi
  "
  ["rabbitmq"]="
    STATUS=\$(systemctl is-active rabbitmq-server 2>/dev/null || echo 'unknown')
    if [ \"\$STATUS\" = 'active' ]; then
      echo '  [✓] RabbitMQ  (Bhavna) : RUNNING  (systemctl active)'
    else
      echo '  [✗] RabbitMQ  (Bhavna) : STOPPED  (systemctl: '\"\$STATUS\"')'
    fi
    # Also check port 5672
    if ss -lntp 2>/dev/null | grep -q ':5672'; then
      echo '       port 5672          : OPEN'
    else
      echo '       port 5672          : NOT listening'
    fi
  "
  ["rabbitmq_dhaya"]="
    STATUS=\$(systemctl is-active rabbitmq-server 2>/dev/null || echo 'unknown')
    if [ \"\$STATUS\" = 'active' ]; then
      echo '  [✓] RabbitMQ  (Dhaya cloud) : RUNNING  (systemctl active)'
    else
      echo '  [✗] RabbitMQ  (Dhaya cloud) : STOPPED  (systemctl: '\"\$STATUS\"')'
    fi
    if ss -lntp 2>/dev/null | grep -q ':5672'; then
      echo '       port 5672          : OPEN'
    else
      echo '       port 5672          : NOT listening'
    fi
  "
  ["mysql"]="
    STATUS=\$(systemctl is-active mysql 2>/dev/null || systemctl is-active mysqld 2>/dev/null || echo 'unknown')
    if [ \"\$STATUS\" = 'active' ]; then
      echo '  [✓] MySQL     (Ravi)   : RUNNING  (systemctl active)'
    else
      echo '  [✗] MySQL     (Ravi)   : STOPPED  (systemctl: '\"\$STATUS\"')'
    fi
    # Also check port 3306
    if ss -lntp 2>/dev/null | grep -q ':3306'; then
      echo '       port 3306          : OPEN'
    else
      echo '       port 3306          : NOT listening'
    fi
  "
)

# =========================
# Detect this machine's ZeroTier IP (prefer zt* interface over VirtualBox NAT)
# =========================
LOCAL_ZT_IP="$(ip -4 addr show | awk '/zt[a-z0-9]+/{found=1} found && /inet /{print $2; exit}' | cut -d/ -f1 || true)"
# Fallback: any 10.67.x.x address
if [ -z "$LOCAL_ZT_IP" ]; then
  LOCAL_ZT_IP="$(hostname -I | tr ' ' '\n' | grep -E '^10\.67\.' | head -n 1 || true)"
fi

# =========================
# Menu
# =========================
show_menu() {
  echo ""
  echo "=================================="
  echo "  IT490 Composer - Group 01"
  echo "  My ZeroTier IP: ${LOCAL_ZT_IP:-unknown}"
  echo "=================================="
  echo "1) Start a service"
  echo "2) Stop a service"
  echo "3) Check service status"
  echo "4) Start ALL services"
  echo "5) Stop ALL services"
  echo "6) Status of ALL services"
  echo "7) Node connectivity (reachability + app paths + SSH)"
  echo "8) Set active MySQL write node — Ravi / Bhavna / Rishu (active_mysql.env)"
  echo "9) Apply DB_HOST to Rishu backend + restart Flask (:5000)"
  echo "10) MySQL failover: promote Bhavna (replica→writable) when Ravi DB is down"
  echo "11) Set active FRONTEND node — Dhaya / Rishu / Ravi (active_frontend.env)"
  echo "12) Set active BACKEND node — Rishu / Dhaya / Ravi (active_backend.env)"
  echo "13) Set active RabbitMQ node — Bhavna / Dhaya cloud / Ravi (active_rabbitmq.env)"
  echo "14) Group Replication health (gr-health.sh)"
  echo "15) Apply backend DB_HOST to MySQL Router (apply-router-dbhost.sh)"
  echo "16) Exit"
  read -r -p "Choice: " CHOICE
}

select_service() {
  echo ""
  echo "Pick a service:"
  echo "1) Frontend only        Dhayasagar Ubuntu (${SERVERS[frontend]})"
  echo "2) Frontend + Backend   Rishu           (${SERVERS[frontendbe]})"
  echo "3) RabbitMQ             Bhavna          (${SERVERS[rabbitmq]})"
  echo "4) MySQL                Ravi            (${SERVERS[mysql]})"
  echo "5) RabbitMQ             Dhaya cloud VM  (${SERVERS[rabbitmq_dhaya]})"
  read -r -p "Choice: " SERVICE_CHOICE

  case "$SERVICE_CHOICE" in
    1) SERVICE="frontend" ;;
    2) SERVICE="frontendbe" ;;
    3) SERVICE="rabbitmq" ;;
    4) SERVICE="mysql" ;;
    5) SERVICE="rabbitmq_dhaya" ;;
    *) echo "Invalid choice"; return 1 ;;
  esac
}

execute_action() {
  local service="$1"
  local action="$2"
  local ip="${SERVERS[$service]}"
  local user="${USERS[$service]}"
  local cmd=""

  if [[ "$ip" == "CHANGE_ME" || "$user" == "CHANGE_ME" ]]; then
    echo "[$service] Skipped — fill in IP/username in composer.sh first"
    return 0
  fi

  case "$action" in
    start)  cmd="${START_COMMANDS[$service]}" ;;
    stop)   cmd="${STOP_COMMANDS[$service]}" ;;
    status) cmd="${STATUS_COMMANDS[$service]}" ;;
    *) echo "Unknown action"; return 1 ;;
  esac

  if [[ -n "$LOCAL_ZT_IP" && "$LOCAL_ZT_IP" == "$ip" ]]; then
    echo "[$service] $action (LOCAL: $user@$ip)"
    bash -l <<< "$cmd" || true
  else
    echo "[$service] $action (REMOTE: $user@$ip)"
    # Pipe cmd via stdin — do NOT use -n (that blocks stdin, killing the heredoc)
    composer_ssh "$service" "$user@$ip" bash -l <<< "$cmd" || true
  fi
}

composer_run_local_php_deps() {
  if [[ "${COMPOSER_SKIP_PHP_DEPS:-0}" == "1" ]]; then
    return 0
  fi
  local s="${COMPOSER_DIR}/scripts/install-php-deps.sh"
  if [[ ! -f "$s" ]]; then
    return 0
  fi
  if ! command -v composer >/dev/null 2>&1; then
    echo "[i] composer not in PATH here — skipping local install-php-deps (PHP hosts still run it on start)."
    return 0
  fi
  echo "[*] This machine: install-php-deps.sh (before remote starts)..."
  bash "$s" || echo "[!] Local install-php-deps exited non-zero — continuing start-all"
}

start_all() {
  echo "--- Starting all services (dependency order) ---"
  composer_run_local_php_deps
  execute_action "rabbitmq"        "start"   # 1st: broker (Bhavna)
  execute_action "rabbitmq_dhaya" "start"   # Dhaya cloud RMQ node (cluster)
  execute_action "mysql"      "start"   # MySQL on Ravi
  execute_action "frontendbe" "start"   # Rishu PHP + Flask (consumers)
  execute_action "frontend"   "start"   # Dhayasagar Ubuntu PHP FE
  echo ""
  echo "Start-all done. Run option 6 to verify."
}

stop_all() {
  echo "--- Stopping all services ---"
  execute_action "frontend"   "stop"
  execute_action "frontendbe" "stop"
  execute_action "mysql"      "stop"
  execute_action "rabbitmq_dhaya" "stop"
  execute_action "rabbitmq"   "stop"
  echo ""
  echo "Stop-all done."
}

status_all() {
  echo "--- Status of all services ---"
  execute_action "rabbitmq"        "status"
  execute_action "rabbitmq_dhaya" "status"
  execute_action "mysql"      "status"
  execute_action "frontendbe" "status"
  execute_action "frontend"   "status"
}

# =========================
# Node connectivity — TCP reachability + app paths (from THIS machine)
# Uses ZeroTier IPs in SERVERS. Open port = host reachable AND service likely listening.
# =========================
tcp_open() {
  local host="$1" port="$2"
  [ -z "$host" ] && return 1
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 3 "$host" "$port" 2>/dev/null
    return $?
  fi
  timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
}

fmt_ok() {
  if [ "$1" -eq 0 ]; then
    printf '%s\n' "  OK   (reach / listen)"
  else
    printf '%s\n' "  FAIL (down, firewall, or wrong network)"
  fi
}

show_connectivity() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  NODE CONNECTIVITY  (from this machine: ${LOCAL_ZT_IP:-unknown})"
  echo "═══════════════════════════════════════════════════════════════════"
  if [[ -f "${ROOT_ENV}" ]]; then
    echo "  Repo .env loaded — SERVERS / USERS / BACKEND_PORT may override script defaults."
  fi
  echo "  Legend: OK = TCP connect to port succeeded from here."
  echo "          If a teammate's row is FAIL, their VM may be off, on a"
  echo "          different VPN, or blocking the port (ufw / only localhost)."
  echo ""

  local rc=0 r
  local _fe _be _rmq _my
  _fe="$(get_active_frontend_host)"
  _be="$(get_active_backend_host)"
  _rmq="$(get_active_rabbitmq_host)"
  _my="$(get_active_db_write_host)"

  echo "── Active node targets (milestone4/active_*.env — menus 8, 11–13) ──"
  echo "  Frontend :7012   → ${_fe}"
  echo "  Backend  :${BACKEND_PORT}   → ${_be}"
  echo "  MySQL    :3306   → ${_my}"
  echo "  RabbitMQ :5672   → ${_rmq}"
  echo ""

  echo "── Service endpoints (each team member's main ports) ──"
  printf '  %-20s %7s %-22s ' "Dhayasagar (FE)" "${SERVERS[frontend]}" ":7012"
  r=0; tcp_open "${SERVERS[frontend]}" 7012 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-20s %7s %-22s ' "Rishu (PHP FE)" "${SERVERS[frontendbe]}" ":7012"
  r=0; tcp_open "${SERVERS[frontendbe]}" 7012 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-20s %7s %-22s ' "Rishu (backend FE)" "${SERVERS[frontendbe]}" ":${BACKEND_PORT}"
  r=0; tcp_open "${SERVERS[frontendbe]}" "${BACKEND_PORT}" || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-20s %7s %-22s ' "Bhavna (RabbitMQ)" "${SERVERS[rabbitmq]}" ":5672"
  r=0; tcp_open "${SERVERS[rabbitmq]}" 5672 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-20s %7s %-22s ' "Dhaya cloud (RMQ)" "${SERVERS[rabbitmq_dhaya]}" ":5672"
  r=0; tcp_open "${SERVERS[rabbitmq_dhaya]}" 5672 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-20s %7s %-22s ' "Ravi (MySQL)" "${SERVERS[mysql]}" ":3306"
  r=0; tcp_open "${SERVERS[mysql]}" 3306 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  echo ""
  echo "── Application data paths (must work for register / login / jobs) ──"
  printf '  %-42s' "Active frontend :7012 (${_fe})"
  r=0; tcp_open "${_fe}" 7012 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-42s' "Active backend :${BACKEND_PORT} (${_be})"
  r=0; tcp_open "${_be}" "${BACKEND_PORT}" || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-42s' "Backend → RabbitMQ (active ${_rmq}:5672)"
  r=0; tcp_open "${_rmq}" 5672 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-42s' "Backend → MySQL (active ${_my}:3306)"
  r=0; tcp_open "${_my}" 3306 || r=1
  fmt_ok "$r"
  rc=$((rc | r))

  printf '  %-42s' "Frontend → RabbitMQ (active ${_rmq}:5672)"
  r=0; tcp_open "${_rmq}" 5672 || r=1
  fmt_ok "$r"
  rc=$((rc | r))
  echo "       (confirm PHP .env RABBITMQ_HOST on each FE host if needed)"

  echo ""
  echo "── Optional: HTTP health (backend JSON) ──"
  if command -v curl >/dev/null 2>&1; then
    printf '  %-42s' "GET http://${_be}:${BACKEND_PORT}/health"
    if curl -sS -m 4 "http://${_be}:${BACKEND_PORT}/health" 2>/dev/null | grep -qi healthy; then
      echo "  OK   (responding)"
    else
      echo "  FAIL (no response or not healthy)"
      rc=1
    fi
  else
    echo "  (install curl for HTTP health check)"
  fi

  echo ""
  echo "── SSH reachability (composer remote actions) ──"
  local svc u ip_
  for svc in frontend rabbitmq_dhaya frontendbe rabbitmq mysql; do
    ip_="${SERVERS[$svc]}"
    u="${USERS[$svc]}"
    printf '  ssh %s@%s  ' "$u" "$ip_"
    if composer_ssh "$svc" -o ConnectTimeout=3 "$u@$ip_" "echo ok" 2>/dev/null | grep -q ok; then
      echo "  OK"
    else
      echo "  FAIL (key, user, or host offline)"
      rc=1
    fi
  done

  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  if [ "$rc" -eq 0 ]; then
    echo "  Summary: all TCP checks from this host passed (or only curl missing)."
  else
    echo "  Summary: one or more checks FAILED — fix host, ZeroTier, or firewall."
  fi
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
}

# =========================
# Non-interactive CLI (automation / CI / cron)
# Usage: bash composer.sh <command>   or   COMPOSER_ASSUME_YES=1 bash composer.sh promote-bhavna
# =========================
composer_usage() {
  cat <<'USAGE'
IT490 composer.sh — remote/local service control

Interactive menu (default):
  bash composer.sh
  bash composer.sh menu

Non-interactive commands:
  bash composer.sh start-all          Start RabbitMQ, MySQL, backends, frontends (dependency order)
  bash composer.sh stop-all           Stop all managed services
  bash composer.sh status-all         Print status for each tier
  bash composer.sh connectivity       TCP + SSH checks from this machine
  bash composer.sh gr-health          Run gr-health.sh (needs cluster.env on MySQL node)
  bash composer.sh apply-router       sudo apply-router-dbhost.sh on this machine
  bash composer.sh apply-db           Push DB_HOST to Rishu backend + restart Flask
  bash composer.sh promote-bhavna   Promote Bhavna MySQL (prompts unless COMPOSER_ASSUME_YES=1)
  bash composer.sh install-php-deps Run scripts/install-php-deps.sh (Composer deps root + frontend)

Environment:
  Loads repo .env if present (FRONTEND_HOST, BACKEND_HOST, …).
  COMPOSER_ASSUME_YES=1  Auto-confirm promote-bhavna SSH prompt.
  COMPOSER_SKIP_PHP_DEPS=1  Skip install-php-deps.sh (start-all + frontend/frontendbe start).

USAGE
}

composer_run_cli() {
  local cmd="${1:-menu}"
  shift || true
  case "$cmd" in
    help|-h|--help)
      composer_usage
      return 0
      ;;
    menu|interactive) return 2 ;;
    start-all) start_all ;;
    stop-all) stop_all ;;
    status-all|status) status_all ;;
    connectivity|node-check) show_connectivity ;;
    gr-health|gr_health) show_gr_health ;;
    apply-router|apply_router)
      if [[ "$(id -u)" -eq 0 ]]; then
        bash "${COMPOSER_DIR}/apply-router-dbhost.sh" || true
      else
        sudo bash "${COMPOSER_DIR}/apply-router-dbhost.sh" || true
      fi
      ;;
    apply-db|apply_db) apply_db_host_to_rishu ;;
    promote-bhavna|promote_bhavna)
      if [[ "${1:-}" == "--yes" ]]; then
        export COMPOSER_ASSUME_YES=1
      fi
      promote_bhavna_mysql_failover
      ;;
    install-php-deps)
      if [[ ! -f "${COMPOSER_DIR}/scripts/install-php-deps.sh" ]]; then
        echo "[ERROR] Missing ${COMPOSER_DIR}/scripts/install-php-deps.sh" >&2
        return 1
      fi
      bash "${COMPOSER_DIR}/scripts/install-php-deps.sh"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      composer_usage >&2
      return 1
      ;;
  esac
}

# =========================
# Main loop
# =========================
if [[ $# -gt 0 ]]; then
  composer_run_cli "$@"
  cli_rc=$?
  if [[ "$cli_rc" -eq 0 ]]; then
    exit 0
  elif [[ "$cli_rc" -eq 2 ]]; then
    : # "menu" / interactive — fall through to menu loop
  else
    exit "$cli_rc"
  fi
fi

while true; do
  show_menu
  case "${CHOICE:-}" in
    1) select_service && execute_action "$SERVICE" "start" ;;
    2) select_service && execute_action "$SERVICE" "stop" ;;
    3) select_service && execute_action "$SERVICE" "status" ;;
    4) start_all ;;
    5) stop_all ;;
    6) status_all ;;
    7) show_connectivity ;;
    8) select_mysql_write_node ;;
    9) apply_db_host_to_rishu ;;
    10) promote_bhavna_mysql_failover ;;
    11) select_active_frontend_node ;;
    12) select_active_backend_node ;;
    13) select_active_rabbitmq_node ;;
    14) show_gr_health ;;
    15) apply_router_dbhost_local ;;
    16) echo "Bye."; exit 0 ;;
    *) echo "Invalid choice." ;;
  esac
done
