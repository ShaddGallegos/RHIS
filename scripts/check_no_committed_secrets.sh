#!/usr/bin/env bash
# Lightweight check for plaintext secrets in tracked files.
# Exit 1 if potential secrets are found.
set -euo pipefail

patterns=(
  "password"
  "passwd"
  "token"
  "api_key"
  "apikey"
  "BEGIN RSA PRIVATE KEY"
  "BEGIN PRIVATE KEY"
  "PRIVATE KEY"
)

echo "Scanning tracked files for potential plaintext secrets..."
found=0
for p in "${patterns[@]}"; do
  if git grep -n --no-color -I -E "$p" -- ':!*.md' -- ':!:log/' >/dev/null 2>&1; then
    echo "Potential matches for pattern: $p"
    git grep -n --no-color -I -E "$p" -- ':!*.md' -- ':!:log/' || true
    found=1
  fi
done

if [ "$found" -ne 0 ]; then
  echo "Potential plaintext secrets found in tracked files. Please review and remove/secure them before committing."
  exit 1
fi

echo "No obvious plaintext secrets found in tracked files (MD & log files excluded)."
exit 0
