#!/bin/bash
set -euo pipefail

# =========================
# IT490 SSH Key Setup - Group 01
# Run this ONCE on EVERY team machine.
# =========================

KEY="$HOME/.ssh/master_composer"
PUB="$KEY.pub"

echo "=================================="
echo "  IT490 SSH Setup - Group 01"
echo "=================================="
echo ""

# 1. Generate master_composer key if missing
if [ ! -f "$KEY" ]; then
  echo "[1] Generating SSH key: $KEY"
  ssh-keygen -t rsa -b 4096 -C "capstone-group01-$(hostname)" -N "" -f "$KEY"
  echo "    Done."
else
  echo "[1] Key already exists: $KEY"
fi

echo ""
echo "[2] YOUR PUBLIC KEY — share this with ALL teammates:"
echo "    ─────────────────────────────────────────────────"
cat "$PUB"
echo "    ─────────────────────────────────────────────────"
echo ""
echo "    Each teammate runs this on their machine to add your key:"
echo "      echo '<paste key>' >> ~/.ssh/authorized_keys"
echo "      chmod 600 ~/.ssh/authorized_keys"
echo ""

# 3. Add a teammate's key to this machine
echo "[3] Add a teammate's public key to THIS machine"
echo "    Paste their key, press ENTER, then CTRL+D."
echo "    Press CTRL+C to skip."
echo ""

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

TMPFILE=$(mktemp)
echo -n "    Paste now: "
if cat > "$TMPFILE" 2>/dev/null; then
  if [ -s "$TMPFILE" ]; then
    if grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2)' "$TMPFILE"; then
      cat "$TMPFILE" >> ~/.ssh/authorized_keys
      echo "    Added to ~/.ssh/authorized_keys ✓"
    else
      echo "    (Skipped — does not look like an SSH public key)"
    fi
  else
    echo "    (Skipped — no input)"
  fi
fi
rm -f "$TMPFILE"

echo ""
echo "[4] Testing SSH connectivity to team machines..."
echo "    (Uses $KEY)"
echo ""

SSH_KEY="$HOME/.ssh/master_composer"
SSH_OPTS="-i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=4"

declare -A SERVERS=(
  ["frontend    10.67.151.133"]="dhayasagar"
  ["frontendbe  10.67.151.212"]="vboxuser"
  ["rabbitmq    10.67.151.114"]="bhavnasahai3"
  ["mysql       10.67.151.166"]="ravi"
)

for entry in "${!SERVERS[@]}"; do
  name=$(echo "$entry" | awk '{print $1}')
  ip=$(echo "$entry"   | awk '{print $2}')
  user="${SERVERS[$entry]}"

  if [[ "$ip" == "CHANGE_ME" || "$user" == "CHANGE_ME" ]]; then
    echo "    [ ? ] $name — not configured yet (fill in composer.sh)"
    continue
  fi

  if ssh $SSH_OPTS -n "$user@$ip" "echo ok" &>/dev/null; then
    echo "    [ ✓ ] $name ($user@$ip) — SSH OK"
  else
    echo "    [ ✗ ] $name ($user@$ip) — SSH FAILED"
    echo "          Ask them to add your public key (step 2 above)"
  fi
done

echo ""
echo "=================================="
echo "  When ALL machines show ✓, run:"
echo "    ./composer.sh"
echo "=================================="
