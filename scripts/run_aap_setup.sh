#!/usr/bin/env bash
set -euo pipefail

# Run the AAP container setup Ansible playbook and capture verbose logs.
LOG_DIR="${LOG_DIR:-/var/log/mrhis}"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%dT%H%M%S)
LOG_FILE="$LOG_DIR/run-aap-setup-$TS.log"

echo "Running AAP container setup playbook. Logs: $LOG_FILE"

# If a bundle directory is provided, try to auto-detect Redis-related vars
# and add sensible demo overrides so single-node installs succeed.
BUNDLE_DIR="${BUNDLE_DIR:-}"
EXTRA_VARS=()
if [[ -n "$BUNDLE_DIR" && -d "$BUNDLE_DIR" ]]; then
	if grep -Rq "redis_mode" "$BUNDLE_DIR" 2>/dev/null; then
		EXTRA_VARS+=( -e "redis_mode=standalone" )
	elif grep -Rq "redis_cluster" "$BUNDLE_DIR" 2>/dev/null; then
		EXTRA_VARS+=( -e "redis_cluster=false" )
	fi
fi

ANSIBLE_ROLES_PATH="$(pwd)/roles" ANSIBLE_LIBRARY="$(pwd)/library" ansible-playbook -i inventory/hosts playbooks/run-aap-container-setup.yml "${EXTRA_VARS[@]}" -vvv | tee "$LOG_FILE"

echo "Playbook finished. Review $LOG_FILE for details."
