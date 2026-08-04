#!/bin/bash
# Quick test helper: source MRHIS.sh (without executing main) and parse args
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Ensure we use the repo copy
# shellcheck disable=SC1090
. "${SCRIPT_DIR}/MRHIS.sh"

# Call parse_args for a typical invocation and then apply overrides
parse_args --DEMO --rhis --gittea --reconfigure
apply_cli_overrides

# Print a concise set of variables relevant to the example
cat <<EOF
Parsed CLI/test variables (after parse_args + apply_cli_overrides):
  CLI_DEMO=${CLI_DEMO:-}
  CLI_MRHIS=${CLI_MRHIS:-}
  CLI_GITTEA=${CLI_GITTEA:-}
  CLI_RECONFIGURE=${CLI_RECONFIGURE:-}
  DEMO_MODE=${DEMO_MODE:-}
  NONINTERACTIVE=${NONINTERACTIVE:-}
  RUN_ONCE=${RUN_ONCE:-}
  MENU_CHOICE=${MENU_CHOICE:-}
  FORCE_PROMPT_ALL=${FORCE_PROMPT_ALL:-}
EOF
