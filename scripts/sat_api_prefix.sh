#!/usr/bin/env bash
set -euo pipefail
# Usage: sat_api_prefix.sh <api_path>
API_PATH="${1:-}"
USER="${ADMIN_USER:-${HAMMER_USERNAME:-admin}}"
PASS="${ADMIN_PASS:-${HAMMER_PASSWORD:-}}"
SAT_URL="${SAT_URL:-${satellite_url:-}}"
SAT_IP="${SAT_IP:-}"
if [ -z "$SAT_URL" ] && [ -n "$SAT_IP" ]; then
  SAT_URL="https://$SAT_IP"
fi
if [ -z "$SAT_URL" ]; then
  echo "/api/v2"
  exit 0
fi
# Try katello first, then core /api/v2
for pref in "/katello/api/v2" "/api/v2"; do
  set +e
  code=$(curl -s -k -u "${USER}:${PASS}" -o /dev/null -w "%{http_code}" "${SAT_URL}${pref}/${API_PATH}" || true)
  set -e
  if [[ "$code" =~ ^2 ]]; then
    echo "$pref"
    exit 0
  fi
done
# Default to katello path if detection inconclusive
echo "/katello/api/v2"
exit 0
