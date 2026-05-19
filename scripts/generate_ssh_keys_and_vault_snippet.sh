#!/usr/bin/env bash
# Helper: generate installer SSH keypair and print a vault-friendly YAML snippet
set -euo pipefail

OUT_DIR=${1:-$HOME/.ssh/minirhis-installer}
SNIPPET_FILE=${2:-/tmp/minirhis_ssh_keys_snippet.yml}
USERS=${3:-"admin root gittea"}

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

KEY_PRIV="$OUT_DIR/id_rsa"
KEY_PUB="$OUT_DIR/id_rsa.pub"

if [ ! -f "$KEY_PRIV" ]; then
  ssh-keygen -t rsa -b 4096 -f "$KEY_PRIV" -N "" -C "minirhis-installer@$(hostname)"
  chmod 600 "$KEY_PRIV"
  chmod 644 "$KEY_PUB"
fi

PUBKEY=$(cat "$KEY_PUB")

cat > "$SNIPPET_FILE" <<EOF
# Vault-friendly snippet: add to your $HOME/.ansible/conf/env.yml via ansible-vault
# Example: ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/conf/.vaultpass.txt ansible-vault edit ~/.ansible/conf/env.yml
rhis_ssh_installer:
  path: "$OUT_DIR"
  public_key: |
    $PUBKEY
  users:
EOF

for u in $USERS; do
  echo "    - \"$u\"" >> "$SNIPPET_FILE"
done

echo
echo "Generated keypair: $KEY_PRIV (private), $KEY_PUB (public)" >&2
echo "Vault snippet written to: $SNIPPET_FILE" >&2
echo "Add the public key to target accounts' authorized_keys via the minirhis-ssh-keys role or manually." >&2
echo
exit 0
