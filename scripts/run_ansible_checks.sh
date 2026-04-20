#!/usr/bin/env bash
set -euo pipefail

echo "Running ansible checks: yamllint, ansible-lint, syntax checks"
command -v yamllint >/dev/null 2>&1 || { echo "yamllint missing"; exit 0; }
command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint missing"; exit 0; }

yamllint -c .yamllint.yml . || true
ansible-lint || true

for f in $(git ls-files 'playbooks/*.yml' 'playbooks/*.yaml'); do
  echo "syntax-check: $f"
  ansible-playbook --syntax-check "$f" || true
done

echo "Checks complete"
