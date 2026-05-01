#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 REALM [VAULT_PASSWORD_FILE]"
  echo
  echo "Examples:" 
  echo "  $0 EXAMPLE.COM --ask-vault-pass"
  echo "  $0 EXAMPLE.COM /path/to/.vaultpass"
  exit 2
fi

REALM="$1"
VAULT_PASS_FILE="${2:-}"

if [ -n "$VAULT_PASS_FILE" ]; then
  ansible-playbook playbooks/add-realm-to-env.yml -i localhost, -c local -e "realm=${REALM}" -e "vault_password_file=${VAULT_PASS_FILE}"
else
  ansible-playbook playbooks/add-realm-to-env.yml -i localhost, -c local -e "realm=${REALM}" --ask-vault-pass
fi
