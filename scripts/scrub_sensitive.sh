#!/usr/bin/env bash
set -euo pipefail
# Move detected sensitive runtime artifacts into a local tmp stash and replace
# them with small placeholder files so accidental `git add .` won't capture secrets.
# This script is idempotent and safe to run locally before commits.

TS=$(date -u +%Y%m%dT%H%M%SZ)
STASH_DIR="/tmp/mrhis_sensitive_${TS}"
mkdir -p "$STASH_DIR"

echo "Stashing sensitive files to $STASH_DIR"

declare -a PATTERNS=(
  "artifacts_user"
  "log"
  "logs"
  "server_facts"
  "server_diagnostics"
  "host_vars"
  "local/vars/vault"
  "local/vars/ssh/id_rsa"
  "local/vars/ssh/id_rsa.pub"
  "local/vars/ssh/known_hosts"
  "local/vars/external_inventory/hosts.generated"
  "*.pem"
  "*.key"
  "*.crt"
  "*.csr"
  "*.log"
)

for p in "${PATTERNS[@]}"; do
  # find matches under repo root
  while IFS= read -r -d $'\0' file; do
    rel=$(realpath --relative-to="$PWD" "$file" 2>/dev/null || echo "$file")
    target="$STASH_DIR/$(basename "$rel")"
    echo "Moving $rel -> $target"
    mkdir -p "$(dirname "$target")"
    mv "$file" "$target"
    # create a lightweight placeholder to keep layout but no secrets
    mkdir -p "$(dirname "$rel")"
    echo "This file was moved to $target on $(date -u)" > "$rel.placeholder"
  done < <(find . -path './.git' -prune -o -name "$(basename "$p")" -print0)
done

echo "Stash complete. Review $STASH_DIR and secure/delete as needed."
