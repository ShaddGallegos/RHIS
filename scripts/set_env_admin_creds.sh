#!/usr/bin/env bash
set -euo pipefail

# Update vaulted env.yml with admin/aap/idm credentials.
# Usage examples:
#  tools/set_env_admin_creds.sh --admin-user admin --admin-pass secret --aap-pass secret --idm-pass secret
#  tools/set_env_admin_creds.sh --dry-run --admin-user admin --admin-pass secret

ENV_FILE_DEFAULT="$HOME/.ansible/conf/env.yml"
VAULT_PASS_DEFAULT="$HOME/.ansible/conf/.vaultpass.txt"
ENV_FILE="$ENV_FILE_DEFAULT"
VAULT_PASS_FILE=""
DRY_RUN=0
ADMIN_USER=""
ADMIN_PASS=""
AAP_PASS=""
IDM_PASS=""

usage() {
    cat <<'EOF'
Usage: set_env_admin_creds.sh [options]

Options:
  --env-file PATH           Path to vaulted env file (default: ~/.ansible/conf/env.yml)
  --vault-pass-file PATH    Path to ansible-vault password file (default: ~/.ansible/conf/.vaultpass.txt)
  --admin-user USER         Set admin_user in env.yml
  --admin-pass PASSWORD     Set admin_pass in env.yml (will not echo if omitted; script will prompt)
  --aap-pass PASSWORD       Set aap_admin_pass in env.yml (defaults to admin_pass when omitted)
  --idm-pass PASSWORD       Set idm_admin_pass in env.yml (defaults to aap/admin pass when omitted)
  --dry-run                 Show what would change without writing
  -h, --help                Show this help
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
        --admin-user)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --admin-user" >&2; usage >&2; exit 2; fi
            ADMIN_USER="$2"; shift 2;;
        --admin-pass)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --admin-pass" >&2; usage >&2; exit 2; fi
            ADMIN_PASS="$2"; shift 2;;
        --aap-pass)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --aap-pass" >&2; usage >&2; exit 2; fi
            AAP_PASS="$2"; shift 2;;
        --idm-pass)
            if [[ $# -lt 2 || "$2" == --* ]]; then echo "Missing value for --idm-pass" >&2; usage >&2; exit 2; fi
            IDM_PASS="$2"; shift 2;;
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

if [[ -z "$ADMIN_PASS" ]]; then
    # prompt silently if user requested changes but didn't pass pass via CLI
    if [[ -n "$ADMIN_USER" || -n "$AAP_PASS" || -n "$IDM_PASS" ]]; then
        echo -n "Enter admin password (will not echo, leave empty to skip setting): " >&2
        read -rs ADMIN_PASS; echo >&2
    fi
fi

if [[ -z "$AAP_PASS" && -n "$ADMIN_PASS" ]]; then
    AAP_PASS="$ADMIN_PASS"
fi
if [[ -z "$IDM_PASS" && -n "$AAP_PASS" ]]; then
    IDM_PASS="$AAP_PASS"
fi

TMP_DEC=$(mktemp)
TMP_MOD=$(mktemp)
TMP_JSON=$(mktemp)
cleanup() { rm -f "$TMP_DEC" "$TMP_MOD" "$TMP_JSON"; }
trap cleanup EXIT

ansible-vault view "$ENV_FILE" --vault-password-file "$VAULT_PASS_FILE" > "$TMP_DEC"

# Export shell vars so Python can read them via the environment
export ADMIN_USER ADMIN_PASS AAP_PASS IDM_PASS

# Create JSON payload from environment (does not use here-doc to avoid parser edge-cases)
python3 -c 'import json,os,sys; d={};
au=os.getenv("ADMIN_USER");
ap=os.getenv("ADMIN_PASS");
aa=os.getenv("AAP_PASS");
idp=os.getenv("IDM_PASS");
if au: d["admin_user"]=au
if ap: d["admin_pass"]=ap
if aa: d["aap_admin_pass"]=aa
if idp: d["idm_admin_pass"]=idp
sys.stdout.write(json.dumps(d))' > "$TMP_JSON"

# Merge decrypted env.yml with payload and produce normalized YAML (read decrypted file explicitly)
python3 -c 'import sys,yaml,json
payload=json.load(open(sys.argv[1]))
orig=open(sys.argv[2]).read()
try:
    data=yaml.safe_load(orig) or {}
except Exception:
    data={}
for k,v in payload.items():
    if v is not None and v != "":
        data[k]=v
sys.stdout.write(yaml.safe_dump(data, default_flow_style=False))' "$TMP_JSON" "$TMP_DEC" > "$TMP_MOD"

changed=0
for key in admin_user admin_pass aap_admin_pass idm_admin_pass; do
    old=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_DEC" || true)
    new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
    if [[ "$old" != "$new" ]]; then changed=1; fi
done

if [[ $DRY_RUN -eq 1 ]]; then
    if [[ $changed -eq 0 ]]; then
        echo "No changes needed (dry-run)."
    else
        echo "Changes that would be applied:";
        for key in admin_user admin_pass aap_admin_pass idm_admin_pass; do
            old=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_DEC" || true)
            new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
            if [[ -n "$new" ]]; then
                masked_new=$(printf '%s' "$new" | sed -E 's/./*/g')
            else
                masked_new="(unset)"
            fi
            echo "  $key: $old -> $masked_new"
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

ansible-vault encrypt "$TMP_MOD" --vault-password-file "$VAULT_PASS_FILE"
install -m 600 "$TMP_MOD" "$ENV_FILE"

echo "Updated vaulted env file: $ENV_FILE"
echo "Backup saved: $BACKUP"
echo "Updated keys:"
for key in admin_user admin_pass aap_admin_pass idm_admin_pass; do
    new=$(awk -v k="$key" '$0 ~ "^[[:space:]]*"k":" {sub("^[[:space:]]*"k"[[:space:]]*:[[:space:]]*\"?", "", $0); sub("\"?[[:space:]]*$", "", $0); print $0; exit}' "$TMP_MOD" || true)
    if [[ -n "$new" ]]; then
        masked=$(printf '%s' "$new" | sed -E 's/./*/g')
        echo "  $key: $masked"
    fi
done

exit 0
