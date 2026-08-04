#!/usr/bin/env bash
set -euo pipefail

# Update vaulted env.yml with installer/ansible connection details.
# Usage examples:
#  scripts/set_env_ansible_user.sh --installer-user admin --ansible-user admin --ansible-pass redhat --ansible-become-pass redhat
#  scripts/set_env_ansible_user.sh --dry-run --installer-user admin

ENV_FILE_DEFAULT="$HOME/.ansible/conf/env.yml"
VAULT_PASS_DEFAULT="$HOME/.ansible/conf/.vaultpass.txt"
ENV_FILE="$ENV_FILE_DEFAULT"
VAULT_PASS_FILE=""
DRY_RUN=0
INSTALLER_USER=""
ANSIBLE_USER=""
ANSIBLE_PASS=""
ANSIBLE_BECOME_PASS=""

usage() {
    cat <<'EOF'
Usage: set_env_ansible_user.sh [options]

Options:
  --env-file PATH             Path to vaulted env file (default: ~/.ansible/conf/env.yml)
  --vault-pass-file PATH      Path to ansible-vault password file (default: ~/.ansible/conf/.vaultpass.txt)
  --installer-user USER       Set installer_user in env.yml
  --ansible-user USER         Set ansible_user in env.yml
  --ansible-pass PASSWORD     Set ansible_password in env.yml
  --ansible-become-pass PASS  Set ansible_become_password in env.yml
  --dry-run                   Show what would change without writing
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --env-file" >&2; usage >&2; exit 2; fi
            ENV_FILE="$2"; shift 2;;
        --vault-pass-file)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --vault-pass-file" >&2; usage >&2; exit 2; fi
            VAULT_PASS_FILE="$2"; shift 2;;
        --installer-user)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --installer-user" >&2; usage >&2; exit 2; fi
            INSTALLER_USER="$2"; shift 2;;
        --ansible-user)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --ansible-user" >&2; usage >&2; exit 2; fi
            ANSIBLE_USER="$2"; shift 2;;
        --ansible-pass)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --ansible-pass" >&2; usage >&2; exit 2; fi
            ANSIBLE_PASS="$2"; shift 2;;
        --ansible-become-pass)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --ansible-become-pass" >&2; usage >&2; exit 2; fi
            ANSIBLE_BECOME_PASS="$2"; shift 2;;
        --dry-run)
            DRY_RUN=1; shift;;
        -h|--help)
            usage; exit 0;;
        *)
            echo "Unknown arg: $1" >&2; usage >&2; exit 1;;
    esac
done

if [[ -z "$VAULT_PASS_FILE" ]]; then
    VAULT_PASS_FILE="$VAULT_PASS_DEFAULT"
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "env file not found: $ENV_FILE" >&2
    exit 1
fi
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "vault password file not found: $VAULT_PASS_FILE" >&2
    exit 1
fi

TMP_DEC=$(mktemp)
TMP_MOD=$(mktemp)
TMP_JSON=$(mktemp)
cleanup() { rm -f "$TMP_DEC" "$TMP_MOD" "$TMP_JSON"; }
trap cleanup EXIT

ANSIBLE_VAULT_CMD="$(command -v ansible-vault 2>/dev/null || true)"
if [[ -z "$ANSIBLE_VAULT_CMD" ]]; then
    echo "ansible-vault not found in PATH" >&2; exit 1
fi

# Decrypt
"$ANSIBLE_VAULT_CMD" view "$ENV_FILE" --vault-password-file "$VAULT_PASS_FILE" > "$TMP_DEC" || { echo "Failed to decrypt $ENV_FILE" >&2; exit 1; }

# Export vars so Python subprocess can read them via the environment
export INSTALLER_USER ANSIBLE_USER ANSIBLE_PASS ANSIBLE_BECOME_PASS

# Create JSON payload from supplied args
python3 - <<PY > "$TMP_JSON"
import json, os
payload={}
if os.getenv('INSTALLER_USER'):
    payload['installer_user']=os.getenv('INSTALLER_USER')
if os.getenv('ANSIBLE_USER'):
    payload['ansible_user']=os.getenv('ANSIBLE_USER')
if os.getenv('ANSIBLE_PASS'):
    payload['ansible_password']=os.getenv('ANSIBLE_PASS')
if os.getenv('ANSIBLE_BECOME_PASS'):
    payload['ansible_become_password']=os.getenv('ANSIBLE_BECOME_PASS')
print(json.dumps(payload))
PY

# Merge decrypted YAML with payload and produce normalized YAML
python3 - "$TMP_JSON" "$TMP_DEC" <<PY > "$TMP_MOD"
import sys, yaml, json
payload=json.load(open(sys.argv[1]))
orig=open(sys.argv[2]).read()
try:
    data=yaml.safe_load(orig) or {}
except Exception:
    data={}
for k,v in payload.items():
    if v is not None and v != "":
        data[k]=v
sys.stdout.write(yaml.safe_dump(data, default_flow_style=False))
PY

changed=0
for key in installer_user ansible_user ansible_password ansible_become_password; do
    old=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_DEC" || true)
    new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
    if [[ "$old" != "$new" ]]; then changed=1; fi
done

if [[ $DRY_RUN -eq 1 ]]; then
    if [[ $changed -eq 0 ]]; then
        echo "No changes needed (dry-run)."
    else
        echo "Changes that would be applied:";
        for key in installer_user ansible_user ansible_password ansible_become_password; do
            old=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_DEC" || true)
            new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
            if [[ -n "$new" ]]; then
                masked_new=$(printf '%s' "$new" | sed -E 's/./*/g')
            else
                masked_new="(unset)"
            fi
            echo "  $key: ${old:-'(unset)'} -> $masked_new"
        done
    fi
    exit 0
fi

if [[ $changed -eq 0 ]]; then
    echo "No changes needed."
    exit 0
fi

TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${ENV_FILE}.bak.${TS}"
cp -a "$ENV_FILE" "$BACKUP"

"$ANSIBLE_VAULT_CMD" encrypt "$TMP_MOD" --vault-password-file "$VAULT_PASS_FILE"
install -m 600 "$TMP_MOD" "$ENV_FILE"

echo "Updated vaulted env file: $ENV_FILE"
echo "Backup saved: $BACKUP"
for key in installer_user ansible_user ansible_password ansible_become_password; do
    new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
    if [[ -n "$new" ]]; then
        masked=$(printf '%s' "$new" | sed -E 's/./*/g')
        echo "  $key: $masked"
    fi
done

exit 0
