#!/usr/bin/env bash
set -euo pipefail

ENV_YML=${ENV_YML:-/home/sgallego/.ansible/conf/env.yml}
VAULT_PASS=${VAULT_PASS:-/home/sgallego/.ansible/conf/.vaultpass.txt}
SSH_KEY=${SSH_KEY:-/home/sgallego/.ssh/minirhis-installer/id_rsa}
REMOTE_HOST=${REMOTE_HOST:-root@10.168.128.2}
DEMO_REMOTE=${DEMO_REMOTE:-/home/admin/ansible-automation-platform-containerized-setup-bundle-2.6-8-x86_64/DEMO-inventory}

TMP_DIR=$(mktemp -d)
LOCAL_TEMPLATE="$TMP_DIR/DEMO-inventory.template"
RENDERED="$TMP_DIR/DEMO-inventory.rendered"

echo "Fetching remote DEMO-inventory to render locally (will fall back to local template)..."
if scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$REMOTE_HOST:$DEMO_REMOTE" "$LOCAL_TEMPLATE" 2>/dev/null; then
  echo "Fetched remote DEMO-inventory into template"
else
  echo "Remote DEMO-inventory not available; trying local template"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  LOCAL_CANDIDATE="${SCRIPT_DIR}/local/vars/external_inventory/aap/DEMO-inventory.j2"
  if [ -f "${LOCAL_CANDIDATE}" ]; then
    cp "${LOCAL_CANDIDATE}" "$LOCAL_TEMPLATE"
    echo "Using local template: ${LOCAL_CANDIDATE}"
  else
    echo "No local DEMO-inventory.j2 found at ${LOCAL_CANDIDATE}; aborting."
    exit 2
  fi
fi

if [[ -f "$ENV_YML" && -f "$VAULT_PASS" ]] && command -v ansible-vault >/dev/null 2>&1; then
  tmpenv=$(mktemp)
  ansible-vault view "$ENV_YML" --vault-password-file "$VAULT_PASS" > "$tmpenv"
else
  echo "Vault not available; aborting render."
  exit 2
fi

cp "$LOCAL_TEMPLATE" "$RENDERED"

# gather placeholders and build mapping file
placeholders=$(grep -o '{{[^}]*}}' "$LOCAL_TEMPLATE" || true | sed 's/[{}]//g' | sed -e 's/|.*//' -e 's/\s//g' | sort -u)
MAPPING="$TMP_DIR/mapping.txt"
: > "$MAPPING"
for ph in $placeholders; do
  ph_clean=$(echo "$ph" | sed 's/[^A-Za-z0-9_]/_/g' | tr '[:upper:]' '[:lower:]')
  val=$(grep -iE "^$ph_clean:|^${ph_clean//_/-}:|^${ph_clean//_/.}:" "$tmpenv" | head -n1 | sed -E 's/^[^:]+:\s*//') || true
  if [[ -z "$val" ]]; then
    val=$(grep -iE "^admin_pass:|^admin_password:|^postgresql_admin_password:|^rh_offline_token:|^rh_pass:|^rh_user:" "$tmpenv" | head -n1 | sed -E 's/^[^:]+:\s*//') || true
  fi
  if [[ -n "$val" ]]; then
    # strip surrounding quotes
    val=$(echo "$val" | sed "s/^['\"]//; s/['\"]$//")
    # encode value to base64 to avoid shell quoting issues
    b64=$(printf '%s' "$val" | base64 -w0)
    printf '%s\t%s\n' "$ph" "$b64" >> "$MAPPING"
  fi
done

# apply mappings via Python to handle arbitrary characters safely
python3 - "$LOCAL_TEMPLATE" "$RENDERED" "$MAPPING" <<'PY'
import sys,base64,re
tpl = sys.argv[1]
out = sys.argv[2]
mapf = sys.argv[3]
with open(mapf) as f:
  pairs = [line.strip().split('\t',1) for line in f if line.strip()]
with open(tpl,'r') as f:
  text = f.read()
for ph,b64 in pairs:
  val = base64.b64decode(b64.encode()).decode('utf-8')
  pattern = re.compile(r"\{\{\s*" + re.escape(ph) + r"\s*\}\}")
  text = pattern.sub(val, text)
with open(out,'w') as f:
  f.write(text)
print('Rendered file written')
PY

# ensure admin_user default is resolved
perl -0777 -pe "s/\{%?\s*\{?\s*admin_user\s*\|\s*default\('admin'\)\s*\}?\s*\}?/admin/g" -i "$RENDERED" || true

echo "Uploading rendered inventory to remote host..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$RENDERED" "$REMOTE_HOST:$DEMO_REMOTE"

rm -rf "$TMP_DIR" "$tmpenv"
echo "Render and upload complete."
