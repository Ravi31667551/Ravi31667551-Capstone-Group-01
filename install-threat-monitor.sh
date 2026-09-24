#!/usr/bin/env bash
# Minimal host threat monitoring: fail2ban for SSH brute-force + optional HTTP 401 abuse.
# For course demos: show ban in fail2ban-client + journalctl. Tune jails for production.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban

JAIL_DIR="/etc/fail2ban/jail.d"
mkdir -p "${JAIL_DIR}"

cat >"${JAIL_DIR}/capstone-ssh.local" <<'EOF'
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 10m
bantime  = 1h
EOF

# If Apache is present, optional jail for repeated 401s (login abuse pattern)
if command -v apache2 >/dev/null 2>&1 && [[ -d /var/log/apache2 ]]; then
  cat >"${JAIL_DIR}/capstone-apache-401.local" <<'EOF'
[apache-auth]
enabled = true
port    = http,https
filter  = apache-auth
logpath = /var/log/apache2/*error.log
maxretry = 8
findtime = 10m
bantime  = 30m
EOF
fi

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
fail2ban-client status || true

echo ""
echo "[✓] fail2ban installed. Response workflow:"
echo "    - List jails:    sudo fail2ban-client status"
echo "    - Banned IPs:    sudo fail2ban-client status sshd"
echo "    - Unban:         sudo fail2ban-client set sshd unbanip <IP>"
echo "    - Logs:          sudo journalctl -u fail2ban -n 50 --no-pager"
