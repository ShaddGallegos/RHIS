#!/usr/bin/env bash
set -euo pipefail
# Import a Satellite manifest ZIP using either the API (tries both /katello/api/v2 and /api/v2)
# or the hammer CLI as a fallback. Safe to run non-interactively.

ENV_FILE="${HOME}/.ansible/conf/env.yml"
ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
DEST_DIR="/var/lib/libvirt/images/files"
DEFAULT_VAULT_PASS_FILE="${ANSIBLE_ENV_DIR}/.vaultpass.txt"

usage() {
    cat <<EOF
Usage: $0 [--file /path/to/manifest.zip] [--org ORG]
Reads credentials from environment or ${ENV_FILE} if present.
EOF
    exit 1
}

FILE=""
ORG_OVERRIDE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --file) FILE="$2"; shift 2;;
        --org) ORG_OVERRIDE="$2"; shift 2;;
        -h|--help) usage;;
        *) echo "Unknown arg: $1"; usage;;
    esac
done

# Load minimal creds from env.yml if present
if [ -f "${ENV_FILE}" ]; then
    EFFECTIVE_VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-}"
    if [ -z "${EFFECTIVE_VAULT_PASS_FILE}" ] && [ -f "${DEFAULT_VAULT_PASS_FILE}" ]; then
        EFFECTIVE_VAULT_PASS_FILE="${DEFAULT_VAULT_PASS_FILE}"
    fi
    # Support encrypted ansible-vault files if vault password file is available
    if head -n1 "${ENV_FILE}" 2>/dev/null | grep -q "ANSIBLE_VAULT"; then
        if [ -n "${EFFECTIVE_VAULT_PASS_FILE}" ] && [ -f "${EFFECTIVE_VAULT_PASS_FILE}" ]; then
            YAML_CONTENT=$(ansible-vault view --vault-password-file "${EFFECTIVE_VAULT_PASS_FILE}" "${ENV_FILE}" 2>/dev/null || true)
        else
            YAML_CONTENT=$(ansible-vault view "${ENV_FILE}" 2>/dev/null || true)
        fi
    else
        YAML_CONTENT=$(cat "${ENV_FILE}")
    fi
    if [ -n "${YAML_CONTENT}" ]; then
        eval "$(printf '%s' "${YAML_CONTENT}" | python3 - <<'PY'
import sys,yaml
try:
    d=yaml.safe_load(sys.stdin.read()) or {}
except Exception:
    sys.exit(0)
def q(v):
    return repr(v)
if 'satellite_url' in d:
    print('SAT_URL='+q(d['satellite_url']))
if 'sat_ip' in d and 'satellite_url' not in d:
    print('SAT_URL='+q('https://'+d['sat_ip']))
if 'admin_user' in d:
    print('ADMIN_USER='+q(d['admin_user']))
if 'admin_pass' in d:
    print('ADMIN_PASS='+q(d['admin_pass']))
if 'SAT_HOSTNAME' in d and 'satellite_url' not in d:
    print('SAT_URL='+q('https://'+d.get('SAT_HOSTNAME')))
if 'admin_user' in d and 'ADMIN_USER' not in d:
    print('ADMIN_USER='+q(d.get('admin_user')))
if 'admin_pass' in d and 'ADMIN_PASS' not in d:
    print('ADMIN_PASS='+q(d.get('admin_pass')))
if 'sat_org' in d:
    print('SAT_ORG='+q(d['sat_org']))
if 'satellite_organization' in d:
    print('SAT_ORG='+q(d['satellite_organization']))
if 'SAT_ORG' in d:
    print('SAT_ORG='+q(d.get('SAT_ORG')))
PY
        )"
    fi
fi

SAT_URL="${SAT_URL:-${satellite_url:-}}"
ADMIN_USER="${ADMIN_USER:-${admin_user:-admin}}"
ADMIN_PASS="${ADMIN_PASS:-${admin_pass:-}}"
SAT_ORG="${ORG_OVERRIDE:-${SAT_ORG:-${sat_org:-}}}"

# Fallback parsing from raw YAML text for common lowercase keys
if [ -n "${YAML_CONTENT:-}" ]; then
    if [ -z "${SAT_URL:-}" ]; then
        sat_ip_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^sat_ip:' | head -1 | sed -E 's/^[0-9]+:sat_ip:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        sat_host_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^sat_hostname:' | head -1 | sed -E 's/^[0-9]+:sat_hostname:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        if [ -n "${sat_host_raw}" ]; then
            SAT_URL="https://${sat_host_raw}"
        elif [ -n "${sat_ip_raw}" ]; then
            SAT_URL="https://${sat_ip_raw}"
        fi
    fi
    if [ -z "${ADMIN_USER:-}" ]; then
        admin_user_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^admin_user:' | head -1 | sed -E 's/^[0-9]+:admin_user:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        if [ -n "${admin_user_raw}" ]; then
            ADMIN_USER="${admin_user_raw}"
        fi
    fi
    if [ -z "${ADMIN_PASS:-}" ]; then
        admin_pass_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^admin_pass:' | head -1 | sed -E 's/^[0-9]+:admin_pass:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        if [ -n "${admin_pass_raw}" ]; then
            ADMIN_PASS="${admin_pass_raw}"
        fi
    fi
    if [ -z "${SAT_ORG:-}" ]; then
        sat_org_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^sat_org:' | head -1 | sed -E 's/^[0-9]+:sat_org:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        if [ -n "${sat_org_raw}" ]; then
            SAT_ORG="${sat_org_raw}"
        fi
    fi
    if [ -z "${FILE}" ]; then
        sat_manifest_path_raw=$(printf '%s' "${YAML_CONTENT}" | grep -nEi '^sat_manifest_path:' | head -1 | sed -E 's/^[0-9]+:sat_manifest_path:[[:space:]]*"?([^" ]+)"?.*/\1/') || true
        if [ -n "${sat_manifest_path_raw}" ]; then
            FILE="${sat_manifest_path_raw}"
        fi
    fi
fi

# Determine source manifest
if [ -n "${FILE}" ]; then
    SOURCE_PATH="${FILE}"
elif [ -f "${ANSIBLE_ENV_DIR}/manifest.zip" ]; then
    SOURCE_PATH="${ANSIBLE_ENV_DIR}/manifest.zip"
else
    SOURCE_PATH="$(ls -1t ${HOME}/Downloads/manifest*.zip 2>/dev/null | head -1 || true)"
    if [ -z "${SOURCE_PATH}" ]; then
        SOURCE_PATH="$(ls -1t ${HOME}/Downloads/*.zip 2>/dev/null | head -1 || true)"
    fi
    if [ -z "${SOURCE_PATH}" ] && [ -d "/var/lib/libvirt/images" ]; then
        SOURCE_PATH="$(ls -1t /var/lib/libvirt/images/manifest*.zip 2>/dev/null | head -1 || true)"
        if [ -z "${SOURCE_PATH}" ]; then
            SOURCE_PATH="$(ls -1t /var/lib/libvirt/images/*.zip 2>/dev/null | head -1 || true)"
        fi
    fi
fi

if [ -z "${SOURCE_PATH}" ] || [ ! -f "${SOURCE_PATH}" ]; then
    echo "No manifest found (looked in ${ANSIBLE_ENV_DIR}, ${HOME}/Downloads, /var/lib/libvirt/images)."
    exit 2
fi

mkdir -p "${DEST_DIR}" >/dev/null 2>&1 || true
if cp -f "${SOURCE_PATH}" "${DEST_DIR}/" 2>/dev/null; then
    TARGET="${DEST_DIR}/$(basename "${SOURCE_PATH}")"
    echo "Staged manifest: ${TARGET}"
elif command -v sudo >/dev/null 2>&1 && sudo -n mkdir -p "${DEST_DIR}" >/dev/null 2>&1 && sudo -n cp -f "${SOURCE_PATH}" "${DEST_DIR}/" >/dev/null 2>&1; then
    TARGET="${DEST_DIR}/$(basename "${SOURCE_PATH}")"
    echo "Staged manifest with sudo: ${TARGET}"
else
    TARGET="${SOURCE_PATH}"
    echo "Info: cannot copy to ${DEST_DIR} (permission denied). Using source manifest: ${TARGET}"
fi

# Resolve SAT_URL fallback from env var SAT_IP if needed
if [ -z "${SAT_URL}" ] && [ -n "${SAT_IP:-}" ]; then
    SAT_URL="https://${SAT_IP}"
fi

if [ -z "${SAT_URL}" ]; then
    echo "No Satellite URL found in environment or ${ENV_FILE}. Will attempt hammer fallback if available."
fi

posted=0
if [ -n "${SAT_URL}" ] && [ -n "${ADMIN_USER}" ] && [ -n "${ADMIN_PASS}" ]; then
    # Preferred flow for Satellite/Katello: upload under an organization context.
    # Try to discover organization ID from SAT_ORG name when provided, or use first org.
    ORG_ID=""
    ORG_JSON=""
    for pref in "/katello/api/v2" "/api/v2"; do
        ORG_JSON=$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL}${pref}/organizations" 2>/dev/null || true)
        if [ -n "${ORG_JSON}" ]; then
            break
        fi
    done

    if [ -n "${ORG_JSON}" ]; then
        if [ -n "${SAT_ORG}" ]; then
            ORG_ID=$(printf '%s' "${ORG_JSON}" | python3 -c '
import json,sys
name = sys.argv[1]
try:
    data=json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit
orgs = data.get("results") if isinstance(data, dict) else []
for o in orgs or []:
    if str(o.get("name", "")).strip() == name.strip():
        print(o.get("id", ""))
        break
else:
    print("")
' "${SAT_ORG}")
        else
            ORG_ID=$(printf '%s' "${ORG_JSON}" | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit
orgs = data.get("results") if isinstance(data, dict) else []
if orgs:
    print(orgs[0].get("id", ""))
else:
    print("")
')
        fi
    fi

    if [ -n "${ORG_ID}" ]; then
        for pref in "/katello/api/v2" "/api/v2"; do
            url="${SAT_URL}${pref}/organizations/${ORG_ID}/subscriptions/upload"
            echo "Attempting org-scoped API upload to ${url}"
            code=$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" -F "content=@${TARGET}" -o /dev/null -w '%{http_code}' "${url}" || true)
            echo "  HTTP ${code}"
            if echo "${code}" | grep -qE '^20[0-3]$'; then
                echo "Manifest uploaded via Satellite API (${pref})"
                posted=1
                break
            fi
        done
    elif [ -n "${SAT_ORG}" ]; then
        echo "Warning: could not resolve organization id for SAT_ORG='${SAT_ORG}', trying legacy endpoints..."
    fi

    if [ "${posted}" -ne 1 ]; then
        # Legacy endpoints retained for compatibility with older workflows.
        for pref in "/katello/api/v2" "/api/v2"; do
            url="${SAT_URL}${pref}/manifest_imports"
            echo "Attempting legacy API upload to ${url}"
            code=$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" -F "file=@${TARGET}" -o /dev/null -w '%{http_code}' "${url}" || true)
            echo "  HTTP ${code}"
            if echo "${code}" | grep -qE '^20[1-3]$'; then
                echo "Manifest uploaded via Satellite API (${pref})"
                posted=1
                break
            fi
        done
    fi
fi

if [ "${posted}" -ne 1 ]; then
    if command -v hammer >/dev/null 2>&1; then
        if [ -z "${SAT_ORG}" ]; then
            echo "hammer available but SAT_ORG not set; please provide --org or set sat_org in ${ENV_FILE}."
            exit 4
        fi
        echo "Attempting hammer CLI upload..."
        if hammer subscription upload_manifest --organization="${SAT_ORG}" --file="${TARGET}" 2>/dev/null; then
            echo "Manifest uploaded via hammer"
            exit 0
        else
            echo "hammer upload failed"
            exit 5
        fi
    else
        echo "Manifest upload via API failed and hammer CLI not available. Please import ${TARGET} in Satellite web UI or ensure credentials are set."
        exit 6
    fi
fi

exit 0
