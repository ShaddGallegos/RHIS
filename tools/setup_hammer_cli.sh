#!/usr/bin/env bash
set -euo pipefail

# tools/setup_hammer_cli.sh
# Centralize Hammer CLI configuration for root and admin users.

log_dir_default="/root/.hammer/log"

install -d -m 0700 /root/.hammer /etc/skel/.hammer || true
install -d -m 0700 /root/.hammer/log || true

cat > /root/.hammer/cli_config.yml <<HAMMER_CONFIG
:log_dir: '${log_dir_default}'
HAMMER_CONFIG

chmod 0600 /root/.hammer/cli_config.yml || true
install -m 0600 /root/.hammer/cli_config.yml /etc/skel/.hammer/cli_config.yml || true

# Per-wheel-group admin users
if getent group wheel >/dev/null 2>&1; then
  getent group wheel | awk -F: '{print $4}' | tr ',' '\n' | sed '/^$/d' | while read -r _wuser; do
    _home=$(getent passwd "${_wuser}" | cut -d: -f6 || echo "")
    if [ -n "${_home}" ]; then
      mkdir -p "${_home}/.hammer" "${_home}/.hammer/log" || true
      cat > "${_home}/.hammer/cli_config.yml" <<HAMMER_CONFIG_USER
:log_dir: '${_home}/.hammer/log'
HAMMER_CONFIG_USER
      chmod 0600 "${_home}/.hammer/cli_config.yml" || true
      chown -R "${_wuser}:${_wuser}" "${_home}/.hammer" >/dev/null 2>&1 || true
    fi
  done
fi

# Fallback: ensure /etc/skel has the cli_config for future users
chmod 0600 /etc/skel/.hammer/cli_config.yml || true

exit 0
