#!/usr/bin/env bash
set -euo pipefail

# Normalizes vault password aliases to the canonical aap_admin_pass value.
# The script decrypts env.yml, updates known password keys, re-encrypts, and writes back atomically.

ENV_FILE_DEFAULT="$HOME/.ansible/conf/env.yml"
VAULT_PASS_TXT="$HOME/.ansible/conf/.vaultpass.txt"
VAULT_PASS_TEXT="$HOME/.ansible/conf/.vaultpass.text"
DRY_RUN=0
ENV_FILE="$ENV_FILE_DEFAULT"
VAULT_PASS_FILE=""

usage() {
    cat <<'EOF'
Usage:
  scripts/normalize_env_password_aliases.sh [--dry-run] [--env-file PATH] [--vault-pass-file PATH]

Options:
  --dry-run              Show what would be normalized without writing changes.
  --env-file PATH        Path to vaulted env file (default: ~/.ansible/conf/env.yml).
  --vault-pass-file PATH Path to ansible-vault password file.
  -h, --help             Show this help.

Behavior:
  - Canonical source key: aap_admin_pass (fallback: admin_pass, then redhat).
  - Normalized keys:
      admin_pass
      aap_admin_pass
      sat_admin_pass
      sat_initial_admin_pass
      global_admin_password
      idm_admin_pass
      idm_ds_pass
      ipadm_password
      ipaadmin_password
      sat_compute_password
      sat_image_password
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --vault-pass-file)
            VAULT_PASS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$VAULT_PASS_FILE" ]]; then
    if [[ -s "$VAULT_PASS_TXT" ]]; then
        VAULT_PASS_FILE="$VAULT_PASS_TXT"
    elif [[ -s "$VAULT_PASS_TEXT" ]]; then
        VAULT_PASS_FILE="$VAULT_PASS_TEXT"
    else
        echo "Vault password file not found. Tried: $VAULT_PASS_TXT and $VAULT_PASS_TEXT" >&2
        exit 1
    fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "env file not found: $ENV_FILE" >&2
    exit 1
fi
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "vault password file not found: $VAULT_PASS_FILE" >&2
    exit 1
fi

KEYS=(
    admin_pass
    aap_admin_pass
    sat_admin_pass
    sat_initial_admin_pass
    global_admin_password
    idm_admin_pass
    idm_ds_pass
    ipadm_password
    ipaadmin_password
    sat_compute_password
    sat_image_password
)

TMP_DECRYPTED="$(mktemp)"
TMP_NORMALIZED="$(mktemp)"
cleanup() {
    rm -f "$TMP_DECRYPTED" "$TMP_NORMALIZED"
}
trap cleanup EXIT

ansible-vault view "$ENV_FILE" --vault-password-file "$VAULT_PASS_FILE" > "$TMP_DECRYPTED"
chmod 600 "$TMP_DECRYPTED" "$TMP_NORMALIZED"

extract_value() {
    local key="$1"
    awk -v k="$key" '
        $0 ~ "^[[:space:]]*" k ":[[:space:]]*" {
            line=$0
            sub("^[[:space:]]*" k ":[[:space:]]*\"?", "", line)
            sub("\"?[[:space:]]*$", "", line)
            print line
            exit
        }
    ' "$TMP_DECRYPTED"
}

value_from_file() {
    local key="$1"
    local file="$2"
    awk -v k="$key" '
        $0 ~ "^[[:space:]]*" k ":[[:space:]]*" {
            line=$0
            sub("^[[:space:]]*" k ":[[:space:]]*\"?", "", line)
            sub("\"?[[:space:]]*$", "", line)
            print line
            exit
        }
    ' "$file"
}

CANONICAL="$(extract_value "aap_admin_pass" || true)"
if [[ -z "$CANONICAL" ]]; then
    CANONICAL="$(extract_value "admin_pass" || true)"
fi
if [[ -z "$CANONICAL" ]]; then
    CANONICAL="redhat"
fi

KEYS_CSV="$(IFS=,; echo "${KEYS[*]}")"
awk -v canonical="$CANONICAL" -v keys_csv="$KEYS_CSV" '
    BEGIN {
        n=split(keys_csv, arr, ",")
        for (i=1; i<=n; i++) targets[arr[i]]=1
    }
    {
        if (match($0, /^[[:space:]]*([A-Za-z0-9_]+):[[:space:]]*/, m)) {
            key=m[1]
            if (key in targets) {
                match($0, /^[[:space:]]*/)
                indent=substr($0, 1, RLENGTH)
                print indent key ": \"" canonical "\""
                next
            }
        }
        print $0
    }
' "$TMP_DECRYPTED" > "$TMP_NORMALIZED"

changed=0
if ! cmp -s "$TMP_DECRYPTED" "$TMP_NORMALIZED"; then
    changed=1
fi

echo "Canonical password: $CANONICAL"
for key in "${KEYS[@]}"; do
    old_val="$(value_from_file "$key" "$TMP_DECRYPTED" || true)"
    new_val="$(value_from_file "$key" "$TMP_NORMALIZED" || true)"
    if [[ -n "$old_val" || -n "$new_val" ]]; then
        if [[ "$old_val" != "$new_val" ]]; then
            echo "  $key: $old_val -> $new_val"
        else
            echo "  $key: $new_val"
        fi
    fi
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$changed" -eq 1 ]]; then
        echo "Dry run complete: changes would be applied."
    else
        echo "Dry run complete: no changes needed."
    fi
    exit 0
fi

if [[ "$changed" -eq 0 ]]; then
    echo "No changes needed."
    exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ENV_FILE}.bak.${TS}"
cp -a "$ENV_FILE" "$BACKUP"

ansible-vault encrypt "$TMP_NORMALIZED" --vault-password-file "$VAULT_PASS_FILE"
install -m 600 "$TMP_NORMALIZED" "$ENV_FILE"

echo "Applied changes and re-encrypted env file."
echo "Backup: $BACKUP"
