#!/usr/bin/env bash
set -euo pipefail

# Append a small pointer to the top-level README into all tracked README.md files
# so readers can find the headless noninteractive test and vault guidance.

REPO_ROOT=$(git rev-parse --show-toplevel)
PTR_TEXT="Headless Noninteractive Test (developer)"

git ls-files -- "*README.md" | while IFS= read -r f; do
  # skip if pointer already present
  if grep -qF "$PTR_TEXT" "$f" 2>/dev/null; then
    continue
  fi
  printf "\n## Headless Test & Vault\n\nSee the top-level README 'Headless Noninteractive Test (developer)' for the noninteractive test command and vault guidance.\n" >> "$f"
  echo "Updated: $f"
done

echo "README bulk-update complete."
