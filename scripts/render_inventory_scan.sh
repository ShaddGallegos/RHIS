#!/usr/bin/env bash
set -euo pipefail
# Safely scan remote DEMO-inventory for Jinja placeholders and check vaulted env.yml
# Outputs files under /tmp with placeholder, found, and missing lists.

ENV_YML=${ENV_YML:-/home/sgallego/.ansible/conf/env.yml}
VAULT_PASS=${VAULT_PASS:-/home/sgallego/.ansible/conf/.vaultpass.txt}
SSH_KEY=${SSH_KEY:-/home/sgallego/.ssh/minirhis-installer/id_rsa}
REMOTE_HOST=${REMOTE_HOST:-root@10.168.128.2}
DEMO_REMOTE=${DEMO_REMOTE:-/home/admin/ansible-automation-platform-containerized-setup-bundle-2.6-8-x86_64/DEMO-inventory}

OUT_DIR=/tmp/minirhis_inventory_scan_$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT_DIR"

echo "Scanning remote DEMO-inventory for placeholders..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" $REMOTE_HOST "grep -o '{{[^}]*}}' $DEMO_REMOTE || true" \
  | sed 's/[{}]//g' | sed -e 's/|.*//' -e 's/\s//g' | sort -u > "$OUT_DIR/placeholders.txt"

echo "Checking vaulted env.yml for matches (no secrets will be printed)..."
: > "$OUT_DIR/found.txt"
: > "$OUT_DIR/missing.txt"

if [[ -f "$ENV_YML" && -f "$VAULT_PASS" ]] && command -v ansible-vault >/dev/null 2>&1; then
  tmpenv=$(mktemp)
  ansible-vault view "$ENV_YML" --vault-password-file "$VAULT_PASS" > "$tmpenv"
  while IFS= read -r ph; do
    [[ -z "$ph" ]] && continue
    ph_clean=$(echo "$ph" | sed 's/[^A-Za-z0-9_]/_/g' | tr '[:upper:]' '[:lower:]')
    if grep -iE "^$ph_clean:|^${ph_clean//_/-}:|^${ph_clean//_/.}:" "$tmpenv" >/dev/null 2>&1; then
      echo "$ph" >> "$OUT_DIR/found.txt"
    else
      # check some common aliases
      if grep -iE "^admin_pass:|^admin_password:|^postgresql_admin_password:|^rh_offline_token:|^rh_pass:|^rh_user:" "$tmpenv" >/dev/null 2>&1; then
        echo "$ph" >> "$OUT_DIR/found.txt"
      else
        echo "$ph" >> "$OUT_DIR/missing.txt"
      fi
    fi
  done < "$OUT_DIR/placeholders.txt"
  rm -f "$tmpenv"
else
  # vault not available; everything missing
  cp "$OUT_DIR/placeholders.txt" "$OUT_DIR/missing.txt" || true
fi

echo "Scan complete. Output directory: $OUT_DIR"
echo "Placeholders:"
sed -n '1,200p' "$OUT_DIR/placeholders.txt" || true
echo
echo "Found (in vault):"
sed -n '1,200p' "$OUT_DIR/found.txt" || true
echo
echo "Missing (needs prompting):"
sed -n '1,200p' "$OUT_DIR/missing.txt" || true

exit 0
