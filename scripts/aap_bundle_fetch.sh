#!/usr/bin/env bash
set -euo pipefail

# Fetch AAP installer bundle with resilient Red Hat SSO token handling.
# Usage: scripts/aap_bundle_fetch.sh -u <download-url> -o <out-path> [--user USER --pass PASS]
# Environment variables accepted:
#   RH_USER, RH_PASS, RH_OFFLINE_TOKEN, TOKEN_ENDPOINT, CLIENT_ID, REFRESH_CLIENT_ID,
#   VAULT_PASS_FILE, ENV_YML, TOKEN_CACHE_FILE
# Defaults:
#   ENV_YML=${HOME}/.ansible/conf/env.yml
#   VAULT_PASS_FILE=${HOME}/.ansible/conf/.vaultpass.txt
#   TOKEN_CACHE_FILE=${HOME}/.cache/minirhis/aap_access_token.cache

usage(){
  grep '^#' "$0" | sed 's/^#//'
  exit 1
}

OUT=""
URL=""
RH_USER="${RH_USER:-}"
RH_PASS="${RH_PASS:-}"
TOKEN_ENDPOINT="${TOKEN_ENDPOINT:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"
CLIENT_ID="${CLIENT_ID:-openshift}"
REFRESH_CLIENT_ID="${REFRESH_CLIENT_ID:-cloud-services}"
ENV_YML="${ENV_YML:-${HOME}/.ansible/conf/env.yml}"
VAULT_PASS_FILE="${VAULT_PASS_FILE:-${HOME}/.ansible/conf/.vaultpass.txt}"
TOKEN_CACHE_FILE="${TOKEN_CACHE_FILE:-${HOME}/.cache/minirhis/aap_access_token.cache}"
TOKEN_LOCK_FILE="${TOKEN_CACHE_FILE}.lock"

HTTP_CODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url) URL="$2"; shift 2;;
    -o|--out) OUT="$2"; shift 2;;
    --user) RH_USER="$2"; shift 2;;
    --pass) RH_PASS="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$URL" || -z "$OUT" ]]; then
  echo "Missing required arguments." >&2
  usage
fi

mkdir -p "$(dirname "$OUT")"
mkdir -p "$(dirname "$TOKEN_CACHE_FILE")"

try_validate(){
  local f="$1"
  # Accept .tar.gz and plain .tar outputs, reject html/text responses.
  local mime
  mime=$(file --brief --mime-type "$f" 2>/dev/null || true)
  case "$mime" in
    application/gzip|application/x-gzip|application/x-tar|application/octet-stream) ;;
    *) return 1 ;;
  esac

  if tar -tzf "$f" >/dev/null 2>&1; then
    return 0
  fi
  if tar -tf "$f" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

now_epoch(){ date +%s; }

read_cache(){
  if [[ -f "$TOKEN_CACHE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$TOKEN_CACHE_FILE" || true
  fi
}

write_cache(){
  local token="$1"
  local exp_epoch="$2"
  umask 077
  {
    printf "access_token='%s'\n" "$token"
    printf "exp_epoch='%s'\n" "$exp_epoch"
  } > "$TOKEN_CACHE_FILE"
}

extract_json_field(){
  local json="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${field} // empty"
  else
    printf '%s' "$json" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
  fi
}

extract_json_number(){
  local json="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${field} // empty"
  else
    printf '%s' "$json" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p"
  fi
}

read_offline_token(){
  local offline="${RH_OFFLINE_TOKEN:-}"
  if [[ -n "$offline" ]]; then
    printf '%s' "$offline"
    return 0
  fi

  if [[ -f "$ENV_YML" && -f "$VAULT_PASS_FILE" ]] && command -v ansible-vault >/dev/null 2>&1; then
    offline=$(ansible-vault view "$ENV_YML" --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null | sed -n 's/^rh_offline_token:[[:space:]]*\("\{0,1\}\)\(.*\)\1$/\2/p' | tr -d '"') || true
    printf '%s' "$offline"
    return 0
  fi

  printf ''
}

read_rh_user_pass(){
  if [[ -n "$RH_USER" && -n "$RH_PASS" ]]; then
    return 0
  fi
  if [[ -f "$ENV_YML" && -f "$VAULT_PASS_FILE" ]] && command -v ansible-vault >/dev/null 2>&1; then
    echo "Attempting to read RH_USER/RH_PASS from $ENV_YML using ansible-vault"
    RH_USER=$(ansible-vault view "$ENV_YML" --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null | sed -n 's/^rh_user:[[:space:]]*\(.*\)$/\1/p' | tr -d '"') || true
    RH_PASS=$(ansible-vault view "$ENV_YML" --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null | sed -n 's/^rh_pass:[[:space:]]*\(.*\)$/\1/p' | tr -d '"') || true
  fi
}

token_request_refresh(){
  local offline="$1"
  local cid="$2"
  curl -sSL "$TOKEN_ENDPOINT" \
    --data-urlencode "grant_type=refresh_token" \
    --data-urlencode "refresh_token=${offline}" \
    --data-urlencode "client_id=${cid}" \
    --data-urlencode "scope=openid offline_access"
}

token_request_password(){
  curl -sSL "$TOKEN_ENDPOINT" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "username=${RH_USER}" \
    --data-urlencode "password=${RH_PASS}" \
    --data-urlencode "scope=openid offline_access" \
    --data-urlencode "client_id=${CLIENT_ID}"
}

obtain_access_token(){
  local force_refresh="${1:-0}"
  local current now token exp response expires_in offline token_err token_err_desc cid

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$TOKEN_LOCK_FILE"
    flock -x 9
  fi

  read_cache
  current="${access_token:-}"
  exp="${exp_epoch:-0}"
  now=$(now_epoch)

  if [[ "$force_refresh" != "1" && -n "$current" && "$exp" =~ ^[0-9]+$ && "$exp" -gt $((now + 60)) ]]; then
    printf '%s' "$current"
    return 0
  fi

  # Preferred path: refresh/offline token grant
  offline=$(read_offline_token)
  if [[ -n "$offline" ]]; then
    for cid in "$REFRESH_CLIENT_ID" "$CLIENT_ID" rhsm-api; do
      [[ -n "$cid" ]] || continue
      echo "Requesting access token via refresh_token grant (client_id=${cid})"
      response=$(token_request_refresh "$offline" "$cid")
      token=$(extract_json_field "$response" access_token)
      expires_in=$(extract_json_number "$response" expires_in)
      if [[ -n "$token" ]]; then
        if [[ -z "$expires_in" || ! "$expires_in" =~ ^[0-9]+$ ]]; then
          expires_in=900
        fi
        exp=$((now + expires_in))
        write_cache "$token" "$exp"
        printf '%s' "$token"
        return 0
      fi
      token_err=$(extract_json_field "$response" error)
      token_err_desc=$(extract_json_field "$response" error_description)
      if [[ -n "$token_err" || -n "$token_err_desc" ]]; then
        echo "refresh_token grant failed for client_id=${cid}: ${token_err:-unknown_error} ${token_err_desc:-}" >&2
      fi
    done
  fi

  # Fallback path: password grant
  read_rh_user_pass
  if [[ -n "$RH_USER" && -n "$RH_PASS" ]]; then
    echo "Requesting access token via password grant"
    response=$(token_request_password)
    token=$(extract_json_field "$response" access_token)
    expires_in=$(extract_json_number "$response" expires_in)
    if [[ -n "$token" ]]; then
      if [[ -z "$expires_in" || ! "$expires_in" =~ ^[0-9]+$ ]]; then
        expires_in=900
      fi
      exp=$((now + expires_in))
      write_cache "$token" "$exp"
      printf '%s' "$token"
      return 0
    fi

    token_err=$(extract_json_field "$response" error)
    token_err_desc=$(extract_json_field "$response" error_description)
    if [[ -n "$token_err" || -n "$token_err_desc" ]]; then
      echo "password grant failed: ${token_err:-unknown_error} ${token_err_desc:-}" >&2
    fi
  fi

  return 1
}

download_url_with_optional_token(){
  local url="$1"
  local token="${2:-}"
  local code
  if [[ -n "$token" ]]; then
    code=$(curl -sSL -H "Authorization: Bearer $token" -H "Accept: application/octet-stream" -o "$OUT" -w "%{http_code}" "$url") || return 1
  else
    code=$(curl -sSL -H "Accept: application/octet-stream" -o "$OUT" -w "%{http_code}" "$url") || return 1
  fi
  HTTP_CODE="$code"
  [[ "$code" =~ ^2[0-9][0-9]$ ]]
}

# Try plain URL first in case a signed URL is still valid.
echo "Downloading without token..."
if download_url_with_optional_token "$URL" ""; then
  if try_validate "$OUT"; then
    echo "Downloaded valid bundle to $OUT"
    exit 0
  fi
  echo "Plain download returned non-archive content (HTTP $HTTP_CODE)."
else
  echo "Plain download failed (HTTP ${HTTP_CODE:-unknown})."
fi

TOKEN=""
if TOKEN=$(obtain_access_token 0); then
  echo "Downloading with token..."
  if download_url_with_optional_token "$URL" "$TOKEN"; then
    if try_validate "$OUT"; then
      echo "Downloaded valid bundle to $OUT using access token"
      exit 0
    fi
    baseurl="${URL%%\?*}"
    if [[ "$baseurl" != "$URL" ]]; then
      echo "Token-auth download returned non-archive content; retrying base URL."
      if download_url_with_optional_token "$baseurl" "$TOKEN" && try_validate "$OUT"; then
        echo "Downloaded valid bundle to $OUT using access token and base URL"
        exit 0
      fi
    fi
  fi

  # Retry once after forced refresh on 401 or invalid body from expired token usage.
  if [[ "${HTTP_CODE:-}" == "401" ]]; then
    echo "Received 401; forcing token refresh and retrying once."
    TOKEN=$(obtain_access_token 1) || true
    if [[ -n "$TOKEN" ]] && download_url_with_optional_token "$URL" "$TOKEN" && try_validate "$OUT"; then
      echo "Downloaded valid bundle to $OUT after token refresh"
      exit 0
    fi
  fi
else
  echo "Could not obtain an access token via refresh_token or password grant."
fi
# Last-resort attempt: some endpoints accept the offline token directly as a
# bearer token. Try that before giving up so users with a valid offline token
# stored in the vault get a chance to download the bundle without interactive
# flows.
offline=$(read_offline_token)
if [[ -n "$offline" ]]; then
  echo "Attempting download using offline token as Bearer..."
  if download_url_with_optional_token "$URL" "$offline"; then
    if try_validate "$OUT"; then
      echo "Downloaded valid bundle to $OUT using offline token (as Bearer)"
      exit 0
    fi
  fi
  echo "Offline-token attempt did not produce a valid archive (HTTP ${HTTP_CODE:-unknown})."
fi

echo "All attempts failed. The downloaded file at $OUT is likely an HTML login page or redirect."
echo "Downloaded file mime-type: $(file --brief --mime-type "$OUT" 2>/dev/null || echo unknown)"
echo "First bytes of downloaded file (sanitized):" || true
head -c 512 "$OUT" 2>/dev/null | sed -n '1,120p' || true
echo "Options: supply valid credentials (RH_USER/RH_PASS), provide a pre-authenticated URL, or manually place the tarball at the destination."
exit 2
