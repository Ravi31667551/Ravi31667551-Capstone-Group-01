#!/usr/bin/env bash
# Unified log viewer for Capstone Group 01 components.
# Shows service status + recent logs for MySQL, RabbitMQ, MySQL Router, backend,
# and frontend helpers.
#
# Usage:
#   bash scripts/show-system-logs.sh
#   bash scripts/show-system-logs.sh --follow
#   bash scripts/show-system-logs.sh --lines 200

set -euo pipefail

LINES=80
FOLLOW=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow|-f)
      FOLLOW=1
      shift
      ;;
    --lines|-n)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      LINES="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--follow|-f] [--lines|-n <count>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--follow|-f] [--lines|-n <count>]"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

print_section() {
  echo
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

show_service_status() {
  local unit="$1"
  if systemctl list-unit-files | awk '{print $1}' | rg -q "^${unit}$"; then
    systemctl --no-pager --full status "$unit" || true
  else
    echo "[i] ${unit} not installed on this host."
  fi
}

show_journal() {
  local unit="$1"
  local title="$2"
  print_section "$title"
  if systemctl list-unit-files | awk '{print $1}' | rg -q "^${unit}$"; then
    journalctl -u "$unit" -n "$LINES" --no-pager || true
  else
    echo "[i] ${unit} not installed on this host."
  fi
}

show_file_log() {
  local log_file="$1"
  local title="$2"
  print_section "$title"
  if [[ -f "$log_file" ]]; then
    sed -n "1,${LINES}p" "$log_file" | tail -n "$LINES"
  else
    echo "[i] Missing: ${log_file}"
  fi
}

print_section "CAPSTONE COMPONENT STATUS ($(date))"
echo "Repo: ${REPO_ROOT}"

print_section "SYSTEMD STATUS"
show_service_status "mysql.service"
show_service_status "rabbitmq-server.service"
show_service_status "mysqlrouter.service"
show_service_status "jobtracker-backend.service"

show_journal "mysql.service" "MYSQL JOURNAL (last ${LINES} lines)"
show_journal "rabbitmq-server.service" "RABBITMQ JOURNAL (last ${LINES} lines)"
show_journal "mysqlrouter.service" "MYSQL ROUTER JOURNAL (last ${LINES} lines)"
show_journal "jobtracker-backend.service" "BACKEND JOURNAL (last ${LINES} lines)"

show_file_log "/tmp/frontend.log" "FRONTEND LOG (/tmp/frontend.log)"
show_file_log "/tmp/frontendbe_php.log" "RISHU PHP LOG (/tmp/frontendbe_php.log)"
show_file_log "/tmp/frontendbe_py.log" "RISHU BACKEND LOG (/tmp/frontendbe_py.log)"

print_section "BACKEND RUN.SH USER LOGS"
if compgen -G "/tmp/backenddb-*.log" >/dev/null; then
  for f in /tmp/backenddb-*.log; do
    show_file_log "$f" "BACKEND USER LOG (${f})"
  done
else
  echo "[i] No /tmp/backenddb-*.log files found."
fi

if [[ "$FOLLOW" -eq 1 ]]; then
  print_section "LIVE FOLLOW MODE (Ctrl+C to stop)"
  echo "[*] Following journal for mysql, rabbitmq-server, mysqlrouter, jobtracker-backend..."
  journalctl -f -u mysql.service -u rabbitmq-server.service -u mysqlrouter.service -u jobtracker-backend.service
fi
