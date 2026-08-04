#!/usr/bin/env bash
set -euo pipefail
# Wrapper to call terminator_launcher with a default node set or user-provided list.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="${SCRIPT_DIR}/terminator_launcher.sh"
if [ ! -x "${LAUNCHER}" ]; then
    echo "Launcher not found or not executable: ${LAUNCHER}" >&2
    exit 2
fi

if [ "$#" -eq 0 ]; then
    exec "${LAUNCHER}"
else
    exec "${LAUNCHER}" "$@"
fi
