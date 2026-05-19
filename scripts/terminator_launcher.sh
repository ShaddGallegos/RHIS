#!/usr/bin/env bash
set -euo pipefail
# Launch node-specific Ansible playbooks in separate Terminator windows (or tmux/background fallback).

ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
ANSIBLE_ENV_FILE="${ANSIBLE_ENV_FILE:-${ANSIBLE_ENV_DIR}/env.yml}"
ANSIBLE_VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-${ANSIBLE_ENV_DIR}/.vaultpass.txt}"
INVENTORY="${MINIRHIS_INVENTORY_FILE:-${PWD}/local/vars/external_inventory/hosts.yml}"
LOG_DIR="${LOG_DIR:-/var/log/minirhis}"
mkdir -p "${LOG_DIR}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [node1 node2 ...]
If no nodes provided, launches: installer idm satellite aap
Each node will run its corresponding playbook under local/<node>/playbooks
EOF
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

nodes=("$@")
if [ ${#nodes[@]} -eq 0 ]; then
    nodes=(installer idm satellite aap)
fi

for node in "${nodes[@]}"; do
    playbook="local/${node}/playbooks/${node}-provision.yml"
    logfile="${LOG_DIR}/${node}-provision.$(date +%s).log"
    cmd="ansible-playbook --inventory ${INVENTORY} --vault-password-file ${ANSIBLE_VAULT_PASS_FILE} --extra-vars @${ANSIBLE_ENV_FILE} ${playbook} 2>&1 | tee ${logfile}"

    if command -v terminator >/dev/null 2>&1; then
        # Launch Terminator with a shell that runs the playbook and keeps the terminal open
        terminator -x bash -lc "${cmd}; echo; echo 'Playbook for ${node} completed. Press Enter to close.'; read -r" &
        echo "Launched terminator for ${node}, log: ${logfile}"
    elif command -v tmux >/dev/null 2>&1; then
        session="minirhis-${node}"
        tmux new-session -d -s "${session}" "bash -lc '${cmd}; echo "Playbook for ${node} completed"; sleep 2'"
        echo "Launched tmux session ${session} for ${node}, log: ${logfile}"
    else
        nohup bash -lc "${cmd}" > "${logfile}" 2>&1 &
        echo "Launched background job for ${node}, log: ${logfile}"
    fi
done

echo "All requested nodes launched. Logs in ${LOG_DIR}."
