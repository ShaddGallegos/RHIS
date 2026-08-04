#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_PLAYBOOK_CMD="${ANSIBLE_PLAYBOOK_CMD:-ansible-playbook}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-${SCRIPT_DIR}/../local/vars/external_inventory/hosts.yml}"
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-${HOME}/.ansible/conf/.vaultpass.txt}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|podman|sudoers]

  podman   - Run rootless Podman remediation locally (localhost)
  sudoers  - Fix guest sudoers snippet across inventory (hosts in inventory)
  all      - Run both (podman then sudoers)

Options (via env): ANSIBLE_PLAYBOOK_CMD, ANSIBLE_INVENTORY, ANSIBLE_VAULT_PASS_FILE
EOF
}

if [ "$#" -gt 1 ]; then
  usage
  exit 1
fi

mode="${1:-all}"

run_playbook() {
  local pb="$1"
  local inv_opt="$2"
  local -a inv_args=()
  if [ -n "${inv_opt:-}" ]; then
    IFS=' ' read -r -a inv_args <<< "$inv_opt"
  fi
  local -a vault_opt=()
  if [ -f "$VAULT_PASS_FILE" ]; then
    vault_opt=("--vault-password-file" "$VAULT_PASS_FILE")
  fi
  echo "Running: $ANSIBLE_PLAYBOOK_CMD ${inv_args[*]} $pb"
  "$ANSIBLE_PLAYBOOK_CMD" "${inv_args[@]:-}" "$pb" "${vault_opt[@]:-}"
}

case "$mode" in
  podman)
    run_playbook "$(dirname "$SCRIPT_DIR")/playbooks/remediate-rootless-podman.yml" ""
    ;;
  sudoers)
    run_playbook "$(dirname "$SCRIPT_DIR")/playbooks/fix-guest-sudoers.yml" "-i $ANSIBLE_INVENTORY"
    ;;
  all)
    run_playbook "$(dirname "$SCRIPT_DIR")/playbooks/remediate-rootless-podman.yml" ""
    run_playbook "$(dirname "$SCRIPT_DIR")/playbooks/fix-guest-sudoers.yml" "-i $ANSIBLE_INVENTORY"
    ;;
  *)
    usage
    exit 1
    ;;
esac

exit 0
