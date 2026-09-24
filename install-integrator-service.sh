#!/usr/bin/env bash
# Install systemd unit for the FE–BE RabbitMQ integrator (fe-be/integration.py).
# When jobtracker-backend is also enabled on this host, systemd starts the integrator first (Before=).
# Run on ONE VM (usually the same host as primary Flask) so one bridge consumes fe.login / fe.registration.
#
#   sudo bash install-integrator-service.sh
#
# Requires: backend/venv (pika), repo root .env with RABBITMQ_*.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/fe-be/integration.py" ]]; then
  REPO="$SCRIPT_DIR"
else
  REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
if [[ ! -f "${REPO}/fe-be/integration.py" ]]; then
  echo "Cannot find fe-be/integration.py (REPO=${REPO})"
  exit 1
fi

UNIT="jobtracker-integrator.service"
ACTUAL_USER="${SUDO_USER:-$USER}"
VENV_PY="${REPO}/backend/venv/bin/python"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo to install under /etc/systemd/system/"
  exit 1
fi

echo "[install-integrator] repo=${REPO} user=${ACTUAL_USER}"

if [[ ! -x "$VENV_PY" ]]; then
  echo "[install-integrator] Creating venv (may take 1–2 min on slow networks)..."
  sudo -u "$ACTUAL_USER" python3 -m venv "${REPO}/backend/venv"
  echo "[install-integrator] pip install -r backend/requirements.txt ..."
  sudo -u "$ACTUAL_USER" "${REPO}/backend/venv/bin/pip" install -r "${REPO}/backend/requirements.txt"
  echo "[install-integrator] venv ready."
fi

if [[ ! -f "${REPO}/.env" ]]; then
  echo "Warning: ${REPO}/.env missing — copy .env.example first."
fi

# Quoted heredoc so Restart=on-failure is never parsed by bash as separate words/substitutions.
UNIT_TMP="$(mktemp)"
trap 'rm -f "${UNIT_TMP}"' EXIT
cat >"${UNIT_TMP}" <<'EOSYSTEMD'
[Unit]
Description=JobTracker FE–BE integrator (fe.login / fe.registration bridge)
After=network-online.target
Before=jobtracker-backend.service
Wants=network-online.target

[Service]
Type=simple
User=__ACTUAL_USER__
Group=__ACTUAL_USER__
WorkingDirectory=__REPO__
EnvironmentFile=-__REPO__/.env
Environment=PYTHONUNBUFFERED=1
ExecStart=__VENV_PY__ __REPO__/fe-be/integration.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOSYSTEMD
sed -e "s|__ACTUAL_USER__|${ACTUAL_USER}|g" \
    -e "s|__REPO__|${REPO}|g" \
    -e "s|__VENV_PY__|${VENV_PY}|g" \
    "${UNIT_TMP}" >"/etc/systemd/system/${UNIT}"
rm -f "${UNIT_TMP}"
trap - EXIT

echo "[install-integrator] Writing unit OK; daemon-reload..."
systemctl daemon-reload
echo "[install-integrator] enable ${UNIT}"
systemctl enable "${UNIT}"
echo "[install-integrator] restart ${UNIT} (--no-block avoids dbus hang on some VMs)"
systemctl restart --no-block "${UNIT}"
sleep 2

echo "Installed ${UNIT}. Status:"
systemctl --no-pager status "${UNIT}" || true
echo ""
echo "Journal (use sudo if you see \"not seeing messages from other users\"): journalctl -u ${UNIT} -f"
echo "Same lines as manual python run (log + audit file): tail -f ${REPO}/logs/fe-be-integrator.log"
