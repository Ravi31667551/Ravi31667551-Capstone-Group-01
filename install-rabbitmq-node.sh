#!/usr/bin/env bash
# Install RabbitMQ. Cluster join is manual (cookie + hostname must match team).
# Usage:
#   sudo bash install-rabbitmq-node.sh
# Then follow README.md on seed node vs joining nodes.
set -euo pipefail
if ! command -v rabbitmqctl >/dev/null 2>&1; then
  echo "[*] Installing rabbitmq-server..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y rabbitmq-server
fi
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
rabbitmq-plugins enable rabbitmq_management 2>/dev/null || true
echo "[✓] RabbitMQ installed and running."
echo ""
echo "Next steps (every node must share the SAME .erlang.cookie):"
echo "  1. On SEED node (Bhavna): sudo cat /var/lib/rabbitmq/.erlang.cookie"
echo "  2. On THIS node: sudo systemctl stop rabbitmq-server"
echo "  3. echo 'PASTE_COOKIE' | sudo tee /var/lib/rabbitmq/.erlang.cookie"
echo "  4. sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie && sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie"
echo "  5. sudo bash milestone4/add-cluster-hosts.sh   # short names resolve"
echo "  6. sudo systemctl start rabbitmq-server"
echo "  7. On joiner: sudo rabbitmqctl stop_app && sudo rabbitmqctl join_cluster rabbit@rabbit1 && sudo rabbitmqctl start_app"
echo "  8. sudo rabbitmqctl cluster_status"
