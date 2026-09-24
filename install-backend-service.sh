#!/usr/bin/env bash
# Install systemd unit jobtracker-backend (Flask + RabbitMQ consumers).
# Run from repo clone:
#   sudo bash install-backend-service.sh
#
# Requires: backend/venv, repo root .env (DB_*, RABBITMQ_*, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/backend/app.py" ]]; then
  REPO="$SCRIPT_DIR"
else
  REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
if [[ ! -f "${REPO}/backend/app.py" ]]; then
  echo "Cannot find repo root (missing backend/app.py). SCRIPT_DIR=${SCRIPT_DIR}"
  exit 1
fi

UNIT="jobtracker-backend.service"
ACTUAL_USER="${SUDO_USER:-$USER}"
VENV_PY="${REPO}/backend/venv/bin/python"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo so the unit can be installed under /etc/systemd/system/"
  exit 1
fi

if [[ ! -x "$VENV_PY" ]]; then
  echo "Creating venv and installing backend dependencies..."
  sudo -u "$ACTUAL_USER" python3 -m venv "${REPO}/backend/venv"
  sudo -u "$ACTUAL_USER" "${REPO}/backend/venv/bin/pip" install -q -r "${REPO}/backend/requirements.txt"
fi

if [[ ! -f "${REPO}/.env" ]]; then
  echo "Warning: ${REPO}/.env missing — copy .env.example first."
fi

BACKEND_PORT=5000
if [[ -f "${REPO}/.env" ]]; then
  _line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?BACKEND_PORT=' "${REPO}/.env" | tail -1 || true)"
  if [[ -n "${_line}" ]]; then
    BACKEND_PORT="$(echo "${_line#*=}" | tr -d "\"'[:space:]")"
  fi
fi

cat >"/etc/systemd/system/${UNIT}" <<EOF
[Unit]
Description=JobTracker backend (Flask + RabbitMQ consumers)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${ACTUAL_USER}
Group=${ACTUAL_USER}
WorkingDirectory=${REPO}/backend
EnvironmentFile=-${REPO}/.env
Environment=PYTHONUNBUFFERED=1
# Bounded time: bare fuser can hang indefinitely on some VMs / proc-net quirks (systemctl start then times out).
ExecStartPre=-/bin/sh -c 'command -v fuser >/dev/null && timeout 8 fuser -k ${BACKEND_PORT}/tcp 2>/dev/null || true'
ExecStart=${VENV_PY} ${REPO}/backend/app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${UNIT}"
systemctl restart "${UNIT}"

echo "Installed ${UNIT}. Status:"
systemctl --no-pager status "${UNIT}" || true
echo ""
echo "Logs: journalctl -u ${UNIT} -f"
