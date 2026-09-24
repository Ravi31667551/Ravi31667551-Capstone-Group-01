#!/usr/bin/env bash
# Demo: continuous HTTP checks against an LB or single backend while you roll a node.
# Usage:
#   DEMO_LB_URL=http://10.67.151.x:8080/health bash demo-zero-downtime.sh
#   bash demo-zero-downtime.sh --seconds 120 --url http://127.0.0.1:8080/health
#
# During the run, restart one backend (e.g. sudo systemctl restart jobtracker-backend) or
# use composer.sh stop on one VM — success count should stay high if the other serves traffic.
set -euo pipefail

URL="${DEMO_LB_URL:-http://127.0.0.1:8080/health}"
SECONDS="${DEMO_SECONDS:-90}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url|-u)
      URL="$2"
      shift 2
      ;;
    --seconds|-s)
      SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | head -20 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "[ERROR] curl is required."
  exit 1
fi

echo "Hitting ${URL} every 0.5s for ${SECONDS}s — keep this running while you restart one backend."
echo "Expect mostly OK if load balancer + second backend are healthy."
echo ""

end=$((SECONDS * 2))
ok=0
fail=0
for ((i = 0; i < end; i++)); do
  if out=$(curl -sS -m 3 -o /dev/null -w "%{http_code}" "${URL}" 2>/dev/null); then
    if [[ "${out}" =~ ^2 ]]; then
      ok=$((ok + 1))
      printf '\rOK=%d FAIL=%d (last HTTP %s)   ' "${ok}" "${fail}" "${out}"
    else
      fail=$((fail + 1))
      printf '\rOK=%d FAIL=%d (last HTTP %s)   ' "${ok}" "${fail}" "${out}"
    fi
  else
    fail=$((fail + 1))
    printf '\rOK=%d FAIL=%d (last: connection error)   ' "${ok}" "${fail}"
  fi
  sleep 0.5
done
echo ""
echo "Done. OK=${ok} FAIL=${fail}"
