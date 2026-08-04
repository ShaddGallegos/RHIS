#!/usr/bin/env bash
# Shim to keep backward compatibility for callers expecting
# run_mrhis_install_sequence.sh while delegating logic to
# installer.yml (Ansible playbook).
set -euo pipefail

PLAYBOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK="${PLAYBOOK_DIR}/installer.yml"

VENV_ANSIBLE="${PLAYBOOK_DIR}/.venv-ansible/bin/ansible-playbook"

# Prefer a repository-local virtualenv's ansible-playbook when available,
# otherwise fall back to a system-wide ansible-playbook on PATH.
if [ -x "${VENV_ANSIBLE}" ]; then
	exec "${VENV_ANSIBLE}" "${PLAYBOOK}" "$@"
elif command -v ansible-playbook >/dev/null 2>&1; then
	exec ansible-playbook "$PLAYBOOK" "$@"
else
	echo "ansible-playbook not found; either activate the repo virtualenv:" >&2
	echo "  source ${PLAYBOOK_DIR}/.venv-ansible/bin/activate" >&2
	echo "or install Ansible system-wide (see README.md)." >&2
	exit 1
fi
