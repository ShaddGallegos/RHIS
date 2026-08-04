#!/usr/bin/env bash
set -euo pipefail

# Basic smoke tests for scripts/wait_for_ssh.sh
script="scripts/wait_for_ssh.sh"

if [ ! -f "$script" ]; then
    echo "SKIP: $script missing"
    exit 2
fi

# Syntax check
bash -n "$script"

echo "Syntax OK"

# Usage output should include 'Usage:'
out=$(bash "$script" -h 2>&1 || true)
if ! grep -q "Usage:" <<<"$out"; then
    echo "FAIL: usage not printed"
    echo "$out"
    exit 1
fi

echo "Usage printed"

echo "OK"
