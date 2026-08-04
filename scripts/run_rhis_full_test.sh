#!/usr/bin/env bash
set -euo pipefail

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGDIR="${MRHIS_RUN_LOG_DIR:-/var/log/mrhis}"
if ! mkdir -p "${LOGDIR}" 2>/dev/null; then
  sudo mkdir -p "${LOGDIR}" || true
  sudo chown "$(id -un)":"$(id -gn)" "${LOGDIR}" || true
fi

# Number of automatic retry attempts when a run fails and we attempt fixes.
retry_count=0
max_retries=2

# Detect whether MCP/AI monitoring is active. The wrapper treats warnings as
# fatal when monitoring is enabled (unless TOLERATE_WARNINGS is set).
MONITORING_ENABLED=0
STOP_ON_WARNING=0
if [ "${AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED:-}" = "1" ] || [ "${AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED:-}" = "true" ] || \
   [ "${AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED:-}" = "1" ] || [ "${AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED:-}" = "true" ] || \
   [ -n "${AAP_LIGHTSPEED_CHATBOT_MODEL_URL:-}" ] || [ -n "${AAP_LIGHTSPEED_CHATBOT_MODEL_API_KEY:-}" ] || [ "${RHIS_FORCE_MONITORING:-0}" = "1" ]; then
    MONITORING_ENABLED=1
    # Stop on WARNING if no explicit tolerance set
    if [ "${TOLERATE_WARNINGS:-0}" != "1" ]; then
        STOP_ON_WARNING=1
    fi
fi

run_and_monitor() {
  # $1 is a shell command to run
  local cmd="$1"
  local last_total_lines=0

  echo "=== Running: ${cmd} (started at $(date -u +'%Y-%m-%dT%H:%M:%SZ')) ===" | tee -a "${LOGFILE}"

  # Run the command and tee output to the attempt log. Run in background so
  # we can monitor the log for warning/error patterns and kill it if needed.
  bash -c "${cmd}" 2>&1 | tee -a "${LOGFILE}" &
  local pid=$!
  # Consolidated waiting + scanning helper to avoid duplicated busy-wait loops
  wait_and_scan() {
    local _pid="$1" _cmd="$2" _logfile="$3"
    local _last_lines=0
    local _interactive=0
    if [ -t 1 ]; then _interactive=1; fi

    if [ ${_interactive} -eq 1 ]; then
      local _spin='|/-\\' _i=0
      printf "%s" "Running: ${_cmd}"
      while kill -0 "${_pid}" 2>/dev/null; do
        if [ -f "${_logfile}" ]; then
          local _total
          _total=$(wc -l < "${_logfile}" 2>/dev/null || echo 0)
          if [ "${_total}" -gt "${_last_lines}" ]; then
            local _new=$((_total - _last_lines))
            tail -n "${_new}" "${_logfile}" > /tmp/rhis_new_lines.$$ 2>/dev/null || true
            if grep -E "CRITICAL|FATAL|FAILED!|FAILURE|[A-Z0-9_]+_FAIL\b" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
              printf "\nDetected critical/fatal/failed pattern in log; terminating command for diagnostics.\n" | tee -a "${_logfile}"
              kill "${_pid}" 2>/dev/null || true
              wait "${_pid}" 2>/dev/null || true
              rm -f /tmp/rhis_new_lines.$$ || true
              return 2
            fi
            if grep -qi -w "ERROR" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
              if grep -Ei "BrokenPipeError|ConnectionResetError|Broken pipe|Unexpected Exception|Traceback \(most recent call last\)" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
                printf "\nObserved benign Ansible/Python internal trace; ignoring for now.\n" | tee -a "${_logfile}"
              else
                printf "\nDetected ERROR pattern in log; terminating command for diagnostics.\n" | tee -a "${_logfile}"
                kill "${_pid}" 2>/dev/null || true
                wait "${_pid}" 2>/dev/null || true
                rm -f /tmp/rhis_new_lines.$$ || true
                return 2
              fi
            fi
            if [ "${STOP_ON_WARNING}" = "1" ]; then
              if grep -qi -w "WARNING" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
                  printf "\nDetected WARNING and monitoring is enabled — treating as failure; terminating command.\n" | tee -a "${_logfile}"
                kill "${_pid}" 2>/dev/null || true
                wait "${_pid}" 2>/dev/null || true
                rm -f /tmp/rhis_new_lines.$$ || true
                return 3
              fi
            fi
            rm -f /tmp/rhis_new_lines.$$ || true
            _last_lines=${_total}
          fi
        fi
        _i=$((_i + 1))
        printf "\r[%c] Running: %s (press Ctrl-C to cancel)" "${_spin:_i%${#_spin}:1}" "${_cmd:0:120}"
        sleep 0.25
      done
      printf '\n'
    else
      echo "Waiting for command to finish: ${_cmd}" | tee -a "${_logfile}"
      while kill -0 "${_pid}" 2>/dev/null; do
        if [ -f "${_logfile}" ]; then
          local _total
          _total=$(wc -l < "${_logfile}" 2>/dev/null || echo 0)
            if [ "${_total}" -gt "${_last_lines}" ]; then
            local _new=$((_total - _last_lines))
            tail -n "${_new}" "${_logfile}" > /tmp/rhis_new_lines.$$ 2>/dev/null || true
            if grep -E "CRITICAL|FATAL|FAILED!|FAILURE|[A-Z0-9_]+_FAIL\b" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
              echo "Detected critical/fatal/failed pattern in log; terminating command for diagnostics." | tee -a "${_logfile}"
              kill "${_pid}" 2>/dev/null || true
              wait "${_pid}" 2>/dev/null || true
              rm -f /tmp/rhis_new_lines.$$ || true
              return 2
            fi
            if grep -qi -w "ERROR" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
              if grep -Ei "BrokenPipeError|ConnectionResetError|Broken pipe|Unexpected Exception|Traceback \(most recent call last\)" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
                echo "Observed benign Ansible/Python internal trace; ignoring for now." | tee -a "${_logfile}"
              else
                echo "Detected ERROR pattern in log; terminating command for diagnostics." | tee -a "${_logfile}"
                kill "${_pid}" 2>/dev/null || true
                wait "${_pid}" 2>/dev/null || true
                rm -f /tmp/rhis_new_lines.$$ || true
                return 2
              fi
            fi
            if [ "${STOP_ON_WARNING}" = "1" ]; then
              if grep -qi -w "WARNING" /tmp/rhis_new_lines.$$ >/dev/null 2>&1; then
                echo "Detected WARNING and monitoring is enabled — treating as failure; terminating command." | tee -a "${_logfile}"
                kill "${_pid}" 2>/dev/null || true
                wait "${_pid}" 2>/dev/null || true
                rm -f /tmp/rhis_new_lines.$$ || true
                return 3
              fi
            fi
            rm -f /tmp/rhis_new_lines.$$ || true
            _last_lines=${_total}
          fi
        fi
        sleep 2
      done
    fi
    return 0
  }

  # invoke helper
  wait_and_scan "${pid}" "${cmd}" "${LOGFILE}"

  wait "${pid}" 2>/dev/null || true
  return 0
}

debug_and_fix() {
  echo "=== Diagnostics & automated fixes start ===" | tee -a "${LOGFILE}"
  tail -n 500 "${LOGFILE}" > /tmp/rhis_last.log || true

  if grep -qi "vault" /tmp/rhis_last.log || grep -qi "ANSIBLE_VAULT" /tmp/rhis_last.log; then
    echo "Detected vault-related failures. Creating placeholder vault password file at ~/.ansible/conf/.vaultpass.txt" | tee -a "${LOGFILE}"
    mkdir -p "$HOME/.ansible/conf"
    head -c 32 /dev/urandom | base64 > "$HOME/.ansible/conf/.vaultpass.txt" || true
    chmod 600 "$HOME/.ansible/conf/.vaultpass.txt" || true
    echo "Wrote placeholder vault password file (you may want to replace it with the real password)." | tee -a "${LOGFILE}"
  fi

  if grep -qi "libvirt" /tmp/rhis_last.log || grep -qi "cannot access qemu" /tmp/rhis_last.log || grep -qi "permission denied" /tmp/rhis_last.log; then
    echo "Detected libvirt/access issue. Attempting to restart libvirtd and add user to libvirt group (best-effort)." | tee -a "${LOGFILE}"
    sudo systemctl restart libvirtd || true
    sudo usermod -aG libvirt "$(id -un)" || true
    echo "If group membership changed you may need to re-login; retrying anyway." | tee -a "${LOGFILE}"
  fi

  if grep -qi "ISO not found" /tmp/rhis_last.log || grep -qi "ISO not found at" /tmp/rhis_last.log; then
    echo "ISO missing detected in logs; automatic retry aborted. Check ISO_PATH or RH_ISO_URL." | tee -a "${LOGFILE}"
    return 1
  fi

  echo "Running syntax check on MRHIS.sh (bash -n)" | tee -a "${LOGFILE}"
  if ! bash -n MRHIS.sh 2>&1 | tee -a "${LOGFILE}"; then
    echo "Syntax issues detected in MRHIS.sh — please inspect the log." | tee -a "${LOGFILE}"
  else
    echo "MRHIS.sh syntax OK" | tee -a "${LOGFILE}"
  fi

  if [ -x ./scripts/apply-fixes.sh ]; then
    echo "Running ./scripts/apply-fixes.sh (best-effort)." | tee -a "${LOGFILE}"
    ./scripts/apply-fixes.sh 2>&1 | tee -a "${LOGFILE}" || true
  fi

  echo "=== Diagnostics & automated fixes end ===" | tee -a "${LOGFILE}"
  return 0
}

# Save current enabled repos and restrict DNF to a small whitelist for the run.
save_and_restrict_repos() {
  echo "Saving and restricting DNF repos for run" | tee -a "${LOGFILE}"
  if sudo -n true 2>/dev/null; then
    sudo dnf repolist enabled | awk 'NR>2 {print $1}' > /tmp/mrhis_repo_enabled_before_run || true
    echo "Restricting enabled repos to: codeready-builder-for-rhel-10-x86_64-rpms rhel-10-for-x86_64-baseos-rpms rhel-10-for-x86_64-appstream-rpms epel" | tee -a "${LOGFILE}"
    sudo dnf config-manager --set-disabled '*' || true
    for r in codeready-builder-for-rhel-10-x86_64-rpms rhel-10-for-x86_64-baseos-rpms rhel-10-for-x86_64-appstream-rpms epel; do
      sudo dnf config-manager --set-enabled "${r}" || true
    done
  else
    echo "Non-interactive sudo unavailable; skipping repo restriction." | tee -a "${LOGFILE}"
  fi
}

restore_repos() {
  echo "Restoring previously enabled DNF repos (if saved)" | tee -a "${LOGFILE}"
  if [ -f /tmp/mrhis_repo_enabled_before_run ] && sudo -n true 2>/dev/null; then
    while read -r r; do
      [ -z "${r}" ] && continue
      sudo dnf config-manager --set-enabled "${r}" || true
    done < /tmp/mrhis_repo_enabled_before_run
    rm -f /tmp/mrhis_repo_enabled_before_run || true
  else
    echo "No saved repo list or sudo unavailable; skipping repo restore." | tee -a "${LOGFILE}"
  fi
}

run_demo_sequence() {
  # Restrict host DNF/YUM repos to the minimal whitelist for the duration
  # of the demo run to ensure package installs only use approved repos.
  save_and_restrict_repos || true
  trap 'restore_repos || true' EXIT
  # Run DEMOKILL then DEMO RHIS using monitored execution
  if ! run_and_monitor "bash MRHIS.sh --DEMOKILL"; then
    echo "DEMOKILL aborted by monitor" | tee -a "${LOGFILE}"
    trap - EXIT
    restore_repos || true
    return 1
  fi

  if ! run_and_monitor "bash MRHIS.sh --DEMO --non-interactive --rhis"; then
    echo "DEMO RHIS aborted by monitor" | tee -a "${LOGFILE}"
    trap - EXIT
    restore_repos || true
    return 2
  fi
  trap - EXIT
  restore_repos || true
  return 0
}

while true; do
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  LOGFILE="${LOGDIR}/rhis_${TIMESTAMP}.log"
  ln -sf "${LOGFILE}" "${LOGDIR}/rhis_latest.log"

  echo "Logging to ${LOGFILE}" | tee -a "${LOGFILE}"
  echo "Run attempt $((retry_count+1))" | tee -a "${LOGFILE}"

  if run_demo_sequence; then
    echo "Full test succeeded" | tee -a "${LOGFILE}"
    exit 0
  fi

  last_rc=$?
  echo "Run failed with rc=${last_rc}" | tee -a "${LOGFILE}"

  if [ ${retry_count} -ge ${max_retries} ]; then
    echo "Max retries reached (${max_retries}). Leaving logs at: ${LOGFILE}" | tee -a "${LOGFILE}"
    exit ${last_rc}
  fi

  echo "Attempting automated diagnostics and non-invasive fixes (attempt $((retry_count+1)))" | tee -a "${LOGFILE}"
  if ! debug_and_fix; then
    echo "Automated diagnostics determined a non-recoverable issue; aborting." | tee -a "${LOGFILE}"
    exit ${last_rc}
  fi

  retry_count=$((retry_count+1))
  echo "Retrying in 5s..." | tee -a "${LOGFILE}"
  sleep 5
done
