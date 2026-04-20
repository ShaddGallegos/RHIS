#!/usr/bin/env bash
set -euo pipefail

# Run the AAP container setup Ansible playbook and capture verbose logs.
LOG_DIR="$(pwd)/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%dT%H%M%S)
LOG_FILE="$LOG_DIR/run-aap-setup-$TS.log"

echo "Running AAP container setup playbook. Logs: $LOG_FILE"
ANSIBLE_ROLES_PATH="$(pwd)/roles" ANSIBLE_LIBRARY="$(pwd)/library" ansible-playbook -i inventory/hosts playbooks/run-aap-container-setup.yml -vvv | tee "$LOG_FILE"

echo "Playbook finished. Review $LOG_FILE for details."
