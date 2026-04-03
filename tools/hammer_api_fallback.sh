#!/usr/bin/env bash
set -euo pipefail
# Usage: hammer_api_fallback.sh <api_path> <search_expr> -- <hammer command...>
# Example:
#   tools/hammer_api_fallback.sh products 'name="MyProduct"' -- hammer product synchronize --organization "ORG"

API_PATH="$1"; shift
SEARCH_EXPR="$1"; shift

# consume the '--' separator if present
if [ "$1" = "--" ]; then
  shift
fi

HAMMER_CMD=("$@")

# Determine SAT URL and credentials from environment fallbacks
SAT_URL="${SAT_URL:-${satellite_url:-}}"
SAT_IP="${SAT_IP:-}" # optional
if [ -z "$SAT_URL" ] && [ -n "$SAT_IP" ]; then
  SAT_URL="https://$SAT_IP"
fi

# Load secrets from user-local encrypted env file if present (~/.ansible/conf/env.yml)
ENV_FILE="${HOME}/.ansible/conf/env.yml"
if [ -f "$ENV_FILE" ]; then
  # Use Python to safely parse YAML and emit shell assignments for relevant keys
  eval "$(
    python3 - "$ENV_FILE" <<'PY'
import sys,yaml,os
p=os.path.expanduser(sys.argv[1])
try:
    with open(p) as f:
        data=yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
def q(v):
    return repr(v)
if 'satellite_url' in data:
    print('SAT_URL='+q(data['satellite_url']))
if 'SAT_IP' in data and 'satellite_url' not in data and 'SAT_URL' not in data:
    print('SAT_URL='+q('https://'+data['SAT_IP']))
if 'sat_ip' in data and 'satellite_url' not in data and 'SAT_URL' not in data:
    print('SAT_URL='+q('https://'+data['sat_ip']))
if 'admin_user' in data:
    print('ADMIN_USER='+q(data['admin_user']))
if 'ADMIN_USER' in data:
    print('ADMIN_USER='+q(data['ADMIN_USER']))
if 'global_admin_password' in data:
    print('ADMIN_PASS='+q(data['global_admin_password']))
if 'admin_pass' in data:
    print('ADMIN_PASS='+q(data['admin_pass']))
if 'hammer_username' in data:
    print('HAMMER_USERNAME='+q(data['hammer_username']))
if 'hammer_password' in data:
    print('HAMMER_PASSWORD='+q(data['hammer_password']))
PY
  )"
fi

# Prefer ADMIN_USER/ADMIN_PASS, fall back to hammer-specific creds, default username to 'admin'
USER="${ADMIN_USER:-${HAMMER_USERNAME:-admin}}"
PASS="${ADMIN_PASS:-${HAMMER_PASSWORD:-}}"

if [ -z "$SAT_URL" ]; then
  echo "No SAT_URL or SAT_IP provided; running hammer fallback" >&2
  exec "${HAMMER_CMD[@]}"
fi

# URL-encode the search expression
_enc_search=$(python3 - <<PY
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
"$SEARCH_EXPR")

set +e
resp=$(curl -sS -k -u "$USER:$PASS" "$SAT_URL/api/v2/$API_PATH?search=$_enc_search" 2>/dev/null)
rc=$?
set -e

if [ $rc -ne 0 ]; then
  echo "API request failed (rc=$rc); running hammer fallback" >&2
  exec "${HAMMER_CMD[@]}"
fi

if echo "$resp" | grep -q '"total": *0'; then
  echo "Resource not found via API; running hammer fallback" >&2
  exec "${HAMMER_CMD[@]}"
else
  echo "Resource exists (API): $API_PATH?search=$SEARCH_EXPR" >&2
  exit 0
fi
