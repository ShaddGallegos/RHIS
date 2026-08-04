#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
ANSIBLE_ENV_FILE="${ANSIBLE_ENV_FILE:-$ANSIBLE_ENV_DIR/env.yml}"
SAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="$SAMPLE_DIR/env.yml.SAMPLE"

usage() {
    cat <<EOF
Usage: $0 [--force]

Copies tools/env.yml.SAMPLE to ${ANSIBLE_ENV_FILE} and optionally encrypts it with ansible-vault.
EOF
}

FORCE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1"; usage; exit 1 ;;
    esac
done

if [ ! -f "$SAMPLE" ]; then
    echo "Sample not found: $SAMPLE" >&2
    exit 1
fi

mkdir -p "$ANSIBLE_ENV_DIR" && chmod 700 "$ANSIBLE_ENV_DIR"

if [ -f "$ANSIBLE_ENV_FILE" ] && [ "$FORCE" -ne 1 ]; then
    echo "${ANSIBLE_ENV_FILE} already exists. Use --force to overwrite." >&2
    exit 1
fi

cp -f "$SAMPLE" "$ANSIBLE_ENV_FILE"
chmod 600 "$ANSIBLE_ENV_FILE"

cat <<EOF
Wrote sample env to: ${ANSIBLE_ENV_FILE}
Edit this file and replace placeholders (especially AAP_ADMIN_PASS/ADMIN_PASS),
then either encrypt it with ansible-vault or leave plaintext for quick testing.

To encrypt with an existing vault password file:
  ansible-vault encrypt --vault-password-file ${ANSIBLE_ENV_DIR}/.vaultpass.text ${ANSIBLE_ENV_FILE}

To create a vault password file interactively, run this script and choose to encrypt.
EOF

# Offer encryption if ansible-vault available
if command -v ansible-vault >/dev/null 2>&1; then
    read -r -p "Encrypt ${ANSIBLE_ENV_FILE} with ansible-vault now? [y/N]: " resp
    case "${resp,,}" in
        y|yes)
            VAULT_PASS_FILE="${ANSIBLE_ENV_DIR}/.vaultpass.text"
            if [ ! -f "$VAULT_PASS_FILE" ]; then
                echo "Creating vault password file at $VAULT_PASS_FILE"
                while true; do
                    read -s -r -p "Enter new vault password: " p1; echo
                    read -s -r -p "Confirm vault password: " p2; echo
                    if [ "$p1" != "$p2" ]; then
                        echo "Passwords do not match; try again." >&2
                    else
                        printf '%s\n' "$p1" > "$VAULT_PASS_FILE"
                        chmod 600 "$VAULT_PASS_FILE"
                        break
                    fi
                done
            fi
            ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" "$ANSIBLE_ENV_FILE"
            echo "Encrypted ${ANSIBLE_ENV_FILE} using ${VAULT_PASS_FILE}"
            ;;
        *) echo "Left ${ANSIBLE_ENV_FILE} plaintext." ;;
    esac
else
    echo "ansible-vault not found; left ${ANSIBLE_ENV_FILE} plaintext. Install ansible-core to encrypt."
fi
