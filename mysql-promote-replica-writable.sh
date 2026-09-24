#!/usr/bin/env bash
# Run on the REPLICA host (e.g. Bhavna) when the PRIMARY (e.g. Ravi) is down and
# this machine must accept application WRITES.
#
# Usage (on that machine):
#   sudo bash milestone4/mysql-promote-replica-writable.sh
#
# After this: point the Flask backend DB_HOST at this host (composer menu 8 → Bhavna, then 9).
# When the old primary returns, avoid two writers — re-sync or keep one node read-only.
set -euo pipefail

echo "[*] Stopping replication and clearing read-only (MySQL failover promote)..."

sudo mysql -e "STOP REPLICA;" 2>/dev/null || sudo mysql -e "STOP SLAVE;" 2>/dev/null || true
sudo mysql -e "RESET REPLICA ALL;" 2>/dev/null || sudo mysql -e "RESET SLAVE ALL;" 2>/dev/null || true
sudo mysql -e "SET GLOBAL super_read_only = OFF;" 2>/dev/null || true
sudo mysql -e "SET GLOBAL read_only = OFF;"

echo "[✓] This server should accept writes if schema and GRANTs (e.g. it490) are present."
echo "    Verify: SHOW REPLICA STATUS; (empty) — SELECT @@read_only, @@super_read_only;"
