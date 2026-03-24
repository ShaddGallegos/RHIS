#!/bin/bash
# shellcheck disable=SC2317

set -e

echo ==========================================
echo 'RHIS Installation Sequence'
echo ==========================================

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'

# Best practice: use /var/lib/libvirt/images for all ISO/disk files
ISO_DIR="${ISO_DIR:-/var/lib/libvirt/images}"
ISO_NAME="${ISO_NAME:-rhel-10-everything-x86_64-dvd.iso}"
ISO_PATH="${ISO_PATH:-$ISO_DIR/$ISO_NAME}"
SAT_ISO_NAME="${SAT_ISO_NAME:-rhel-9-everything-x86_64-dvd.iso}"
SAT_ISO_PATH="${SAT_ISO_PATH:-$ISO_DIR/$SAT_ISO_NAME}"
RH_TOKEN_URL="${RH_TOKEN_URL:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"
RH_OSINFO="${RH_OSINFO:-linux2024}"
SAT_RH_OSINFO="${SAT_RH_OSINFO:-rhel9.0}"
VM_DIR="${VM_DIR:-/var/lib/libvirt/images}"
KS_DIR="${KS_DIR:-/var/lib/libvirt/images/kickstarts}"
OEMDRV_ISO="${OEMDRV_ISO:-$ISO_DIR/OEMDRV.iso}"
ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
ANSIBLE_ENV_FILE="${ANSIBLE_ENV_FILE:-$ANSIBLE_ENV_DIR/env.yml}"
# Canonical vault password file location used by RHIS.
# Keep this fixed so all playbook/manual rerun paths remain consistent.
ANSIBLE_VAULT_PASS_FILE="${HOME}/.ansible/conf/.vaultpass.txt"
RHIS_ANSIBLE_CFG_BASENAME="${RHIS_ANSIBLE_CFG_BASENAME:-rhis-ansible.cfg}"
RHIS_ANSIBLE_CFG_HOST="${RHIS_ANSIBLE_CFG_HOST:-$ANSIBLE_ENV_DIR/${RHIS_ANSIBLE_CFG_BASENAME}}"
RHIS_ANSIBLE_CFG_CONTAINER="${RHIS_ANSIBLE_CFG_CONTAINER:-/rhis/vars/vault/${RHIS_ANSIBLE_CFG_BASENAME}}"
RHIS_ANSIBLE_FACT_CACHE_BASENAME="${RHIS_ANSIBLE_FACT_CACHE_BASENAME:-facts-cache}"
RHIS_ANSIBLE_FACT_CACHE_HOST="${RHIS_ANSIBLE_FACT_CACHE_HOST:-$ANSIBLE_ENV_DIR/${RHIS_ANSIBLE_FACT_CACHE_BASENAME}}"
RHIS_ANSIBLE_FACT_CACHE_CONTAINER="${RHIS_ANSIBLE_FACT_CACHE_CONTAINER:-/rhis/vars/vault/${RHIS_ANSIBLE_FACT_CACHE_BASENAME}}"
RHIS_ANSIBLE_FORKS="${RHIS_ANSIBLE_FORKS:-15}"
RHIS_ANSIBLE_TIMEOUT="${RHIS_ANSIBLE_TIMEOUT:-30}"
RHIS_ANSIBLE_FACT_CACHE_TIMEOUT="${RHIS_ANSIBLE_FACT_CACHE_TIMEOUT:-86400}"
RHIS_RUN_LOG_DIR="${RHIS_RUN_LOG_DIR:-/var/log/rhis}"
RHIS_RUN_LOG_FILE="${RHIS_RUN_LOG_FILE:-}"
RHIS_LOG_STDIO_REDIRECTED="${RHIS_LOG_STDIO_REDIRECTED:-0}"
RHIS_RUN_LOG_KEEP_COUNT="${RHIS_RUN_LOG_KEEP_COUNT:-30}"

# Resolve the script's own directory first so it can be used as the default
# base for all relative paths below.  Users can override any of these by
# exporting them before invoking the script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# RHIS Provisioner container
RHIS_CONTAINER_IMAGE="${RHIS_CONTAINER_IMAGE:-quay.io/parmstro/rhis-provisioner-9-2.5:latest}"
RHIS_CONTAINER_NAME="${RHIS_CONTAINER_NAME:-rhis-provisioner}"
# Ansible inventory consumed by the rhis-builder playbooks inside the container.
# Defaults to an 'inventory/' subdirectory alongside this script so the repo is
# self-contained.  Override RHIS_INVENTORY_DIR to point at an existing checkout
# of your own inventory (e.g. a separate rhis-builder-* project).
RHIS_INVENTORY_DIR="${RHIS_INVENTORY_DIR:-$SCRIPT_DIR/inventory}"
# Per-host variable files (satellite.yml, aap.yml, idm.yml, …).
# Defaults to 'host_vars/' alongside this script; override as needed.
RHIS_HOST_VARS_DIR="${RHIS_HOST_VARS_DIR:-$SCRIPT_DIR/host_vars}"

REPO_URL="${REPO_URL:-}"
PRESEED_ENV_FILE="${PRESEED_ENV_FILE:-$SCRIPT_DIR/.env}"
RH_ISO_URL="${RH_ISO_URL:-https://access.cdn.redhat.com/content/origin/files/sha256/ec/ecc0e9b760247f0ef43100d88ed930a3a8a868545d5db6ad940c5c73be6fb047/rhel-10.1-x86_64-boot.iso?user=dfb5278729bd015d083f488da113c04b&_auth_=1773884550_69d13122ab14a5736321fe8cfe9c1c9d}"
RH9_ISO_URL="${RH9_ISO_URL:-https://access.cdn.redhat.com/content/origin/files/sha256/aa/aac774e5aba1c0275d50e0cc4e0e08eca660a116773280596e0bcb894d2da16d/rhel-9.7-x86_64-dvd.iso?user=dfb5278729bd015d083f488da113c04b&_auth_=1774126174_9c7dc7bd033124cd0884ec0b856f122e}"
CLI_MENU_CHOICE=""
CLI_NONINTERACTIVE=""
RUN_ONCE="${RUN_ONCE:-0}"
DEMO_MODE="${DEMO_MODE:-0}"
CLI_DEMO=""
CLI_DEMOKILL=""
CLI_RECONFIGURE=""
CLI_AAP_INVENTORY_TEMPLATE=""
CLI_AAP_INVENTORY_GROWTH_TEMPLATE=""
CLI_CONTAINER_CONFIG_ONLY=""
CLI_ATTACH_CONSOLES=""
CLI_STATUS=""
CLI_TEST=""
CLI_TEST_PROFILE="full"
MENU_CHOICE_CONSUMED=0
RHIS_TEST_MODE="${RHIS_TEST_MODE:-0}"
RHIS_DASHBOARD_SINGLE_SHOT="${RHIS_DASHBOARD_SINGLE_SHOT:-0}"
RHIS_TEST_WARNING_COUNT=0
RHIS_TEST_FAILURE_COUNT=0
RHIS_TEST_WARNING_FILE="${RHIS_TEST_WARNING_FILE:-/tmp/rhis-test-warnings-$$.log}"
declare -a RHIS_TEST_RESULTS=()
_RHIS_TEST_STEP=0
_RHIS_TEST_TOTAL=0
# Auto-run config-as-code sequence after container-only deployment (menu option 2).
# Set to 0/false/no/off to disable.
RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY="${RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY:-1}"
# Retry only failed config-as-code phases once (IdM/Satellite/AAP).
# Set to 0/false/no/off to disable.
RHIS_RETRY_FAILED_PHASES_ONCE="${RHIS_RETRY_FAILED_PHASES_ONCE:-1}"
# Apply/verify runtime playbook hotfixes inside provisioner container before phase runs.
RHIS_ENABLE_CONTAINER_HOTFIXES="${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"
# Fail fast if hotfix verification cannot be confirmed.
RHIS_ENFORCE_CONTAINER_HOTFIXES="${RHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"
# Internal SSH readiness wait for config-as-code preflight
RHIS_INTERNAL_SSH_WAIT_TIMEOUT="${RHIS_INTERNAL_SSH_WAIT_TIMEOUT:-1800}"
RHIS_INTERNAL_SSH_WAIT_INTERVAL="${RHIS_INTERNAL_SSH_WAIT_INTERVAL:-10}"
RHIS_POST_VM_SETTLE_GRACE="${RHIS_POST_VM_SETTLE_GRACE:-650}"
RHIS_INTERNAL_SSH_WARN_GRACE="${RHIS_INTERNAL_SSH_WARN_GRACE:-600}"
RHIS_INTERNAL_SSH_LOG_EVERY="${RHIS_INTERNAL_SSH_LOG_EVERY:-60}"
# Inventory transport selection for managed nodes.
# 0 (default): use internal RHIS IPs (10.168.x.x) for Ansible connectivity.
# 1: prefer externally discovered eth0/NAT addresses (192.168.122.x) when available.
RHIS_MANAGED_SSH_OVER_ETH0="${RHIS_MANAGED_SSH_OVER_ETH0:-0}"
# IdM web UI readiness check after IdM configuration phase.
RHIS_IDM_WEB_UI_TIMEOUT="${RHIS_IDM_WEB_UI_TIMEOUT:-900}"
RHIS_IDM_WEB_UI_INTERVAL="${RHIS_IDM_WEB_UI_INTERVAL:-15}"
# Post-install healthcheck/repair controls.
RHIS_ENABLE_POST_HEALTHCHECK="${RHIS_ENABLE_POST_HEALTHCHECK:-1}"
RHIS_HEALTHCHECK_AUTOFIX="${RHIS_HEALTHCHECK_AUTOFIX:-1}"
RHIS_HEALTHCHECK_RERUN_COMPONENT="${RHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"
RHC_AUTO_CONNECT="${RHC_AUTO_CONNECT:-1}"
# If enabled, fail the run when root-to-root SSH mesh cannot be fully established.
# Default keeps root mesh best-effort while installer-user mesh remains mandatory.
RHIS_REQUIRE_ROOT_SSH_MESH="${RHIS_REQUIRE_ROOT_SSH_MESH:-0}"
# Optional pre-flight ad-hoc probes/upgrades before phase playbooks.
# Default OFF to avoid noisy lockout-prone retries on fresh installs.
RHIS_ENABLE_PRECHECK_ADHOC="${RHIS_ENABLE_PRECHECK_ADHOC:-0}"
# Guard to ensure the full prompt wizard runs at most once per process.
RHIS_PROMPTS_COMPLETED="${RHIS_PROMPTS_COMPLETED:-0}"

# Automation Hub + AAP bundle pre-flight HTTP-serve variables
HUB_TOKEN="${HUB_TOKEN:-}"
# Automation Hub API token used for [galaxy_server.*] in rhis-ansible.cfg.
# If unset, HUB_TOKEN is used as fallback.
VAULT_CONSOLE_REDHAT_TOKEN="${VAULT_CONSOLE_REDHAT_TOKEN:-}"
HOST_INT_IP="${HOST_INT_IP:-192.168.122.1}"
AAP_BUNDLE_URL="${AAP_BUNDLE_URL:-https://access.cdn.redhat.com/content/origin/files/sha256/c9/c953da394644892ad66dabdc57fcb4e4022724501466a90904001526fe5660d3/ansible-automation-platform-containerized-setup-bundle-2.6-6-x86_64.tar.gz?user=dfb5278729bd015d083f488da113c04b&_auth_=1773884622_1b332b37fd083ba0f82e94d32ee65a51}"
AAP_BUNDLE_DIR="${AAP_BUNDLE_DIR:-${VM_DIR}/aap-bundle}"
AAP_HTTP_PID=""
AAP_HTTP_LOG="${AAP_HTTP_LOG:-/tmp/aap-http-server-$(date +%s).log}"
AAP_ANSIBLE_LOG_BASENAME="${AAP_ANSIBLE_LOG_BASENAME:-ansible-provisioner.log}"
STAGED_VAULT_PASS_BASENAME="${STAGED_VAULT_PASS_BASENAME:-.vaultpass.container}"
AAP_ADMIN_PASS="${AAP_ADMIN_PASS:-}"
SAT_ADMIN_PASS="${SAT_ADMIN_PASS:-}"
# AAP installer inventory template selection.
# These templates are rendered into /root/aap-setup/inventory and
# /root/aap-setup/inventory-growth inside the AAP VM during kickstart %post.
AAP_INVENTORY_TEMPLATE_DIR="${AAP_INVENTORY_TEMPLATE_DIR:-$SCRIPT_DIR/inventory/aap}"
AAP_INVENTORY_TEMPLATE="${AAP_INVENTORY_TEMPLATE:-}"
AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-}"
# Used by inventory.j2 templates (e.g. gateway_pg_database={{ pg_database }}).
# Prompted when inventory.j2 is selected.
AAP_PG_DATABASE="${AAP_PG_DATABASE:-}"
# The local Linux username that runs this script — injected into host_vars so
# Ansible knows which user to SSH as from the controller/installer host.
INSTALLER_USER="${INSTALLER_USER:-${USER}}"

# Shared identity/network defaults (single source of truth)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-}"  # loaded from vault; fallback set in normalize_shared_env_vars
ROOT_PASS="${ROOT_PASS:-}"
DOMAIN="${DOMAIN:-}"
REALM="${REALM:-}"
INTERNAL_NETWORK="${INTERNAL_NETWORK:-10.168.0.0}"
NETMASK="${NETMASK:-255.255.0.0}"
INTERNAL_GW="${INTERNAL_GW:-10.168.0.1}"

# Internal interface static defaults (eth1)
SAT_IP="${SAT_IP:-10.168.128.1}"
AAP_IP="${AAP_IP:-10.168.128.2}"
IDM_IP="${IDM_IP:-10.168.128.3}"
SAT_HOSTNAME="${SAT_HOSTNAME:-}"
AAP_HOSTNAME="${AAP_HOSTNAME:-}"
IDM_HOSTNAME="${IDM_HOSTNAME:-}"
SAT_ALIAS="${SAT_ALIAS:-satellite}"
AAP_ALIAS="${AAP_ALIAS:-aap}"
IDM_ALIAS="${IDM_ALIAS:-idm}"

# Satellite defaults
SAT_ORG="${SAT_ORG:-REDHAT}"
SAT_LOC="${SAT_LOC:-CORE}"
IDM_DS_PASS="${IDM_DS_PASS:-}"  # loaded from vault; fallback set in normalize_shared_env_vars
SATELLITE_DISCONNECTED="${SATELLITE_DISCONNECTED:-false}"
REGISTER_TO_SATELLITE="${REGISTER_TO_SATELLITE:-false}"
SATELLITE_PRE_USE_IDM="${SATELLITE_PRE_USE_IDM:-false}"
IPADM_PASSWORD="${IPADM_PASSWORD:-}"
IPAADMIN_PASSWORD="${IPAADMIN_PASSWORD:-}"
CDN_ORGANIZATION_ID="${CDN_ORGANIZATION_ID:-}"
CDN_SAT_ACTIVATION_KEY="${CDN_SAT_ACTIVATION_KEY:-}"
SAT_FIREWALLD_ZONE="${SAT_FIREWALLD_ZONE:-public}"
SAT_FIREWALLD_INTERFACE="${SAT_FIREWALLD_INTERFACE:-eth1}"
SAT_FIREWALLD_SERVICES_JSON='["ssh","http","https"]'
IDM_REPOSITORY_IDS_JSON='["rhel-10-for-x86_64-baseos-rpms","rhel-10-for-x86_64-appstream-rpms"]'
# Required Satellite server repositories.  Your RHSM account MUST expose all
# four IDs below before run_config_as_code() reaches the Satellite phase.
# See assert_satellite_server_repos_available() for the pre-flight guard.
SAT_REPOSITORY_IDS_JSON='["rhel-9-for-x86_64-baseos-rpms","rhel-9-for-x86_64-appstream-rpms","satellite-6.18-for-rhel-9-x86_64-rpms","satellite-maintenance-6.18-for-rhel-9-x86_64-rpms"]'

# Disk I/O mode: "fast" (cache=none,discard=unmap,io=native — optimal for SSD/NVMe)
#                "safe" (cache=writeback — conservative; use for spinning HDDs or shared storage)
VM_DISK_PERF_MODE="${VM_DISK_PERF_MODE:-fast}"

# Tracks whether serve_aap_bundle() opened a firewalld port so we can close it later
AAP_FW_RULE_ADDED=""

# SSH callback orchestration for AAP post-boot setup
AAP_SSH_KEY_DIR="${AAP_SSH_KEY_DIR:-${HOME}/.ssh/rhis-aap}"
AAP_SSH_PRIVATE_KEY="${AAP_SSH_KEY_DIR}/id_rsa"
AAP_SSH_PUBLIC_KEY="${AAP_SSH_KEY_DIR}/id_rsa.pub"
AAP_SETUP_LOG_LOCAL="${AAP_SETUP_LOG_LOCAL:-/tmp/aap-setup-$(date +%s).log}"
RHIS_VM_MONITOR_SESSION="${RHIS_VM_MONITOR_SESSION:-rhis-vm-consoles}"
RHIS_VM_MONITOR_PID_FILE="${RHIS_VM_MONITOR_PID_FILE:-/tmp/rhis-vm-console-pids-${USER}}"
RHIS_VM_WATCHDOG_PID=""
# Guardrail: disable AAP SSH callback probing unless explicitly enabled by the
# VM provisioning/callback workflow path.
AAP_SSH_CALLBACK_ENABLED="${AAP_SSH_CALLBACK_ENABLED:-0}"
# Dedicated persistent installer-host key used by RHIS mesh operations.
# Keeps RHIS traffic isolated from the operator's default ~/.ssh/id_rsa identity.
RHIS_INSTALLER_SSH_KEY_DIR="${RHIS_INSTALLER_SSH_KEY_DIR:-${HOME}/.ssh/rhis-installer}"
RHIS_INSTALLER_SSH_PRIVATE_KEY="${RHIS_INSTALLER_SSH_KEY_DIR}/id_rsa"
RHIS_INSTALLER_SSH_PUBLIC_KEY="${RHIS_INSTALLER_SSH_KEY_DIR}/id_rsa.pub"
# If enabled, prune/reseed known_hosts entries for RHIS node IPs/hostnames each run.
RHIS_REFRESH_KNOWN_HOSTS="${RHIS_REFRESH_KNOWN_HOSTS:-1}"
# Fail fast when SSH port is reachable but key auth repeatedly fails.
# 18 attempts * 10s = ~3 minutes (after SSH becomes reachable).
AAP_SSH_KEY_FAIL_FAST_ATTEMPTS="${AAP_SSH_KEY_FAIL_FAST_ATTEMPTS:-18}"
# AAP callback wait-loop controls
AAP_SSH_WAIT_TIMEOUT="${AAP_SSH_WAIT_TIMEOUT:-5400}"
AAP_SSH_WAIT_INTERVAL="${AAP_SSH_WAIT_INTERVAL:-10}"
AAP_SSH_PROGRESS_EVERY="${AAP_SSH_PROGRESS_EVERY:-30}"
# If there is no observed callback-stage progress for this long, fail fast.
AAP_SSH_NO_PROGRESS_TIMEOUT="${AAP_SSH_NO_PROGRESS_TIMEOUT:-900}"

# Function to print colored output
sanitize_log_message() {
    local message="$*"
    printf '%s' "${message}" | sed -E \
        -e 's#([?&](_auth_|auth|token|access_token|refresh_token|password|passwd|pass|api_key|apikey)=)[^&[:space:]]+#\1<redacted>#Ig' \
        -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1<redacted>#Ig' \
        -e 's#(--(password|passwd|token|secret|api-key|api_key|apikey)(=|[[:space:]]+))[^[:space:]]+#\1<redacted>#Ig' \
        -e 's#((^|[[:space:]])(password|passwd|token|secret|api_key|apikey|offline_token|access_token|refresh_token)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig'
}

print_step() {
    local msg
    msg="$(sanitize_log_message "$*")"
    echo -e "${BLUE}[STEP]${NC} ${msg}"
}

print_success() {
    local msg
    msg="$(sanitize_log_message "$*")"
    echo -e "${GREEN}[SUCCESS]${NC} ${msg}"
}

print_warning() {
    local msg
    msg="$(sanitize_log_message "$*")"
    if is_enabled "${RHIS_TEST_MODE:-0}"; then
        RHIS_TEST_WARNING_COUNT=$((RHIS_TEST_WARNING_COUNT + 1))
        printf '%s\n' "${msg}" >> "${RHIS_TEST_WARNING_FILE}"
    fi
    echo -e "${YELLOW}[WARNING]${NC} ${msg}"
}

print_phase() {
    local index="$1"
    local total="$2"
    local label="$3"
    label="$(sanitize_log_message "${label}")"
    echo -e "${CYAN}[PHASE ${index}/${total}]${NC} ${BOLD}${label}${NC}"
}

ensure_rhis_installer_ssh_key() {
    mkdir -p "${RHIS_INSTALLER_SSH_KEY_DIR}" >/dev/null 2>&1 || true
    chmod 700 "${RHIS_INSTALLER_SSH_KEY_DIR}" >/dev/null 2>&1 || true

    if [ ! -f "${RHIS_INSTALLER_SSH_PRIVATE_KEY}" ]; then
        ssh-keygen -q -t rsa -b 4096 -N "" -f "${RHIS_INSTALLER_SSH_PRIVATE_KEY}" -C "rhis-installer-host" >/dev/null 2>&1 || return 1
    fi

    chmod 600 "${RHIS_INSTALLER_SSH_PRIVATE_KEY}" >/dev/null 2>&1 || true
    chmod 644 "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" >/dev/null 2>&1 || true
    return 0
}

refresh_rhis_known_hosts() {
    local host
    local -a rhis_hosts

    if ! is_enabled "${RHIS_REFRESH_KNOWN_HOSTS:-1}"; then
        return 0
    fi

    [ -d "${HOME}/.ssh" ] || mkdir -p "${HOME}/.ssh" >/dev/null 2>&1 || true
    touch "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true
    chmod 600 "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true

    rhis_hosts=(
        "${SAT_IP:-}" "${AAP_IP:-}" "${IDM_IP:-}"
        "${SAT_HOSTNAME:-}" "${AAP_HOSTNAME:-}" "${IDM_HOSTNAME:-}"
    )

    for host in "${rhis_hosts[@]}"; do
        [ -n "${host}" ] || continue
        ssh-keygen -R "${host}" -f "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true
        ssh-keyscan -H -T 3 "${host}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    done
}

init_rhis_run_logging() {
    local run_ts target_dir log_file

    # Idempotent guard for re-entry.
    if [ "${RHIS_LOG_STDIO_REDIRECTED:-0}" = "1" ]; then
        return 0
    fi

    target_dir="${RHIS_RUN_LOG_DIR:-/var/log/rhis}"
    run_ts="$(date +%Y%m%d-%H%M%S)"
    log_file="${target_dir}/rhis_install_${run_ts}_pid$$.log"

    # Ensure /var/log/rhis exists; requires elevated permissions on most systems.
    if [ ! -d "${target_dir}" ]; then
        if ! sudo mkdir -p "${target_dir}" 2>/dev/null; then
            print_warning "Could not create ${target_dir}; run logging disabled for this invocation."
            return 0
        fi
    fi

    sudo chown "${USER}:${USER}" "${target_dir}" >/dev/null 2>&1 || true
    sudo chmod 0755 "${target_dir}" >/dev/null 2>&1 || true

    if ! touch "${log_file}" 2>/dev/null; then
        if ! sudo touch "${log_file}" 2>/dev/null; then
            print_warning "Could not create run log file at ${log_file}; run logging disabled for this invocation."
            return 0
        fi
    fi

    sudo chown "${USER}:${USER}" "${log_file}" >/dev/null 2>&1 || true
    sudo chmod 0644 "${log_file}" >/dev/null 2>&1 || true

    RHIS_RUN_LOG_FILE="${log_file}"
    export RHIS_RUN_LOG_FILE
    export RHIS_LOG_STDIO_REDIRECTED=1

    # Mirror all script output to console and a per-run logfile.
    exec > >(tee -a "${RHIS_RUN_LOG_FILE}") 2>&1

    ln -sfn "${RHIS_RUN_LOG_FILE}" "${target_dir}/latest.log" >/dev/null 2>&1 || true
    print_step "RHIS run logging enabled: ${RHIS_RUN_LOG_FILE}"

    prune_rhis_run_logs || true
}

prune_rhis_run_logs() {
    local target_dir keep_count
    local -a run_logs
    local i

    target_dir="${RHIS_RUN_LOG_DIR:-/var/log/rhis}"
    keep_count="${RHIS_RUN_LOG_KEEP_COUNT:-30}"

    case "${keep_count}" in
        ''|*[!0-9]*)
            print_warning "Invalid RHIS_RUN_LOG_KEEP_COUNT='${keep_count}'; skipping log pruning."
            return 0
            ;;
    esac

    [ "${keep_count}" -ge 1 ] || {
        print_warning "RHIS_RUN_LOG_KEEP_COUNT must be >= 1; skipping log pruning."
        return 0
    }

    [ -d "${target_dir}" ] || return 0

    # Newest first by mtime, only per-run RHIS installer logs.
    mapfile -t run_logs < <(ls -1t "${target_dir}"/rhis_install_*.log 2>/dev/null || true)

    if [ "${#run_logs[@]}" -le "${keep_count}" ]; then
        return 0
    fi

    for (( i=keep_count; i<${#run_logs[@]}; i++ )); do
        rm -f "${run_logs[$i]}" >/dev/null 2>&1 || sudo rm -f "${run_logs[$i]}" >/dev/null 2>&1 || true
    done

    print_step "Pruned RHIS run logs; kept newest ${keep_count} file(s) in ${target_dir}."
    return 0
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --non-interactive        Run without prompts; required values must be preseeded
  --menu-choice <0-8>      Preselect a visible menu option
  --env-file <path>        Load preseed variables from a custom env file
  --inventory <template>   Pin AAP inventory template; skips interactive submenu
  --inventory-growth <tpl> Pin AAP inventory-growth template; skips interactive submenu
                           Interactive (no --non-interactive): a guided submenu with
                           About pages is presented when template values are unset.
                           --DEMO always forces DEMO-inventory.j2 and skips the submenu.
  --container-config-only  Start container and run config order (IdM -> Satellite -> AAP)
  --attach-consoles        Re-open VM console monitors for Satellite/AAP/IdM
    --status                 Read-only status snapshot (no provisioning changes)
  --reconfigure            Prompt for all env values and update env.yml
  --test[=fast|full]       Run a curated non-interactive test sweep and print a summary
  --demo                   Use minimal PoC/demo VM specs and kickstarts
  --demokill               Destroy demo VMs/files/temp locks and exit (CLI-only)
  (env) RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0  Disable auto config after menu option 2
  (env) RHIS_RETRY_FAILED_PHASES_ONCE=0       Disable automatic retry of failed phases
    (env) RHIS_ENABLE_CONTAINER_HOTFIXES=0      Disable runtime role hotfix patching in container
    (env) RHIS_ENFORCE_CONTAINER_HOTFIXES=0     Do not fail when hotfix verification cannot be confirmed
    (env) RHIS_MANAGED_SSH_OVER_ETH0=1          Prefer external/NAT (eth0) addresses for managed-node Ansible SSH
    (env) RHIS_ENABLE_POST_HEALTHCHECK=0        Disable post-install healthchecks (IdM/Satellite/AAP)
    (env) RHIS_HEALTHCHECK_AUTOFIX=0            Disable automatic healthcheck remediation attempts
    (env) RHIS_HEALTHCHECK_RERUN_COMPONENT=0    Disable targeted component rerun after healthcheck failure
    (env) RHIS_REFRESH_KNOWN_HOSTS=0            Do not refresh RHIS node host keys in ~/.ssh/known_hosts
    (env) RHIS_INSTALLER_SSH_KEY_DIR=<path>     Override dedicated persistent RHIS installer SSH key directory
    (env) RHC_AUTO_CONNECT=0                    Disable automatic rhc connect in guest kickstarts
  --help                   Show this help message
EOF
}

mask_secret() {
    local value="${1:-}"
    local length

    if [ -z "$value" ]; then
        echo "(unset)"
        return 0
    fi

    length="${#value}"
    if [ "$length" -le 4 ]; then
        printf '%*s\n' "$length" '' | tr ' ' '*'
        return 0
    fi

    printf '%s***%s\n' "${value:0:2}" "${value: -2}"
}

mask_url_secret() {
    local value="${1:-}"
    local base=""

    if [ -z "$value" ]; then
        echo "(unset)"
        return 0
    fi

    # Strip query/hash to avoid leaking auth tokens in logs.
    base="${value%%\?*}"
    base="${base%%#*}"
    if [ "$base" != "$value" ]; then
        printf '%s?<redacted>\n' "$base"
        return 0
    fi

    printf '%s\n' "$base"
}

sed_escape_replacement() {
    # Escape chars that are special in sed replacement context: &, |, \
    printf '%s' "${1:-}" | sed -e 's/[&|\\]/\\&/g'
}

kickstart_nogpg_policy_block() {
    cat <<'EOF'
# RHIS policy: disable package signature checks for all dnf/yum repo operations.
mkdir -p /etc/dnf
if [ -f /etc/dnf/dnf.conf ]; then
    if ! grep -q '^gpgcheck=0$' /etc/dnf/dnf.conf; then
        cat >> /etc/dnf/dnf.conf <<'EOF_DNF_GPG'

# RHIS override: disable GPG checks
gpgcheck=0
repo_gpgcheck=0
localpkg_gpgcheck=0
EOF_DNF_GPG
    fi
fi
[ -e /etc/yum.conf ] || ln -sf /etc/dnf/dnf.conf /etc/yum.conf
EOF
}

kickstart_ssh_baseline_block() {
    cat <<'EOF'
# 1.1 SSH baseline for automation and internal preflight
mkdir -p /etc/ssh/sshd_config.d
mkdir -p /etc/ssh/ssh_config.d
cat > /etc/ssh/sshd_config.d/99-rhis-root.conf <<'EOF_SSHD'
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding yes
UseDNS no
EOF_SSHD

cat > /etc/ssh/ssh_config.d/99-rhis-client.conf <<'EOF_SSH'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ForwardX11 yes
EOF_SSH

systemctl enable --now sshd || true
systemctl restart sshd || true
systemctl disable --now firewalld >/dev/null 2>&1 || true
setenforce 0 >/dev/null 2>&1 || true
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true
fi
EOF
}

kickstart_user_sudo_bootstrap_block() {
    cat <<'EOF'
# 1.2 Ensure installer/admin user has passwordless sudo and virtualization groups
target_user="${INSTALLER_USER:-${ADMIN_USER}}"
if [ "${INSTALLER_USER:-${ADMIN_USER}}" != "${ADMIN_USER}" ] && ! id "${INSTALLER_USER:-${ADMIN_USER}}" >/dev/null 2>&1; then
    useradd -m -G wheel "${INSTALLER_USER:-${ADMIN_USER}}" || true
    echo "${INSTALLER_USER:-${ADMIN_USER}}:${ADMIN_PASS}" | chpasswd || true
fi
for grp in libvirt qemu kvm wheel; do
    getent group "$grp" >/dev/null 2>&1 || groupadd -f "$grp" || true
done
usermod -aG libvirt,qemu,kvm,wheel "$target_user" || true
sed -i -E 's/^#?[[:space:]]*%wheel[[:space:]]+ALL=\(ALL\)[[:space:]]+ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers || true
printf '%s\n' "$target_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-rhis-nopasswd
chmod 0440 /etc/sudoers.d/90-rhis-nopasswd
visudo -cf /etc/sudoers >/dev/null 2>&1 || true
EOF
}

kickstart_rhsm_register_block() {
    local include_org_id="${1:-0}"

    cat <<'EOF'
# 2. Registration (retry until network/RHSM are reachable)
register_rhsm() {
    local try
    for try in $(seq 1 10); do
EOF

    if [ "$include_org_id" = "1" ]; then
        cat <<'EOF'
        if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
            subscription-manager register --org="${CDN_ORGANIZATION_ID}" --activationkey="${CDN_SAT_ACTIVATION_KEY}" --force && return 0
        elif [ -n "${CDN_ORGANIZATION_ID:-}" ]; then
            subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --org="${CDN_ORGANIZATION_ID}" --auto-attach --force && return 0
        else
            subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach --force && return 0
        fi
EOF
    else
        cat <<'EOF'
        subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach --force && return 0
EOF
    fi

    cat <<'EOF'
        subscription-manager unregister >/dev/null 2>&1 || true
        subscription-manager clean >/dev/null 2>&1 || true
        sleep 15
    done
    return 1
}

register_rhsm
subscription-manager refresh || true
EOF
}

kickstart_rhc_connect_block() {
    cat <<'EOF'
# 2.1 Red Hat Hybrid Cloud Console registration (rhc)
if [ "${RHC_AUTO_CONNECT:-1}" = "1" ]; then
    dnf install -y --nogpgcheck rhc >/dev/null 2>&1 || true
    if command -v rhc >/dev/null 2>&1; then
        if ! rhc status >/dev/null 2>&1; then
            rhc connect --username="${RH_USER}" --password="${RH_PASS}" >/dev/null 2>&1 || true
        fi
    fi
fi
EOF
}

kickstart_repo_enable_verify_block() {
    local role_label="$1"
    shift
    local -a repos=("$@")
    local i

    printf '%s\n' '# 3. Repositories'
    printf '%s' 'subscription-manager repos --disable="*"'
    printf '\n'
    printf '%s' 'subscription-manager repos'
    for i in "${repos[@]}"; do
        printf ' --enable="%s"' "$i"
    done
    printf '\n\n'

    printf '%s\n' 'for repo in \\'
    for ((i=0; i<${#repos[@]}; i++)); do
        if [ "$i" -lt $(( ${#repos[@]} - 1 )) ]; then
            printf '    %s \\\n' "${repos[$i]}"
        else
            printf '    %s; do\n' "${repos[$i]}"
        fi
    done

    printf '%s\n' '    if ! subscription-manager repos --list-enabled | grep -q "$repo"; then'
    printf '        echo "ERROR: Required %s repository not enabled: $repo"\n' "$role_label"
    printf '%s\n' '        subscription-manager repos --list-enabled || true'
    printf '%s\n' '        exit 1'
    printf '%s\n' '    fi'
    printf '%s\n' 'done'
}

kickstart_networkmanager_dual_nic_block() {
    local ext_mac="$1"
    local int_mac="$2"
    local int_ip="$3"
    local int_prefix="$4"
    local int_gw="$5"

    cat <<EOF
# 0. Deterministic NetworkManager keyfiles (persisted for first boot)
mkdir -p /etc/NetworkManager/system-connections /etc/NetworkManager/conf.d
rm -f /etc/NetworkManager/system-connections/*.nmconnection || true

cat > /etc/NetworkManager/system-connections/eth0.nmconnection <<'EOF_NM_ETH0'
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ethernet]
mac-address=${ext_mac}

[ipv4]
method=auto
# DHCP primary with explicit resolver fallback for early bootstrap tasks.
dns=10.168.0.1;1.1.1.1;8.8.8.8;
dns-options=rotate;
ignore-auto-dns=false

[ipv6]
method=auto
EOF_NM_ETH0

cat > /etc/NetworkManager/system-connections/eth1.nmconnection <<'EOF_NM_ETH1'
[connection]
id=eth1
type=ethernet
interface-name=eth1
autoconnect=true

[ethernet]
mac-address=${int_mac}

[ipv4]
# Internal management network — static IP, no default route.
# eth0 (DHCP) is the sole default route for internet access.
# Intra-cluster VMs are on the same /16 subnet so no gateway is needed.
method=manual
addresses=${int_ip}/${int_prefix}
never-default=true

[ipv6]
method=ignore
EOF_NM_ETH1

chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection /etc/NetworkManager/system-connections/eth1.nmconnection

cat > /etc/NetworkManager/conf.d/10-rhis-no-auto-default.conf <<'EOF_NM_MAIN'
[main]
no-auto-default=${ext_mac},${int_mac}
EOF_NM_MAIN

systemctl enable NetworkManager || true

# Ensure resolver file exists for registration/DNS lookups
if [ ! -s /etc/resolv.conf ] && [ -f /run/NetworkManager/resolv.conf ]; then
    ln -sf /run/NetworkManager/resolv.conf /etc/resolv.conf || true
fi
EOF
}

kickstart_hosts_mapping_block() {
    local sat_ip="$1"
    local sat_host="$2"
    local sat_short="$3"
    local aap_ip="$4"
    local aap_host="$5"
    local aap_short="$6"
    local idm_ip="$7"
    local idm_host="$8"
    local idm_short="$9"

    cat <<EOF
# 1. Local hosts mapping (temporary DNS-independent bootstrap)
cat > /etc/hosts <<EOF_HOSTS
127.0.0.1 localhost localhost.localdomain
${sat_ip} ${sat_host} ${sat_short}
${aap_ip} ${aap_host} ${aap_short}
${idm_ip} ${idm_host} ${idm_short}
EOF_HOSTS
EOF
}

kickstart_trust_bootstrap_keys_block() {
    local include_target_user_copy="${1:-1}"

    cat <<'EOF'
# 1.3 Trust installer/orchestration/container SSH keys for root and installer user
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Ensure root has a local SSH keypair on first boot.
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa || true
fi

cat >> /root/.ssh/authorized_keys <<'SSH_KEYS'
${bootstrap_ssh_keys}
SSH_KEYS
[ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys || true
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys || true
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_rsa 2>/dev/null || true
chmod 644 /root/.ssh/id_rsa.pub 2>/dev/null || true
chmod 600 /root/.ssh/authorized_keys
EOF

    if [ "$include_target_user_copy" = "1" ]; then
        cat <<'EOF'
if id "$target_user" >/dev/null 2>&1; then
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
    [ -n "$target_home" ] || target_home="/home/$target_user"
    install -d -m 700 -o "$target_user" -g "$target_user" "$target_home/.ssh"

    # Ensure target installer/admin user has a local SSH keypair.
    if [ ! -f "$target_home/.ssh/id_rsa" ]; then
        sudo -u "$target_user" ssh-keygen -q -t rsa -b 4096 -N "" -f "$target_home/.ssh/id_rsa" || true
    fi

    cat > "$target_home/.ssh/authorized_keys" <<'SSH_KEYS'
${bootstrap_ssh_keys}
SSH_KEYS
    [ -f "$target_home/.ssh/id_rsa.pub" ] && cat "$target_home/.ssh/id_rsa.pub" >> "$target_home/.ssh/authorized_keys" || true
    [ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> "$target_home/.ssh/authorized_keys" || true
    [ -f "$target_home/.ssh/id_rsa.pub" ] && cat "$target_home/.ssh/id_rsa.pub" >> /root/.ssh/authorized_keys || true
    sort -u "$target_home/.ssh/authorized_keys" -o "$target_home/.ssh/authorized_keys" || true
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys || true
    chown "$target_user:$target_user" "$target_home/.ssh/authorized_keys"
    chown "$target_user:$target_user" "$target_home/.ssh/id_rsa" "$target_home/.ssh/id_rsa.pub" 2>/dev/null || true
    chmod 600 "$target_home/.ssh/id_rsa" 2>/dev/null || true
    chmod 644 "$target_home/.ssh/id_rsa.pub" 2>/dev/null || true
    chmod 600 "$target_home/.ssh/authorized_keys"
fi
EOF
    fi
}

print_runtime_configuration() {
    print_step "Runtime configuration summary"
    local galaxy_token_effective="${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}"
    echo "  PRESEED_ENV_FILE=${PRESEED_ENV_FILE}"
    echo "  NONINTERACTIVE=${NONINTERACTIVE:-0}"
    echo "  MENU_CHOICE=${MENU_CHOICE:-'(unset)'}"
    echo "  RH_ISO_URL=$(mask_url_secret "${RH_ISO_URL:-}")"
    echo "  RH9_ISO_URL=$(mask_url_secret "${RH9_ISO_URL:-}")"
    echo "  RH_OFFLINE_TOKEN=$(mask_secret "${RH_OFFLINE_TOKEN:-}")"
    echo "  RH_ACCESS_TOKEN=$(mask_secret "${RH_ACCESS_TOKEN:-}")"
    echo "  RH_PASS=$(mask_secret "${RH_PASS:-}")"
    echo "  SAT_HOSTNAME=${SAT_HOSTNAME:-'(unset)'}"
    echo "  SAT_ORG=${SAT_ORG:-'(unset)'}"
    echo "  SAT_LOC=${SAT_LOC:-'(unset)'}"
    echo "  DEMO_MODE=${DEMO_MODE:-0}"
    echo "  HUB_TOKEN=$(mask_secret "${HUB_TOKEN:-}")"
    echo "  VAULT_CONSOLE_REDHAT_TOKEN=$(mask_secret "${VAULT_CONSOLE_REDHAT_TOKEN:-}")"
    echo "  GALAXY_TOKEN_EFFECTIVE=$(mask_secret "${galaxy_token_effective:-}")"
    echo "  HOST_INT_IP=${HOST_INT_IP:-'(unset)'}"
    echo "  AAP_BUNDLE_URL=$(mask_url_secret "${AAP_BUNDLE_URL:-}")"
    echo "  AAP_INVENTORY_TEMPLATE=${AAP_INVENTORY_TEMPLATE:-'(unset)'}"
    echo "  AAP_INVENTORY_GROWTH_TEMPLATE=${AAP_INVENTORY_GROWTH_TEMPLATE:-'(unset)'}"
    echo "  AAP_PG_DATABASE=${AAP_PG_DATABASE:-'(unset)'}"
    echo "  AAP_SSH_KEY_DIR=${AAP_SSH_KEY_DIR:-'(unset)'}"
    echo "  RHIS_ANSIBLE_CFG_HOST=${RHIS_ANSIBLE_CFG_HOST}"
    echo "  RHIS_ANSIBLE_FACT_CACHE_HOST=${RHIS_ANSIBLE_FACT_CACHE_HOST}"
    echo "  AAP_ANSIBLE_LOG=${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    echo "  RHIS_RETRY_FAILED_PHASES_ONCE=${RHIS_RETRY_FAILED_PHASES_ONCE:-1}"
    echo "  RHIS_ENABLE_CONTAINER_HOTFIXES=${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"
    echo "  RHIS_ENFORCE_CONTAINER_HOTFIXES=${RHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"
    echo "  RHIS_MANAGED_SSH_OVER_ETH0=${RHIS_MANAGED_SSH_OVER_ETH0:-0}"
    echo "  RHIS_IDM_WEB_UI_TIMEOUT=${RHIS_IDM_WEB_UI_TIMEOUT:-900}"
    echo "  RHIS_IDM_WEB_UI_INTERVAL=${RHIS_IDM_WEB_UI_INTERVAL:-15}"
    echo "  RHIS_ENABLE_POST_HEALTHCHECK=${RHIS_ENABLE_POST_HEALTHCHECK:-1}"
    echo "  RHIS_HEALTHCHECK_AUTOFIX=${RHIS_HEALTHCHECK_AUTOFIX:-1}"
    echo "  RHIS_HEALTHCHECK_RERUN_COMPONENT=${RHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"
    echo "  RHIS_REQUIRE_ROOT_SSH_MESH=${RHIS_REQUIRE_ROOT_SSH_MESH:-0}"
    echo "  RHIS_REFRESH_KNOWN_HOSTS=${RHIS_REFRESH_KNOWN_HOSTS:-1}"
    echo "  RHIS_INSTALLER_SSH_KEY_DIR=${RHIS_INSTALLER_SSH_KEY_DIR:-'(unset)'}"
    echo "  RHIS_ENABLE_PRECHECK_ADHOC=${RHIS_ENABLE_PRECHECK_ADHOC:-0}"
    echo "  RHC_AUTO_CONNECT=${RHC_AUTO_CONNECT:-1}"
    echo "  NETWORKS_ACTIVE=SAT(${SAT_IP:-10.168.128.1}/${SAT_NETMASK:-255.255.0.0} gw:${SAT_GW:-10.168.0.1}) AAP(${AAP_IP:-10.168.128.2}/${AAP_NETMASK:-255.255.0.0} gw:${AAP_GW:-10.168.0.1}) IDM(${IDM_IP:-10.168.128.3}/${IDM_NETMASK:-255.255.0.0} gw:${IDM_GW:-10.168.0.1})"
}

generate_rhis_ansible_cfg() {
    mkdir -p "${ANSIBLE_ENV_DIR}" "${RHIS_ANSIBLE_FACT_CACHE_HOST}" || return 1
    chmod 700 "${ANSIBLE_ENV_DIR}" "${RHIS_ANSIBLE_FACT_CACHE_HOST}" 2>/dev/null || true

    # Prefer explicit vaulted console token; fall back to HUB_TOKEN.
    # This token is used for Automation Hub galaxy server auth entries.
    local ah_token="${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}"

    cat > "${RHIS_ANSIBLE_CFG_HOST}" <<EOF
[defaults]
inventory = /rhis/vars/external_inventory/hosts
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent
remote_tmp = /var/tmp
forks = ${RHIS_ANSIBLE_FORKS}
timeout = ${RHIS_ANSIBLE_TIMEOUT}
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ${RHIS_ANSIBLE_FACT_CACHE_CONTAINER}
fact_caching_timeout = ${RHIS_ANSIBLE_FACT_CACHE_TIMEOUT}
callbacks_enabled = ansible.posix.profile_tasks,ansible.posix.timer
bin_ansible_callbacks = True
log_path = /rhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}
nocows = 1

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
control_path_dir = /tmp/.ansible-cp
retries = 3

[galaxy]
server_list = published, validated, community_galaxy

[galaxy_server.published]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token redacted (use vaulted var vault_console_redhat_token)
token = ${ah_token}

[galaxy_server.validated]
url = https://console.redhat.com/api/automation-hub/content/validated/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token redacted (use vaulted var vault_console_redhat_token)
token = ${ah_token}

[galaxy_server.community_galaxy]
url = https://galaxy.ansible.com/
EOF

    chmod 600 "${RHIS_ANSIBLE_CFG_HOST}" 2>/dev/null || true
    touch "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
    chmod 600 "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
    print_success "Generated RHIS Ansible config: ${RHIS_ANSIBLE_CFG_HOST}"
    return 0
}

# Persist a consolidated view of runtime credentials/config into the encrypted
# ~/.ansible/conf/env.yml vault so the workflow has a single source of truth.
# This intentionally runs after stale container teardown in ensure_container_running().
sync_runtime_values_to_ansible_vault() {
    [ -f "${ANSIBLE_ENV_FILE}" ] || return 0

    print_step "Consolidating runtime variables into encrypted vault file: ${ANSIBLE_ENV_FILE}"

    # Load existing vaulted values first, then merge any runtime-sourced values.
    load_ansible_env_file || return 1

    # Bidirectional fallback between dedicated Automation Hub token and legacy HUB_TOKEN.
    if [ -z "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ] && [ -n "${HUB_TOKEN:-}" ]; then
        VAULT_CONSOLE_REDHAT_TOKEN="${HUB_TOKEN}"
    fi
    if [ -z "${HUB_TOKEN:-}" ] && [ -n "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ]; then
        HUB_TOKEN="${VAULT_CONSOLE_REDHAT_TOKEN}"
    fi

    normalize_shared_env_vars
    write_ansible_env_file
}

# ─── Test suite helpers ─────────────────────────────────────────────────────

    # Render a 14-char filled/empty progress bar using block characters.
    _rhis_test_bar() {
        local n="$1" total="$2" width=14
        local bar="" fill i
        [ "${total}" -le 0 ] && { printf '░░░░░░░░░░░░░░'; return; }
        fill=$(( n * width / total ))
        i=0
        while [ "$i" -lt "$fill"   ]; do bar="${bar}█"; i=$((i+1)); done
        while [ "$i" -lt "$width"  ]; do bar="${bar}░"; i=$((i+1)); done
        printf '%s' "${bar}"
    }

    # One-line "why we test this" shown in the per-test step header.
    _rhis_test_why() {
        case "$1" in
            *"Ansible config"*)    printf '%s' "Verifies pipelining, forks, fact-cache, and log path before the container ever starts." ;;
            *"Generate inventory") printf '%s' "Builds the hosts file that defines every group (sat_primary, aap_hosts, idm_primary) for playbooks." ;;
            *"host_vars"*)         printf '%s' "Creates per-node connection details (IP, ansible_host, user) read by playbooks at run time." ;;
            *"inventory model"*)   printf '%s' "Validates the chosen AAP topology resolves to a real template before kickstart writes it." ;;
            *"Container Deploy"*)  printf '%s' "Starts rhis-provisioner — the sole execution engine for all config-as-code phases." ;;
            *"OEMDRV"*)            printf '%s' "Exercises kickstart + ISO build pipeline (genisoimage/xorriso) without a live Satellite." ;;
            *"Dashboard"*)         printf '%s' "Renders the runtime monitor and exercises the ansible-provisioner.log tail path." ;;
            *"Local Install"*)     printf '%s' "Verifies the local npm/Node.js toolchain or confirms fall-through to container deployment." ;;
            *"Virt-Manager"*)      printf '%s' "Tests libvirt connectivity and VM definition logic — most common blocker on new installs." ;;
            *"Config-Only"*)       printf '%s' "End-to-end run of IdM -> Satellite -> AAP config sequence inside the provisioner container." ;;
            *)                     printf '%s' "Validates this component functions correctly in the current environment." ;;
        esac
    }

    # One-line "what a passing result means for you" shown in the summary.
    _rhis_test_impact() {
        case "$1" in
            *"Ansible config"*)    printf '%s' "Provisioner inherits correct tuning — missing config causes silent container failures." ;;
            *"Generate inventory") printf '%s' "All platform VMs (IdM / Satellite / AAP) are reachable by group name from every playbook." ;;
            *"host_vars"*)         printf '%s' "Node details match env.yml — SSH auth will succeed on first contact with each VM." ;;
            *"inventory model"*)   printf '%s' "AAP_INVENTORY_TEMPLATE and AAP_INVENTORY_GROWTH_TEMPLATE resolve to valid files on disk." ;;
            *"Container Deploy"*)  printf '%s' "Container healthy and vault bind-mount accessible — playbooks can execute immediately." ;;
            *"OEMDRV"*)            printf '%s' "Satellite kickstart + OEMDRV ISO build — the VM will boot to unattended OS installation." ;;
            *"Dashboard"*)         printf '%s' "Option 8 is functional — live provisioning progress is visible without leaving the script." ;;
            *"Local Install"*)     printf '%s' "Menu options 1 and 4 are viable on this host." ;;
            *"Virt-Manager"*)      printf '%s' "KVM/libvirt is accessible — VM definitions can be created; menu options 3-5 are viable." ;;
            *"Config-Only"*)       printf '%s' "Config-as-code phases run in order — the full platform can be provisioned from this host." ;;
            *)                     printf '%s' "This stage will not block platform provisioning." ;;
        esac
    }

    # Print the numbered per-test step header and increment the step counter.
    _rhis_test_step_header() {
        local label="$1" why
        _RHIS_TEST_STEP=$((_RHIS_TEST_STEP + 1))
        why="$(_rhis_test_why "${label}")"
        echo ""
        printf "${CYAN}  ┌─ [%d/%d]  ${BOLD}%s${NC}\n" "${_RHIS_TEST_STEP}" "${_RHIS_TEST_TOTAL}" "${label}"
        printf "${DIM}  │   %s${NC}\n" "${why}"
        printf "${CYAN}  └──────────────────────────────────────────────────────────────${NC}\n"
    }

    # ─── Core test machinery ────────────────────────────────────────────────────

    rhis_test_record_result() {
        local label="$1"
        local status="$2"
        local details="${3:-}"
        RHIS_TEST_RESULTS+=("${label}|${status}|${details}")
        if [ "$status" = "fail" ]; then
            RHIS_TEST_FAILURE_COUNT=$((RHIS_TEST_FAILURE_COUNT + 1))
        fi
    }

    rhis_test_run_case() {
        local label="$1"
        shift
        _rhis_test_step_header "${label}"
        if "$@"; then
            printf "${GREEN}  ✔  ${BOLD}%s${NC}${GREEN}  [ PASS ]${NC}\n" "${label}"
            rhis_test_record_result "${label}" "success"
        else
            printf "${RED}  ✘  ${BOLD}%s${NC}${RED}  [ FAIL ]${NC}\n" "${label}"
            rhis_test_record_result "${label}" "fail" \
                "See ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}, ${AAP_HTTP_LOG}, and option 8 dashboard."
        fi
    }

    rhis_test_print_summary() {
        local item label status details impact
        local total_count passed_count skipped_count
        local overall_status demo_display pass_bar fail_bar

        passed_count=0; skipped_count=0
        for item in "${RHIS_TEST_RESULTS[@]}"; do
            IFS='|' read -r label status details <<< "${item}"
            [ "${status}" = "success" ] && passed_count=$((passed_count + 1))
            [ "${status}" = "skipped" ] && skipped_count=$((skipped_count + 1))
        done
        total_count="${#RHIS_TEST_RESULTS[@]}"
        overall_status="PASS"; [ "${RHIS_TEST_FAILURE_COUNT}" -eq 0 ] || overall_status="FAIL"
        demo_display="OFF";    [ "${DEMO_MODE:-0}" = "1" ] && demo_display="ON"

        echo ""
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}${CYAN}        R H I S   ·   Test Suite   Status  Report${NC}\n"
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        echo ""
        printf "  ${BOLD}Profile${NC}  : %-18s   ${BOLD}Demo${NC}  : %s\n" \
            "${CLI_TEST_PROFILE:-full}" "${demo_display}"
        printf "  ${BOLD}Host${NC}     : %-18s   ${BOLD}Date${NC}  : %s\n" \
            "$(hostname -s 2>/dev/null)" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "  ${BOLD}Config${NC}   : %s\n" "${RHIS_ANSIBLE_CFG_HOST}"
        printf "  ${BOLD}Log${NC}      : %s\n" "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
        echo ""
        printf "${CYAN}  ───────────────────────────────────────────────────────────────${NC}\n"
        echo ""

        for item in "${RHIS_TEST_RESULTS[@]}"; do
            IFS='|' read -r label status details <<< "${item}"
            impact="$(_rhis_test_impact "${label}")"
            case "${status}" in
                success)
                    printf "${GREEN}  ✔  ${BOLD}%s${NC}${GREEN}   [ PASS ]${NC}\n" "${label}"
                    printf "${DIM}       ↳  %s${NC}\n" "${impact}"
                    echo ""
                    ;;
                fail)
                    printf "${RED}  ✘  ${BOLD}%s${NC}${RED}   [ FAIL ]${NC}\n" "${label}"
                    printf "${DIM}       ↳  %s${NC}\n" "${impact}"
                    [ -n "${details}" ] && printf "${RED}       ⚑  %s${NC}\n" "${details}"
                    echo ""
                    ;;
                skipped)
                    printf "${YELLOW}  ⊘  ${BOLD}%s${NC}${YELLOW}   [ SKIP ]${NC}\n" "${label}"
                    [ -n "${details}" ] && printf "${DIM}       ↳  %s${NC}\n" "${details}"
                    echo ""
                    ;;
            esac
        done

        printf "${CYAN}  ───────────────────────────────────────────────────────────────${NC}\n"
        echo ""
        pass_bar="$(_rhis_test_bar "${passed_count}"              "${total_count}")"
        fail_bar="$(_rhis_test_bar "${RHIS_TEST_FAILURE_COUNT}"   "${total_count}")"
        printf "  ${GREEN}Passed   :  %d / %d   ${BOLD}%s${NC}\n" \
            "${passed_count}" "${total_count}" "${pass_bar}"
        printf "  ${RED}Failed   :  %d / %d   ${BOLD}%s${NC}\n" \
            "${RHIS_TEST_FAILURE_COUNT}" "${total_count}" "${fail_bar}"
        printf "  ${YELLOW}Skipped  :  %-3d${NC}\n" "${skipped_count}"
        printf "  ${YELLOW}Warnings :  %-3d${NC}\n" "${RHIS_TEST_WARNING_COUNT}"

        if [ -s "${RHIS_TEST_WARNING_FILE}" ]; then
            echo ""
            printf "${YELLOW}  ⚠  Warnings collected during this run:${NC}\n"
            while IFS= read -r wline; do
                printf "  ${YELLOW}  · %s${NC}\n" "${wline}"
            done < <(tail -n 20 "${RHIS_TEST_WARNING_FILE}")
        fi

        echo ""
        printf "${CYAN}  ───────────────────────────────────────────────────────────────${NC}\n"
        echo ""
        if [ "${RHIS_TEST_FAILURE_COUNT}" -eq 0 ]; then
            printf "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}\n"
            printf "${BOLD}${GREEN}  ✔  ALL SYSTEMS GO — Your RHIS stack is ready to build.${NC}\n"
            printf "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}\n"
            echo ""
            return 0
        fi

        printf "${BOLD}${RED}════════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}${RED}  ✘  FAILURES DETECTED — Review the items above before${NC}\n"
        printf "${BOLD}${RED}     attempting a full platform provisioning run.${NC}\n"
        printf "${BOLD}${RED}════════════════════════════════════════════════════════════════${NC}\n"
        echo ""
        return 1
    }

    rhis_run_test_suite() {
        RHIS_TEST_MODE=1
        NONINTERACTIVE=1
        RUN_ONCE=1
        RHIS_TEST_RESULTS=()
        RHIS_TEST_FAILURE_COUNT=0
        RHIS_TEST_WARNING_COUNT=0
        _RHIS_TEST_STEP=0
        : > "${RHIS_TEST_WARNING_FILE}"

        local demo_display="OFF"
        [ "${DEMO_MODE:-0}" = "1" ] && demo_display="ON"

        echo ""
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}${CYAN}   RHIS Integration Test Suite  ·  Curated Validation Run${NC}\n"
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        printf "   Profile : %-12s  Demo : %-6s  Host : %s\n" \
            "${CLI_TEST_PROFILE:-full}" "${demo_display}" "$(hostname -s 2>/dev/null)"
        printf "   Started : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        echo ""
        printf "${DIM}   Each component runs non-interactively.  Results are recorded\n"
        printf "   and presented in the Status Report at the end of this run.${NC}\n"
        echo ""

        if [ "${CLI_TEST_PROFILE:-full}" = "fast" ]; then
            _RHIS_TEST_TOTAL=7
            rhis_test_run_case "Generate RHIS Ansible config"            generate_rhis_ansible_cfg
            rhis_test_run_case "Generate inventory"                      generate_rhis_inventory
            rhis_test_run_case "Generate host_vars"                      generate_rhis_host_vars
            rhis_test_run_case "AAP installer inventory model selection"  select_aap_inventory_templates
            rhis_test_run_case "Container Deployment"                    install_container
            rhis_test_run_case "Generate Satellite OEMDRV"               generate_satellite_oemdrv_only
            _rhis_test_step_header "Live Status Dashboard snapshot"
            RHIS_DASHBOARD_SINGLE_SHOT=1
            if show_live_status_dashboard; then
                printf "${GREEN}  ✔  ${BOLD}Live Status Dashboard snapshot${NC}${GREEN}  [ PASS ]${NC}\n"
                rhis_test_record_result "Live Status Dashboard snapshot" "success" \
                    "Rendered single-shot dashboard snapshot."
            else
                printf "${RED}  ✘  ${BOLD}Live Status Dashboard snapshot${NC}${RED}  [ FAIL ]${NC}\n"
                rhis_test_record_result "Live Status Dashboard snapshot" "fail" \
                    "Dashboard snapshot could not be rendered."
            fi
            RHIS_DASHBOARD_SINGLE_SHOT=0
            rhis_test_print_summary
            return $?
        fi

        _RHIS_TEST_TOTAL=7
        rhis_test_run_case "AAP installer inventory model selection"  select_aap_inventory_templates
        rhis_test_run_case "1) Local App Mode (legacy/optional)"     install_local
        rhis_test_run_case "2) Container Deployment"                 install_container
        rhis_test_run_case "3) Setup Virt-Manager Only"              setup_virt_manager
        echo ""
        printf "${YELLOW}  ⊘  ${BOLD}4) Full Setup (Local + Virt-Manager)${NC}${YELLOW}   [ SKIP ]${NC}\n"
        printf "${DIM}       ↳  Covered by items 1 + 3 — avoids duplicate heavy provisioning.${NC}\n"
        rhis_test_record_result "4) Full Setup (Local + Virt-Manager)" "skipped" \
            "Covered by test items 1 + 3 to avoid duplicate heavy provisioning."
        echo ""
        printf "${YELLOW}  ⊘  ${BOLD}5) Full Setup (Container + Virt-Manager)${NC}${YELLOW}   [ SKIP ]${NC}\n"
        printf "${DIM}       ↳  Covered by items 2 + 3 — avoids duplicate heavy provisioning.${NC}\n"
        rhis_test_record_result "5) Full Setup (Container + Virt-Manager)" "skipped" \
            "Covered by test items 2 + 3 to avoid duplicate heavy provisioning."
        echo ""
        rhis_test_run_case "6) Generate Satellite OEMDRV Only"  generate_satellite_oemdrv_only
        rhis_test_run_case "7) Container Config-Only"           run_container_config_only
        _rhis_test_step_header "8) Live Status Dashboard"
        RHIS_DASHBOARD_SINGLE_SHOT=1
        if show_live_status_dashboard; then
            printf "${GREEN}  ✔  ${BOLD}8) Live Status Dashboard${NC}${GREEN}  [ PASS ]${NC}\n"
            rhis_test_record_result "8) Live Status Dashboard" "success" \
                "Rendered single-shot dashboard snapshot."
        else
            printf "${RED}  ✘  ${BOLD}8) Live Status Dashboard${NC}${RED}  [ FAIL ]${NC}\n"
            rhis_test_record_result "8) Live Status Dashboard" "fail" \
                "Dashboard snapshot could not be rendered."
        fi
        RHIS_DASHBOARD_SINGLE_SHOT=0
        rhis_test_print_summary
    }
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --non-interactive|--noninteractive)
                CLI_NONINTERACTIVE="1"
                RUN_ONCE=1
                ;;
            --menu-choice)
                shift
                [ "$#" -gt 0 ] || {
                    print_warning "--menu-choice requires a value"
                    exit 1
                }
                CLI_MENU_CHOICE="$1"
                RUN_ONCE=1
                ;;
            --env-file)
                shift
                [ "$#" -gt 0 ] || {
                    print_warning "--env-file requires a path"
                    exit 1
                }
                PRESEED_ENV_FILE="$1"
                ;;
            --inventory)
                shift
                [ "$#" -gt 0 ] || {
                    print_warning "--inventory requires a template name or absolute path"
                    exit 1
                }
                CLI_AAP_INVENTORY_TEMPLATE="$1"
                ;;
            --inventory-growth)
                shift
                [ "$#" -gt 0 ] || {
                    print_warning "--inventory-growth requires a template name or absolute path"
                    exit 1
                }
                CLI_AAP_INVENTORY_GROWTH_TEMPLATE="$1"
                ;;
            --container-config-only)
                CLI_CONTAINER_CONFIG_ONLY="1"
                RUN_ONCE=1
                ;;
            --attach-consoles)
                CLI_ATTACH_CONSOLES="1"
                RUN_ONCE=1
                ;;
            --status)
                CLI_STATUS="1"
                CLI_NONINTERACTIVE="1"
                RUN_ONCE=1
                ;;
            --test|--TEST)
                CLI_TEST="1"
                CLI_TEST_PROFILE="full"
                RUN_ONCE=1
                ;;
            --test=fast|--TEST=fast)
                CLI_TEST="1"
                CLI_TEST_PROFILE="fast"
                RUN_ONCE=1
                ;;
            --test=full|--TEST=full)
                CLI_TEST="1"
                CLI_TEST_PROFILE="full"
                RUN_ONCE=1
                ;;
            --demo|--DEMO)
                CLI_DEMO="1"
                ;;
            --demokill|--DEMOKILL)
                CLI_DEMOKILL="1"
                RUN_ONCE=1
                ;;
            --reconfigure)
                CLI_RECONFIGURE="1"
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                print_warning "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done
}

apply_cli_overrides() {
    if [ -n "$CLI_NONINTERACTIVE" ]; then
        NONINTERACTIVE="$CLI_NONINTERACTIVE"
    fi

    if [ -n "$CLI_MENU_CHOICE" ]; then
        MENU_CHOICE="$CLI_MENU_CHOICE"
    fi

    if [ -n "$CLI_DEMO" ]; then
        DEMO_MODE="$CLI_DEMO"
    fi

    if [ -n "$CLI_DEMOKILL" ]; then
        :
    fi

    if [ -n "$CLI_RECONFIGURE" ]; then
        FORCE_PROMPT_ALL=1
    fi

    if [ -n "$CLI_AAP_INVENTORY_TEMPLATE" ]; then
        AAP_INVENTORY_TEMPLATE="$CLI_AAP_INVENTORY_TEMPLATE"
    fi

    if [ -n "$CLI_AAP_INVENTORY_GROWTH_TEMPLATE" ]; then
        AAP_INVENTORY_GROWTH_TEMPLATE="$CLI_AAP_INVENTORY_GROWTH_TEMPLATE"
    fi

    if [ -n "$CLI_CONTAINER_CONFIG_ONLY" ]; then
        MENU_CHOICE="7"
    fi

    if [ -n "$CLI_ATTACH_CONSOLES" ]; then
        MENU_CHOICE="7"
    fi

    if [ -n "$CLI_TEST" ]; then
        RHIS_TEST_MODE=1
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    if [ -n "$CLI_STATUS" ]; then
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    return 0
}

is_noninteractive() {
    case "${NONINTERACTIVE:-0}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_demo() {
    case "${DEMO_MODE:-0}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_enabled() {
    case "${1:-0}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

probe_ssh_endpoint() {
    local ip="$1"
    local err

    if timeout 5 ssh \
        -o BatchMode=yes \
        -o PreferredAuthentications=none \
        -o PasswordAuthentication=no \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        "root@${ip}" true >/dev/null 2>&1; then
        return 0
    fi

    err="$(timeout 5 ssh \
        -o BatchMode=yes \
        -o PreferredAuthentications=none \
        -o PasswordAuthentication=no \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        "root@${ip}" true 2>&1 || true)"

    printf '%s' "$err" | grep -Eqi 'permission denied|authentication failed|denied \(publickey\)|too many authentication failures'
}

load_preseed_env() {
    if [ -f "$PRESEED_ENV_FILE" ]; then
        print_step "Loading preseed variables from $PRESEED_ENV_FILE"
        set -a
        # shellcheck disable=SC1090
        . "$PRESEED_ENV_FILE"
        set +a
    fi
}

to_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

derive_gateway_from_network() {
    local network_addr="${1:-}"
    if printf '%s' "$network_addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        printf '%s\n' "$network_addr" | sed -E 's/\.[0-9]+$/\.1/'
        return 0
    fi
    printf '%s\n' "10.168.0.1"
}

is_unresolved_template_value() {
    local value="${1:-}"
    case "$value" in
        *"{{"*|*"}}"*)
            return 0
            ;;
        "example.com"|"example.org"|"EXAMPLE.COM"|"EXAMPLE.ORG")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

needs_prompt_var() {
    local var_name="$1"
    local value="${!var_name:-}"
    if [ -z "$value" ] || is_unresolved_template_value "$value"; then
        return 0
    fi
    return 1
}

normalize_shared_env_vars() {
    # Guard against unresolved templating artifacts such as '{{ DOMAIN }}'.
    if is_unresolved_template_value "${DOMAIN:-}"; then
        DOMAIN=""
    fi
    if is_unresolved_template_value "${SAT_DOMAIN:-}"; then
        SAT_DOMAIN=""
    fi
    if is_unresolved_template_value "${AAP_DOMAIN:-}"; then
        AAP_DOMAIN=""
    fi
    if is_unresolved_template_value "${IDM_DOMAIN:-}"; then
        IDM_DOMAIN=""
    fi

    DOMAIN="${DOMAIN:-${SAT_DOMAIN:-${AAP_DOMAIN:-${IDM_DOMAIN:-}}}}"
    REALM="${REALM:-${IDM_REALM:-${SAT_REALM:-}}}"
    [ -n "${REALM:-}" ] || REALM="$(to_upper "$DOMAIN")"

    ADMIN_USER="${ADMIN_USER:-admin}"
    # Global admin password is the authoritative root password for all systems.
    # Do not infer it from per-system service/admin passwords.
    ADMIN_PASS="${ADMIN_PASS:-r3dh4t7!}"  # fallback only if vault did not supply a value
    ROOT_PASS="${ADMIN_PASS}"
    IDM_ADMIN_PASS="${IDM_ADMIN_PASS:-${ADMIN_PASS}}"
    IPADM_PASSWORD="${IPADM_PASSWORD:-${IDM_ADMIN_PASS:-${ADMIN_PASS}}}"
    IPAADMIN_PASSWORD="${IPAADMIN_PASSWORD:-${IDM_ADMIN_PASS:-${ADMIN_PASS}}}"

    INTERNAL_NETWORK="${INTERNAL_NETWORK:-10.168.0.0}"
    NETMASK="${NETMASK:-${SAT_NETMASK:-${AAP_NETMASK:-${IDM_NETMASK:-255.255.0.0}}}}"
    INTERNAL_GW="${INTERNAL_GW:-${SAT_GW:-${AAP_GW:-${IDM_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK}")}}}}"

    SAT_IP="${SAT_IP:-10.168.128.1}"
    AAP_IP="${AAP_IP:-10.168.128.2}"
    IDM_IP="${IDM_IP:-10.168.128.3}"

    SAT_ORG="${SAT_ORG:-REDHAT}"
    SAT_LOC="${SAT_LOC:-CORE}"

    case "${SATELLITE_DISCONNECTED:-false}" in
        1|true|TRUE|yes|YES|on|ON)
            SATELLITE_DISCONNECTED="true"
            ;;
        *)
            SATELLITE_DISCONNECTED="false"
            ;;
    esac

    case "${REGISTER_TO_SATELLITE:-false}" in
        1|true|TRUE|yes|YES|on|ON)
            REGISTER_TO_SATELLITE="true"
            ;;
        *)
            REGISTER_TO_SATELLITE="false"
            ;;
    esac

    case "${SATELLITE_PRE_USE_IDM:-false}" in
        1|true|TRUE|yes|YES|on|ON)
            SATELLITE_PRE_USE_IDM="true"
            ;;
        *)
            SATELLITE_PRE_USE_IDM="false"
            ;;
    esac

    SAT_DOMAIN="${SAT_DOMAIN:-$DOMAIN}"
    AAP_DOMAIN="${AAP_DOMAIN:-$DOMAIN}"
    IDM_DOMAIN="${IDM_DOMAIN:-$DOMAIN}"
    SAT_FIREWALLD_ZONE="${SAT_FIREWALLD_ZONE:-public}"
    SAT_FIREWALLD_INTERFACE="${SAT_FIREWALLD_INTERFACE:-eth1}"
    SAT_FIREWALLD_SERVICES_JSON="${SAT_FIREWALLD_SERVICES_JSON:-[\"ssh\",\"http\",\"https\"]}"

    if is_unresolved_template_value "${SAT_HOSTNAME:-}"; then
        SAT_HOSTNAME=""
    fi
    if is_unresolved_template_value "${AAP_HOSTNAME:-}"; then
        AAP_HOSTNAME=""
    fi
    if is_unresolved_template_value "${IDM_HOSTNAME:-}"; then
        IDM_HOSTNAME=""
    fi

    SAT_HOSTNAME="${SAT_HOSTNAME:-satellite-618.${DOMAIN}}"
    AAP_HOSTNAME="${AAP_HOSTNAME:-aap-26.${DOMAIN}}"
    IDM_HOSTNAME="${IDM_HOSTNAME:-idm.${DOMAIN}}"
    SAT_ALIAS="${SAT_ALIAS:-satellite}"
    AAP_ALIAS="${AAP_ALIAS:-aap}"
    IDM_ALIAS="${IDM_ALIAS:-idm}"

    SAT_REALM="${SAT_REALM:-$REALM}"
    IDM_REALM="${IDM_REALM:-$REALM}"

    # Per-system admin passwords are intentionally unified to the global value.
    SAT_ADMIN_PASS="${ADMIN_PASS}"
    AAP_ADMIN_PASS="${ADMIN_PASS}"
    IDM_ADMIN_PASS="${ADMIN_PASS}"
    IDM_DS_PASS="${IDM_DS_PASS:-${ADMIN_PASS}}"

    SAT_NETMASK="${SAT_NETMASK:-$NETMASK}"
    AAP_NETMASK="${AAP_NETMASK:-$NETMASK}"
    IDM_NETMASK="${IDM_NETMASK:-$NETMASK}"

    SAT_GW="${SAT_GW:-$INTERNAL_GW}"
    AAP_GW="${AAP_GW:-$INTERNAL_GW}"
    IDM_GW="${IDM_GW:-$INTERNAL_GW}"
}

set_or_prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local is_secret="${3:-0}"
    local prompt_value
    local lower_prompt prompt_label

    lower_prompt="$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')"
    prompt_label="$prompt_text"
    if [[ "$lower_prompt" != *"optional"* ]] && [[ "$lower_prompt" != *"required"* ]]; then
        prompt_label="${prompt_text} [Required]"
    fi

    if [ -n "${!var_name:-}" ]; then
        return 0
    fi

    if is_noninteractive; then
        print_warning "NONINTERACTIVE mode requires $var_name to be set."
        return 1
    fi

    if [ "$is_secret" = "1" ]; then
        read -r -s -p "$prompt_label" prompt_value
        echo ""
    else
        read -r -p "$prompt_label" prompt_value
    fi

    printf -v "$var_name" '%s' "$prompt_value"

    [ -n "${!var_name:-}" ]
}

set_or_prompt_optional() {
    local var_name="$1"
    local prompt_text="$2"
    local is_secret="${3:-0}"
    local prompt_value
    local prompt_label
    prompt_label="$prompt_text"

    if [ -n "${!var_name:-}" ]; then
        return 0
    fi

    if is_noninteractive; then
        return 0
    fi

    if [ "$is_secret" = "1" ]; then
        read -r -s -p "$prompt_label" prompt_value
        echo ""
    else
        read -r -p "$prompt_label" prompt_value
    fi

    printf -v "$var_name" '%s' "$prompt_value"
    return 0
}

prompt_with_default() {
    local var_name="$1"
    local prompt_label="$2"
    local default_value="${3:-}"
    local is_secret="${4:-0}"
    local is_required="${5:-0}"
    local input_value=""
    local prompt_with_meta
    prompt_with_meta="$prompt_label"

    if is_noninteractive; then
        if [ -n "${!var_name:-}" ] && ! is_unresolved_template_value "${!var_name:-}"; then
            return 0
        fi
        if [ -n "$default_value" ] && ! is_unresolved_template_value "$default_value"; then
            printf -v "$var_name" '%s' "$default_value"
            return 0
        fi
        [ "$is_required" = "1" ] && {
            print_warning "NONINTERACTIVE mode requires $var_name to be set."
            return 1
        }
        return 0
    fi

    while true; do
        if [ "$is_secret" = "1" ]; then
            read -r -s -p "$prompt_with_meta: " input_value
            echo ""
        else
            if [ -n "$default_value" ]; then
                read -r -p "$prompt_with_meta [$default_value]: " input_value
            else
                read -r -p "$prompt_with_meta: " input_value
            fi
        fi

        [ -n "$input_value" ] || input_value="$default_value"

        if [ "$is_required" = "1" ] && [ -z "$input_value" ]; then
            print_warning "$var_name is required. Please provide a value."
            continue
        fi

        if is_unresolved_template_value "$input_value"; then
            print_warning "$var_name contains an unresolved template placeholder. Please provide an actual value."
            continue
        fi

        printf -v "$var_name" '%s' "$input_value"
        return 0
    done
}

count_missing_vars() {
    local missing=0
    local var_name
    local value

    for var_name in "$@"; do
        value="${!var_name:-}"
        if [ -z "$value" ] || is_unresolved_template_value "$value"; then
            missing=$((missing + 1))
        fi
    done

    printf '%s' "$missing"
}

validate_resolved_kickstart_inputs() {
    local failed=0
    local var_name value
    local -a required_vars=(
        DOMAIN INTERNAL_NETWORK
        SAT_IP AAP_IP IDM_IP
        SAT_NETMASK AAP_NETMASK IDM_NETMASK
        SAT_GW AAP_GW IDM_GW
        SAT_HOSTNAME AAP_HOSTNAME IDM_HOSTNAME
        SAT_ORG SAT_LOC
        RH_USER RH_PASS RH_ISO_URL RH9_ISO_URL
        AAP_BUNDLE_URL RH_OFFLINE_TOKEN HUB_TOKEN
    )

    for var_name in "${required_vars[@]}"; do
        value="${!var_name:-}"
        if [ -z "$value" ] || is_unresolved_template_value "$value"; then
            print_warning "Missing or unresolved required value: $var_name"
            failed=1
        fi
    done

    if [ "$failed" -ne 0 ]; then
        print_warning "Cannot generate kickstarts until required values are resolved."
        return 1
    fi

    return 0
}

# Menu selection
show_menu() {
    if [ -n "${MENU_CHOICE:-}" ]; then
        choice="$MENU_CHOICE"
        print_step "Using preseeded menu choice: $choice"
        MENU_CHOICE_CONSUMED=1
        if ! is_noninteractive && [ "${RUN_ONCE:-0}" != "1" ]; then
            MENU_CHOICE=""
        fi
        return 0
    fi

    echo ""
    echo "Select installation option:"
    echo "0) Exit"
    echo "1) Local App Mode (npm, legacy/optional)"
    echo "2) Container Deployment (Podman)"
    echo "3) Setup Virt-Manager Only"
    echo "4) Full Setup (Local + Virt-Manager)"
    echo "5) Full Setup (Container + Virt-Manager)"
    echo "6) Generate Satellite OEMDRV Only"
    echo "7) Container Config-Only (IdM -> Satellite -> AAP)"
    echo "8) Live Status Dashboard"
    echo ""
    read -r -p "Enter choice [0-8]: " choice
}

show_live_status_dashboard() {
    local key=""
    local refresh_seconds="5"
    local vm state ip cmdb_status
    local sat_ip=""
    local ansible_log_host="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    local container_name="${RHIS_CONTAINER_NAME:-rhis-provisioner}"
    local container_state="stopped"
    local container_status_line=""
    local container_activity="idle"
    local phase_label="IDLE"

    while true; do
        command -v clear >/dev/null 2>&1 && clear

        # Phase badge inference (best-effort)
        phase_label="IDLE / WAITING"
        if pgrep -af "ansible-playbook|ansible-runner" >/dev/null 2>&1; then
            phase_label="ANSIBLE CONFIG-AS-CODE"
        elif pgrep -af "python3 -m http.server 8080" >/dev/null 2>&1; then
            phase_label="AAP VM INSTALL / BUNDLE DELIVERY"
        elif pgrep -af "virt-install|qemu-img create" >/dev/null 2>&1; then
            phase_label="VM PROVISIONING"
        elif pgrep -af "run_rhis_install_sequence.sh" >/dev/null 2>&1; then
            phase_label="SCRIPT RUNNING (BETWEEN PHASES)"
        fi

        echo "============================================================"
        echo " RHIS Live Status Dashboard"
        echo " Phase: ${phase_label}"
        echo " $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================================"
        echo ""

        echo "[VM states]"
        sudo -n virsh list --all 2>/dev/null || sudo virsh list --all 2>/dev/null || true
        echo ""

        echo "[VM network addresses]"
        for vm in satellite-618 aap-26 idm; do
            echo "- ${vm}"
            sudo -n virsh domifaddr "${vm}" 2>/dev/null | sed '1,2d' || sudo virsh domifaddr "${vm}" 2>/dev/null | sed '1,2d' || true
        done
        echo ""

        echo "[Script / provisioning activity]"
        pgrep -af "run_rhis_install_sequence.sh|python3 -m http.server 8080|ansible-playbook|virsh console|podman exec" 2>/dev/null || echo "(no matching activity processes found)"
        echo ""

        echo "[Container status]"
        if podman ps --filter "name=^${container_name}$" --format '{{.Names}}|{{.Status}}|{{.Image}}' | grep -q "^${container_name}|"; then
            container_state="running"
            container_status_line="$(podman ps --filter "name=^${container_name}$" --format '{{.Names}}|{{.Status}}|{{.Image}}' | head -1)"
            if podman exec "${container_name}" pgrep -af "ansible-playbook|ansible-runner|python3" >/dev/null 2>&1; then
                container_activity="active (processes running)"
            else
                container_activity="running (no active playbook process detected)"
            fi
            echo "- State: ${container_state}"
            echo "- Details: ${container_status_line}"
            echo "- Activity: ${container_activity}"
            echo "- Recent logs:"
            podman logs --tail 8 "${container_name}" 2>/dev/null || echo "(no container logs available)"
        else
            container_state="stopped"
            echo "- State: ${container_state}"
            echo "- Details: ${container_name} not running"
            echo "- Activity: none"
        fi
        echo ""

        echo "[Ansible provisioner log]"
        echo "- Log file: ${ansible_log_host}"
        if [ -f "${ansible_log_host}" ]; then
            tail -n 12 "${ansible_log_host}" 2>/dev/null || true
        else
            echo "(log file not created yet)"
        fi
        echo ""

        echo "[AAP bundle HTTP log]"
        echo "- Log file: ${AAP_HTTP_LOG}"
        if [ -f "${AAP_HTTP_LOG}" ]; then
            tail -n 8 "${AAP_HTTP_LOG}" 2>/dev/null || true
        else
            echo "(log file not created yet)"
        fi
        echo ""

        echo "[AAP callback logs]"
        ls -lt /tmp/aap-setup-*.log 2>/dev/null | head -5 || echo "(no AAP callback log yet)"
        echo ""

        sat_ip="$(sudo -n virsh domifaddr satellite-618 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1 || true)"
        if [ -n "$sat_ip" ]; then
            if timeout 2 bash -lc "cat < /dev/tcp/${sat_ip}/18080" >/dev/null 2>&1; then
                cmdb_status="OPEN"
            else
                cmdb_status="CLOSED"
            fi
            echo "[Satellite CMDB dashboard]"
            echo "- URL: http://${sat_ip}:18080/"
            echo "- Port 18080: ${cmdb_status}"
        else
            echo "[Satellite CMDB dashboard]"
            echo "- Satellite IP not detected yet"
        fi
        echo ""

        if is_enabled "${RHIS_DASHBOARD_SINGLE_SHOT:-0}"; then
            return 0
        fi

        echo "Press [q] to return to menu. Auto-refresh every ${refresh_seconds}s..."
        read -r -t "${refresh_seconds}" -n 1 key || true
        case "${key}" in
            q|Q)
                echo ""
                return 0
                ;;
        esac
    done
}

reattach_vm_consoles() {
    print_step "Reattaching VM console monitors for Satellite/AAP/IdM"
    launch_vm_console_monitors_auto || {
        print_warning "Could not reattach VM console monitors automatically."
        return 1
    }

    if command -v tmux >/dev/null 2>&1; then
        print_step "If running headless, attach monitor session with: tmux attach -t ${RHIS_VM_MONITOR_SESSION}"
    fi

    print_success "VM console monitors reattached."
    return 0
}

get_vm_console_label() {
    case "$1" in
        satellite-618) printf '%s\n' "${SAT_HOSTNAME:-satellite-618}" ;;
        aap-26)        printf '%s\n' "${AAP_HOSTNAME:-aap-26}" ;;
        idm)           printf '%s\n' "${IDM_HOSTNAME:-idm}" ;;
        *)             printf '%s\n' "$1" ;;
    esac
}

launch_vm_console_monitors_auto() {
    local -a vms=("satellite-618" "aap-26" "idm")
    local vm vm_label launched=0
    local term_pid

    stop_vm_console_monitors >/dev/null 2>&1 || true
    : > "${RHIS_VM_MONITOR_PID_FILE}"

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping VM console monitor auto-launch."
        return 0
    fi

    # GUI terminal popups (preferred)
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if command -v gnome-terminal >/dev/null 2>&1; then
            for vm in "${vms[@]}"; do
                vm_label="$(get_vm_console_label "${vm}")"
                gnome-terminal --title="${vm_label}" -- bash -lc "printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] waiting for VM definition...'; while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; sudo virsh console ${vm} || true; exec bash" >/dev/null 2>&1 &
                term_pid=$!
                echo "$term_pid" >> "${RHIS_VM_MONITOR_PID_FILE}"
            done
            launched=1
        elif command -v x-terminal-emulator >/dev/null 2>&1; then
            for vm in "${vms[@]}"; do
                vm_label="$(get_vm_console_label "${vm}")"
                x-terminal-emulator -e bash -lc "printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] waiting for VM definition...'; while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; sudo virsh console ${vm} || true; exec bash" >/dev/null 2>&1 &
                term_pid=$!
                echo "$term_pid" >> "${RHIS_VM_MONITOR_PID_FILE}"
            done
            launched=1
        elif command -v konsole >/dev/null 2>&1; then
            for vm in "${vms[@]}"; do
                vm_label="$(get_vm_console_label "${vm}")"
                konsole --title "${vm_label}" -e bash -lc "printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] waiting for VM definition...'; while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; sudo virsh console ${vm} || true; exec bash" >/dev/null 2>&1 &
                term_pid=$!
                echo "$term_pid" >> "${RHIS_VM_MONITOR_PID_FILE}"
            done
            launched=1
        elif command -v xterm >/dev/null 2>&1; then
            for vm in "${vms[@]}"; do
                vm_label="$(get_vm_console_label "${vm}")"
                xterm -T "${vm_label}" -e bash -lc "printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] waiting for VM definition...'; while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; sudo virsh console ${vm} || true; exec bash" >/dev/null 2>&1 &
                term_pid=$!
                echo "$term_pid" >> "${RHIS_VM_MONITOR_PID_FILE}"
            done
            launched=1
        fi
    fi

    if [ "$launched" = "1" ]; then
        print_step "Opened 3 console monitor terminals (Satellite/AAP/IdM)."
        return 0
    fi

    # Headless fallback: detached tmux session (non-blocking)
    if command -v tmux >/dev/null 2>&1; then
        local sat_label aap_label idm_label
        sat_label="$(get_vm_console_label "satellite-618")"
        aap_label="$(get_vm_console_label "aap-26")"
        idm_label="$(get_vm_console_label "idm")"
        tmux has-session -t "$RHIS_VM_MONITOR_SESSION" 2>/dev/null && tmux kill-session -t "$RHIS_VM_MONITOR_SESSION"
        tmux new-session -d -s "$RHIS_VM_MONITOR_SESSION" -n "$sat_label" "bash -lc 'echo [${sat_label}] waiting for VM definition...; while ! sudo virsh dominfo satellite-618 >/dev/null 2>&1; do sleep 5; done; echo [${sat_label}] connecting virsh console \(Ctrl+\] to detach\); sudo virsh console satellite-618 || true'"
        tmux split-window -h -t "$RHIS_VM_MONITOR_SESSION:0" "bash -lc 'echo [${aap_label}] waiting for VM definition...; while ! sudo virsh dominfo aap-26 >/dev/null 2>&1; do sleep 5; done; echo [${aap_label}] connecting virsh console \(Ctrl+\] to detach\); sudo virsh console aap-26 || true'"
        tmux split-window -v -t "$RHIS_VM_MONITOR_SESSION:0.0" "bash -lc 'echo [${idm_label}] waiting for VM definition...; while ! sudo virsh dominfo idm >/dev/null 2>&1; do sleep 5; done; echo [${idm_label}] connecting virsh console \(Ctrl+\] to detach\); sudo virsh console idm || true'"
        tmux select-layout -t "$RHIS_VM_MONITOR_SESSION:0" tiled >/dev/null 2>&1 || true
        tmux select-pane -t "$RHIS_VM_MONITOR_SESSION:0.0" -T "$sat_label" >/dev/null 2>&1 || true
        tmux select-pane -t "$RHIS_VM_MONITOR_SESSION:0.1" -T "$aap_label" >/dev/null 2>&1 || true
        tmux select-pane -t "$RHIS_VM_MONITOR_SESSION:0.2" -T "$idm_label" >/dev/null 2>&1 || true
        print_step "No GUI terminal detected. Started tmux console monitor session: $RHIS_VM_MONITOR_SESSION"
        print_step "Attach anytime with: tmux attach -t $RHIS_VM_MONITOR_SESSION"
        return 0
    fi

    print_warning "No GUI terminal emulator or tmux found; skipping auto console monitor launch."
    return 0
}

stop_vm_console_monitors() {
    local pid

    if command -v tmux >/dev/null 2>&1; then
        tmux has-session -t "$RHIS_VM_MONITOR_SESSION" 2>/dev/null && tmux kill-session -t "$RHIS_VM_MONITOR_SESSION" || true
    fi

    if [ -f "$RHIS_VM_MONITOR_PID_FILE" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" >/dev/null 2>&1 || true
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < "$RHIS_VM_MONITOR_PID_FILE"
        rm -f "$RHIS_VM_MONITOR_PID_FILE"
    fi

    return 0
}

start_vm_power_watchdog() {
    local duration_sec="${1:-10800}"  # default: 3 hours
    local interval_sec=15

    stop_vm_power_watchdog >/dev/null 2>&1 || true

    (
        local end_ts now state vm
        local -a vms=("satellite-618" "aap-26" "idm")

        end_ts=$(( $(date +%s) + duration_sec ))
        while true; do
            now="$(date +%s)"
            [ "$now" -lt "$end_ts" ] || break

            for vm in "${vms[@]}"; do
                if ! sudo virsh dominfo "$vm" >/dev/null 2>&1; then
                    continue
                fi

                sudo virsh autostart "$vm" >/dev/null 2>&1 || true
                state="$(sudo virsh domstate "$vm" 2>/dev/null | tr -d '[:space:]' || true)"
                case "$state" in
                    running|inshutdown|paused|blocked)
                        ;;
                    shutoff|crashed|pmsuspended)
                        sudo virsh start "$vm" >/dev/null 2>&1 || true
                        ;;
                esac
            done

            sleep "$interval_sec"
        done
    ) >/dev/null 2>&1 &

    RHIS_VM_WATCHDOG_PID="$!"
    print_step "Started VM power watchdog (PID ${RHIS_VM_WATCHDOG_PID}) to keep Satellite/AAP/IdM ON"
    return 0
}

stop_vm_power_watchdog() {
    if [ -n "${RHIS_VM_WATCHDOG_PID:-}" ]; then
        kill "${RHIS_VM_WATCHDOG_PID}" >/dev/null 2>&1 || true
        wait "${RHIS_VM_WATCHDOG_PID}" >/dev/null 2>&1 || true
        RHIS_VM_WATCHDOG_PID=""
    fi
    return 0
}

force_kill_rhis_leftovers() {
    local -a patterns=(
        "python3 -m http.server 8080 --bind"
        "virsh console satellite-618"
        "virsh console aap-26"
        "virsh console idm"
        "rhis-vm-consoles"
        "curl -fL --retry 3 --retry-delay 10"
        "aap-bundle.tar.gz"
        "setup.sh 2>&1"
        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${AAP_SSH_PRIVATE_KEY}"
    )
    local pattern

    print_step "Force-killing RHIS leftover processes from current/past runs"
    for pattern in "${patterns[@]}"; do
        sudo pkill -9 -f "$pattern" >/dev/null 2>&1 || true
    done

    # Also hard-kill any tracked monitor terminal PIDs from previous runs.
    if [ -f "$RHIS_VM_MONITOR_PID_FILE" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < "$RHIS_VM_MONITOR_PID_FILE"
        rm -f "$RHIS_VM_MONITOR_PID_FILE"
    fi

    return 0
}

# Ensure Node.js is installed
ensure_node() {
    if command -v node >/dev/null 2>&1; then
        return 0
    fi

    print_warning "Node.js not found. Attempting installation..."
    sudo dnf install -y --nogpgcheck nodejs npm
    command -v node >/dev/null 2>&1
}

# Security helper functions
ensure_selinux() {
    if ! command -v getenforce >/dev/null 2>&1; then
        print_warning "SELinux tools not found; skipping SELinux checks."
        return 0
    fi

    local mode
    mode="$(getenforce || true)"
    case "$mode" in
        Enforcing)
            print_step "SELinux is Enforcing"
            ;;
        Permissive)
            print_warning "SELinux is Permissive; switching to Enforcing (runtime)"
            sudo setenforce 1 || print_warning "Could not set SELinux to Enforcing at runtime."
            ;;
        Disabled)
            print_warning "SELinux is Disabled. Enable it in /etc/selinux/config and reboot."
            ;;
        *)
            print_warning "Unknown SELinux state: $mode"
            ;;
    esac
}

ensure_firewalld() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        print_warning "firewalld not found. Attempting installation..."
        sudo dnf install -y --nogpgcheck firewalld
    fi

    sudo systemctl enable --now firewalld
    sudo firewall-cmd --state >/dev/null
    print_step "firewalld is enabled and running"
}

configure_rhis_network_policy() {
    ensure_selinux
    ensure_firewalld || return 0

    # RHIS dashboard/API
    sudo firewall-cmd --permanent --add-port=3000/tcp
    sudo firewall-cmd --reload

    # SELinux port label for web-style service on 3000
    if command -v semanage >/dev/null 2>&1; then
        if ! sudo semanage port -l | grep -qE '^http_port_t.*\btcp\b.*\b3000\b'; then
            sudo semanage port -a -t http_port_t -p tcp 3000 2>/dev/null \
                || sudo semanage port -m -t http_port_t -p tcp 3000
        fi
    else
        print_warning "semanage not found; install policycoreutils-python-utils if SELinux port labeling is required."
    fi

    print_step "Security policy applied for RHIS (SELinux + firewalld port 3000)"
}

configure_libvirt_firewall_policy() {
    ensure_selinux
    ensure_firewalld || return 0

    # Keep remote/libvirt management reachable where applicable.
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-service=libvirt 2>/dev/null || true
    sudo firewall-cmd --reload

    print_step "Security policy applied for libvirt/virt-manager"
}

configure_libvirt_networks() {
    print_step "Configuring libvirt networks (ensure external + create internal)"

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping libvirt network configuration."
        return 0
    fi

    # Keep libvirt's default network untouched; only ensure 'external' exists.
    if ! sudo virsh net-info external >/dev/null 2>&1; then
        print_step "Creating network: external (NAT/DHCP fallback for first guest interface)"
        cat <<'EOF' | sudo tee /tmp/external.xml >/dev/null
<network>
    <name>external</name>
    <forward mode='nat'/>
    <bridge name='virbr-external' stp='on' delay='0'/>
    <ip address='192.168.122.1' netmask='255.255.255.0'>
        <dhcp>
            <range start='192.168.122.2' end='192.168.122.254'/>
        </dhcp>
    </ip>
</network>
EOF
        sudo virsh net-define /tmp/external.xml
    else
        print_step "Network 'external' already exists"
    fi

    sudo virsh net-start external >/dev/null 2>&1 || true
    sudo virsh net-autostart external

        # Create internal static network with no DHCP
    if ! sudo virsh net-info internal >/dev/null 2>&1; then
                print_step "Creating network: internal (${INTERNAL_NETWORK}/${NETMASK}, static, no DHCP)"
                cat <<EOF | sudo tee /tmp/internal.xml >/dev/null
<network>
  <name>internal</name>
  <bridge name='virbr-internal' stp='on' delay='0'/>
  <dns enable='no'/>
    <ip address='${INTERNAL_GW}' netmask='${NETMASK}'/>
</network>
EOF
        sudo virsh net-define /tmp/internal.xml
    else
        print_step "Network 'internal' already exists"
    fi

    sudo virsh net-start internal >/dev/null 2>&1 || true
    sudo virsh net-autostart internal

    print_success "Libvirt network configuration complete"
    sudo virsh net-list --all
}

# Local Installation
install_local() {
    print_step "Starting Local Installation"
    configure_rhis_network_policy

    if ! ensure_node; then
        print_warning "Node.js installation failed. Please install Node.js first."
        return 1
    fi

    print_step "Resolving RHIS project directory"
    cd "$SCRIPT_DIR"

    if [ -f "package.json" ]; then
        print_step "Using script directory as RHIS project: $SCRIPT_DIR"
    elif [ -n "$REPO_URL" ] && [[ "$REPO_URL" != *"your-org/RHIS.git"* ]]; then
        print_step "No local package.json found, cloning from REPO_URL"
        if [ ! -d "RHIS/.git" ]; then
            git clone "$REPO_URL" RHIS
        fi
        cd RHIS
    else
        print_warning "No local package.json found in $SCRIPT_DIR (npm app mode unavailable)."
        print_warning "RHIS in this repository is infrastructure/container-first."
        print_warning "Use menu option 2 (Container Deployment) or 7 (Container Config-Only)."
        if is_noninteractive; then
            use_container="Y"
            print_step "NONINTERACTIVE mode: defaulting to container deployment for menu option 1."
        else
            read -r -p "Run container deployment now? [Y/n]: " use_container
        fi
        case "${use_container:-Y}" in
            Y|y|"")
                install_container
                ;;
            *)
                print_warning "Skipped container deployment."
                ;;
        esac
        return 0
    fi

    print_step "Installing dependencies"
    npm install

    print_step "Skipping local .env creation (credentials are centralized in ${ANSIBLE_ENV_FILE})"

    print_step "Starting RHIS service"
    npm start &

    print_success "Local installation complete"
    echo "Access dashboard at http://localhost:3000"
}

# Container Deployment
ensure_rootless_podman() {
    if [ "$(id -u)" -eq 0 ]; then
        print_warning "Run this script as a regular user (not root) for rootless Podman."
        return 1
    fi

    if ! command -v podman >/dev/null 2>&1; then
        print_warning "Podman not found. Installing..."
        sudo dnf install -y --nogpgcheck podman shadow-utils slirp4netns fuse-overlayfs
    fi

    if ! grep -q "^${USER}:" /etc/subuid; then
        sudo usermod --add-subuids 100000-165535 "$USER"
    fi
    if ! grep -q "^${USER}:" /etc/subgid; then
        sudo usermod --add-subgids 100000-165535 "$USER"
    fi

    sudo loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    podman system migrate >/dev/null 2>&1 || true

    if [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" != "true" ]; then
        print_warning "Podman is not operating rootless for this user. Log out/in and retry."
        return 1
    fi

    print_success "Rootless Podman is configured for user: ${USER}"
    return 0
}

# Ensure the RHIS provisioner container is running.  Idempotent: no-op if it is
# already up.  The container's entrypoint drops to an interactive bash shell, so
# it needs a pseudo-TTY (-t) to stay alive in detached (-d) mode.
# Three host directories are bind-mounted inside the container:
#   external_inventory  -> inventory file(s) consumed by rhis-builder playbooks
#   host_vars           -> per-node variable files (satellite.yml, aap.yml, …)
#   vault               -> Ansible vault env.yml + optional .vaultpass.txt

# Pin ansible.utils to 4.1.0 when ansible-core inside the container is 2.14.x.
# ansible.utils >=5.x declares requires_ansible >=2.15 which would flood the
# output with [WARNING] Collection ansible.utils does not support Ansible
# version 2.14.x on every playbook run.  4.1.0 declares >=2.14.0 and is
# functionally equivalent for the tasks we run.
# NOTE: redhat.rhel_system_roles has the same version-declaration mismatch but
# Red Hat Automation Hub only serves the current release; no older compatible
# version is available.  That warning cannot be suppressed via a version pin.
ensure_container_collection_compat() {
    local core_ver
    core_ver=$(podman exec "${RHIS_CONTAINER_NAME}" ansible --version 2>/dev/null \
        | awk '/^ansible \[core/{gsub(/[\[\]]/,"",$3); print $3}')

    # Only needed for ansible-core 2.14.x; newer images are already fine.
    [[ "${core_ver}" == 2.14.* ]] || return 0

    local utils_ver
    utils_ver=$(podman exec "${RHIS_CONTAINER_NAME}" ansible-galaxy collection list 2>/dev/null \
        | awk '/^ansible\.utils[[:space:]]/{print $2}')

    # Already pinned to 4.x — nothing to do.
    [[ "${utils_ver}" == 4.* ]] && return 0

    print_step "Pinning ansible.utils to 4.1.0 for ansible-core ${core_ver} compatibility"
    if podman exec "${RHIS_CONTAINER_NAME}" \
           ansible-galaxy collection install "ansible.utils:4.1.0" --force >/dev/null 2>&1; then
        print_success "ansible.utils pinned to 4.1.0 (was ${utils_ver:-unknown})."
    else
        print_warning "Could not pin ansible.utils to 4.1.0; version-compatibility warning will appear during playbook runs."
    fi
    return 0
}

# Maintain RHIS-managed hotfixes inside the provisioner container so each newly
# deployed container gets the same compatibility/workaround patches before any
# playbooks are executed.
ensure_container_managed_chrony_template() {
    local _tpl_path="/rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2"
    local _mk_cmd='mkdir -p /rhis/rhis-builder-satellite/roles/satellite_pre/templates && cat > /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# RHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

    if podman exec "${RHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
        return 0
    fi

    print_warning "Managed container patch: chrony.j2 missing; applying fallback template."

    if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch applied: fallback chrony.j2 created."
        return 0
    fi

    print_warning "Managed container patch failed: could not create fallback chrony.j2."
    return 1
}

ensure_container_managed_idm_chrony_template() {
    local _tpl_path="/rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2"
    local _mk_cmd='mkdir -p /rhis/rhis-builder-idm/roles/idm_pre/templates && cat > /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# RHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

    if podman exec "${RHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
        return 0
    fi

    print_warning "Managed container patch: IdM chrony.j2 missing; applying fallback template."

    if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch applied: IdM fallback chrony.j2 created."
        return 0
    fi

    print_warning "Managed container patch failed: could not create IdM fallback chrony.j2."
    return 1
}

ensure_container_managed_satellite_foreman_patch() {
    local _root="/rhis/rhis-builder-satellite/roles/satellite_pre/tasks"
    local _py='import pathlib
import re

root = pathlib.Path("/rhis/rhis-builder-satellite/roles/satellite_pre/tasks")
if not root.exists():
    print("MISSING_TASKS_DIR")
    raise SystemExit(0)

updated = 0
for path in root.rglob("*.yml"):
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "Get the state of the foreman service" not in text:
        continue

    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if "Get the state of the foreman service" in line:
            start = i
            break
    if start is None:
        continue

    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^\s*-\s+name:\s+", lines[j]):
            end = j
            break

    register_idx = None
    changed_idx = None
    failed_idx = None
    indent = "      "

    for j in range(start + 1, end):
        if re.match(r"^\s*register:\s*", lines[j]):
            register_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)
        if re.match(r"^\s*changed_when:\s*", lines[j]):
            changed_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)
        if re.match(r"^\s*failed_when:\s*", lines[j]):
            failed_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)

    changed = False

    if changed_idx is not None:
        normalized = f"{indent}changed_when: false"
        if lines[changed_idx].strip() != "changed_when: false":
            lines[changed_idx] = normalized
            changed = True
    else:
        insert_at = register_idx + 1 if register_idx is not None else end
        lines.insert(insert_at, f"{indent}changed_when: false")
        changed_idx = insert_at
        end += 1
        changed = True

    if failed_idx is None:
        lines.insert(changed_idx + 1, f"{indent}failed_when: false")
        changed = True
    elif lines[failed_idx].strip() != "failed_when: false":
        lines[failed_idx] = f"{indent}failed_when: false"
        changed = True

    if changed:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        updated += 1

print(f"UPDATED={updated}")'

    local _cmd=$'python3 - <<\'PY\'\n'"${_py}"$'\nPY'
    local _out=""

    _out="$(podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    if [ -z "${_out}" ]; then
        _out="$(podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    fi

    if printf '%s\n' "${_out}" | grep -q 'UPDATED='; then
        if printf '%s\n' "${_out}" | grep -q 'UPDATED=0'; then
            print_step "Managed container patch: Satellite foreman service check already compatible or absent."
        else
            print_success "Managed container patch applied: Satellite foreman service check made non-fatal."
        fi
        return 0
    fi

    print_warning "Managed container patch failed: could not confirm Satellite foreman service compatibility patch."
    return 1
}

ensure_container_managed_idm_update_patch() {
    local _py='import pathlib
import re

path = pathlib.Path("/rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml")
if not path.exists():
    print("MISSING_IDM_UPDATE_TASK")
    raise SystemExit(0)

lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
updated = False

start = None
for i, line in enumerate(lines):
    if "name: \"Update the system\"" in line:
        start = i
        break

if start is None:
    print("UPDATED=0")
    raise SystemExit(0)

end = len(lines)
for j in range(start + 1, len(lines)):
    if re.match(r"^\s*-\s+name:\s+", lines[j]):
        end = j
        break

module_idx = None
module_indent = ""
async_idx = None
disable_idx = None
exclude_idx = None

for j in range(start + 1, end):
    if re.match(r"^\s*ansible\.builtin\.dnf:\s*$", lines[j]):
        module_idx = j
        module_indent = re.match(r"^(\s*)", lines[j]).group(1)
    if re.match(r"^\s*async:\s*", lines[j]) and async_idx is None:
        async_idx = j
    if re.match(r"^\s*disable_gpg_check:\s*", lines[j]):
        disable_idx = j
    if re.match(r"^\s*exclude:\s*", lines[j]):
        exclude_idx = j

if module_idx is None:
    print("UPDATED=0")
    raise SystemExit(0)

arg_indent = module_indent + "  "

if disable_idx is not None:
    desired = f"{arg_indent}disable_gpg_check: true"
    if lines[disable_idx].strip() != "disable_gpg_check: true":
        lines[disable_idx] = desired
        updated = True

if exclude_idx is not None:
    desired = f"{arg_indent}exclude: \"intel-audio-firmware*\""
    if lines[exclude_idx].strip() != "exclude: \"intel-audio-firmware*\"":
        lines[exclude_idx] = desired
        updated = True

insert_at = async_idx if async_idx is not None else end

if disable_idx is None:
    lines.insert(insert_at, f"{arg_indent}disable_gpg_check: true")
    updated = True
    insert_at += 1

if exclude_idx is None:
    lines.insert(insert_at, f"{arg_indent}exclude: \"intel-audio-firmware*\"")
    updated = True

if updated:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("UPDATED=1")
else:
    print("UPDATED=0")'

    local _cmd=$'python3 - <<\'PY\'\n'"${_py}"$'\nPY'
    local _out=""
    _out="$(podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    if [ -z "${_out}" ]; then
        _out="$(podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    fi

    if printf '%s\n' "${_out}" | grep -q 'UPDATED=1'; then
        print_success "Managed container patch applied: IdM update task GPG guard enabled."
        return 0
    fi
    if printf '%s\n' "${_out}" | grep -q 'UPDATED=0'; then
        print_step "Managed container patch: IdM update task already compatible or absent."
        return 0
    fi

    print_warning "Managed container patch failed: could not confirm IdM update task patch."
    return 1
}

apply_managed_container_patches() {
    local _verify_cmd='test -f /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 && test -f /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2 && grep -q "failed_when: false" /rhis/rhis-builder-satellite/roles/satellite_pre/tasks/is_satellite_installed.yml && grep -q "disable_gpg_check: true" /rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml && grep -q "exclude: \"intel-audio-firmware\\*\"" /rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml'

    if ! is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
        print_step "Managed container patches disabled (RHIS_ENABLE_CONTAINER_HOTFIXES=${RHIS_ENABLE_CONTAINER_HOTFIXES})."
        return 0
    fi

    print_step "Applying RHIS-managed patches to provisioner container components"

    ensure_container_managed_chrony_template || true
    ensure_container_managed_idm_chrony_template || true
    ensure_container_managed_satellite_foreman_patch || true
    ensure_container_managed_idm_update_patch || true

    if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch verification passed."
        return 0
    fi

    if is_enabled "${RHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"; then
        print_warning "Managed container patch verification failed and enforcement is ON."
        return 1
    fi

    print_warning "Managed container patch verification failed, but enforcement is OFF; continuing."
    return 0
}

ensure_container_running() {
    # Auto-generate required host mount directories for runtime artifacts.
    mkdir -p "${RHIS_INVENTORY_DIR}" "${RHIS_HOST_VARS_DIR}" "${ANSIBLE_ENV_DIR}" || {
        print_warning "Failed to create required runtime directories for container mounts."
        return 1
    }

    generate_rhis_ansible_cfg || {
        print_warning "Could not generate RHIS Ansible config at ${RHIS_ANSIBLE_CFG_HOST}"
        return 1
    }

    if podman ps --filter "name=^${RHIS_CONTAINER_NAME}$" --format '{{.Names}}' 2>/dev/null \
           | grep -q "^${RHIS_CONTAINER_NAME}$"; then
        print_success "RHIS provisioner container '${RHIS_CONTAINER_NAME}' is already running."
        ensure_container_collection_compat || true
        apply_managed_container_patches || return 1
        return 0
    fi

    # Remove a stopped/crashed remnant so the name is free
    podman rm -f "${RHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Right after container teardown, consolidate runtime values from any
    # active sources (preseed, shell exports, prior vault state) back into
    # encrypted ~/.ansible/conf/env.yml.
    sync_runtime_values_to_ansible_vault || print_warning "Could not consolidate runtime values into ${ANSIBLE_ENV_FILE}; continuing."

    print_step "Starting RHIS provisioner container '${RHIS_CONTAINER_NAME}'"
    podman run -d -t \
        --name "${RHIS_CONTAINER_NAME}" \
        --network host \
        -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" \
        -v "${RHIS_INVENTORY_DIR}:/rhis/vars/external_inventory:Z" \
        -v "${RHIS_HOST_VARS_DIR}:/rhis/vars/host_vars:Z" \
        -v "${ANSIBLE_ENV_DIR}:/rhis/vars/vault:z" \
        "${RHIS_CONTAINER_IMAGE}"

    ensure_container_collection_compat || true
    apply_managed_container_patches || return 1
    print_success "Container '${RHIS_CONTAINER_NAME}' started."
    echo "Exec into the container : podman exec -it ${RHIS_CONTAINER_NAME} /bin/bash"
    echo "Ansible config file     : ${RHIS_ANSIBLE_CFG_HOST}"
    echo "Ansible log file        : ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    echo "Ansible fact cache      : ${RHIS_ANSIBLE_FACT_CACHE_HOST}"
    echo "Run a playbook example  : podman exec -it ${RHIS_CONTAINER_NAME} ansible-playbook \\"
    echo "    --inventory /rhis/vars/external_inventory/hosts \\" 
    echo "    --user ansiblerunner --ask-pass --ask-vault-pass \\" 
    echo "    --extra-vars 'vault_dir=/rhis/vars/vault/' \\"
    echo "    --limit idm_primary /rhis/rhis-builder-idm/main.yml"
}

install_container() {
    print_step "Starting Container Deployment"
    ensure_rootless_podman || return 1
    configure_rhis_network_policy

    print_step "Pulling RHIS container image: ${RHIS_CONTAINER_IMAGE}"
    podman pull "${RHIS_CONTAINER_IMAGE}"

    ensure_container_running

    print_success "Container deployment complete"
    echo "Exec into the container: podman exec -it ${RHIS_CONTAINER_NAME} /bin/bash"
}

run_container_prescribed_sequence() {
    if ! is_enabled "${RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY:-1}"; then
        print_step "Container auto-config is disabled (RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=${RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY})."
        return 0
    fi

    if ! preflight_config_as_code_targets; then
        print_step "Prerequisites for container auto-config are missing; auto-running VM provisioning workflow"
        print_step "This will generate kickstarts/OEMDRV, create RHIS VMs, and continue configuration automatically"
        create_rhis_vms || return 1
        return 0
    fi

    print_step "Container deployment complete; running prescribed config sequence automatically"
    print_step "Prescribed order: IdM -> Satellite -> AAP"
    run_rhis_config_as_code || {
        print_warning "Automatic prescribed sequence did not complete cleanly."
        print_warning "You can re-run by selecting menu option 2 again or invoking the same playbooks manually."
        return 1
    }

    print_success "Automatic prescribed sequence completed."
}

run_container_config_only() {
    print_step "Running container-config-only workflow"
    install_container || return 1

    if ! preflight_config_as_code_targets; then
        print_step "Prerequisites for config-only are missing; auto-running VM provisioning workflow"
        print_step "This will generate kickstarts/OEMDRV, create RHIS VMs, and continue configuration automatically"
        create_rhis_vms || return 1
        return 0
    fi

    run_container_prescribed_sequence || return 1
    return 0
}

sync_rhis_external_hosts_entries() {
    local block_file rendered_file
    local vm ext_ip fqdn alias
    local -a rows=()
    local -a specs=(
        "satellite-618:${SAT_HOSTNAME}:${SAT_ALIAS}"
        "aap-26:${AAP_HOSTNAME}:${AAP_ALIAS}"
        "idm:${IDM_HOSTNAME}:${IDM_ALIAS}"
    )

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "Skipping /etc/hosts external-entry sync: virsh not found."
        return 0
    fi

    for spec in "${specs[@]}"; do
        vm="${spec%%:*}"
        fqdn="${spec#*:}"; fqdn="${fqdn%%:*}"
        alias="${spec##*:}"

        ext_ip="$(sudo -n virsh domifaddr "${vm}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | awk '$1 !~ /^10\.168\./ {print; exit}' || true)"
        [ -n "${ext_ip}" ] || continue

        if [ -n "${fqdn}" ] && [ -n "${alias}" ]; then
            rows+=("${ext_ip} ${fqdn} ${alias}")
        elif [ -n "${fqdn}" ]; then
            rows+=("${ext_ip} ${fqdn}")
        elif [ -n "${alias}" ]; then
            rows+=("${ext_ip} ${alias}")
        fi
    done

    if [ "${#rows[@]}" -eq 0 ]; then
        print_step "No external RHIS VM addresses discovered for /etc/hosts sync yet."
        return 0
    fi

    block_file="$(mktemp /tmp/rhis-hosts-block.XXXXXX)"
    rendered_file="$(mktemp /tmp/rhis-hosts-rendered.XXXXXX)"

    {
        echo "# BEGIN RHIS EXTERNAL HOSTS"
        for row in "${rows[@]}"; do
            printf '%s\n' "${row}"
        done
        echo "# END RHIS EXTERNAL HOSTS"
    } > "${block_file}"

    if sudo grep -q '^# BEGIN RHIS EXTERNAL HOSTS$' /etc/hosts 2>/dev/null && \
       sudo grep -q '^# END RHIS EXTERNAL HOSTS$' /etc/hosts 2>/dev/null; then
        sudo awk -v bf="${block_file}" '
            BEGIN {
                while ((getline line < bf) > 0) {
                    block = block line ORS
                }
                close(bf)
            }
            /^# BEGIN RHIS EXTERNAL HOSTS$/ {
                print block
                inblock = 1
                next
            }
            inblock && /^# END RHIS EXTERNAL HOSTS$/ {
                inblock = 0
                next
            }
            !inblock { print }
        ' /etc/hosts > "${rendered_file}" || true
    else
        {
            sudo cat /etc/hosts
            cat "${block_file}"
        } > "${rendered_file}" || true
    fi

    if [ -s "${rendered_file}" ] && sudo cp -f "${rendered_file}" /etc/hosts 2>/dev/null; then
        print_success "Updated /etc/hosts with RHIS external interface entries."
    else
        print_warning "Could not update /etc/hosts with RHIS external interface entries."
    fi

    rm -f "${block_file}" "${rendered_file}" || true
    return 0
}

preflight_config_as_code_targets() {
    local missing_vm=0
    local unreachable_target=0
    local vm_name vm_state target_ip configured_ip
    local wait_deadline wait_start now remaining elapsed
    local last_progress_log=0
    local show_detail_logs=0
    local target_count=0
    local missing_count=0
    local -a missing_vms=()
    local all_ready reached
    local -a vm_specs

    if [ "$#" -gt 0 ]; then
        vm_specs=("$@")
    else
        vm_specs=(
            "satellite-618:${SAT_IP}"
            "aap-26:${AAP_IP}"
            "idm:${IDM_IP}"
        )
    fi

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; cannot verify RHIS VM state before config-as-code."
        return 0
    fi

    discover_vm_ipv4() {
        local vm="$1"
        timeout 10 sudo -n virsh domifaddr "$vm" 2>/dev/null \
            | awk '/ipv4/ {print $4}' \
            | cut -d/ -f1 \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
            | head -1
    }

    resolve_preflight_ip() {
        local vm="$1"
        local configured="$2"
        local discovered=""

        if probe_ssh_endpoint "$configured"; then
            printf '%s\n' "$configured"
            return 0
        fi

        discovered="$(discover_vm_ipv4 "$vm" || true)"
        if [ -n "$discovered" ]; then
            printf '%s\n' "$discovered"
            return 0
        fi

        printf '%s\n' "$configured"
    }

    print_step "Preflight: validating RHIS VM state and internal SSH reachability"
    print_step "Preflight targets: ${vm_specs[*]}"
    target_count="${#vm_specs[@]}"
    for spec in "${vm_specs[@]}"; do
        vm_name="${spec%%:*}"
        configured_ip="${spec#*:}"

        if ! sudo virsh dominfo "$vm_name" >/dev/null 2>&1; then
            missing_vms+=("${vm_name}")
            missing_count=$((missing_count + 1))
            missing_vm=1
            continue
        fi

        vm_state="$(sudo virsh domstate "$vm_name" 2>/dev/null | tr -d '[:space:]' || true)"
        if [ "$vm_state" != "running" ]; then
            print_warning "Required VM is not running: ${vm_name} (state=${vm_state:-unknown})"
            missing_vm=1
            continue
        fi

        target_ip="$(resolve_preflight_ip "${vm_name}" "${configured_ip}")"
        if [ "$target_ip" != "$configured_ip" ]; then
            print_step "Preflight target update: ${vm_name} configured=${configured_ip} discovered=${target_ip}"
        fi

        if ! probe_ssh_endpoint "$target_ip"; then
            unreachable_target=1
        fi
    done

    if [ "$missing_vm" -ne 0 ]; then
        if [ "$missing_count" -eq "$target_count" ]; then
            print_step "Expected on fresh installs or right after --DEMOKILL: target VMs are not defined yet (${missing_vms[*]})."
        else
            for vm_name in "${missing_vms[@]}"; do
                print_warning "Required VM is not defined: ${vm_name}"
            done
        fi
        print_warning "Container Config-Only assumes Satellite, AAP, and IdM already exist."
        print_warning "After --DEMOKILL, rebuild the VMs first with menu option 3 or 5 (or your normal VM build path)."
        return 1
    fi

    if [ "$unreachable_target" -ne 0 ]; then
        print_step "Waiting for internal SSH readiness (timeout=${RHIS_INTERNAL_SSH_WAIT_TIMEOUT}s, interval=${RHIS_INTERNAL_SSH_WAIT_INTERVAL}s)"
        wait_start="$(date +%s)"
        wait_deadline=$(( wait_start + RHIS_INTERNAL_SSH_WAIT_TIMEOUT ))

        while true; do
            all_ready=1
            for spec in "${vm_specs[@]}"; do
                vm_name="${spec%%:*}"
                configured_ip="${spec#*:}"

                vm_state="$(sudo virsh domstate "$vm_name" 2>/dev/null | tr -d '[:space:]' || true)"
                if [ "$vm_state" != "running" ]; then
                    print_warning "${vm_name} became non-running during preflight (state=${vm_state:-unknown}); attempting start"
                    sudo virsh start "$vm_name" >/dev/null 2>&1 || true
                    all_ready=0
                    continue
                fi

                target_ip="$(resolve_preflight_ip "${vm_name}" "${configured_ip}")"
                if probe_ssh_endpoint "$target_ip"; then
                    reached=1
                else
                    reached=0
                    all_ready=0
                fi
                if [ "$reached" -eq 0 ] && [ "$show_detail_logs" -eq 1 ]; then
                    print_warning "Internal SSH is not reachable yet for ${vm_name} at ${target_ip}:22"
                fi
            done

            if [ "$all_ready" -eq 1 ]; then
                break
            fi

            now="$(date +%s)"
            if [ "$now" -ge "$wait_deadline" ]; then
                print_warning "RHIS VMs exist, but internal SSH did not become reachable before timeout."
                print_warning "Check VM console output and network config for the 10.168.0.0/16 interfaces."
                return 1
            fi

            remaining=$(( wait_deadline - now ))
            elapsed=$(( now - wait_start ))

            if [ "$elapsed" -ge "${RHIS_INTERNAL_SSH_WARN_GRACE}" ]; then
                show_detail_logs=1
            fi

            if [ $((now - last_progress_log)) -ge "${RHIS_INTERNAL_SSH_LOG_EVERY}" ] || [ "$show_detail_logs" -eq 1 ]; then
                if [ "$show_detail_logs" -eq 1 ]; then
                    print_warning "Internal SSH still converging after ${elapsed}s (warn_grace=${RHIS_INTERNAL_SSH_WARN_GRACE}s, timeout=${RHIS_INTERNAL_SSH_WAIT_TIMEOUT}s, remaining~${remaining}s)"
                else
                    print_step "Internal SSH is still converging (elapsed=${elapsed}s/${RHIS_INTERNAL_SSH_WAIT_TIMEOUT}s, remaining~${remaining}s). Detailed warnings start after ${RHIS_INTERNAL_SSH_WARN_GRACE}s."
                fi
                last_progress_log="$now"
            fi

            sleep "$RHIS_INTERNAL_SSH_WAIT_INTERVAL"
        done
    fi

    print_success "Preflight passed: RHIS VMs are running and reachable on the internal network."
    return 0
}

wait_for_post_vm_settle() {
    local grace="${1:-${RHIS_POST_VM_SETTLE_GRACE:-650}}"
    local remaining
    local original_grace elapsed percent filled bar

    case "$grace" in
        ''|*[!0-9]*) grace=650 ;;
    esac

    if [ "$grace" -le 0 ]; then
        return 0
    fi

    original_grace="$grace"
    print_step "Guest install settle window: giving RHIS VMs ${grace}s before internal SSH checks begin"
    while [ "$grace" -gt 0 ]; do
        remaining="$grace"
        if [ "$remaining" -gt 60 ]; then
            remaining=60
        fi
        elapsed=$(( original_grace - grace ))
        percent=$(( elapsed * 100 / original_grace ))
        filled=$(( percent / 5 ))
        printf -v bar '%*s' "$filled" ''
        bar="${bar// /#}"
        printf -v bar '%-20s' "$bar"
        print_step "Initial settle progress: [${bar}] ${percent}%% (${elapsed}s/${original_grace}s)"
        sleep "$remaining"
        grace=$((grace - remaining))
    done

    print_step "Initial settle progress: [####################] 100%% (${original_grace}s/${original_grace}s)"
}

print_rhis_health_summary() {
    local vm state ip
    local -a vms=("satellite-618:${SAT_IP}" "aap-26:${AAP_IP}" "idm:${IDM_IP}")

    echo ""
    echo "================ RHIS Health Summary ================"
    for spec in "${vms[@]}"; do
        vm="${spec%%:*}"
        ip="${spec#*:}"
        if sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            state="$(sudo virsh domstate "$vm" 2>/dev/null | tr -d '[:space:]' || true)"
        else
            state="undefined"
        fi

        if probe_ssh_endpoint "$ip"; then
            echo "  - ${vm} (${ip}) state=${state:-unknown} ssh=up"
        else
            echo "  - ${vm} (${ip}) state=${state:-unknown} ssh=down"
        fi
    done
    echo "====================================================="
    echo ""
}

run_deferred_aap_callback() {
    if ! [ "${AAP_HTTP_PID:-0}" -gt 0 ] 2>/dev/null; then
        return 0
    fi

    AAP_SSH_CALLBACK_ENABLED=1
    print_step "AAP VM is installing. SSH callback will begin as soon as the VM is reachable."
    print_step "Grab a cup of coffee and sit back, or come back after lunch — we will continue to configure this environment while you wait."
    print_step "Live monitor is active: you will see AAP callback progress (percent + ETA). If no state progress is detected, this step will fail fast for troubleshooting."

    if run_aap_setup_on_vm "aap-26"; then
        print_success "AAP setup orchestration complete via SSH callback."
        create_aap_credentials
    else
        print_warning "AAP setup failed or timed out. Check ${AAP_SETUP_LOG_LOCAL} for details."
        AAP_SSH_CALLBACK_ENABLED=0
        return 1
    fi

    if kill "${AAP_HTTP_PID}" 2>/dev/null; then
        print_success "AAP bundle HTTP server stopped (PID ${AAP_HTTP_PID})."
    fi
    AAP_HTTP_PID=""
    close_aap_bundle_firewall
    AAP_SSH_CALLBACK_ENABLED=0
    return 0
}

# ─── Inventory + host_vars generation ─────────────────────────────────────────
# Generate $RHIS_INVENTORY_DIR/hosts from current env vars so the container
# always has a correct, up-to-date inventory regardless of who cloned the repo.
generate_rhis_inventory() {
    mkdir -p "${RHIS_INVENTORY_DIR}" || return 1

    local controller_host
    local template_file
    local controller_host_e host_int_ip_e installer_user_e sat_host_e sat_alias_e sat_ip_e aap_host_e aap_alias_e aap_ip_e idm_host_e idm_alias_e idm_ip_e admin_user_e
    local sat_connect_host aap_connect_host idm_connect_host

    # Default behavior uses internal RHIS addressing (10.168.x.x) for stable
    # node-to-node trust and predictable Ansible reachability across rebuilds.
    # Optional eth0 mode can be enabled for environments that intentionally
    # manage nodes via external/NAT addressing.
    # Fallback order when eth0 mode is enabled:
    #   detected external IP via virsh -> FQDN hostname -> configured internal IP
    resolve_vm_connect_host() {
        local vm_name="$1"
        local fallback_host="$2"
        local fallback_ip="$3"
        local detected_ip=""

        if is_enabled "${RHIS_MANAGED_SSH_OVER_ETH0:-0}"; then
            detected_ip="$(sudo virsh domifaddr "${vm_name}" 2>/dev/null | awk 'NR>2{print $4}' | cut -d/ -f1 | awk '$1 !~ /^10\.168\./ {print; exit}')"
            if [ -n "${detected_ip}" ]; then
                printf '%s' "${detected_ip}"
                return 0
            fi

            if [ -n "${fallback_host}" ]; then
                printf '%s' "${fallback_host}"
                return 0
            fi
        fi

        printf '%s' "${fallback_ip}"
        return 0
    }
    controller_host="$(hostname -f 2>/dev/null || hostname)"

    template_file="${RHIS_INVENTORY_DIR}/hosts.SAMPLE"
    controller_host_e="$(sed_escape_replacement "${controller_host}")"
    host_int_ip_e="$(sed_escape_replacement "${HOST_INT_IP:-192.168.122.1}")"
    installer_user_e="$(sed_escape_replacement "${INSTALLER_USER:-${USER}}")"
    sat_host_e="$(sed_escape_replacement "${SAT_HOSTNAME:-satellite}")"
    sat_alias_e="$(sed_escape_replacement "${SAT_ALIAS:-satellite}")"
    sat_connect_host="$(resolve_vm_connect_host "satellite-618" "${SAT_HOSTNAME:-satellite}" "${SAT_IP:-10.168.128.1}")"
    sat_ip_e="$(sed_escape_replacement "${sat_connect_host}")"
    aap_host_e="$(sed_escape_replacement "${AAP_HOSTNAME:-aap}")"
    aap_alias_e="$(sed_escape_replacement "${AAP_ALIAS:-aap}")"
    aap_connect_host="$(resolve_vm_connect_host "aap-26" "${AAP_HOSTNAME:-aap}" "${AAP_IP:-10.168.128.2}")"
    aap_ip_e="$(sed_escape_replacement "${aap_connect_host}")"
    idm_host_e="$(sed_escape_replacement "${IDM_HOSTNAME:-idm}")"
    idm_alias_e="$(sed_escape_replacement "${IDM_ALIAS:-idm}")"
    idm_connect_host="$(resolve_vm_connect_host "idm" "${IDM_HOSTNAME:-idm}" "${IDM_IP:-10.168.128.3}")"
    idm_ip_e="$(sed_escape_replacement "${idm_connect_host}")"
    admin_user_e="$(sed_escape_replacement "${ADMIN_USER:-admin}")"

    if [ -f "${template_file}" ]; then
        sed \
            -e "s|{{CONTROLLER_HOST}}|${controller_host_e}|g" \
            -e "s|{{HOST_INT_IP}}|${host_int_ip_e}|g" \
            -e "s|{{INSTALLER_USER}}|${installer_user_e}|g" \
            -e "s|{{SAT_HOSTNAME}}|${sat_host_e}|g" \
            -e "s|{{SAT_ALIAS}}|${sat_alias_e}|g" \
            -e "s|{{SAT_IP}}|${sat_ip_e}|g" \
            -e "s|{{AAP_HOSTNAME}}|${aap_host_e}|g" \
            -e "s|{{AAP_ALIAS}}|${aap_alias_e}|g" \
            -e "s|{{AAP_IP}}|${aap_ip_e}|g" \
            -e "s|{{IDM_HOSTNAME}}|${idm_host_e}|g" \
            -e "s|{{IDM_ALIAS}}|${idm_alias_e}|g" \
            -e "s|{{IDM_IP}}|${idm_ip_e}|g" \
            -e "s|{{ADMIN_USER}}|${admin_user_e}|g" \
            "${template_file}" > "${RHIS_INVENTORY_DIR}/hosts"
    else
        cat > "${RHIS_INVENTORY_DIR}/hosts" <<INVENTORY_EOF
# RHIS Ansible Inventory — generated by run_rhis_install_sequence.sh on $(date '+%Y-%m-%d %H:%M')
# Do NOT commit this file; it contains host-specific values derived from env.yml.

[ansibledev]
${controller_host}

[libvirt]
${controller_host}

[installer]
${controller_host} ansible_host=${HOST_INT_IP:-192.168.122.1} ansible_user=${INSTALLER_USER:-${USER}} ansible_become=true

[scenario_satellite]
${SAT_HOSTNAME:-satellite} ansible_host=${sat_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true
${SAT_ALIAS:-satellite} ansible_host=${sat_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true

[sat_primary:children]
scenario_satellite

[aap]
${AAP_HOSTNAME:-aap} ansible_host=${aap_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true
${AAP_ALIAS:-aap} ansible_host=${aap_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true

[aap_hosts:children]
aap

[platform_installer:children]
aap

[idm]
${IDM_HOSTNAME:-idm} ansible_host=${idm_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true
${IDM_ALIAS:-idm} ansible_host=${idm_connect_host} ansible_user=${ADMIN_USER:-admin} ansible_become=true

[idm_primary:children]
idm

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
INVENTORY_EOF
    fi

    chmod 600 "${RHIS_INVENTORY_DIR}/hosts"
    print_success "Generated inventory: ${RHIS_INVENTORY_DIR}/hosts"
}

# Generate actual host_vars/*.yml files from current env vars so playbooks
# can find per-node connection details without additional prompts.
# Passwords are referenced via the vault extra-vars loaded at runtime from
# /rhis/vars/vault/env.yml (decrypted by --vault-password-file automatically).
generate_rhis_host_vars() {
    mkdir -p "${RHIS_HOST_VARS_DIR}" || return 1
    local sat_pre_use_idm_value="${SATELLITE_PRE_USE_IDM:-false}"

    # Installer / controller host
    cat > "${RHIS_HOST_VARS_DIR}/installer.yml" <<EOF
# installer.yml — generated by run_rhis_install_sequence.sh
ansible_user: "${INSTALLER_USER:-${USER}}"
aap_remote_user: "${INSTALLER_USER:-${USER}}"
ansible_ssh_private_key_file: "/home/${INSTALLER_USER:-${USER}}/.ssh/id_rsa"
EOF

    # Satellite
    cat > "${RHIS_HOST_VARS_DIR}/satellite.yml" <<EOF
# satellite.yml — generated by run_rhis_install_sequence.sh
ansible_user: "${ADMIN_USER:-admin}"
ansible_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"
ansible_admin_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"
ansible_become: true
ansible_connection: ssh
ansible_ssh_private_key_file: "/home/{{ lookup('env', 'USER') | default('root') }}/.ssh/id_rsa"
satellite_organization: "${SAT_ORG:-REDHAT}"
satellite_location: "${SAT_LOC:-CORE}"
satellite_pre_use_idm: ${sat_pre_use_idm_value}
ipa_client_dns_servers: "${IDM_IP:-10.168.128.3}"
ipa_server_fqdn: "${IDM_HOSTNAME:-idm.${DOMAIN:-localdomain}}"
EOF

    # AAP
    cat > "${RHIS_HOST_VARS_DIR}/aap.yml" <<EOF
# aap.yml — generated by run_rhis_install_sequence.sh
ansible_become_pass: "{{ global_admin_password | default('') }}"
aap_admin_user: "${ADMIN_USER:-admin}"
aap_admin_password: "{{ aap_admin_pass | default(global_admin_password) | default('') }}"
platform_deployment_type: "container"
EOF

    # IdM
    cat > "${RHIS_HOST_VARS_DIR}/idm.yml" <<EOF
# idm.yml — generated by run_rhis_install_sequence.sh
ansible_user: "${ADMIN_USER:-admin}"
ansible_password: "{{ idm_admin_pass | default(global_admin_password) | default('') }}"
ansible_become: true
idm_realm: "${IDM_REALM:-$(echo "${DOMAIN:-}" | tr '[:lower:]' '[:upper:]')}"
idm_domain: "${IDM_DOMAIN:-${DOMAIN:-}}"
EOF

    chmod 600 "${RHIS_HOST_VARS_DIR}"/*.yml 2>/dev/null || true
    print_success "Generated host_vars in ${RHIS_HOST_VARS_DIR}/"
}

# ─── Container playbook runner ─────────────────────────────────────────────────
# Run one rhis-builder playbook inside the provisioner container.
# Usage: run_container_playbook <playbook_path_inside_container> <--limit GROUP> [extra args...]
# The vault env.yml is passed as @extra-vars so all vault keys become Ansible vars.
run_container_playbook() {
    local playbook="$1"; shift
    local limit_flag="$1"; shift      # typically "--limit idm_primary" etc.
    local limit_group="$1"; shift
    local extra_args=("$@")

    # Ensure container is up; start it if not
    ensure_container_running || return 1

    local vault_file="/rhis/vars/vault/$(basename "${ANSIBLE_ENV_FILE}")"
    local vault_pass="/rhis/vars/vault/$(basename "${ANSIBLE_VAULT_PASS_FILE}")"
    local ansible_log_file="/rhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}"
    local -a podman_user_args=()

    print_step "Running ${playbook} --limit ${limit_group} inside container '${RHIS_CONTAINER_NAME}'"

    # If vault password file is readable, use it. If not readable as default
    # container user, try root. Otherwise fall back to prompting.
    local vault_arg=()
    if podman exec "${RHIS_CONTAINER_NAME}" test -r "${vault_pass}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass}")
    elif podman exec --user 0 "${RHIS_CONTAINER_NAME}" test -r "${vault_pass}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass}")
        podman_user_args=(--user 0)
        print_step "Vault password file requires container root access; executing playbook as root."
    else
        vault_arg=(--ask-vault-pass)
    fi

    print_step "Ansible log: ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    print_step "Ansible config: ${RHIS_ANSIBLE_CFG_HOST}"

    podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
        ansible-playbook \
            --inventory /rhis/vars/external_inventory/hosts \
            "${vault_arg[@]}" \
            --extra-vars "@${vault_file}" \
            --limit "${limit_group}" \
            "${extra_args[@]}" \
            "${playbook}"
}

# ─── Post-install config-as-code orchestration ────────────────────────────────
# Called automatically after all VMs are running.  Regenerates inventory and
# host_vars from the current env, starts the provisioner container, then runs
# the rhis-builder playbooks in dependency order: IdM → Satellite → AAP.
run_rhis_config_as_code() {
    print_step "===== RHIS Config-as-Code Phase ====="
    print_step "Generating fresh inventory and host_vars from env.yml..."
    local idm_status="not-run"
    local satellite_status="not-run"
    local aap_status="not-run"
    local idm_auth_fallback_status="not-needed"
    local satellite_auth_fallback_status="not-needed"
    local aap_auth_fallback_status="not-needed"
    local phase_auth_fallback_status="not-needed"
    local any_failed=0

    load_ansible_env_file || true
    normalize_shared_env_vars

    # Keep installer-host /etc/hosts aligned with current external/NAT VM IPs.
    sync_rhis_external_hosts_entries || true

    # Re-sync installer/user/root trust before entering phase playbooks.
    # This is intentionally best-effort here because some nodes may still be
    # converging; phase auth fallback remains the final safety net.
    print_step "Pre-flight: refreshing RHIS SSH trust baseline before config-as-code"
    if ! setup_rhis_ssh_mesh; then
        print_warning "SSH trust baseline refresh did not fully converge; continuing with phase auth fallback logic."
    fi

    # Ensure root auth fallback path is reliable even on reruns where guest-side
    # passwords drifted from current vault values.
    print_step "Pre-flight: normalizing VM root passwords for auth fallback reliability"
    fix_vm_root_passwords || print_warning "Root password pre-flight normalization did not complete cleanly; continuing."

    generate_rhis_inventory     || { print_warning "Inventory generation failed; skipping config-as-code."; return 1; }
    generate_rhis_host_vars     || { print_warning "host_vars generation failed; skipping config-as-code."; return 1; }
    print_step "Phase gate: waiting only for IdM and Satellite so foundational services can proceed first"
    preflight_config_as_code_targets "idm:${IDM_IP}" "satellite-618:${SAT_IP}" || return 1

    # Pull latest image and ensure container is running with fresh mounts
    print_step "Ensuring RHIS provisioner container is running..."
    podman pull "${RHIS_CONTAINER_IMAGE}" 2>/dev/null || true
    ensure_container_running || { print_warning "Could not start provisioner container; skipping config-as-code."; return 1; }

    # Auto-reattach VM consoles so progress can be observed during configuration.
    # In non-interactive mode this is skipped to avoid spawning terminals/tmux unexpectedly.
    if ! is_noninteractive; then
        reattach_vm_consoles || print_warning "Automatic VM console reattach failed; continuing config-as-code."
    fi

    local vault_file="/rhis/vars/vault/$(basename "${ANSIBLE_ENV_FILE}")"
    local vault_pass_file="/rhis/vars/vault/$(basename "${ANSIBLE_VAULT_PASS_FILE}")"
    local ansible_log_file="/rhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}"
    local vault_arg=()
    local -a podman_user_args=()
    local use_interactive_vault_prompt=0
    local staged_vault_pass_host=""
    local staged_vault_pass_file=""

    cleanup_staged_vaultpass() {
        # Keep a stable staged vaultpass file so manual reruns can reuse:
        #   --vault-password-file /rhis/vars/vault/.vaultpass.container
        return 0
    }

    if podman exec "${RHIS_CONTAINER_NAME}" test -r "${vault_pass_file}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass_file}")
    elif podman exec --user 0 "${RHIS_CONTAINER_NAME}" test -r "${vault_pass_file}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass_file}")
        podman_user_args=(--user 0)
        print_step "Vault password file requires container root access; executing config-as-code phases as root."
    else
        # Attempt to stage a short-lived container-readable copy in the mounted vault dir.
        if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
            staged_vault_pass_host="${ANSIBLE_ENV_DIR}/${STAGED_VAULT_PASS_BASENAME}"
            cp -f "${ANSIBLE_VAULT_PASS_FILE}" "${staged_vault_pass_host}" 2>/dev/null || staged_vault_pass_host=""
            if [ -n "${staged_vault_pass_host}" ] && [ -f "${staged_vault_pass_host}" ]; then
                chmod 0644 "${staged_vault_pass_host}" 2>/dev/null || true
                staged_vault_pass_file="/rhis/vars/vault/$(basename "${staged_vault_pass_host}")"

                if podman exec "${RHIS_CONTAINER_NAME}" test -r "${staged_vault_pass_file}" 2>/dev/null; then
                    vault_arg=(--vault-password-file "${staged_vault_pass_file}")
                    print_step "Using temporary container-readable vault password file for this run."
                elif podman exec --user 0 "${RHIS_CONTAINER_NAME}" test -r "${staged_vault_pass_file}" 2>/dev/null; then
                    vault_arg=(--vault-password-file "${staged_vault_pass_file}")
                    podman_user_args=(--user 0)
                    print_step "Using temporary vault password file (container root access) for this run."
                else
                    cleanup_staged_vaultpass
                    staged_vault_pass_host=""
                    staged_vault_pass_file=""
                fi
            fi
        fi

        if [ "${#vault_arg[@]}" -gt 0 ]; then
            :
        elif is_noninteractive; then
            cleanup_staged_vaultpass
            print_warning "Vault password file not readable in container at ${vault_pass_file}."
            print_warning "NONINTERACTIVE mode cannot prompt for a vault password."
            print_warning "Fix permissions/ownership on ${ANSIBLE_VAULT_PASS_FILE} and retry."
            return 1
        else
            vault_arg=(--ask-vault-pass)
            use_interactive_vault_prompt=1
            print_warning "Vault password file not readable in container at ${vault_pass_file}."
            print_warning "Falling back to interactive vault password prompt for config-as-code phases."
        fi
    fi

    local inv="--inventory /rhis/vars/external_inventory/hosts"
    local sat_pre_use_idm="${SATELLITE_PRE_USE_IDM:-false}"
    local idm_async_timeout="${IDM_ASYNC_TIMEOUT:-14400}"
    local idm_async_delay="${IDM_ASYNC_DELAY:-15}"
    local sat_ipa_dns="${IDM_IP:-10.168.128.3}"
    local sat_ipa_fqdn="${IDM_HOSTNAME:-idm.${DOMAIN:-localdomain}}"
    local evars="--extra-vars @${vault_file} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}"
    local manual_evars="--extra-vars @${vault_file} --extra-vars '{\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}'"
    local manual_vault_arg="${vault_arg[*]}"
    if [ -z "${manual_vault_arg}" ]; then
        manual_vault_arg="--ask-vault-pass"
    fi

    # Per-phase extras for copy-paste manual reruns — must mirror what run_phase_playbook injects.
    # IdM: bypass the rhc 'Configure remediation' block (GPG fails on RHEL 10 for rhc-worker-playbook)
    local manual_idm_extras="--extra-vars '{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}'"
    if [ -n "${IPADM_PASSWORD:-}" ]; then
        manual_idm_extras+=" -e 'ipadm_password=${IPADM_PASSWORD}' -e 'ipaadmin_password=${IPAADMIN_PASSWORD:-${IPADM_PASSWORD}}'"
    fi

    # Satellite: supply sat_repository_ids, firewall settings, and CDN registration vars
    local _sat_manual_json="{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\"}"
    local manual_satellite_extras="--extra-vars '${_sat_manual_json}'"
    local manual_podman_env="-e ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}"

    ensure_satellite_chrony_template() {
        local _tpl_path="/rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2"
        local _mk_cmd='mkdir -p /rhis/rhis-builder-satellite/roles/satellite_pre/templates && cat > /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# RHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

        if podman exec "${RHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
            return 0
        fi

        print_warning "chrony.j2 is missing in rhis-builder-satellite; applying fallback template workaround."

        if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
            print_success "Fallback chrony.j2 created in rhis-builder-satellite templates."
            return 0
        fi

        print_warning "Failed to create fallback chrony.j2; will skip tags_satellite_pre_chrony."
        return 1
    }

    ensure_idm_chrony_template() {
        local _tpl_path="/rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2"
        local _mk_cmd='mkdir -p /rhis/rhis-builder-idm/roles/idm_pre/templates && cat > /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# RHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

        if podman exec "${RHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
            return 0
        fi

        print_warning "chrony.j2 is missing in rhis-builder-idm; applying fallback template workaround."

        if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
            print_success "Fallback chrony.j2 created in rhis-builder-idm templates."
            return 0
        fi

        print_warning "Failed to create IdM fallback chrony.j2; idm_pre chrony task may fail."
        return 1
    }

    ensure_satellite_foreman_service_check_nonfatal() {
        local _root="/rhis/rhis-builder-satellite/roles/satellite_pre/tasks"
        local _py='import pathlib
import re

root = pathlib.Path("/rhis/rhis-builder-satellite/roles/satellite_pre/tasks")
if not root.exists():
    print("MISSING_TASKS_DIR")
    raise SystemExit(0)

updated = 0
for path in root.rglob("*.yml"):
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "Get the state of the foreman service" not in text:
        continue

    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if "Get the state of the foreman service" in line:
            start = i
            break
    if start is None:
        continue

    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^\s*-\s+name:\s+", lines[j]):
            end = j
            break

    block = lines[start:end]
    block_text = "\n".join(block)

    register_idx = None
    changed_idx = None
    failed_idx = None
    indent = "      "

    for j in range(start + 1, end):
        if re.match(r"^\s*register:\s*", lines[j]):
            register_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)
        if re.match(r"^\s*changed_when:\s*", lines[j]):
            changed_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)
        if re.match(r"^\s*failed_when:\s*", lines[j]):
            failed_idx = j
            indent = re.match(r"^(\s*)", lines[j]).group(1)

    changed = False

    if changed_idx is not None:
        normalized = f"{indent}changed_when: false"
        if lines[changed_idx].strip() != "changed_when: false":
            lines[changed_idx] = normalized
            changed = True
    else:
        insert_at = register_idx + 1 if register_idx is not None else end
        lines.insert(insert_at, f"{indent}changed_when: false")
        changed_idx = insert_at
        end += 1
        changed = True

    if failed_idx is None:
        lines.insert(changed_idx + 1, f"{indent}failed_when: false")
        changed = True
    elif lines[failed_idx].strip() != "failed_when: false":
        lines[failed_idx] = f"{indent}failed_when: false"
        changed = True

    if changed:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        updated += 1

print(f"UPDATED={updated}")'

        local _cmd=$'python3 - <<\'PY\'\n'"${_py}"$'\nPY'
        local _out=""

        _out="$(podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        if [ -z "${_out}" ]; then
            _out="$(podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        fi

        if printf '%s\n' "${_out}" | grep -q 'UPDATED='; then
            if printf '%s\n' "${_out}" | grep -q 'UPDATED=0'; then
                print_step "satellite_pre foreman service check patch: already compatible or task not present."
            else
                print_success "Patched satellite_pre foreman service check to be non-fatal when service is absent."
            fi
            return 0
        fi

        print_warning "Could not confirm satellite_pre foreman service check patch; continuing."
        return 1
    }

    ensure_idm_update_task_nogpgcheck() {
        local _py='import pathlib
import re

path = pathlib.Path("/rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml")
if not path.exists():
    print("MISSING_IDM_UPDATE_TASK")
    raise SystemExit(0)

lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
updated = False

start = None
for i, line in enumerate(lines):
    if "name: \"Update the system\"" in line:
        start = i
        break

if start is None:
    print("UPDATED=0")
    raise SystemExit(0)

end = len(lines)
for j in range(start + 1, len(lines)):
    if re.match(r"^\s*-\s+name:\s+", lines[j]):
        end = j
        break

module_idx = None
module_indent = ""
async_idx = None
disable_idx = None
exclude_idx = None

for j in range(start + 1, end):
    if re.match(r"^\s*ansible\.builtin\.dnf:\s*$", lines[j]):
        module_idx = j
        module_indent = re.match(r"^(\s*)", lines[j]).group(1)
    if re.match(r"^\s*async:\s*", lines[j]) and async_idx is None:
        async_idx = j
    if re.match(r"^\s*disable_gpg_check:\s*", lines[j]):
        disable_idx = j
    if re.match(r"^\s*exclude:\s*", lines[j]):
        exclude_idx = j

if module_idx is None:
    print("UPDATED=0")
    raise SystemExit(0)

arg_indent = module_indent + "  "

if disable_idx is not None:
    desired = f"{arg_indent}disable_gpg_check: true"
    if lines[disable_idx].strip() != "disable_gpg_check: true":
        lines[disable_idx] = desired
        updated = True

if exclude_idx is not None:
    desired = f"{arg_indent}exclude: \"intel-audio-firmware*\""
    if lines[exclude_idx].strip() != "exclude: \"intel-audio-firmware*\"":
        lines[exclude_idx] = desired
        updated = True

insert_at = async_idx if async_idx is not None else end

if disable_idx is None:
    lines.insert(insert_at, f"{arg_indent}disable_gpg_check: true")
    updated = True
    insert_at += 1

if exclude_idx is None:
    lines.insert(insert_at, f"{arg_indent}exclude: \"intel-audio-firmware*\"")
    updated = True

if updated:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("UPDATED=1")
else:
    print("UPDATED=0")'

        local _cmd=$'python3 - <<\'PY\'\n'"${_py}"$'\nPY'
        local _out=""
        _out="$(podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        if [ -z "${_out}" ]; then
            _out="$(podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        fi

        if printf '%s\n' "${_out}" | grep -q 'UPDATED=1'; then
            print_success "Patched idm_pre update task to bypass problematic GPG signature checks."
            return 0
        fi
        if printf '%s\n' "${_out}" | grep -q 'UPDATED=0'; then
            print_step "idm_pre update task patch: already compatible or task not present."
            return 0
        fi

        print_warning "Could not confirm idm_pre update task patch; continuing."
        return 1
    }

    ensure_container_playbook_hotfixes() {
        local _verify_cmd='test -f /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 && test -f /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2 && grep -q "failed_when: false" /rhis/rhis-builder-satellite/roles/satellite_pre/tasks/is_satellite_installed.yml && grep -q "disable_gpg_check: true" /rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml && grep -q "exclude: \"intel-audio-firmware\\*\"" /rhis/rhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml'
        local _verified=1

        print_step "Pre-flight: applying container role hotfixes"

        ensure_satellite_foreman_service_check_nonfatal || true
        ensure_idm_chrony_template || true
        ensure_idm_update_task_nogpgcheck || true

        if podman exec "${RHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${RHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1; then
            _verified=0
        fi

        if [ "${_verified}" -eq 0 ]; then
            print_success "Container hotfix verification passed (Satellite foreman + IdM GPG update guards)."
            return 0
        fi

        if is_enabled "${RHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"; then
            print_warning "Container hotfix verification failed and enforcement is ON; stopping before phase playbooks."
            return 1
        fi

        print_warning "Container hotfix verification failed, but enforcement is OFF; continuing."
        return 0
    }

    if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
        manual_satellite_extras+=" -e cdn_organization_id=${CDN_ORGANIZATION_ID} -e cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}"
    else
        manual_satellite_extras+=" --skip-tags tags_satellite_pre_cdn_registration"
    fi
    if ! ensure_satellite_chrony_template; then
        manual_satellite_extras+=" --skip-tags tags_satellite_pre_chrony"
    fi
    if is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
        ensure_container_playbook_hotfixes || return 1
    fi

    print_manual_rerun_template() {
        print_warning "Manual rerun template (works for all groups):"
        print_warning "  # Ensure the provisioner container exists/runs before re-run"
        print_warning "  podman ps -a --format '{{.Names}} {{.Status}}' | grep -E '^${RHIS_CONTAINER_NAME}\\b' || echo 'Container missing: run menu option 2 first'"
        print_warning "  podman start ${RHIS_CONTAINER_NAME} >/dev/null 2>&1 || true"
        print_warning "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} --limit <GROUP> /rhis/rhis-builder-<COMPONENT>/main.yml"
        print_warning "  # Root-auth fallback template (when admin/inventory auth fails)"
        print_warning "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} -e ansible_user=root -e ansible_password='<ROOT_PASS>' -e ansible_become=false --limit <GROUP> /rhis/rhis-builder-<COMPONENT>/main.yml"
    }

    print_step "Ansible log: ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    print_step "Ansible config: ${RHIS_ANSIBLE_CFG_HOST}"

    run_phase_playbook() {
        local phase_label="$1"
        local phase_limit="$2"
        local phase_playbook="$3"
        local -a phase_args=()

        phase_args=("${extra_args[@]}")

        # IdM collection expects ipadm_password in some install paths.
        if [ "${phase_limit}" = "idm" ] && [ -n "${IPADM_PASSWORD:-}" ]; then
            phase_args+=( -e "ipadm_password=${IPADM_PASSWORD}" )
            phase_args+=( -e "ipaadmin_password=${IPAADMIN_PASSWORD:-${IPADM_PASSWORD}}" )
        fi
        # Skip the rhc role's 'Configure remediation' block — it installs
        # rhc-worker-playbook but GPG validation fails on RHEL 10 CDN packages;
        # the package is pre-installed by ensure_core_role_packages_on_managed_nodes.
        if [ "${phase_limit}" = "idm" ]; then
            if is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_idm_chrony_template || true
                ensure_idm_update_task_nogpgcheck || true
            fi
            phase_args+=( --extra-vars "{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}" )
        fi

        # Satellite collection expects sat_repository_ids and (optionally) CDN activation vars.
        if [ "${phase_limit}" = "scenario_satellite" ]; then
            phase_args+=( --extra-vars "{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\"}" )
            if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
                phase_args+=( -e "cdn_organization_id=${CDN_ORGANIZATION_ID}" )
                phase_args+=( -e "cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}" )
            else
                phase_args+=( --skip-tags "tags_satellite_pre_cdn_registration" )
            fi

            if ! ensure_satellite_chrony_template; then
                phase_args+=( --skip-tags "tags_satellite_pre_chrony" )
                print_warning "chrony.j2 is missing in rhis-builder-satellite; skipping tags_satellite_pre_chrony for this run."
            fi
            if is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_satellite_foreman_service_check_nonfatal || true
            fi
        fi

        print_step "${phase_label}"
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                "${phase_args[@]}" \
                "${phase_playbook}"
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                "${phase_args[@]}" \
                "${phase_playbook}"
        fi
    }

    run_phase_playbook_with_auth_fallback() {
        local phase_label="$1"
        local phase_limit="$2"
        local phase_playbook="$3"
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local -a fallback_phase_args=()

        fallback_phase_args=("${extra_args[@]}")
        if [ "${phase_limit}" = "idm" ] && [ -n "${IPADM_PASSWORD:-}" ]; then
            fallback_phase_args+=( -e "ipadm_password=${IPADM_PASSWORD}" )
            fallback_phase_args+=( -e "ipaadmin_password=${IPAADMIN_PASSWORD:-${IPADM_PASSWORD}}" )
        fi
        if [ "${phase_limit}" = "idm" ]; then
            if is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_idm_chrony_template || true
                ensure_idm_update_task_nogpgcheck || true
            fi
            fallback_phase_args+=( --extra-vars "{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}" )
        fi
        if [ "${phase_limit}" = "scenario_satellite" ]; then
            fallback_phase_args+=( --extra-vars "{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\"}" )
            if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
                fallback_phase_args+=( -e "cdn_organization_id=${CDN_ORGANIZATION_ID}" )
                fallback_phase_args+=( -e "cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}" )
            else
                fallback_phase_args+=( --skip-tags "tags_satellite_pre_cdn_registration" )
            fi

            if ! ensure_satellite_chrony_template; then
                fallback_phase_args+=( --skip-tags "tags_satellite_pre_chrony" )
                print_warning "chrony.j2 is missing in rhis-builder-satellite; skipping tags_satellite_pre_chrony for fallback run."
            fi
            if is_enabled "${RHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_satellite_foreman_service_check_nonfatal || true
            fi
        fi

        phase_auth_fallback_status="not-needed"

        if run_phase_playbook "$phase_label" "$phase_limit" "$phase_playbook"; then
            phase_auth_fallback_status="not-needed"
            return 0
        fi

        if [ -z "$root_auth_pass" ]; then
            print_warning "Auth fallback skipped for ${phase_label}: ROOT_PASS/ADMIN_PASS is unset."
            phase_auth_fallback_status="unavailable"
            return 1
        fi

        print_warning "${phase_label} failed on first attempt; retrying once with root SSH auth fallback."
        phase_auth_fallback_status="used"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                "${fallback_phase_args[@]}" \
                "${phase_playbook}"
            if [ "$?" -eq 0 ]; then
                phase_auth_fallback_status="used/succeeded"
                return 0
            fi
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                "${fallback_phase_args[@]}" \
                "${phase_playbook}"
            if [ "$?" -eq 0 ]; then
                phase_auth_fallback_status="used/succeeded"
                return 0
            fi
        fi

        phase_auth_fallback_status="used/failed"
        return 1
    }

    # -------------------------------------------------------------------------
    # assert_satellite_server_repos_available
    # -------------------------------------------------------------------------
    # Connects to the Satellite host and validates that every repo ID listed in
    # SAT_REPOSITORY_IDS_JSON is visible via subscription-manager.  Fails fast
    # with a human-readable remediation guide when any server repo is absent.
    # Returns 0 when all repos are present or when the host is unreachable
    # (non-blocking soft-fail with a warning so a later SSH failure surfaces the
    # real problem instead of a duplicate pre-flight error).
    # -------------------------------------------------------------------------
    assert_satellite_server_repos_available() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local check_cmd='source /etc/os-release >/dev/null 2>&1 || true; printf "OS_MAJOR=%s\n" "${VERSION_ID%%.*}"; subscription-manager repos --list-enabled 2>/dev/null | awk "/^Repo ID/{print \$NF}" | sort'
        local repos_out=""
        local -a missing=()
        local -a required_repos=()
        local sat_os_major=""

        # Parse the JSON array into a bash array without requiring jq.
        local raw="${SAT_REPOSITORY_IDS_JSON}"
        raw="${raw//[/}" ; raw="${raw//]/}" ; raw="${raw//\"/}"
        IFS=',' read -ra required_repos <<< "${raw}"

        print_step "Pre-flight: verifying RHSM repo entitlements on Satellite host (${SAT_HOSTNAME:-satellite})..."

        # First try vault credentials.
        repos_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" \
            "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
            ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
            -m ansible.builtin.shell \
            -a "${check_cmd}" 2>/dev/null) || true

        # Fall back to root password if vault auth yielded nothing.
        if [ -z "${repos_out}" ] && [ -n "${root_auth_pass}" ]; then
            repos_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" \
                "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m ansible.builtin.shell \
                -a "${check_cmd}" 2>/dev/null) || true
        fi

        if [ -z "${repos_out}" ]; then
            print_warning "Could not reach Satellite host to verify repo entitlements; proceeding (will fail later if repos absent)."
            return 0
        fi

        sat_os_major="$(printf '%s\n' "${repos_out}" | awk -F= '/OS_MAJOR=/{print $2; exit}')"
        if [ -n "${sat_os_major}" ] && [ "${sat_os_major}" != "9" ]; then
            print_warning "Satellite host is not running RHEL 9 (detected major=${sat_os_major})."
            print_warning "Satellite 6.18 workflow in this installer is pinned to RHEL 9 repos/media."
            return 1
        fi

        for repo_id in "${required_repos[@]}"; do
            repo_id="${repo_id// /}"     # trim whitespace from JSON parse
            [ -z "${repo_id}" ] && continue
            if ! echo "${repos_out}" | grep -qF "${repo_id}"; then
                missing+=( "${repo_id}" )
            fi
        done

        if [ "${#missing[@]}" -eq 0 ]; then
            print_success "All required Satellite repos confirmed in RHSM entitlement."
            return 0
        fi

        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}  ✘  SATELLITE PRE-FLIGHT FAILED — entitlement repos missing${NC}"
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${RED}  The following repo IDs are NOT currently exposed via RHSM${NC}"
        echo -e "${RED}  on Satellite host: ${SAT_HOSTNAME:-satellite}${NC}"
        echo ""
        for r in "${missing[@]}"; do
            echo -e "${RED}    ✗  ${r}${NC}"
        done
        echo ""
        echo -e "${BOLD}  Your RHSM account MUST expose ALL of these repo IDs before${NC}"
        echo -e "${BOLD}  this Satellite installation can proceed:${NC}"
        echo ""
        for r in "${required_repos[@]}"; do
            r="${r// /}" ; [ -z "${r}" ] && continue
            echo    "    •  ${r}"
        done
        echo ""
        echo -e "${BOLD}  How to resolve:${NC}"
        echo    "  1. Log into https://access.redhat.com/management/subscriptions"
        echo    "     and confirm your account has a Red Hat Satellite Server"
        echo    "     subscription (SKU: MCT0370 or similar Smart Management SKU)."
        echo    "  2. If using an activation key, set CDN_ORGANIZATION_ID and"
        echo    "     CDN_SAT_ACTIVATION_KEY before re-running so the Satellite"
        echo    "     host attaches via a key that includes 'Smart Management'."
        echo    "  3. Otherwise run directly on ${SAT_HOSTNAME:-your Satellite host}:"
        echo    "       subscription-manager attach --auto"
        echo    "     then verify with:"
        echo    "       subscription-manager repos --list | grep satellite-6.18"
        echo    "     Expected output should include:"
        echo    "       satellite-6.18-for-rhel-9-x86_64-rpms"
        echo    "       satellite-maintenance-6.18-for-rhel-9-x86_64-rpms"
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        return 1
    }

    ensure_managed_nodes_registered() {
        local register_target="idm:scenario_satellite:aap"
        local reg_shell='subscription-manager identity >/dev/null 2>&1 || subscription-manager register --username="{{ rh_user }}" --password="{{ rh_pass }}" --force; subscription-manager attach --auto >/dev/null 2>&1 || true; subscription-manager refresh >/dev/null 2>&1 || true; if [ -d /etc/pki/rpm-gpg ]; then for k in /etc/pki/rpm-gpg/*; do [ -f "$k" ] && rpm --import "$k" >/dev/null 2>&1 || true; done; fi; dnf clean metadata >/dev/null 2>&1 || true'

        if [ -z "${RH_USER:-}" ] || [ -z "${RH_PASS:-}" ]; then
            print_warning "Skipping RHSM registration precheck: RH_USER/RH_PASS is not set."
            return 0
        fi

        print_step "Ensuring RHSM registration on IdM/Satellite/AAP before config-as-code phases"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${register_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${reg_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${register_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${reg_shell}"
        fi

        if [ "$?" -eq 0 ]; then
            print_success "RHSM registration precheck complete for IdM/Satellite/AAP."
            return 0
        fi

        print_warning "RHSM registration precheck failed; continuing to phase playbooks (they have their own auth fallback)."
        return 1
    }

    precheck_auth_ready() {
        # If inventory auth is not ready yet, skip optional ad-hoc prechecks to
        # avoid noisy UNREACHABLE output and account lockout noise.
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.ping >/dev/null 2>&1
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.ping >/dev/null 2>&1
        fi

        return $?
    }

    ensure_idm_fqdn_resolution() {
        local fqdn_shell="f='${IDM_HOSTNAME}'; h='${IDM_ALIAS:-idm}'; ip='${IDM_IP}'; [ -n \"\$ip\" ] || ip=\"\$(hostname -I 2>/dev/null | awk '{print \$1}')\"; if [ -n \"\$f\" ] && [ -n \"\$ip\" ] && ! getent hosts \"\$f\" >/dev/null 2>&1; then echo \"\$ip \$f \$h\" >> /etc/hosts; fi; getent hosts \"\$f\" >/dev/null 2>&1"

        print_step "Ensuring IdM host can resolve its own FQDN before idm_pre checks"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${fqdn_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${fqdn_shell}"
        fi

        if [ "$?" -eq 0 ]; then
            print_success "IdM FQDN resolution precheck passed."
            return 0
        fi

        print_warning "IdM FQDN resolution precheck failed; idm_pre DNS assertions may fail."
        return 1
    }

    ensure_idm_internet_resolution() {
        local net_shell='set -e; nmcli con up eth0 >/dev/null 2>&1 || nmcli dev connect eth0 >/dev/null 2>&1 || true; if ! getent hosts redhat.com >/dev/null 2>&1; then printf "nameserver 10.168.0.1\nnameserver 1.1.1.1\nnameserver 8.8.8.8\noptions rotate\n" > /etc/resolv.conf || true; fi; getent hosts redhat.com >/dev/null 2>&1'

        print_step "Pre-flight: ensuring IdM can resolve public internet names (redhat.com)"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${net_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${net_shell}"
        fi

        if [ "$?" -eq 0 ]; then
            print_success "IdM internet resolution precheck passed."
            return 0
        fi

        print_warning "IdM internet resolution precheck could not be confirmed; idm_pre internet assertions may still fail."
        return 1
    }

    remediate_satellite_repo_entitlements() {
        local _classify="remediation-ok"
        # Requested remediation flow for Satellite host:
        #   1) dnf upgrade -y --skip-broken --allowerasing --best
        #   2) dnf install -y sos rhc
        #   3) rhc connect --activation-key <key> --organization <org>
        #   4) dnf install -y rhc-worker-playbook
        # Then continue with RHSM repo enablement assertions.
        local sat_shell='dnf upgrade -y --skip-broken --allowerasing --best || true; dnf install -y sos rhc || true; if [ -n "{{ cdn_organization_id | default("") }}" ] && [ -n "{{ cdn_sat_activation_key | default("") }}" ]; then rhc connect --activation-key "{{ cdn_sat_activation_key }}" --organization "{{ cdn_organization_id }}" || true; fi; dnf install -y rhc-worker-playbook || true; if ! subscription-manager identity >/dev/null 2>&1; then if [ -n "{{ cdn_organization_id | default("") }}" ] && [ -n "{{ cdn_sat_activation_key | default("") }}" ]; then subscription-manager register --org="{{ cdn_organization_id }}" --activationkey="{{ cdn_sat_activation_key }}" --force || true; else subscription-manager register --username="{{ rh_user | default("") }}" --password="{{ rh_pass | default("") }}" --force || true; fi; fi; subscription-manager attach --auto >/dev/null 2>&1 || true; subscription-manager refresh >/dev/null 2>&1 || true; subscription-manager repos --disable="*" >/dev/null 2>&1 || true; subscription-manager repos --enable="rhel-9-for-x86_64-baseos-rpms" --enable="rhel-9-for-x86_64-appstream-rpms" --enable="satellite-6.18-for-rhel-9-x86_64-rpms" --enable="satellite-maintenance-6.18-for-rhel-9-x86_64-rpms" >/dev/null 2>&1 || true; subscription-manager repos --list >/dev/null 2>&1 || true'
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"

        # Build a local evars string that extends the enclosing scope's evars with
        # cdn_organization_id / cdn_sat_activation_key when they are set as host-side
        # environment variables (i.e. not solely inside env.yml).  This mirrors exactly
        # what run_phase_playbook() does for the Satellite phase.
        local _rem_evars="${evars}"
        if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
            _rem_evars="${_rem_evars} --extra-vars cdn_organization_id=${CDN_ORGANIZATION_ID} --extra-vars cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}"
            print_step "Pre-flight: using CDN_ORGANIZATION_ID/CDN_SAT_ACTIVATION_KEY for Satellite RHSM registration"
        else
            print_step "Pre-flight: CDN_ORGANIZATION_ID/CDN_SAT_ACTIVATION_KEY not set as env vars — relying on vault (rh_user/rh_pass) for RHSM registration"
        fi

        print_step "Pre-flight: attempting Satellite RHSM attach and repo enable remediation"

        local _remediate_rc=0
        local _remediate_out=""
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            _remediate_out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
        else
            _remediate_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
        fi

        if [ "${_remediate_rc}" -ne 0 ]; then
            if printf '%s\n' "${_remediate_out}" | grep -qE 'UNREACHABLE|Permission denied'; then
                _classify="auth-failed"
            fi
            if [ -n "${root_auth_pass}" ]; then
                print_warning "Satellite RHSM remediation with inventory auth failed (rc=${_remediate_rc}); retrying once with root SSH auth fallback."
                _remediate_rc=0
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    _remediate_out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
                else
                    _remediate_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
                fi

                if [ "${_remediate_rc}" -eq 0 ]; then
                    print_success "Satellite RHSM remediation succeeded with root SSH fallback."
                    _classify="remediation-ok"
                else
                    if printf '%s\n' "${_remediate_out}" | grep -qE 'UNREACHABLE|Permission denied'; then
                        _classify="auth-failed-both"
                    else
                        _classify="remediation-failed"
                    fi
                fi
            fi
        fi

        if [ "${_remediate_rc}" -ne 0 ]; then
            [ "${_classify}" != "auth-failed" ] && [ "${_classify}" != "auth-failed-both" ] && _classify="remediation-failed"
            print_warning "Satellite RHSM remediation ansible task returned rc=${_remediate_rc}."
            print_warning "Remediation output:"
            printf '%s\n' "${_remediate_out}" | head -40
            print_warning "Collecting verbose remediation diagnostics (-vvv)..."
            local _remediate_dbg_out=""
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                _remediate_dbg_out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" -vvv 2>&1 || true)
            else
                _remediate_dbg_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" -vvv 2>&1 || true)
            fi
            print_warning "Verbose remediation output (first 80 lines):"
            printf '%s\n' "${_remediate_dbg_out}" | head -80
            if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
                print_warning "CDN_ORGANIZATION_ID and CDN_SAT_ACTIVATION_KEY were set — verify the"
                print_warning "activation key includes a 'Smart Management' subscription and that the"
                print_warning "Satellite host can reach subscription.rhsm.redhat.com."
            else
                print_warning "Set CDN_ORGANIZATION_ID and CDN_SAT_ACTIVATION_KEY before re-running"
                print_warning "to use an activation key instead of username/password registration."
                print_warning "Alternatively ensure rh_user/rh_pass are present in your vault env.yml."
            fi
        fi

        print_step "Satellite RHSM remediation: ${_classify}"
        return 0
    }

    prepare_idm_runtime_network() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local prep_shell='set -e; nmcli con up eth0 >/dev/null 2>&1 || nmcli dev connect eth0 >/dev/null 2>&1 || true; nmcli con up eth1 >/dev/null 2>&1 || nmcli dev connect eth1 >/dev/null 2>&1 || true; if ! getent hosts redhat.com >/dev/null 2>&1; then printf "nameserver 10.168.0.1\nnameserver 1.1.1.1\nnameserver 8.8.8.8\noptions rotate\n" > /etc/resolv.conf || true; fi; ip route show >/dev/null 2>&1; getent hosts redhat.com >/dev/null 2>&1'

        if [ -z "$root_auth_pass" ]; then
            print_warning "Skipping IdM runtime network prep: ROOT_PASS/ADMIN_PASS is unset."
            return 1
        fi

        print_step "Preparing IdM runtime network/DNS state before phase playbook"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m shell \
                -a "${prep_shell}" >/dev/null 2>&1
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m shell \
                -a "${prep_shell}" >/dev/null 2>&1
        fi

        if [ "$?" -eq 0 ]; then
            print_success "IdM runtime network prep completed."
            return 0
        fi

        print_warning "IdM runtime network prep could not be confirmed; continuing to phase playbook."
        return 1
    }

        # Import RPM GPG keys and clear per-repo gpgcheck=1 overrides before the
        # IdM phase runs.  RHEL 10 packages like rhc-worker-playbook carry a GPG
        # signature; RHSM-managed repo files frequently set gpgcheck=1 per-repo,
        # overriding the global dnf.conf setting written during kickstart.
        ensure_idm_gpg_keys() {
            local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
            # Fix: use s/^gpgcheck=.*/gpgcheck=0/ to catch any existing value (not just =1),
            # sed-replace in dnf.conf instead of appending (dnf uses first occurrence wins),
            # and create a drop-in override for both dnf and dnf5 (RHEL 10).
            local gpg_shell='if [ -d /etc/pki/rpm-gpg ]; then for k in /etc/pki/rpm-gpg/*; do [ -f "$k" ] && rpm --import "$k" 2>/dev/null || true; done; fi; if ls /etc/yum.repos.d/*.repo >/dev/null 2>&1; then sed -i "s/^gpgcheck=.*/gpgcheck=0/" /etc/yum.repos.d/*.repo 2>/dev/null || true; sed -i "s/^repo_gpgcheck=.*/repo_gpgcheck=0/" /etc/yum.repos.d/*.repo 2>/dev/null || true; fi; for _conf in /etc/dnf/dnf.conf /etc/dnf5/dnf.conf; do [ -f "$_conf" ] || continue; sed -i "s/^gpgcheck=.*/gpgcheck=0/" "$_conf" 2>/dev/null || true; grep -q "^gpgcheck=" "$_conf" || printf "\ngpgcheck=0\n" >> "$_conf" 2>/dev/null || true; done; for _d in /etc/dnf/dnf.conf.d /etc/dnf5/dnf.conf.d; do [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || true; printf "[main]\ngpgcheck=0\nrepo_gpgcheck=0\nlocalpkg_gpgcheck=0\nexclude=intel-audio-firmware*\n" > "$_d/rhis-disable-gpgcheck.conf" 2>/dev/null || true; done'

            [ -n "$root_auth_pass" ] || { print_warning "Skipping IdM GPG pre-flight: ROOT_PASS/ADMIN_PASS is unset."; return 0; }

            print_step "Pre-flight: importing RPM GPG keys and normalising repo gpgcheck on IdM host"

            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${gpg_shell}" >/dev/null 2>&1
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${gpg_shell}" >/dev/null 2>&1
            fi

            if [ "$?" -eq 0 ]; then
                print_success "IdM GPG keys imported and repo gpgcheck normalised."
            else
                print_warning "IdM GPG key pre-flight could not complete; IdM phase may fail on GPG validation."
            fi
            return 0
        }

    # Print IdM network state (routes, resolver, internet check) after a failure
    # so the root cause is immediately visible without manual SSH.
    dump_idm_network_diagnostics() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local diag_shell='echo "=== ip route ==="; ip route show; echo "=== /etc/resolv.conf ==="; cat /etc/resolv.conf; echo "=== internet resolution ==="; getent hosts redhat.com && echo "PASS: redhat.com resolves" || echo "FAIL: redhat.com does NOT resolve"'

        print_step "Diagnostics: collecting IdM network state after failure"

        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            fi
        fi

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        fi

        return 0
    }

    dump_idm_web_ui_diagnostics() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local diag_shell='echo "=== hostname ==="; hostname -f || hostname; echo "=== service states ==="; systemctl is-active ipa || true; systemctl is-active httpd || true; systemctl is-active pki-tomcatd@pki-tomcat || true; systemctl --no-pager --full -l status ipa httpd pki-tomcatd@pki-tomcat 2>/dev/null | tail -120 || true; echo "=== port 443 listeners ==="; ss -ltnp | grep -E "(:443\\b|:80\\b)" || true; echo "=== local curl /ipa/ui ==="; curl -k -sS -o /dev/null -w "HTTP %{http_code}\\n" https://localhost/ipa/ui/ || true'

        print_step "Diagnostics: collecting IdM Web UI/service state"

        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            fi
        fi

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        fi

        return 0
    }

    ensure_idm_web_ui_ready() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local timeout interval start_ts now elapsed
        local rc=0
        local check_out=""
        local remediate_shell='systemctl enable --now chronyd >/dev/null 2>&1 || true; systemctl enable --now httpd >/dev/null 2>&1 || true; ipactl status >/dev/null 2>&1 || ipactl start >/dev/null 2>&1 || true; systemctl restart httpd pki-tomcatd@pki-tomcat >/dev/null 2>&1 || true; curl -k -sS -o /dev/null -w "HTTP %{http_code}\\n" https://localhost/ipa/ui/ || true'
        local check_shell='code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ipa/ui/ 2>/dev/null || true)"; ss -ltn | grep -q ":443\\b" || exit 1; case "$code" in 200|301|302|303|307|308|401|403) echo "IDM_WEB_UI_READY:$code" ;; *) echo "IDM_WEB_UI_NOT_READY:$code"; exit 1 ;; esac'

        timeout="${RHIS_IDM_WEB_UI_TIMEOUT:-900}"
        interval="${RHIS_IDM_WEB_UI_INTERVAL:-15}"
        case "${timeout}" in ''|*[!0-9]*) timeout=900 ;; esac
        case "${interval}" in ''|*[!0-9]*) interval=15 ;; esac
        [ "${timeout}" -gt 0 ] || timeout=900
        [ "${interval}" -gt 0 ] || interval=15

        print_step "IdM Web UI gate: attempting service remediation before readiness checks"
        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" -e "ansible_password=${root_auth_pass}" -e "ansible_become=false" -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${remediate_shell}" >/dev/null 2>&1 || true
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" -e "ansible_password=${root_auth_pass}" -e "ansible_become=false" -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${remediate_shell}" >/dev/null 2>&1 || true
            fi
        fi

        print_step "IdM Web UI gate: waiting up to ${timeout}s for https://${IDM_HOSTNAME:-idm}/ipa/ui"
        start_ts="$(date +%s)"
        while true; do
            rc=0
            if [ -n "$root_auth_pass" ]; then
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    check_out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" -e "ansible_password=${root_auth_pass}" -e "ansible_become=false" -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${check_shell}" --one-line 2>&1) || rc=$?
                else
                    check_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" -e "ansible_password=${root_auth_pass}" -e "ansible_become=false" -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${check_shell}" --one-line 2>&1) || rc=$?
                fi
            else
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    check_out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${check_shell}" --one-line 2>&1) || rc=$?
                else
                    check_out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "idm" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${check_shell}" --one-line 2>&1) || rc=$?
                fi
            fi

            if [ "$rc" -eq 0 ] && printf '%s\n' "${check_out}" | grep -q 'IDM_WEB_UI_READY:'; then
                print_success "IdM Web UI is reachable and healthy (${check_out##*IDM_WEB_UI_READY:})."
                return 0
            fi

            now="$(date +%s)"
            elapsed=$(( now - start_ts ))
            if [ "$elapsed" -ge "$timeout" ]; then
                print_warning "IdM Web UI did not become ready within ${timeout}s."
                print_warning "Last Web UI probe output: ${check_out}"
                dump_idm_web_ui_diagnostics || true
                return 1
            fi

            if [ $(( elapsed % 60 )) -eq 0 ]; then
                print_step "IdM Web UI still converging (elapsed=${elapsed}s/${timeout}s)."
            fi
            sleep "$interval"
        done
    }

    # Print Satellite RHSM identity, status, and enabled repos after a failure
    # so entitlement and repo issues are immediately visible.
    dump_satellite_rhsm_diagnostics() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local diag_shell='echo "=== subscription-manager identity ==="; subscription-manager identity || echo "(not registered)"; echo "=== subscription-manager status ==="; subscription-manager status || true; echo "=== enabled repos ==="; subscription-manager repos --list-enabled || echo "(none or error)"'

        print_step "Diagnostics: collecting Satellite RHSM state after failure"

        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${diag_shell}" && return 0
            fi
        fi

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${diag_shell}" || true
        fi

        return 0
    }

    # Ensure rhel-system-roles and rhc-worker-playbook are present on managed
    # nodes. For rhc-worker-playbook we try the pinned version first, then
    # latest if unavailable; if install fails, retry with --nogpgcheck.
    ensure_core_role_packages_on_managed_nodes() {
        local target="${1:-idm:scenario_satellite:aap}"
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local pkg_shell='if ! rpm -q rhel-system-roles >/dev/null 2>&1; then dnf -y install rhel-system-roles || dnf -y install --nogpgcheck rhel-system-roles || true; fi; if ! rpm -q rhc-worker-playbook >/dev/null 2>&1; then if ! dnf -y install rhc-worker-playbook-0.2.3-3.el10_1; then dnf -y install rhc-worker-playbook || dnf -y install --nogpgcheck rhc-worker-playbook || true; fi; fi'
        local classify="pkg-preflight-failed"

        print_step "Pre-flight: ensuring rhel-system-roles + rhc-worker-playbook on ${target} (nogpgcheck fallback enabled)"

        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${pkg_shell}" >/dev/null 2>&1
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${pkg_shell}" >/dev/null 2>&1
            fi

            if [ "$?" -eq 0 ]; then
                classify="pkg-preflight-root-ok"
                print_success "Package pre-flight complete on ${target}."
                print_step "Package pre-flight (${target}): ${classify}"
                return 0
            fi
        fi

        print_warning "Package pre-flight with root auth failed/unavailable for ${target}; trying inventory auth."
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${pkg_shell}" >/dev/null 2>&1
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${pkg_shell}" >/dev/null 2>&1
        fi

        if [ "$?" -eq 0 ]; then
            classify="pkg-preflight-inventory-ok"
            print_success "Package pre-flight complete on ${target} (inventory auth)."
            print_step "Package pre-flight (${target}): ${classify}"
            return 0
        fi

        print_step "Package pre-flight (${target}): ${classify}"
        print_warning "Package pre-flight could not be confirmed on ${target}; continuing."
        return 1
    }

    # Ensure all managed hosts are fully up to date before any config-as-code
    # phase runs. Prefer root-auth execution when ROOT_PASS/ADMIN_PASS exists.
    # If root auth is unavailable, fall back to inventory credentials.
    # Non-fatal (|| true) so a single host issue does not abort everything.
    ensure_all_hosts_upgraded() {
        local upgrade_target="idm:aap"
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local upgrade_shell='if subscription-manager identity >/dev/null 2>&1; then echo "Upgrade preflight: registered=yes"; else echo "Upgrade preflight: registered=no"; subscription-manager register --username="{{ rh_user }}" --password="{{ rh_pass }}" --force; fi; subscription-manager refresh; dnf -y --nogpgcheck upgrade subscription-manager; subscription-manager refresh; (dnf -y --nogpgcheck group install "Base" || dnf -y --nogpgcheck groupinstall "Base"); dnf install -y --nogpgcheck yum-utils; dnf autoremove -y; dnf clean all; dnf -y --nogpgcheck upgrade'

        print_step "Pre-flight: ensuring RHSM registration and running the requested DNF upgrade sequence on IdM/AAP hosts..."

        if [ -n "$root_auth_pass" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${upgrade_shell}"
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell \
                    -a "${upgrade_shell}"
            fi

            if [ "$?" -eq 0 ]; then
                print_success "IdM/AAP hosts upgraded successfully."
                return 0
            fi

            print_warning "dnf upgrade failed with root auth; skipping inventory-credential retry to avoid known admin auth noise."
            print_warning "Root-auth connectivity summary (expected IdM/AAP reachable as root):"
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m ansible.builtin.ping \
                    --one-line 2>/dev/null || true
            else
                podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                    ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m ansible.builtin.ping \
                    --one-line 2>/dev/null || true
            fi
            return 1
        fi

        print_warning "ROOT_PASS/ADMIN_PASS is unset; attempting upgrade with inventory credentials."

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${upgrade_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${upgrade_shell}"
        fi

        if [ "$?" -eq 0 ]; then
            print_success "IdM/AAP hosts upgraded successfully."
            return 0
        fi

        print_warning "Upgrade preflight failed with inventory credentials; continuing."
        return 1
    }

    reboot_managed_hosts_after_upgrade() {
        local reboot_target="idm:aap"
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local reboot_shell='nohup bash -c "sleep 2; systemctl reboot" >/dev/null 2>&1 &'

        [ -n "$root_auth_pass" ] || {
            print_warning "Skipping post-upgrade reboot: ROOT_PASS/ADMIN_PASS is unset."
            return 1
        }

        print_step "Post-upgrade: rebooting IdM/AAP before continuing"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${reboot_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m shell \
                -a "${reboot_shell}" >/dev/null 2>&1 || true
        else
            podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                ansible "${reboot_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m shell \
                -a "${reboot_shell}" >/dev/null 2>&1 || true
        fi

        sleep 15
        print_step "Post-upgrade: waiting for IdM and Satellite to return after reboot"
        preflight_config_as_code_targets "idm:${IDM_IP}" "satellite-618:${SAT_IP}" || return 1
        print_success "Post-upgrade reboot complete; IdM and Satellite are reachable again."
        return 0
    }

    if is_enabled "${RHIS_ENABLE_PRECHECK_ADHOC:-0}"; then
        if precheck_auth_ready; then
            ensure_managed_nodes_registered || true
            ensure_idm_fqdn_resolution || true
            ensure_idm_internet_resolution || true
            if ensure_all_hosts_upgraded; then
                reboot_managed_hosts_after_upgrade || true
            fi
        else
            print_warning "Skipping optional pre-flight ad-hoc probes/upgrades: authenticated SSH is not ready yet."
        fi
    else
        print_step "Skipping optional pre-flight ad-hoc probes/upgrades (RHIS_ENABLE_PRECHECK_ADHOC=0)."
    fi

    prepare_idm_runtime_network || true
    ensure_idm_gpg_keys || true
    ensure_core_role_packages_on_managed_nodes "idm:scenario_satellite" || true

    # ── 1. IdM — must be ready first (Satellite/AAP enroll against it) ─────────
    if ! run_phase_playbook_with_auth_fallback "Phase 1/3 — Configuring IdM..." "idm" "/rhis/rhis-builder-idm/main.yml"; then
        idm_auth_fallback_status="${phase_auth_fallback_status}"
        idm_status="failed"
        any_failed=1
        print_warning "IdM config-as-code failed.  Check the output above."
        dump_idm_network_diagnostics || true
        dump_idm_web_ui_diagnostics || true
        print_warning "You can re-run manually:"
        print_manual_rerun_template
        print_warning "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} ${manual_idm_extras} --limit idm /rhis/rhis-builder-idm/main.yml"
    else
        idm_auth_fallback_status="${phase_auth_fallback_status}"
        if ensure_idm_web_ui_ready; then
            idm_status="success"
            print_success "IdM configuration complete."
        else
            idm_status="failed-webui"
            any_failed=1
            print_warning "IdM phase completed but Web UI readiness gate failed."
        fi
    fi
    print_step "Auth fallback (IdM): ${idm_auth_fallback_status}"

    # ── 2. Satellite ───────────────────────────────────────────────────────────
    remediate_satellite_repo_entitlements || true
    print_step "Pre-flight: collecting Satellite RHSM state"
    dump_satellite_rhsm_diagnostics || true

    if ! run_phase_playbook_with_auth_fallback "Phase 2/3 — Configuring Satellite..." "scenario_satellite" "/rhis/rhis-builder-satellite/main.yml"; then
        satellite_auth_fallback_status="${phase_auth_fallback_status}"
        satellite_status="failed"
        any_failed=1
        print_warning "Satellite config-as-code failed.  Check the output above."
        dump_satellite_rhsm_diagnostics || true
        print_warning "You can re-run manually:"
        print_manual_rerun_template
        print_warning "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} ${manual_satellite_extras} --limit scenario_satellite /rhis/rhis-builder-satellite/main.yml"
    else
        satellite_auth_fallback_status="${phase_auth_fallback_status}"
        satellite_status="success"
        print_success "Satellite configuration complete."
    fi
    print_step "Auth fallback (Satellite): ${satellite_auth_fallback_status}"

    ensure_core_role_packages_on_managed_nodes "aap" || true

    # ── 3. AAP ─────────────────────────────────────────────────────────────────
    print_step "Phase gate: starting deferred AAP callback and readiness checks"
    if ! run_deferred_aap_callback; then
        aap_status="callback-failed"
        aap_auth_fallback_status="not-needed"
        any_failed=1
        print_warning "AAP callback did not complete; skipping AAP config-as-code phase."
    elif ! preflight_config_as_code_targets "aap-26:${AAP_IP}"; then
        aap_status="ssh-unreachable"
        aap_auth_fallback_status="not-needed"
        any_failed=1
        print_warning "AAP internal SSH is still not reachable; skipping AAP config-as-code phase."
    elif ! run_phase_playbook_with_auth_fallback "Phase 3/3 — Configuring AAP..." "aap" "/rhis/rhis-builder-aap/main.yml"; then
        aap_auth_fallback_status="${phase_auth_fallback_status}"
        aap_status="failed"
        any_failed=1
        print_warning "AAP config-as-code failed.  Check the output above."
        print_warning "You can re-run manually:"
        print_manual_rerun_template
        print_warning "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} --limit aap /rhis/rhis-builder-aap/main.yml"
    else
        aap_auth_fallback_status="${phase_auth_fallback_status}"
        aap_status="success"
        print_success "AAP configuration complete."
    fi
    print_step "Auth fallback (AAP): ${aap_auth_fallback_status}"

    if [ "$any_failed" -ne 0 ] && is_enabled "${RHIS_RETRY_FAILED_PHASES_ONCE:-1}"; then
        print_step "Retry mode enabled: re-running only failed phases once"
        any_failed=0

        if [ "$idm_status" = "failed" ]; then
            if run_phase_playbook_with_auth_fallback "Retry — IdM" "idm" "/rhis/rhis-builder-idm/main.yml"; then
                idm_status="success-after-retry"
                print_success "IdM succeeded on retry."
            else
                any_failed=1
                print_warning "IdM retry failed."
            fi
            idm_auth_fallback_status="${phase_auth_fallback_status}"
            print_step "Auth fallback (IdM retry): ${idm_auth_fallback_status}"
        fi

        if [ "$satellite_status" = "failed" ]; then
            if run_phase_playbook_with_auth_fallback "Retry — Satellite" "scenario_satellite" "/rhis/rhis-builder-satellite/main.yml"; then
                satellite_status="success-after-retry"
                print_success "Satellite succeeded on retry."
            else
                any_failed=1
                print_warning "Satellite retry failed."
            fi
            satellite_auth_fallback_status="${phase_auth_fallback_status}"
            print_step "Auth fallback (Satellite retry): ${satellite_auth_fallback_status}"
        fi

        if [ "$aap_status" = "failed" ]; then
            if run_phase_playbook_with_auth_fallback "Retry — AAP" "aap" "/rhis/rhis-builder-aap/main.yml"; then
                aap_status="success-after-retry"
                print_success "AAP succeeded on retry."
            else
                any_failed=1
                print_warning "AAP retry failed."
            fi
            aap_auth_fallback_status="${phase_auth_fallback_status}"
            print_step "Auth fallback (AAP retry): ${aap_auth_fallback_status}"
        fi
    fi

    run_post_install_healthcheck() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local local_failures=0

        healthcheck_run_shell() {
            local _target="$1"
            local _label="$2"
            local _shell="$3"
            local _out=""
            local _rc=0

            print_step "Healthcheck: ${_label}"

            if [ -n "${root_auth_pass}" ]; then
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    _out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${_shell}" --one-line 2>&1) || _rc=$?
                else
                    _out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${_shell}" --one-line 2>&1) || _rc=$?
                fi
            else
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    _out=$(podman exec -it -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${_shell}" --one-line 2>&1) || _rc=$?
                else
                    _out=$(podman exec -e "ANSIBLE_CONFIG=${RHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${RHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} -m shell -a "${_shell}" --one-line 2>&1) || _rc=$?
                fi
            fi

            [ -n "${_out}" ] && printf '%s\n' "${_out}" | head -40
            return ${_rc}
        }

        if ! is_enabled "${RHIS_ENABLE_POST_HEALTHCHECK:-1}"; then
            print_step "Post-install healthcheck is disabled (RHIS_ENABLE_POST_HEALTHCHECK=0)."
            return 0
        fi

        print_step "===== Post-install healthcheck (IdM/Satellite/AAP) ====="

        local idm_check='code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ipa/ui/ 2>/dev/null || true)"; ipactl status >/dev/null 2>&1; systemctl is-active --quiet httpd; ss -ltn | grep -q ":443\\b"; case "$code" in 200|301|302|303|307|308|401|403) echo "IDM_HEALTH_OK:$code" ;; *) echo "IDM_HEALTH_BAD:$code"; exit 1 ;; esac'
        local idm_fix='systemctl enable --now chronyd >/dev/null 2>&1 || true; systemctl enable --now httpd >/dev/null 2>&1 || true; ipactl status >/dev/null 2>&1 || ipactl start >/dev/null 2>&1 || true; systemctl restart httpd pki-tomcatd@pki-tomcat >/dev/null 2>&1 || true; true'

        if healthcheck_run_shell "idm" "IdM web/service readiness" "${idm_check}"; then
            print_success "Healthcheck passed: IdM"
        else
            local_failures=$((local_failures + 1))
            print_warning "Healthcheck failed: IdM"
            if is_enabled "${RHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                print_step "Healthcheck autofix: IdM service remediation"
                healthcheck_run_shell "idm" "IdM autofix action" "${idm_fix}" || true
                if healthcheck_run_shell "idm" "IdM post-autofix verification" "${idm_check}"; then
                    print_success "IdM recovered after autofix."
                    local_failures=$((local_failures - 1))
                elif is_enabled "${RHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                    print_warning "Healthcheck rerun: IdM component playbook"
                    if run_phase_playbook_with_auth_fallback "Healthcheck repair — IdM" "idm" "/rhis/rhis-builder-idm/main.yml" && \
                       healthcheck_run_shell "idm" "IdM post-rerun verification" "${idm_check}"; then
                        print_success "IdM recovered after targeted component rerun."
                        local_failures=$((local_failures - 1))
                    else
                        dump_idm_network_diagnostics || true
                        dump_idm_web_ui_diagnostics || true
                    fi
                else
                    dump_idm_network_diagnostics || true
                    dump_idm_web_ui_diagnostics || true
                fi
            fi
        fi

        local sat_check='systemctl is-active --quiet httpd; ss -ltn | grep -q ":443\\b"; code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null || true)"; case "$code" in 200|301|302|303|307|308|401|403) echo "SAT_HEALTH_OK:$code" ;; *) echo "SAT_HEALTH_BAD:$code"; exit 1 ;; esac'
        local sat_fix='systemctl enable --now httpd >/dev/null 2>&1 || true; satellite-maintain service start >/dev/null 2>&1 || true; systemctl restart httpd >/dev/null 2>&1 || true; true'

        if healthcheck_run_shell "scenario_satellite" "Satellite web/service readiness" "${sat_check}"; then
            print_success "Healthcheck passed: Satellite"
        else
            local_failures=$((local_failures + 1))
            print_warning "Healthcheck failed: Satellite"
            if is_enabled "${RHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                print_step "Healthcheck autofix: Satellite service remediation"
                healthcheck_run_shell "scenario_satellite" "Satellite autofix action" "${sat_fix}" || true
                if healthcheck_run_shell "scenario_satellite" "Satellite post-autofix verification" "${sat_check}"; then
                    print_success "Satellite recovered after autofix."
                    local_failures=$((local_failures - 1))
                elif is_enabled "${RHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                    print_warning "Healthcheck rerun: Satellite component playbook"
                    if run_phase_playbook_with_auth_fallback "Healthcheck repair — Satellite" "scenario_satellite" "/rhis/rhis-builder-satellite/main.yml" && \
                       healthcheck_run_shell "scenario_satellite" "Satellite post-rerun verification" "${sat_check}"; then
                        print_success "Satellite recovered after targeted component rerun."
                        local_failures=$((local_failures - 1))
                    else
                        dump_satellite_rhsm_diagnostics || true
                    fi
                else
                    dump_satellite_rhsm_diagnostics || true
                fi
            fi
        fi

        local aap_check='(ss -ltn | grep -q ":443\\b" || ss -ltn | grep -q ":80\\b"); code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null || true)"; [ "$code" != "000" ] || code="$(curl -sS -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || true)"; case "$code" in 200|301|302|303|307|308|401|403) echo "AAP_HEALTH_OK:$code" ;; *) echo "AAP_HEALTH_BAD:$code"; exit 1 ;; esac'
        local aap_fix='systemctl enable --now podman >/dev/null 2>&1 || true; systemctl restart podman >/dev/null 2>&1 || true; true'

        if [ "${aap_status}" = "success" ] || [ "${aap_status}" = "success-after-retry" ]; then
            if healthcheck_run_shell "aap" "AAP web/service readiness" "${aap_check}"; then
                print_success "Healthcheck passed: AAP"
            else
                local_failures=$((local_failures + 1))
                print_warning "Healthcheck failed: AAP"
                if is_enabled "${RHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                    print_step "Healthcheck autofix: AAP service remediation"
                    healthcheck_run_shell "aap" "AAP autofix action" "${aap_fix}" || true
                    if healthcheck_run_shell "aap" "AAP post-autofix verification" "${aap_check}"; then
                        print_success "AAP recovered after autofix."
                        local_failures=$((local_failures - 1))
                    elif is_enabled "${RHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                        print_warning "Healthcheck rerun: AAP component playbook"
                        if run_phase_playbook_with_auth_fallback "Healthcheck repair — AAP" "aap" "/rhis/rhis-builder-aap/main.yml" && \
                           healthcheck_run_shell "aap" "AAP post-rerun verification" "${aap_check}"; then
                            print_success "AAP recovered after targeted component rerun."
                            local_failures=$((local_failures - 1))
                        fi
                    fi
                fi
            fi
        else
            print_warning "Skipping AAP post-install healthcheck because AAP phase status is '${aap_status}'."
        fi

        if [ "${local_failures}" -ne 0 ]; then
            print_warning "Post-install healthcheck finished with ${local_failures} unresolved issue(s)."
            return 1
        fi

        print_success "Post-install healthcheck passed for all applicable components."
        return 0
    }

    if ! run_post_install_healthcheck; then
        any_failed=1
    fi

    print_step "===== Config-as-Code Summary ====="
    echo "  IdM:       ${idm_status}"
    echo "  Satellite: ${satellite_status}"
    echo "  AAP:       ${aap_status}"

    if [ "$any_failed" -ne 0 ]; then
        print_warning "===== Config-as-Code phase finished with failures. ====="
    else
        print_success "===== Config-as-Code phase finished successfully. ====="
    fi

    echo ""
    echo "To re-run any component:"
    echo "  podman exec -it ${RHIS_CONTAINER_NAME} /bin/bash"
    echo "  podman exec -it ${manual_podman_env} ${RHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} --limit <GROUP> /rhis/rhis-builder-<COMPONENT>/main.yml"

    cleanup_staged_vaultpass

    [ "$any_failed" -eq 0 ]
}

# Virt-Manager Setup
enable_virt_manager_xml_editor() {
    print_step "Ensuring virt-manager XML editor is enabled"

    # Preferred path: gsettings
    if command -v gsettings >/dev/null 2>&1; then
        if gsettings writable org.virt-manager.virt-manager xmleditor-enabled >/dev/null 2>&1; then
            gsettings set org.virt-manager.virt-manager xmleditor-enabled true
            print_success "virt-manager XML editor enabled (gsettings)"
            return 0
        fi
    fi

    # Fallback: dconf direct write
    if command -v dconf >/dev/null 2>&1; then
        dconf write /org/virt-manager/virt-manager/xmleditor-enabled true
        print_success "virt-manager XML editor enabled (dconf)"
        return 0
    fi

    print_warning "Could not auto-enable virt-manager XML editor. Enable manually in Edit -> Preferences -> Enable XML editing."
    return 0
}

enable_virt_manager_resize_guest() {
    print_step "Ensuring virt-manager 'Resize guest with window' is enabled"

    # Try known gsettings keys first (version-dependent)
    if command -v gsettings >/dev/null 2>&1; then
        if gsettings writable org.virt-manager.virt-manager console-resize-guest >/dev/null 2>&1; then
            gsettings set org.virt-manager.virt-manager console-resize-guest true
            print_success "Enabled resize guest with window (console-resize-guest)"
            return 0
        elif gsettings writable org.virt-manager.virt-manager resize-guest >/dev/null 2>&1; then
            gsettings set org.virt-manager.virt-manager resize-guest true
            print_success "Enabled resize guest with window (resize-guest)"
            return 0
        fi
    fi

    # dconf fallback (common path used by virt-manager)
    if command -v dconf >/dev/null 2>&1; then
        dconf write /org/virt-manager/virt-manager/console/resize-guest true \
            && print_success "Enabled resize guest with window (dconf)" \
            && return 0
    fi

    print_warning "Could not auto-enable resize setting. Enable manually in Edit -> Preferences -> Console -> Resize guest with window."
    return 0
}

setup_virt_manager() {
    print_step "Setting up Virt-Manager"
    ensure_platform_packages_for_virt_manager || {
        print_warning "Could not install required installer-host packages for virt-manager/libvirt."
        return 1
    }
    configure_libvirt_firewall_policy
    enable_virt_manager_xml_editor
    enable_virt_manager_resize_guest
    configure_libvirt_networks
    download_rhel10_iso || true
    download_rhel9_iso || true

    read -r -p "Create Satellite/AAP VMs now? [Y/n]: " build_vms
    case "${build_vms:-Y}" in
        Y|y|"")
            create_rhis_vms || print_warning "VM creation did not complete."
            ;;
        *)
            print_warning "Skipping VM creation."
            ;;
    esac

    print_step "Installing build dependency tooling for virtualization packages"
    sudo dnf install -y --nogpgcheck yum-utils
    sudo yum-builddep -y virt-install qemu-img libvirt-client libvirt virt-manager

    print_step "Installing virt-manager and dependencies"
    sudo dnf install -y --nogpgcheck virt-manager virt-viewer libvirt qemu-kvm

    print_step "Enabling libvirtd service"
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd

    print_step "Verifying virt-manager installation"
    virsh list --all

    print_success "Virt-Manager setup complete"

    print_step "Configuring RHIS to monitor VMs"

    if [ -f "RHIS/config.json" ]; then
        echo "config.json found. Add the following to your resources:"
        echo ""
        echo '{
  "name": "vm-server-1",
  "type": "libvirt",
  "endpoint": "qemu:///system",
  "collectInterval": 60
}'
        echo ""
    else
        print_warning "config.json not found. Manually add VM endpoints after installation."
    fi

    print_step "Launching virt-manager"
    virt-manager &
}

ensure_iso_vars() {
    if ! mkdir -p "${ISO_DIR:?}" 2>/dev/null; then
        sudo mkdir -p "${ISO_DIR:?}" || return 1
    fi

    if ! mkdir -p "${VM_DIR:?}" 2>/dev/null; then
        sudo mkdir -p "${VM_DIR:?}" || return 1
    fi

    if ! mkdir -p "${KS_DIR:?}" 2>/dev/null; then
        sudo mkdir -p "${KS_DIR:?}" || return 1
    fi
}

ensure_jq() {
	if command -v jq >/dev/null 2>&1; then return 0; fi
    sudo dnf install -y --nogpgcheck jq
	return $?
}

# ─── Credential store: ~/.ansible/conf/env.yml ────────────────────────────────
# Ensure ansible-vault exists.
ensure_ansible_vault() {
    if command -v ansible-vault >/dev/null 2>&1; then
        return 0
    fi

    print_warning "ansible-vault not found. Attempting to install ansible-core..."
    sudo dnf install -y --nogpgcheck ansible-core >/dev/null 2>&1 || {
        print_warning "Could not install ansible-core. Please install ansible-vault and re-run."
        return 1
    }

    command -v ansible-vault >/dev/null 2>&1
}

# Ensure vault password file exists at ~/.ansible/conf/.vaultpass.txt (chmod 600).
ensure_vault_password_file() {
    mkdir -p "$ANSIBLE_ENV_DIR" || return 1
    chmod 700 "$ANSIBLE_ENV_DIR" 2>/dev/null || true

    if [ -s "$ANSIBLE_VAULT_PASS_FILE" ]; then
        chmod 600 "$ANSIBLE_VAULT_PASS_FILE" 2>/dev/null || true
        return 0
    fi

    if is_noninteractive; then
        print_warning "Missing vault password file: $ANSIBLE_VAULT_PASS_FILE"
        print_warning "Create it before using NONINTERACTIVE mode."
        return 1
    fi

    local pass1 pass2
    print_step "Creating Ansible Vault password file: $ANSIBLE_VAULT_PASS_FILE"
    while true; do
        read -r -s -p "Create Ansible Vault password: " pass1
        echo ""
        read -r -s -p "Confirm Ansible Vault password: " pass2
        echo ""

        if [ -z "$pass1" ]; then
            print_warning "Vault password cannot be empty."
            continue
        fi

        if [ "$pass1" != "$pass2" ]; then
            print_warning "Passwords did not match. Try again."
            continue
        fi

        printf '%s\n' "$pass1" > "$ANSIBLE_VAULT_PASS_FILE"
        chmod 600 "$ANSIBLE_VAULT_PASS_FILE"
        print_success "Vault password file created."
        break
    done

    return 0
}

# Read env.yml content (decrypting via ansible-vault when needed).
read_ansible_env_content() {
    [ -f "$ANSIBLE_ENV_FILE" ] || {
        ANSIBLE_ENV_CONTENT=""
        return 0
    }

    if grep -q '^\$ANSIBLE_VAULT;' "$ANSIBLE_ENV_FILE" 2>/dev/null; then
        ensure_ansible_vault || return 1
        ensure_vault_password_file || return 1
        ANSIBLE_ENV_CONTENT="$(ansible-vault view --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" "$ANSIBLE_ENV_FILE" 2>/dev/null || true)"
        if [ -z "$ANSIBLE_ENV_CONTENT" ]; then
            print_warning "Failed to decrypt $ANSIBLE_ENV_FILE."
            return 1
        fi
    else
        ANSIBLE_ENV_CONTENT="$(cat "$ANSIBLE_ENV_FILE" 2>/dev/null || true)"
    fi

    return 0
}

# Read one YAML key from env.yml into a bash variable; no-op if already set.
_load_env_key() {
    local var_name="$1" yml_key="$2" val
    [ -n "${!var_name:-}" ] && return 0
    val="$(printf '%s\n' "$ANSIBLE_ENV_CONTENT" | grep -E "^${yml_key}:" 2>/dev/null \
        | sed -E "s|^${yml_key}:[[:space:]]*\"?||;s|\"?[[:space:]]*$||")"
    [ -n "$val" ] && printf -v "$var_name" '%s' "$val"
    return 0
}

# Read one nested networks field from env.yml into a bash variable (no-op if already set).
# Expected shape:
# networks:
#   satellite:
#     ip: "10.168.128.1"
#     mask: "255.255.0.0"
#     gateway: "10.168.0.1"
_load_env_network_field() {
    local var_name="$1" node_name="$2" field_name="$3" val
    [ -n "${!var_name:-}" ] && return 0

    val="$(printf '%s\n' "$ANSIBLE_ENV_CONTENT" | awk -v node="$node_name" -v field="$field_name" '
        /^networks:[[:space:]]*$/ { in_networks=1; next }
        in_networks && /^[^[:space:]]/ { in_networks=0 }
        in_networks && $0 ~ ("^  " node ":[[:space:]]*$") { in_node=1; next }
        in_networks && in_node && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { in_node=0 }
        in_networks && in_node && $0 ~ ("^    " field ":[[:space:]]*") {
            line=$0
            sub("^    " field ":[[:space:]]*\"?", "", line)
            sub("\"?[[:space:]]*$", "", line)
            print line
            exit
        }
    ')"

    [ -n "$val" ] && printf -v "$var_name" '%s' "$val"
    return 0
}

# Load all RHIS credentials from ~/.ansible/conf/env.yml.
# Only populates variables currently unset — preseed / CLI values always win.
load_ansible_env_file() {
    [ -f "$ANSIBLE_ENV_FILE" ] || return 0
    read_ansible_env_content || return 1
    _load_env_key ADMIN_USER      admin_user
    _load_env_key ADMIN_PASS      admin_pass
    _load_env_key DOMAIN          domain
    _load_env_key REALM           realm
    _load_env_key INTERNAL_NETWORK internal_network
    _load_env_key NETMASK         netmask
    _load_env_key INTERNAL_GW     internal_gw
    _load_env_key RH_USER          rh_user
    _load_env_key RH_PASS          rh_pass
    _load_env_key RH_OFFLINE_TOKEN rh_offline_token
    _load_env_key RH_ACCESS_TOKEN  rh_access_token
    _load_env_key HUB_TOKEN        hub_token
    _load_env_key VAULT_CONSOLE_REDHAT_TOKEN vault_console_redhat_token
    _load_env_key SAT_ADMIN_PASS   sat_admin_pass
    _load_env_key AAP_ADMIN_PASS   aap_admin_pass
    _load_env_key SATELLITE_DISCONNECTED satellite_disconnected
    _load_env_key REGISTER_TO_SATELLITE register_to_satellite
    _load_env_key SATELLITE_PRE_USE_IDM satellite_pre_use_idm
    _load_env_key IPADM_PASSWORD   ipadm_password
    _load_env_key IPAADMIN_PASSWORD ipaadmin_password
    _load_env_key CDN_ORGANIZATION_ID cdn_organization_id
    _load_env_key CDN_SAT_ACTIVATION_KEY cdn_sat_activation_key
    _load_env_key SAT_FIREWALLD_ZONE sat_firewalld_zone
    _load_env_key SAT_FIREWALLD_INTERFACE sat_firewalld_interface
    _load_env_key SAT_FIREWALLD_SERVICES_JSON sat_firewalld_services_json
    _load_env_key INSTALLER_USER   installer_user
    _load_env_key AAP_INVENTORY_TEMPLATE aap_inventory_template
    _load_env_key AAP_INVENTORY_GROWTH_TEMPLATE aap_inventory_growth_template
    _load_env_key AAP_PG_DATABASE aap_pg_database
    _load_env_key SAT_REALM        sat_realm
    _load_env_key SAT_IP           sat_ip
    _load_env_key AAP_IP           aap_ip
    _load_env_key IDM_IP           idm_ip
    _load_env_key SAT_NETMASK      sat_netmask
    _load_env_key AAP_NETMASK      aap_netmask
    _load_env_key IDM_NETMASK      idm_netmask
    _load_env_key SAT_GW           sat_gw
    _load_env_key AAP_GW           aap_gw
    _load_env_key IDM_GW           idm_gw

    # Backward/forward compatibility: support nested networks mapping as a source.
    _load_env_network_field SAT_IP satellite ip
    _load_env_network_field SAT_NETMASK satellite mask
    _load_env_network_field SAT_GW satellite gateway
    _load_env_network_field AAP_IP aap ip
    _load_env_network_field AAP_NETMASK aap mask
    _load_env_network_field AAP_GW aap gateway
    _load_env_network_field IDM_IP idm ip
    _load_env_network_field IDM_NETMASK idm mask
    _load_env_network_field IDM_GW idm gateway
    _load_env_key SAT_HOSTNAME     sat_hostname
    _load_env_key SAT_ALIAS        sat_alias
    _load_env_key SAT_DOMAIN       sat_domain
    _load_env_key SAT_ORG          sat_org
    _load_env_key SAT_LOC          sat_loc
    _load_env_key AAP_HOSTNAME     aap_hostname
    _load_env_key AAP_ALIAS        aap_alias
    _load_env_key AAP_DOMAIN       aap_domain
    _load_env_key IDM_HOSTNAME     idm_hostname
    _load_env_key IDM_ALIAS        idm_alias
    _load_env_key IDM_DOMAIN       idm_domain
    _load_env_key IDM_REALM        idm_realm
    _load_env_key IDM_ADMIN_PASS   idm_admin_pass
    _load_env_key IDM_DS_PASS      idm_ds_pass
    _load_env_key HOST_INT_IP      host_int_ip
    _load_env_key AAP_BUNDLE_URL   aap_bundle_url
    _load_env_key RH_ISO_URL       rh_iso_url
    _load_env_key RH9_ISO_URL      rh9_iso_url
    normalize_shared_env_vars

    # Keep legacy HUB_TOKEN and dedicated vault_console_redhat_token aligned.
    if [ -z "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ] && [ -n "${HUB_TOKEN:-}" ]; then
        VAULT_CONSOLE_REDHAT_TOKEN="${HUB_TOKEN}"
    fi
    if [ -z "${HUB_TOKEN:-}" ] && [ -n "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ]; then
        HUB_TOKEN="${VAULT_CONSOLE_REDHAT_TOKEN}"
    fi
}

# Persist all RHIS credentials to ~/.ansible/conf/env.yml (atomic write, chmod 600).
write_ansible_env_file() {
    mkdir -p "$ANSIBLE_ENV_DIR" || return 1
    ensure_ansible_vault || return 1
    ensure_vault_password_file || return 1
    normalize_shared_env_vars

    local tmp_env
    tmp_env="$(mktemp "${ANSIBLE_ENV_DIR}/.env.yml.XXXXXX")"
    cat > "$tmp_env" <<RHIS_ENV_EOF
# RHIS credentials — written by run_rhis_install_sequence.sh on $(date '+%Y-%m-%d %H:%M')
# Permissions: 600 — do NOT commit this file to version control.
---
admin_user: "${ADMIN_USER:-}"
admin_pass: "${ADMIN_PASS:-}"
domain: "${DOMAIN:-}"
realm: "${REALM:-}"
internal_network: "${INTERNAL_NETWORK:-}"
netmask: "${NETMASK:-}"
internal_gw: "${INTERNAL_GW:-}"
rh_user: "${RH_USER:-}"
rh_pass: "${RH_PASS:-}"
rh_offline_token: "${RH_OFFLINE_TOKEN:-}"
rh_access_token: "${RH_ACCESS_TOKEN:-}"
hub_token: "${HUB_TOKEN:-}"
vault_console_redhat_token: "${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}"
aap_ip: "${AAP_IP:-}"
idm_ip: "${IDM_IP:-}"
aap_admin_pass: "${AAP_ADMIN_PASS:-}"
sat_admin_pass: "${SAT_ADMIN_PASS:-}"
satellite_disconnected: ${SATELLITE_DISCONNECTED:-false}
register_to_satellite: ${REGISTER_TO_SATELLITE:-false}
satellite_pre_use_idm: ${SATELLITE_PRE_USE_IDM:-false}
ipadm_password: "${IPADM_PASSWORD:-}"
ipaadmin_password: "${IPAADMIN_PASSWORD:-}"
cdn_organization_id: "${CDN_ORGANIZATION_ID:-}"
cdn_sat_activation_key: "${CDN_SAT_ACTIVATION_KEY:-}"
# Aliases expected by rhis-builder-idm idm_pre role (redhat.rhel_system_roles.rhc)
cdn_organization_vault: "${CDN_ORGANIZATION_ID:-}"
cdn_activation_key_vault: "${CDN_SAT_ACTIVATION_KEY:-}"
sat_firewalld_zone: "${SAT_FIREWALLD_ZONE:-public}"
sat_firewalld_interface: "${SAT_FIREWALLD_INTERFACE:-eth1}"
sat_firewalld_services_json: '${SAT_FIREWALLD_SERVICES_JSON:-["ssh","http","https"]}'
# Alias used by rhis-builder host_vars templates ({{ global_admin_password }})
global_admin_password: "${ADMIN_PASS:-}"
# The local username running this script — consumed by installer host_vars
installer_user: "${INSTALLER_USER:-${USER}}"
aap_inventory_template: "${AAP_INVENTORY_TEMPLATE:-}"
aap_inventory_growth_template: "${AAP_INVENTORY_GROWTH_TEMPLATE:-}"
aap_pg_database: "${AAP_PG_DATABASE:-}"
sat_ip: "${SAT_IP:-}"
sat_netmask: "${SAT_NETMASK:-}"
sat_gw: "${SAT_GW:-}"
sat_hostname: "${SAT_HOSTNAME:-}"
sat_alias: "${SAT_ALIAS:-}"
sat_domain: "${SAT_DOMAIN:-}"
sat_realm: "${SAT_REALM:-}"
sat_org: "${SAT_ORG:-}"
sat_loc: "${SAT_LOC:-}"
aap_hostname: "${AAP_HOSTNAME:-}"
aap_alias: "${AAP_ALIAS:-}"
aap_domain: "${AAP_DOMAIN:-}"
aap_netmask: "${AAP_NETMASK:-}"
aap_gw: "${AAP_GW:-}"
idm_hostname: "${IDM_HOSTNAME:-}"
idm_alias: "${IDM_ALIAS:-}"
idm_domain: "${IDM_DOMAIN:-}"
idm_realm: "${IDM_REALM:-}"
idm_admin_pass: "${IDM_ADMIN_PASS:-}"
idm_ds_pass: "${IDM_DS_PASS:-}"
idm_netmask: "${IDM_NETMASK:-}"
idm_gw: "${IDM_GW:-}"

# Canonical network mapping (new format). Flat keys are retained above for compatibility.
networks:
    satellite:
        ip: "${SAT_IP:-}"
        mask: "${SAT_NETMASK:-}"
        gateway: "${SAT_GW:-}"
    aap:
        ip: "${AAP_IP:-}"
        mask: "${AAP_NETMASK:-}"
        gateway: "${AAP_GW:-}"
    idm:
        ip: "${IDM_IP:-}"
        mask: "${IDM_NETMASK:-}"
        gateway: "${IDM_GW:-}"

host_int_ip: "${HOST_INT_IP:-}"
aap_bundle_url: "${AAP_BUNDLE_URL:-}"
rh_iso_url: "${RH_ISO_URL:-}"
rh9_iso_url: "${RH9_ISO_URL:-}"
RHIS_ENV_EOF
    chmod 600 "$tmp_env"

    ansible-vault encrypt --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" "$tmp_env" >/dev/null 2>&1 || {
        print_warning "Failed to encrypt $tmp_env with ansible-vault."
        rm -f "$tmp_env"
        return 1
    }

    mv "$tmp_env" "$ANSIBLE_ENV_FILE"
    print_success "Credentials saved and encrypted in $ANSIBLE_ENV_FILE"
}

prompt_all_env_options_once() {
    local env_changed=0
    local global_missing sat_missing aap_missing idm_missing
    local has_env_file=0
    local realm_default
    [ -f "$ANSIBLE_ENV_FILE" ] && has_env_file=1

    if [ "$has_env_file" -eq 1 ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1

        if is_noninteractive; then
            return 0
        fi

        global_missing="$(count_missing_vars ADMIN_USER ADMIN_PASS DOMAIN REALM INTERNAL_NETWORK NETMASK INTERNAL_GW RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL RH9_ISO_URL HOST_INT_IP)"
        echo ""
        echo "=== Global (remaining missing: ${global_missing}/15) ==="
        if [ -z "${ADMIN_USER:-}" ]; then
            prompt_with_default ADMIN_USER "Shared Admin Username" "${ADMIN_USER:-admin}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${ADMIN_PASS:-}" ]; then
            prompt_with_default ADMIN_PASS "Shared Admin Password" "${ADMIN_PASS:-}" 1 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var DOMAIN; then
            prompt_with_default DOMAIN "Shared Domain" "${DOMAIN:-}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${REALM:-}" ] || is_unresolved_template_value "${REALM:-}"; then
            realm_default="$(to_upper "${DOMAIN}")"
            prompt_with_default REALM "Shared Kerberos Realm" "${REALM:-$realm_default}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${INTERNAL_NETWORK:-}" ]; then
            prompt_with_default INTERNAL_NETWORK "Shared Internal Network" "${INTERNAL_NETWORK:-10.168.0.0}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${NETMASK:-}" ]; then
            prompt_with_default NETMASK "Shared Internal Netmask" "${NETMASK:-255.255.0.0}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${INTERNAL_GW:-}" ]; then
            prompt_with_default INTERNAL_GW "Shared Internal Gateway" "${INTERNAL_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK:-10.168.0.0}")}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_USER:-}" ]; then
            prompt_with_default RH_USER "Red Hat CDN Username" "${RH_USER:-}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_PASS:-}" ]; then
            prompt_with_default RH_PASS "Red Hat CDN Password" "${RH_PASS:-}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_OFFLINE_TOKEN:-}" ]; then
            prompt_with_default RH_OFFLINE_TOKEN "Red Hat Offline Token" "${RH_OFFLINE_TOKEN:-}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_ACCESS_TOKEN:-}" ]; then
            prompt_with_default RH_ACCESS_TOKEN "Red Hat Access Token" "${RH_ACCESS_TOKEN:-}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${HUB_TOKEN:-}" ]; then
            prompt_with_default HUB_TOKEN "Automation Hub token" "${HUB_TOKEN:-}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_ISO_URL:-}" ]; then
            prompt_with_default RH_ISO_URL "RHEL 10 ISO URL (AAP/IdM)" "${RH_ISO_URL:-}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH9_ISO_URL:-}" ]; then
            prompt_with_default RH9_ISO_URL "RHEL 9 ISO URL (Satellite)" "${RH9_ISO_URL:-}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${HOST_INT_IP:-}" ]; then
            prompt_with_default HOST_INT_IP "Host bridge IP for guest HTTP callbacks" "${HOST_INT_IP:-192.168.122.1}" 0 1 || return 1
            env_changed=1
        fi

        sat_missing="$(count_missing_vars SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY)"
        echo ""
        echo "=== Satellite (remaining missing: ${sat_missing}/10) ==="
        if [ -z "${SAT_IP:-}" ]; then
            prompt_with_default SAT_IP "Satellite Internal IP (eth1)" "${SAT_IP:-10.168.128.1}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${SAT_NETMASK:-}" ]; then
            prompt_with_default SAT_NETMASK "Satellite Internal Netmask" "${SAT_NETMASK:-$NETMASK}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${SAT_GW:-}" ]; then
            prompt_with_default SAT_GW "Satellite Internal Gateway" "${SAT_GW:-$INTERNAL_GW}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var SAT_HOSTNAME; then
            prompt_with_default SAT_HOSTNAME "Satellite Hostname (FQDN)" "${SAT_HOSTNAME:-satellite-618.${DOMAIN}}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${SAT_ALIAS:-}" ]; then
            prompt_with_default SAT_ALIAS "Satellite Alias" "${SAT_ALIAS:-satellite}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var SAT_DOMAIN; then
            prompt_with_default SAT_DOMAIN "Satellite Domain" "${SAT_DOMAIN:-$DOMAIN}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${SAT_ORG:-}" ]; then
            prompt_with_default SAT_ORG "Satellite Organization" "${SAT_ORG:-REDHAT}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${SAT_LOC:-}" ]; then
            prompt_with_default SAT_LOC "Satellite Location" "${SAT_LOC:-CORE}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${CDN_ORGANIZATION_ID:-}" ]; then
            prompt_with_default CDN_ORGANIZATION_ID "Satellite RHSM Organization ID (console.redhat.com/insights/connector/activation-keys#tags=)" "${CDN_ORGANIZATION_ID:-}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
            prompt_with_default CDN_SAT_ACTIVATION_KEY "Satellite Activation Key name" "${CDN_SAT_ACTIVATION_KEY:-}" 0 1 || return 1
            env_changed=1
        fi
        SAT_ADMIN_PASS="${ADMIN_PASS}"

        aap_missing="$(count_missing_vars AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS AAP_BUNDLE_URL AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE)"
        echo ""
        echo "=== AAP (remaining missing: ${aap_missing}/8) ==="
        if [ -z "${AAP_IP:-}" ]; then
            prompt_with_default AAP_IP "AAP Internal IP (eth1)" "${AAP_IP:-10.168.128.2}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${AAP_NETMASK:-}" ]; then
            prompt_with_default AAP_NETMASK "AAP Internal Netmask" "${AAP_NETMASK:-$NETMASK}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${AAP_GW:-}" ]; then
            prompt_with_default AAP_GW "AAP Internal Gateway" "${AAP_GW:-$INTERNAL_GW}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var AAP_HOSTNAME; then
            prompt_with_default AAP_HOSTNAME "AAP Hostname (FQDN)" "${AAP_HOSTNAME:-aap-26.${DOMAIN}}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${AAP_ALIAS:-}" ]; then
            prompt_with_default AAP_ALIAS "AAP Alias" "${AAP_ALIAS:-aap}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${AAP_BUNDLE_URL:-}" ]; then
            prompt_with_default AAP_BUNDLE_URL "AAP bundle URL" "${AAP_BUNDLE_URL:-}" 0 1 || return 1
            env_changed=1
        fi
        AAP_ADMIN_PASS="${ADMIN_PASS}"
        if [ -z "${AAP_INVENTORY_TEMPLATE:-}" ] || [ -z "${AAP_INVENTORY_GROWTH_TEMPLATE:-}" ]; then
            select_aap_inventory_templates || return 1
            env_changed=1
        fi
        if aap_inventory_requires_pg_database && [ -z "${AAP_PG_DATABASE:-}" ]; then
            prompt_with_default AAP_PG_DATABASE "AAP PostgreSQL database name (pg_database)" "${AAP_PG_DATABASE:-awx}" 0 1 || return 1
            env_changed=1
        fi

        idm_missing="$(count_missing_vars IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS)"
        echo ""
        echo "=== IdM (remaining missing: ${idm_missing}/6) ==="
        if [ -z "${IDM_IP:-}" ]; then
            prompt_with_default IDM_IP "IdM Internal IP (eth1)" "${IDM_IP:-10.168.128.3}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${IDM_NETMASK:-}" ]; then
            prompt_with_default IDM_NETMASK "IdM Internal Netmask" "${IDM_NETMASK:-$NETMASK}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${IDM_GW:-}" ]; then
            prompt_with_default IDM_GW "IdM Internal Gateway" "${IDM_GW:-$INTERNAL_GW}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var IDM_HOSTNAME; then
            prompt_with_default IDM_HOSTNAME "IdM Hostname (FQDN)" "${IDM_HOSTNAME:-idm.${DOMAIN}}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${IDM_ALIAS:-}" ]; then
            prompt_with_default IDM_ALIAS "IdM Alias" "${IDM_ALIAS:-idm}" 0 1 || return 1
            env_changed=1
        fi
        IDM_ADMIN_PASS="${ADMIN_PASS}"
        if [ -z "${IDM_DS_PASS:-}" ]; then
            prompt_with_default IDM_DS_PASS "IdM Directory Service Password" "${IDM_DS_PASS:-}" 1 1 || return 1
            env_changed=1
        fi

        if [ "$env_changed" = "1" ]; then
            normalize_shared_env_vars
            write_ansible_env_file || return 1
            print_success "Missing environment values were captured and saved to $ANSIBLE_ENV_FILE"
        fi

        return 0
    fi

    if is_noninteractive && [ "$has_env_file" -eq 0 ]; then
        print_warning "No encrypted env file found at $ANSIBLE_ENV_FILE."
        print_warning "Run once interactively to bootstrap values, or create the file manually."
        return 0
    fi

    if is_noninteractive && [ "$has_env_file" -eq 1 ] && [ "${FORCE_PROMPT_ALL:-0}" = "1" ]; then
        print_warning "--reconfigure ignored in NONINTERACTIVE mode."
        return 0
    fi

    if [ "$has_env_file" -eq 1 ] && [ "${FORCE_PROMPT_ALL:-0}" = "1" ]; then
        print_step "Reconfigure mode: prompting for all values (press Enter to keep current defaults)"
        # In reconfigure mode, sensitive values should be re-entered explicitly.
        RH_USER=""
        RH_PASS=""
        RH_OFFLINE_TOKEN=""
        RH_ACCESS_TOKEN=""
        HUB_TOKEN=""
        RH_ISO_URL=""
        RH9_ISO_URL=""
        AAP_BUNDLE_URL=""
    fi

    print_step "First run detected: collecting environment values and storing them in ansible-vault"
    echo "(Press Enter to accept the shown default where applicable.)"

    global_missing="$(count_missing_vars ADMIN_USER ADMIN_PASS DOMAIN REALM INTERNAL_NETWORK NETMASK INTERNAL_GW RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL RH9_ISO_URL HOST_INT_IP)"
    echo ""
    echo "=== Global (remaining missing: ${global_missing}/15) ==="
    prompt_with_default ADMIN_USER "Shared Admin Username" "${ADMIN_USER:-admin}" 0 1 || return 1
    prompt_with_default ADMIN_PASS "Shared Admin Password" "${ADMIN_PASS:-}" 1 1 || return 1
    prompt_with_default DOMAIN "Shared Domain" "${DOMAIN:-}" 0 1 || return 1
    realm_default="$(to_upper "${DOMAIN}")"
    prompt_with_default REALM "Shared Kerberos Realm" "${REALM:-$realm_default}" 0 1 || return 1
    prompt_with_default INTERNAL_NETWORK "Shared Internal Network" "${INTERNAL_NETWORK:-10.168.0.0}" 0 1 || return 1
    prompt_with_default NETMASK "Shared Internal Netmask" "${NETMASK:-255.255.0.0}" 0 1 || return 1
    prompt_with_default INTERNAL_GW "Shared Internal Gateway" "${INTERNAL_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK:-10.168.0.0}")}" 0 1 || return 1

    prompt_with_default RH_USER "Red Hat CDN Username" "${RH_USER:-}" 0 1 || return 1
    prompt_with_default RH_PASS "Red Hat CDN Password" "${RH_PASS:-}" 1 1 || return 1
    prompt_with_default RH_OFFLINE_TOKEN "Red Hat Offline Token" "${RH_OFFLINE_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ACCESS_TOKEN "Red Hat Access Token" "${RH_ACCESS_TOKEN:-}" 1 1 || return 1
    prompt_with_default HUB_TOKEN "Automation Hub token" "${HUB_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ISO_URL "RHEL 10 ISO URL (AAP/IdM)" "${RH_ISO_URL:-}" 0 1 || return 1
    prompt_with_default RH9_ISO_URL "RHEL 9 ISO URL (Satellite)" "${RH9_ISO_URL:-}" 0 1 || return 1
    prompt_with_default HOST_INT_IP "Host bridge IP for guest HTTP callbacks" "${HOST_INT_IP:-192.168.122.1}" 0 1 || return 1

    sat_missing="$(count_missing_vars SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY)"
    echo ""
    echo "=== Satellite (remaining missing: ${sat_missing}/10) ==="
    prompt_with_default SAT_IP "Satellite Internal IP (eth1)" "${SAT_IP:-10.168.128.1}" 0 1 || return 1
    prompt_with_default SAT_NETMASK "Satellite Internal Netmask" "${SAT_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default SAT_GW "Satellite Internal Gateway" "${SAT_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default SAT_HOSTNAME "Satellite Hostname (FQDN)" "${SAT_HOSTNAME:-satellite-618.${DOMAIN}}" 0 1 || return 1
    prompt_with_default SAT_ALIAS "Satellite Alias" "${SAT_ALIAS:-satellite}" 0 1 || return 1
    prompt_with_default SAT_DOMAIN "Satellite Domain" "${SAT_DOMAIN:-$DOMAIN}" 0 1 || return 1
    prompt_with_default SAT_ORG "Satellite Organization" "${SAT_ORG:-REDHAT}" 0 1 || return 1
    prompt_with_default SAT_LOC "Satellite Location" "${SAT_LOC:-CORE}" 0 1 || return 1
    prompt_with_default CDN_ORGANIZATION_ID "Satellite RHSM Organization ID (console.redhat.com/insights/connector/activation-keys#tags=)" "${CDN_ORGANIZATION_ID:-}" 0 1 || return 1
    prompt_with_default CDN_SAT_ACTIVATION_KEY "Satellite Activation Key name" "${CDN_SAT_ACTIVATION_KEY:-}" 0 1 || return 1
    SAT_ADMIN_PASS="${ADMIN_PASS}"

    aap_missing="$(count_missing_vars AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS AAP_BUNDLE_URL AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE)"
    echo ""
    echo "=== AAP (remaining missing: ${aap_missing}/8) ==="
    prompt_with_default AAP_IP "AAP Internal IP (eth1)" "${AAP_IP:-10.168.128.2}" 0 1 || return 1
    prompt_with_default AAP_NETMASK "AAP Internal Netmask" "${AAP_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default AAP_GW "AAP Internal Gateway" "${AAP_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default AAP_HOSTNAME "AAP Hostname (FQDN)" "${AAP_HOSTNAME:-aap-26.${DOMAIN}}" 0 1 || return 1
    prompt_with_default AAP_ALIAS "AAP Alias" "${AAP_ALIAS:-aap}" 0 1 || return 1
    prompt_with_default AAP_BUNDLE_URL "AAP bundle URL" "${AAP_BUNDLE_URL:-}" 0 1 || return 1
    AAP_ADMIN_PASS="${ADMIN_PASS}"
    select_aap_inventory_templates || return 1
    ensure_aap_pg_database_if_needed || return 1

    idm_missing="$(count_missing_vars IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS)"
    echo ""
    echo "=== IdM (remaining missing: ${idm_missing}/6) ==="
    prompt_with_default IDM_IP "IdM Internal IP (eth1)" "${IDM_IP:-10.168.128.3}" 0 1 || return 1
    prompt_with_default IDM_NETMASK "IdM Internal Netmask" "${IDM_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default IDM_GW "IdM Internal Gateway" "${IDM_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default IDM_HOSTNAME "IdM Hostname (FQDN)" "${IDM_HOSTNAME:-idm.${DOMAIN}}" 0 1 || return 1
    prompt_with_default IDM_ALIAS "IdM Alias" "${IDM_ALIAS:-idm}" 0 1 || return 1
    IDM_ADMIN_PASS="${ADMIN_PASS}"
            prompt_with_default IDM_DS_PASS "IdM Directory Service Password" "${IDM_DS_PASS:-}" 1 1 || return 1

    normalize_shared_env_vars
    write_ansible_env_file || return 1
    print_success "Bootstrap complete. Future runs will reuse encrypted values from $ANSIBLE_ENV_FILE"
}

# Centralized prompt entrypoint used by provisioning flows.
# Ensures first-run bootstrap and missing-value prompting both execute.
prompt_use_existing_env() {
    if [ "${RHIS_PROMPTS_COMPLETED:-0}" = "1" ]; then
        if [ -f "$ANSIBLE_ENV_FILE" ]; then
            load_ansible_env_file || return 1
        fi
        return 0
    fi

    prompt_all_env_options_once || return 1
    RHIS_PROMPTS_COMPLETED=1
    FORCE_PROMPT_ALL=0

    if [ -f "$ANSIBLE_ENV_FILE" ]; then
        load_ansible_env_file || return 1
        print_step "Loaded existing encrypted credentials from $ANSIBLE_ENV_FILE"
    fi

    return 0
}

retire_preseed_env_file() {
    local default_preseed="${SCRIPT_DIR}/.env"
    if [ "$PRESEED_ENV_FILE" = "$default_preseed" ] && [ -f "$default_preseed" ] && [ -f "$ANSIBLE_ENV_FILE" ]; then
        rm -f "$default_preseed"
        print_success "Retired legacy preseed file: $default_preseed"
    fi
}

get_rh_access_token_from_offline_token() {
	local offline_token="$1"
	[ -n "$offline_token" ] || return 1
	[ -n "${RH_TOKEN_URL:-}" ] || return 1
	ensure_jq || return 1

	RH_ACCESS_TOKEN="$(
	  curl -fsSL "${RH_TOKEN_URL}" \
	    -d grant_type=refresh_token \
	    -d client_id=rhsm-api \
	    -d "refresh_token=${offline_token}" \
	  | jq -r '.access_token // empty'
	)"

	[ -n "${RH_ACCESS_TOKEN:-}" ]
}

prompt_for_rh_iso_auth() {
    if [ -n "${RH_ISO_URL:-}" ]; then
        if [ -z "${RH_ACCESS_TOKEN:-}" ] && [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
            get_rh_access_token_from_offline_token "$RH_OFFLINE_TOKEN" || {
                print_warning "Failed to get access token from preseeded offline token."
                return 1
            }
        fi
        return 0
    fi

    if is_noninteractive; then
        if [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
            get_rh_access_token_from_offline_token "$RH_OFFLINE_TOKEN" || {
                print_warning "Failed to get access token from preseeded offline token."
                return 1
            }
        fi

        print_warning "NONINTERACTIVE mode requires RH_ISO_URL to be set."
        return 1
    fi

	echo ""
	echo "RHEL ISO authentication method:"
	echo "1) Manual portal login + paste direct ISO URL"
	echo "2) Use Red Hat offline token (recommended for automation)"
    RH_AUTH_CHOICE="${RH_AUTH_CHOICE:-}"
    if [ -n "$RH_AUTH_CHOICE" ]; then
        rh_auth_choice="$RH_AUTH_CHOICE"
        print_step "Using preseeded ISO auth choice: $rh_auth_choice"
    else
        read -r -p "Select [1-2] (default 1): " rh_auth_choice
    fi

	case "${rh_auth_choice:-1}" in
		2)
            if [ -z "${RH_OFFLINE_TOKEN:-}" ]; then
				read -r -s -p "Enter Red Hat offline token: " RH_OFFLINE_TOKEN; echo ""
			fi

			if get_rh_access_token_from_offline_token "$RH_OFFLINE_TOKEN"; then
				print_success "Red Hat access token acquired."
				write_ansible_env_file
			else
				print_warning "Failed to get access token from offline token."
				return 1
			fi

            [ -n "${RH_ISO_URL:-}" ] || read -r -p "Paste direct RHEL 10 Everything ISO URL: " RH_ISO_URL
			;;
		*)
            print_step "Open: https://access.redhat.com/downloads/content/rhel"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "https://access.redhat.com/downloads/content/rhel" >/dev/null 2>&1 || true
            fi
                [ -n "${RH_ISO_URL:-}" ] || read -r -p "Paste direct RHEL 10 Everything ISO URL: " RH_ISO_URL
			;;
	esac

	[ -n "${RH_ISO_URL:-}" ]
}

prompt_for_satellite_rhel9_iso_auth() {
    if [ -n "${RH9_ISO_URL:-}" ]; then
        if [ -z "${RH_ACCESS_TOKEN:-}" ] && [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
            get_rh_access_token_from_offline_token "$RH_OFFLINE_TOKEN" || {
                print_warning "Failed to get access token from preseeded offline token."
                return 1
            }
        fi
        return 0
    fi

    if is_noninteractive; then
        if [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
            get_rh_access_token_from_offline_token "$RH_OFFLINE_TOKEN" || {
                print_warning "Failed to get access token from preseeded offline token."
                return 1
            }
        fi

        print_warning "NONINTERACTIVE mode requires RH9_ISO_URL to be set."
        return 1
    fi

    print_step "Satellite 6.18 requires RHEL 9 install media."
    [ -n "${RH9_ISO_URL:-}" ] || read -r -p "Paste direct RHEL 9 Everything ISO URL (Satellite): " RH9_ISO_URL
    [ -n "${RH9_ISO_URL:-}" ]
}

download_rhel10_iso() {
	print_step "Preparing RHEL 10 Everything ISO download"
	ensure_iso_vars

	# check if file exists and is NOT HTML (valid ISO)
	if [ -f "$ISO_PATH" ]; then
		if file "$ISO_PATH" | grep -q "ISO 9660"; then
			print_success "ISO already exists and is valid: $ISO_PATH"
			return 0
		else
			print_warning "ISO exists but is NOT valid (likely HTML error page). Removing and re-downloading..."
			sudo rm -f "$ISO_PATH"
		fi
	fi

	[ -n "${RH_ISO_URL:-}" ] || prompt_for_rh_iso_auth || {
		print_warning "ISO URL/auth not provided. Skipping ISO download."
		return 1
	}

	[ -n "${RH_ISO_URL:-}" ] || {
		print_warning "RH_ISO_URL is empty. Skipping ISO download."
		return 1
	}

	print_step "Downloading ISO to: $ISO_PATH"
	if [ -n "${RH_ACCESS_TOKEN:-}" ]; then
		sudo curl -fL --retry 5 --retry-delay 5 \
			-H "Authorization: Bearer ${RH_ACCESS_TOKEN}" \
			-o "$ISO_PATH" "$RH_ISO_URL"
	else
		sudo curl -fL --retry 5 --retry-delay 5 -o "$ISO_PATH" "$RH_ISO_URL"
	fi

	# verify download is valid ISO
	if file "$ISO_PATH" | grep -q "ISO 9660"; then
		sudo chmod 644 "$ISO_PATH"
		print_success "RHEL 10 ISO downloaded and validated: $ISO_PATH"
	else
		print_warning "Downloaded file is not a valid ISO (may be HTML error). Removing."
		sudo rm -f "$ISO_PATH"
		return 1
	fi
}

download_rhel9_iso() {
    print_step "Preparing RHEL 9 Everything ISO download for Satellite"
    ensure_iso_vars

    if [ -f "$SAT_ISO_PATH" ]; then
        if file "$SAT_ISO_PATH" | grep -q "ISO 9660"; then
            print_success "Satellite ISO already exists and is valid: $SAT_ISO_PATH"
            return 0
        else
            print_warning "Satellite ISO exists but is NOT valid (likely HTML error page). Removing and re-downloading..."
            sudo rm -f "$SAT_ISO_PATH"
        fi
    fi

    [ -n "${RH9_ISO_URL:-}" ] || prompt_for_satellite_rhel9_iso_auth || {
        print_warning "RHEL 9 ISO URL/auth not provided. Skipping Satellite ISO download."
        return 1
    }

    [ -n "${RH9_ISO_URL:-}" ] || {
        print_warning "RH9_ISO_URL is empty. Skipping Satellite ISO download."
        return 1
    }

    print_step "Downloading Satellite RHEL 9 ISO to: $SAT_ISO_PATH"
    if [ -n "${RH_ACCESS_TOKEN:-}" ]; then
        sudo curl -fL --retry 5 --retry-delay 5 \
            -H "Authorization: Bearer ${RH_ACCESS_TOKEN}" \
            -o "$SAT_ISO_PATH" "$RH9_ISO_URL"
    else
        sudo curl -fL --retry 5 --retry-delay 5 -o "$SAT_ISO_PATH" "$RH9_ISO_URL"
    fi

    if file "$SAT_ISO_PATH" | grep -q "ISO 9660"; then
        sudo chmod 644 "$SAT_ISO_PATH"
        print_success "RHEL 9 Satellite ISO downloaded and validated: $SAT_ISO_PATH"
    else
        print_warning "Downloaded Satellite file is not a valid ISO (may be HTML error). Removing."
        sudo rm -f "$SAT_ISO_PATH"
        return 1
    fi
}

assert_kickstart_install_iso_is_valid() {
    local role_label="${1:-system}"
    local iso_path="${2:-}"
    local iso_base=""

    if [ -z "${iso_path}" ]; then
        print_warning "${role_label} install media path is empty."
        return 1
    fi

    iso_base="$(basename "${iso_path}" | tr '[:upper:]' '[:lower:]')"

    # Kickstart installs packages from media during Anaconda.
    # Boot ISOs do not contain full package payload and will fail with
    # 'Error setting up software source / selection'.
    if [[ "${iso_base}" == *"boot.iso" ]]; then
        print_warning "${role_label} kickstart requires a full install ISO (DVD/Everything), not a boot ISO."
        print_warning "Current media looks like boot ISO: ${iso_path}"
        print_warning "Please set a full DVD/Everything ISO URL/path and re-run."
        return 1
    fi

    return 0
}

assert_satellite_install_iso_is_valid() {
    assert_kickstart_install_iso_is_valid "Satellite 6.18 (RHEL 9)" "${1:-${SAT_ISO_PATH:-}}"
}

assert_aap_install_iso_is_valid() {
    assert_kickstart_install_iso_is_valid "AAP 2.6 (RHEL 10)" "${1:-${ISO_PATH:-}}"
}

assert_idm_install_iso_is_valid() {
    assert_kickstart_install_iso_is_valid "IdM (RHEL 10)" "${1:-${ISO_PATH:-}}"
}

# Ensure SSH key pair exists for AAP VM post-boot callback orchestration.
ensure_ssh_keys() {
    # Ensure installer host user keypair exists (used by mesh/bootstrap logic).
    if [ ! -f "${HOME}/.ssh/id_rsa" ] || [ ! -f "${HOME}/.ssh/id_rsa.pub" ]; then
        print_step "Generating installer host SSH key pair: ${HOME}/.ssh/id_rsa"
        mkdir -p "${HOME}/.ssh" || return 1
        chmod 700 "${HOME}/.ssh" || true
        ssh-keygen -q -t rsa -b 4096 -N "" -f "${HOME}/.ssh/id_rsa" -C "rhis-installer-host" || return 1
        chmod 600 "${HOME}/.ssh/id_rsa" || true
        chmod 644 "${HOME}/.ssh/id_rsa.pub" || true
    fi

    # Best-effort root keypair on install host as well.
    if command -v sudo >/dev/null 2>&1; then
        sudo bash -lc 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa; fi; chmod 600 /root/.ssh/id_rsa 2>/dev/null || true; chmod 644 /root/.ssh/id_rsa.pub 2>/dev/null || true' >/dev/null 2>&1 || true
    fi

    if [ -f "${AAP_SSH_PRIVATE_KEY}" ] && [ -f "${AAP_SSH_PUBLIC_KEY}" ]; then
        print_success "SSH keys already exist: ${AAP_SSH_KEY_DIR}"
        return 0
    fi

    print_step "Generating SSH key pair for AAP post-boot orchestration..."
    mkdir -p "${AAP_SSH_KEY_DIR}" || return 1
    chmod 700 "${AAP_SSH_KEY_DIR}"

    ssh-keygen -t rsa -b 4096 -f "${AAP_SSH_PRIVATE_KEY}" -N "" -C "rhis-aap-setup" || return 1
    chmod 600 "${AAP_SSH_PRIVATE_KEY}"
    chmod 644 "${AAP_SSH_PUBLIC_KEY}"
    print_success "SSH keys generated: ${AAP_SSH_KEY_DIR}"
}

# Collect public SSH keys that should be trusted by freshly installed guests.
# Sources (best-effort):
#   1. The installing machine user's existing SSH public keys
#   2. The RHIS AAP orchestration key generated by ensure_ssh_keys()
#   3. The RHIS provisioner container root public key, if available
collect_bootstrap_public_keys() {
    local key_file
    local container_pub=""

    ensure_rhis_installer_ssh_key >/dev/null 2>&1 || true

    {
        for key_file in \
            "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" \
            "${HOME}/.ssh/id_ed25519.pub" \
            "${HOME}/.ssh/id_rsa.pub" \
            "${AAP_SSH_PUBLIC_KEY}"; do
            [ -r "${key_file}" ] && cat "${key_file}"
        done

        if command -v podman >/dev/null 2>&1 \
            && podman container exists "${RHIS_CONTAINER_NAME}" >/dev/null 2>&1; then
            container_pub="$(podman exec "${RHIS_CONTAINER_NAME}" sh -lc 'cat /root/.ssh/id_ed25519.pub 2>/dev/null || cat /root/.ssh/id_rsa.pub 2>/dev/null || true' 2>/dev/null || true)"
            [ -n "${container_pub}" ] && printf '%s\n' "${container_pub}"
        fi
    } | awk 'NF && !seen[$0]++'
}

# Download the AAP containerized bundle tarball to AAP_BUNDLE_DIR so it can be
# served over HTTP to the VM during kickstart %post.  The bundle is NOT embedded
# in the OEMDRV ISO — it is too large (5–10 GB) and would break ISO creation.
preflight_download_aap_bundle() {
    local bundle_dest="${AAP_BUNDLE_DIR}/aap-bundle.tar.gz"

    print_step "AAP bundle host path: ${bundle_dest}"

    if [ -f "${bundle_dest}" ]; then
        print_success "AAP bundle already staged: ${bundle_dest}"
        return 0
    fi

    if [ -z "${AAP_BUNDLE_URL:-}" ]; then
        print_warning "AAP_BUNDLE_URL is not set — skipping AAP bundle preflight download."
        print_warning "To enable: set AAP_BUNDLE_URL in .env to the bundle .tar.gz download URL"
        print_warning "from https://access.redhat.com/downloads (search 'Ansible Automation Platform')."
        return 1
    fi

    # Exchange offline token for access token if not already available
    if [ -z "${RH_ACCESS_TOKEN:-}" ] && [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
        get_rh_access_token_from_offline_token "${RH_OFFLINE_TOKEN}" || {
            print_warning "Failed to get RH access token; bundle download will attempt without auth."
        }
    fi

    ensure_iso_vars || return 1
    if ! mkdir -p "${AAP_BUNDLE_DIR}" 2>/dev/null; then
        sudo mkdir -p "${AAP_BUNDLE_DIR}" || return 1
    fi

    print_step "Downloading AAP bundle to ${bundle_dest} (this may take several minutes)..."
    if [ -n "${RH_ACCESS_TOKEN:-}" ]; then
        sudo curl -fL --retry 3 --retry-delay 10 \
            -H "Authorization: Bearer ${RH_ACCESS_TOKEN}" \
            -o "${bundle_dest}" "${AAP_BUNDLE_URL}" || { sudo rm -f "${bundle_dest}"; return 1; }
    else
        sudo curl -fL --retry 3 --retry-delay 10 \
            -o "${bundle_dest}" "${AAP_BUNDLE_URL}" || { sudo rm -f "${bundle_dest}"; return 1; }
    fi

    if ! file "${bundle_dest}" | grep -qE 'gzip|tar|compress'; then
        print_warning "Downloaded file is not a valid tar archive. Removing."
        sudo rm -f "${bundle_dest}"
        return 1
    fi

    print_success "AAP bundle staged at ${bundle_dest}"
}

# Wait for the AAP VM to boot and SSH to be available, checking every 10s up to 10 minutes.
wait_for_vm_ssh() {
    local vm_name="${1:-aap-26}"
    local vm_ip
    local vm_state
    local ssh_wait_timeout="${AAP_SSH_WAIT_TIMEOUT:-5400}"
    local ssh_wait_interval="${AAP_SSH_WAIT_INTERVAL:-10}"
    local ssh_progress_every="${AAP_SSH_PROGRESS_EVERY:-30}"
    local ssh_no_progress_timeout="${AAP_SSH_NO_PROGRESS_TIMEOUT:-900}"
    local ssh_key_auth_failures=0
    local ssh_probe_out=""
    local wait_start=0
    local wait_deadline=0
    local now=0
    local elapsed=0
    local remaining=0
    local percent=0
    local filled=0
    local bar=""
    local last_progress_log=0
    local last_stage_change=0
    local stage=0
    local last_stage=0
    local stage_label="booting"
    local last_vm_state=""
    local last_vm_ip=""
    local ssh_port_reachable=0

    if ! is_enabled "${AAP_SSH_CALLBACK_ENABLED:-0}"; then
        print_step "AAP SSH callback probing is disabled for this workflow; skipping wait_for_vm_ssh."
        return 1
    fi

    case "${ssh_wait_timeout}" in ''|*[!0-9]*) ssh_wait_timeout=5400 ;; esac
    case "${ssh_wait_interval}" in ''|*[!0-9]*) ssh_wait_interval=10 ;; esac
    case "${ssh_progress_every}" in ''|*[!0-9]*) ssh_progress_every=30 ;; esac
    case "${ssh_no_progress_timeout}" in ''|*[!0-9]*) ssh_no_progress_timeout=900 ;; esac
    [ "${ssh_wait_interval}" -le 0 ] && ssh_wait_interval=10
    [ "${ssh_progress_every}" -le 0 ] && ssh_progress_every=30
    [ "${ssh_no_progress_timeout}" -le 0 ] && ssh_no_progress_timeout=900

    wait_start="$(date +%s)"
    wait_deadline=$(( wait_start + ssh_wait_timeout ))
    last_progress_log="${wait_start}"
    last_stage_change="${wait_start}"

    print_step "Waiting for ${vm_name} to boot and SSH to become available..."
    print_step "  (Anaconda install + 3.5 GB bundle download typically takes 30-60 min)"
    print_step "AAP callback monitor enabled: progress every ${ssh_progress_every}s, timeout ${ssh_wait_timeout}s, no-progress fail-fast ${ssh_no_progress_timeout}s."

    while true; do
        now="$(date +%s)"
        elapsed=$(( now - wait_start ))
        remaining=$(( wait_deadline - now ))
        if [ "${remaining}" -le 0 ]; then
            print_warning "${vm_name} SSH did not become available within $((ssh_wait_timeout / 60)) minute(s)."
            return 1
        fi

        stage=0
        vm_state="$(sudo virsh domstate "${vm_name}" 2>/dev/null | tr -d '[:space:]' || true)"
        if [ "${vm_state}" != "${last_vm_state}" ]; then
            print_step "${vm_name} state transition: ${last_vm_state:-unknown} -> ${vm_state:-unknown}"
            last_vm_state="${vm_state}"
            last_stage_change="${now}"
        fi

        if [ "$vm_state" = "shutoff" ] || [ "$vm_state" = "crashed" ] || [ "$vm_state" = "pmsuspended" ]; then
            print_warning "${vm_name} state is ${vm_state}; starting it to continue automated setup"
            sudo virsh start "${vm_name}" >/dev/null 2>&1 || true
            sleep 5
        fi

        if [ "$vm_state" = "running" ]; then
            stage=1
        fi

        # Get the VM's IP from virsh
        vm_ip="$(sudo virsh domifaddr "${vm_name}" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

        if [ -z "${vm_ip}" ]; then
            case "$vm_name" in
                aap-26) vm_ip="${AAP_IP:-}" ;;
                satellite-618) vm_ip="${SAT_IP:-}" ;;
                idm) vm_ip="${IDM_IP:-}" ;;
            esac
        fi

        if [ -n "${vm_ip}" ] && [ "${vm_ip}" != "${last_vm_ip}" ]; then
            print_step "${vm_name} network update: detected IP ${vm_ip}"
            last_vm_ip="${vm_ip}"
            last_stage_change="${now}"
        fi

        if [ -n "${vm_ip}" ]; then
            stage=2

            # If TCP/22 is open, force public-key auth probe to detect bad key setup quickly.
            if timeout 2 bash -lc "cat < /dev/tcp/${vm_ip}/22" >/dev/null 2>&1; then
                stage=3
                if [ "${ssh_port_reachable}" -eq 0 ]; then
                    print_success "${vm_name} is reachable on TCP/22 at ${vm_ip}; starting key-auth validation."
                    ssh_port_reachable=1
                    last_stage_change="${now}"
                fi

                ssh_probe_out="$(timeout 5 ssh \
                    -o BatchMode=yes \
                    -o PreferredAuthentications=publickey \
                    -o PasswordAuthentication=no \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -i "${AAP_SSH_PRIVATE_KEY}" "root@${vm_ip}" "echo 'SSH ready'" 2>&1 || true)"

                if printf '%s' "${ssh_probe_out}" | grep -q "SSH ready"; then
                    print_success "${vm_name} SSH is ready at ${vm_ip}"
                    echo "${vm_ip}"
                    return 0
                fi

                if printf '%s' "${ssh_probe_out}" | grep -Eqi "Permission denied|publickey"; then
                    ssh_key_auth_failures="$((ssh_key_auth_failures + 1))"
                    if [ "${ssh_key_auth_failures}" -ge "${AAP_SSH_KEY_FAIL_FAST_ATTEMPTS:-18}" ]; then
                        print_warning "${vm_name}: SSH port is reachable at ${vm_ip}, but key auth failed ${ssh_key_auth_failures} times."
                        print_warning "Fail-fast triggered: likely SSH key injection/sshd auth mismatch (not a boot wait issue)."
                        print_warning "Check /root/.ssh/authorized_keys, sshd settings, and kickstart %post key injection."
                        return 1
                    fi
                fi
            else
                if [ "${ssh_port_reachable}" -eq 1 ]; then
                    print_warning "${vm_name} TCP/22 is no longer reachable at ${vm_ip}; waiting for recovery."
                    ssh_port_reachable=0
                    last_stage_change="${now}"
                fi
            fi
        fi

        case "${stage}" in
            0) stage_label="booting" ;;
            1) stage_label="running-no-ip" ;;
            2) stage_label="ip-known-no-ssh" ;;
            3) stage_label="ssh-port-open-auth-pending" ;;
            *) stage_label="unknown" ;;
        esac

        if [ "${stage}" -gt "${last_stage}" ]; then
            last_stage="${stage}"
            last_stage_change="${now}"
        fi

        if [ $((now - last_progress_log)) -ge "${ssh_progress_every}" ]; then
            percent=$(( elapsed * 100 / ssh_wait_timeout ))
            [ "${percent}" -gt 100 ] && percent=100
            filled=$(( percent / 5 ))
            printf -v bar '%*s' "${filled}" ''
            bar="${bar// /#}"
            printf -v bar '%-20s' "${bar}"
            print_step "AAP callback wait: [${bar}] ${percent}%% elapsed=${elapsed}s/${ssh_wait_timeout}s remaining~${remaining}s stage=${stage_label}"
            last_progress_log="${now}"
        fi

        if [ $((now - last_stage_change)) -ge "${ssh_no_progress_timeout}" ]; then
            print_warning "${vm_name} callback wait stalled for ${ssh_no_progress_timeout}s (stage=${stage_label})."
            print_warning "Fail-fast triggered for troubleshooting. Check VM console, network, and /var/log/anaconda/ on guest."
            return 1
        fi

        sleep "${ssh_wait_interval}"
    done
}

# Run the AAP 2.6 containerized installer on the VM via SSH callback from the host.
# Captures setup.sh output, validates exit code, and stops the HTTP server upon completion.
run_aap_setup_on_vm() {
    local vm_name="${1:-aap-26}"
    local vm_ip

    if ! is_enabled "${AAP_SSH_CALLBACK_ENABLED:-0}"; then
        print_step "AAP SSH callback is disabled; skipping run_aap_setup_on_vm."
        return 0
    fi

    vm_ip="$(wait_for_vm_ssh "${vm_name}")" || {
        print_warning "Cannot reach ${vm_name} via SSH. Setup not attempted."
        return 1
    }

    print_step "Running AAP containerized installer via SSH on ${vm_name} (${vm_ip})..."
    print_step "  Output will be logged to: ${AAP_SETUP_LOG_LOCAL}"

    # SSH in and run setup.sh, capturing output with timestamp
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting AAP setup on ${vm_ip}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -i "${AAP_SSH_PRIVATE_KEY}" "root@${vm_ip}" \
            'cd /root/aap-setup && bash setup.sh 2>&1' || {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] AAP setup FAILED on ${vm_ip}"
                return 1
            }
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AAP setup completed successfully on ${vm_ip}"
    } | tee -a "${AAP_SETUP_LOG_LOCAL}" || return 1

    print_success "AAP setup completed on ${vm_name}. Full log: ${AAP_SETUP_LOG_LOCAL}"
}

# Poll AAP's /api/v2/ping/ until it returns a valid JSON response (max_wait sec, default 30 min).
wait_for_aap_api() {
    local host="$1" pass="$2" max_wait="${3:-1800}" elapsed=0 interval=30
    print_step "Waiting for AAP API on ${host} (up to $((max_wait / 60)) min)..."
    until curl -sk -u "${ADMIN_USER}:${pass}" "https://${host}/api/v2/ping/" 2>/dev/null | grep -q '"version"'; do
        elapsed=$((elapsed + interval))
        if [ "$elapsed" -ge "$max_wait" ]; then
            print_warning "AAP API on ${host} did not respond within $((max_wait / 60)) minutes."
            return 1
        fi
        printf "."
        sleep "$interval"
    done
    echo ""
    print_success "AAP API is ready on ${host}."
}

# After setup.sh completes, pre-create credentials in AAP via REST API
# using values already stored in ~/.ansible/conf/env.yml.
create_aap_credentials() {
    [ -n "${AAP_HOSTNAME:-}" ] || {
        print_warning "AAP_HOSTNAME not set; skipping credential provisioning."
        return 0
    }
    [ -n "${AAP_ADMIN_PASS:-}" ] || {
        print_warning "AAP_ADMIN_PASS not set; skipping credential provisioning."
        return 0
    }

    wait_for_aap_api "${AAP_HOSTNAME}" "${AAP_ADMIN_PASS}" || return 0

    ensure_jq || {
        print_warning "jq not available; skipping AAP credential provisioning."
        return 0
    }

    local base="https://${AAP_HOSTNAME}/api/v2"
    local auth="${ADMIN_USER}:${AAP_ADMIN_PASS}"
    local http_code

    print_step "Provisioning credentials in AAP from ${ANSIBLE_ENV_FILE}..."

    # ── 1. Machine (SSH) credential — root key for Satellite / IdM job execution ──
    if [ -f "${AAP_SSH_PRIVATE_KEY}" ]; then
        local ssh_key_json
        ssh_key_json="$(jq -Rs . < "${AAP_SSH_PRIVATE_KEY}")"
        http_code="$(curl -sk -u "$auth" -X POST "${base}/credentials/" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"RHIS SSH Machine Credential\",\"credential_type\":1,\"inputs\":{\"username\":\"root\",\"ssh_key_data\":${ssh_key_json}}}" \
            -o /dev/null -w "%{http_code}")"
        case "$http_code" in
            200|201) print_success "Created: RHIS SSH Machine Credential" ;;
            *) print_warning "Machine credential: HTTP ${http_code} (may already exist)" ;;
        esac
    fi

    # ── 2. Container Registry — RH_USER / RH_PASS for registry.redhat.io ──
    if [ -n "${RH_USER:-}" ] && [ -n "${RH_PASS:-}" ]; then
        local reg_type_id
        reg_type_id="$(curl -sk -u "$auth" \
            "${base}/credential_types/?name=Container+Registry" \
            | jq -r '.results[0].id // empty')"
        if [ -n "$reg_type_id" ]; then
            local rh_user_json rh_pass_json
            rh_user_json="$(printf '%s' "${RH_USER}" | jq -Rs .)"
            rh_pass_json="$(printf '%s' "${RH_PASS}" | jq -Rs .)"
            http_code="$(curl -sk -u "$auth" -X POST "${base}/credentials/" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"registry.redhat.io\",\"credential_type\":${reg_type_id},\"inputs\":{\"host\":\"registry.redhat.io\",\"username\":${rh_user_json},\"password\":${rh_pass_json}}}" \
                -o /dev/null -w "%{http_code}")"
            case "$http_code" in
                200|201) print_success "Created: registry.redhat.io Container Registry credential" ;;
                *) print_warning "Container Registry credential: HTTP ${http_code} (may already exist)" ;;
            esac
        else
            print_warning "Container Registry credential type not found in AAP; skipping."
        fi
    fi

    # ── 3. Automation Hub / Galaxy token ──
    if [ -n "${HUB_TOKEN:-}" ]; then
        local hub_type_id
        hub_type_id="$(curl -sk -u "$auth" \
            "${base}/credential_types/?name=Ansible+Galaxy%2FAutomation+Hub+API+Token" \
            | jq -r '.results[0].id // empty')"
        if [ -n "$hub_type_id" ]; then
            local hub_token_json
            hub_token_json="$(printf '%s' "${HUB_TOKEN}" | jq -Rs .)"
            http_code="$(curl -sk -u "$auth" -X POST "${base}/credentials/" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"Automation Hub Token\",\"credential_type\":${hub_type_id},\"inputs\":{\"url\":\"https://console.redhat.com/api/automation-hub/\",\"auth_url\":\"https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token\",\"token\":${hub_token_json}}}" \
                -o /dev/null -w "%{http_code}")"
            case "$http_code" in
                200|201) print_success "Created: Automation Hub Token credential" ;;
                *) print_warning "Automation Hub credential: HTTP ${http_code} (may already exist)" ;;
            esac
        else
            print_warning "Automation Hub credential type not found in AAP; skipping."
        fi
    fi

    print_success "AAP credential provisioning complete → https://${AAP_HOSTNAME}/#/credentials"
}

# Start a temporary Python HTTP server to serve the AAP bundle tarball to the
# VM during kickstart %post.  The server runs until the AAP setup SSH callback
# completes (signaled via a marker file), then stops automatically.
serve_aap_bundle() {
    local bundle_dest="${AAP_BUNDLE_DIR}/aap-bundle.tar.gz"

    print_step "AAP bundle file expected for HTTP serving: ${bundle_dest}"

    if [ ! -f "${bundle_dest}" ]; then
        print_warning "AAP bundle not found at ${bundle_dest}; HTTP server not started."
        print_warning "Run preflight_download_aap_bundle or place aap-bundle.tar.gz in ${AAP_BUNDLE_DIR}."
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        print_warning "python3 not found; cannot start AAP bundle HTTP server."
        return 1
    fi

    print_step "Starting AAP bundle HTTP server on ${HOST_INT_IP}:8080..."

    # If firewalld is running, open port 8080 in the 'libvirt' zone (runtime-only — reverts on reload/reboot).
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        if sudo firewall-cmd --get-zones 2>/dev/null | grep -qw libvirt; then
            if sudo firewall-cmd --zone=libvirt --add-port=8080/tcp >/dev/null 2>&1; then
                AAP_FW_RULE_ADDED=1
                print_step "  Opened 8080/tcp in firewalld 'libvirt' zone (runtime; auto-reverts on reload)."
            else
                print_warning "  Could not open 8080/tcp in firewalld 'libvirt' zone; AAP %post bundle download may fail."
            fi
        else
            print_warning "  firewalld 'libvirt' zone not found; ensure port 8080 is reachable from guests."
        fi
    fi

    (cd "${AAP_BUNDLE_DIR}" && exec python3 -m http.server 8080 --bind "${HOST_INT_IP}") >"${AAP_HTTP_LOG}" 2>&1 &
    AAP_HTTP_PID=$!
    print_success "AAP bundle HTTP server running (PID: ${AAP_HTTP_PID}) — serving ${AAP_BUNDLE_DIR}"
    print_step "AAP HTTP server log: ${AAP_HTTP_LOG}"
    print_step "Server will auto-stop after AAP setup completes or after 2-hour timeout."
}

# Remove the runtime firewalld rule for port 8080 if it was opened by serve_aap_bundle().
close_aap_bundle_firewall() {
    if [ -n "${AAP_FW_RULE_ADDED:-}" ] && systemctl is-active --quiet firewalld 2>/dev/null; then
        sudo firewall-cmd --zone=libvirt --remove-port=8080/tcp >/dev/null 2>&1 || true
        AAP_FW_RULE_ADDED=""
        print_step "Closed firewalld port 8080/tcp in 'libvirt' zone."
    fi
}

# Ensure virtualization tooling is present (virt-install, qemu-img)
ensure_virtualization_tools() {
	if command -v virt-install >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
        :
    else
        print_step "Installing virtualization tooling (virt-install, qemu-img, libvirt client)"
        sudo dnf install -y --nogpgcheck virt-install qemu-img libvirt-client || return 1

        command -v virt-install >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1 || return 1
	fi

    # Resolve a supported os-variant for this host's libosinfo database.
    # Some hosts don't recognize 'rhel10' yet, so we gracefully fall back.
    if virt-install --osinfo list 2>/dev/null | awk '{print $1}' | grep -qx "${RH_OSINFO}"; then
        print_step "Using OS variant: ${RH_OSINFO}"
        return 0
    fi

    if virt-install --osinfo list 2>/dev/null | awk '{print $1}' | grep -qx 'linux2024'; then
        print_warning "OS variant '${RH_OSINFO}' not found; falling back to linux2024"
        RH_OSINFO='linux2024'
        return 0
    fi

    if virt-install --osinfo list 2>/dev/null | awk '{print $1}' | grep -qx 'rhel9.0'; then
        print_warning "OS variant '${RH_OSINFO}' not found; falling back to rhel9.0"
        RH_OSINFO='rhel9.0'
        return 0
    fi

    print_warning "No suitable os-variant found in libosinfo; proceeding without --os-variant"
    RH_OSINFO=''
    return 0
}

get_vm_external_mac() {
    case "$1" in
        satellite-618) printf '%s\n' "${SAT_EXT_MAC:-52:54:00:61:80:01}" ;;
        aap-26)        printf '%s\n' "${AAP_EXT_MAC:-52:54:00:61:80:02}" ;;
        idm)           printf '%s\n' "${IDM_EXT_MAC:-52:54:00:61:80:03}" ;;
        *)             printf '%s\n' "" ;;
    esac
}

get_vm_internal_mac() {
    case "$1" in
        satellite-618) printf '%s\n' "${SAT_INT_MAC:-52:54:00:61:81:01}" ;;
        aap-26)        printf '%s\n' "${AAP_INT_MAC:-52:54:00:61:81:02}" ;;
        idm)           printf '%s\n' "${IDM_INT_MAC:-52:54:00:61:81:03}" ;;
        *)             printf '%s\n' "" ;;
    esac
}

build_internal_kickstart_network_line() {
    local iface_name="$1"
    local iface_mac="$2"
    local ip_addr="$3"
    local netmask="$4"
    local gateway="$5"
    local hostname="$6"

    printf '%%pre\n'
    printf 'HOSTNAME=$(hostname)\n'
    printf 'if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" = "localhost" ]; then\n'
    printf "    HOSTNAME=$(grep -oP 'hostname=\\K\\S+' /proc/cmdline 2>/dev/null || true)\n"
    printf 'fi\n'
    printf 'IP="%s"\n' "$ip_addr"
    printf 'ROLE_HOSTNAME="%s"\n' "$hostname"
    printf 'if [[ "$HOSTNAME" == *"%s"* ]] || [[ "$HOSTNAME" == *"%s"* ]]; then\n' "${SAT_ALIAS}" "${SAT_HOSTNAME%%.*}"
    printf '    IP="%s"\n' "${SAT_IP}"
    printf '    ROLE_HOSTNAME="%s"\n' "${SAT_HOSTNAME}"
    printf 'elif [[ "$HOSTNAME" == *"%s"* ]] || [[ "$HOSTNAME" == *"%s"* ]]; then\n' "${AAP_ALIAS}" "${AAP_HOSTNAME%%.*}"
    printf '    IP="%s"\n' "${AAP_IP}"
    printf '    ROLE_HOSTNAME="%s"\n' "${AAP_HOSTNAME}"
    printf 'elif [[ "$HOSTNAME" == *"%s"* ]] || [[ "$HOSTNAME" == *"%s"* ]]; then\n' "${IDM_ALIAS}" "${IDM_HOSTNAME%%.*}"
    printf '    IP="%s"\n' "${IDM_IP}"
    printf '    ROLE_HOSTNAME="%s"\n' "${IDM_HOSTNAME}"
    printf 'fi\n'
    printf "cat > /tmp/network-eth1 <<EOF_NETWORK_ETH1\n"
    printf 'network --bootproto=static --device=%s --interfacename=%s:%s --ip=$IP --netmask=%s ' "$iface_name" "$iface_name" "$iface_mac" "$netmask"
    if [ -n "$hostname" ]; then
        printf -- '--hostname=$ROLE_HOSTNAME '
    fi
    # eth1 is always the internal management NIC — never install a default route;
    # eth0 (DHCP) remains the sole default route for internet access.
    printf -- '--nodefroute '
    printf -- '--activate --onboot=yes\n'
    printf 'EOF_NETWORK_ETH1\n'
    printf 'if [ -z "$IP" ]; then\n'
    printf '    : > /tmp/network-eth1\n'
    printf 'fi\n'
    printf '%%end\n\n'
}

netmask_to_prefix() {
    local netmask="$1"
    local prefix=0
    local octet
    IFS='.' read -r -a octets <<< "$netmask"
    for octet in "${octets[@]}"; do
        case "$octet" in
            255) prefix=$((prefix + 8)) ;;
            254) prefix=$((prefix + 7)) ;;
            252) prefix=$((prefix + 6)) ;;
            248) prefix=$((prefix + 5)) ;;
            240) prefix=$((prefix + 4)) ;;
            224) prefix=$((prefix + 3)) ;;
            192) prefix=$((prefix + 2)) ;;
            128) prefix=$((prefix + 1)) ;;
            0) ;;
            *) echo "16"; return 0 ;;
        esac
    done
    echo "$prefix"
}

prompt_satellite_618_details() {
    normalize_shared_env_vars
    set_or_prompt RH_USER "Red Hat CDN Username: " || return 1
    set_or_prompt RH_PASS "Red Hat CDN Password: " 1 || return 1
    set_or_prompt ADMIN_USER "Shared Admin Username: " || return 1
    set_or_prompt ADMIN_PASS "Shared Admin Password: " 1 || return 1

    echo -e "\n--- Network (eth1) ---"
    set_or_prompt SAT_IP "Static IP: " || return 1
    set_or_prompt SAT_NETMASK "Subnet Mask: " || return 1
    set_or_prompt SAT_GW "Gateway: " || return 1

    echo -e "--- Satellite Identity ---"
    set_or_prompt SAT_HOSTNAME "Hostname (FQDN): " || return 1
    set_or_prompt SAT_ALIAS "Satellite Alias: " || return 1
    set_or_prompt SAT_DOMAIN "Domain Name: " || return 1
    set_or_prompt SAT_ORG "Organization Name: " || return 1
    set_or_prompt SAT_LOC "Location Name: " || return 1
    set_or_prompt CDN_ORGANIZATION_ID "Satellite RHSM Organization ID (console.redhat.com/insights/connector/activation-keys#tags=): " || return 1
    set_or_prompt CDN_SAT_ACTIVATION_KEY "Satellite Activation Key name: " || return 1
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_satellite_618_kickstart() {
    local ks_file="${KS_DIR}/satellite-618.ks"
    local tmpdir tmp_ks tmp_oem
    local sat_ext_mac sat_int_mac
    local sat_prefix
    local bootstrap_ssh_keys
    local ks_nogpg_policy
    local ks_ssh_baseline
    local ks_user_sudo_bootstrap
    local ks_rhsm_register
    local ks_rhc_connect
    local ks_repo_enable_verify
    local ks_nm_dual_nic
    local ks_hosts_mapping
    local ks_trust_bootstrap_keys

    prompt_satellite_618_details || return 1
    ensure_iso_vars || return 1
    ensure_iso_tools || return 1
    ensure_ssh_keys || return 1

    sat_ext_mac="$(get_vm_external_mac "satellite-618")"
    sat_int_mac="$(get_vm_internal_mac "satellite-618")"
    sat_prefix="$(netmask_to_prefix "${SAT_NETMASK}")"
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"
    ks_nogpg_policy="$(kickstart_nogpg_policy_block)"
    ks_ssh_baseline="$(kickstart_ssh_baseline_block)"
    ks_user_sudo_bootstrap="$(kickstart_user_sudo_bootstrap_block)"
    ks_rhsm_register="$(kickstart_rhsm_register_block 1)"
    ks_rhc_connect="$(kickstart_rhc_connect_block)"
    ks_repo_enable_verify="$(kickstart_repo_enable_verify_block "Satellite" \
        "rhel-9-for-x86_64-baseos-rpms" \
        "rhel-9-for-x86_64-appstream-rpms" \
        "satellite-6.18-for-rhel-9-x86_64-rpms" \
        "satellite-maintenance-6.18-for-rhel-9-x86_64-rpms")"
    ks_nm_dual_nic="$(kickstart_networkmanager_dual_nic_block "${sat_ext_mac}" "${sat_int_mac}" "${SAT_IP}" "${sat_prefix}" "${SAT_GW}")"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_HOSTNAME%%.*}" "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_HOSTNAME%%.*}" "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_HOSTNAME%%.*}")"
    ks_trust_bootstrap_keys="$(kickstart_trust_bootstrap_keys_block 1)"

    tmpdir="$(mktemp -d)"
    tmp_ks="${tmpdir}/satellite-618.ks"
    tmp_oem="${tmpdir}/ks.cfg"

    sudo rm -f "$ks_file" "$OEMDRV_ISO"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --plaintext "${ROOT_PASS}"
user --name="${ADMIN_USER}" --password="${ADMIN_PASS}" --plaintext --groups=wheel

network --bootproto=dhcp --device=eth0 --interfacename=eth0:${sat_ext_mac} --activate --onboot=yes

%include /tmp/network-eth1

HEADER

    build_internal_kickstart_network_line "eth1" "${sat_int_mac}" "${SAT_IP}" "${SAT_NETMASK}" "${SAT_GW}" "${SAT_HOSTNAME}" >> "$tmp_ks"
    echo "" >> "$tmp_ks"

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "Satellite kickstart: DEMO partition layout (/boot 2G + swap 18G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 8 vCPU, 24 GB RAM, 100 GB raw storage
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs"  --size=2048
part swap                   --size=18432
part /     --fstype="xfs"  --grow --size=1

DEMO_PART
    else
        print_step "Satellite kickstart: production/best-practice LVM layout"
        cat >> "$tmp_ks" <<'STD_PART'
# Best Practice Partitioning for Satellite 6.18 (LVM)
# Requirements: 8 vCPU, 32 GB RAM, 75 GB raw storage minimum
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs" --size=2048
part swap  --size=24000
part pv.01 --grow --size=1
volgroup vg_system pv.01
logvol /    --fstype="xfs" --name=lv_root --vgname=vg_system --size=20480
logvol /var --fstype="xfs" --name=lv_var  --vgname=vg_system --size=100000 --grow

STD_PART
    fi

    # --- Packages ---
    cat >> "$tmp_ks" <<'PKGS'
%packages
@Core
bash-completion
ansible-core
man-pages
net-tools
bind-utils
tmux
xfsdump
yum-utils
zip
yum
chrony
qemu-guest-agent
tuned
-ntp
PKGS

    if [[ "${SAT_HOSTNAME}" == *"provisioner"* ]]; then
        cat >> "$tmp_ks" <<'EXTRA_PKGS'
@container-management
EXTRA_PKGS
    fi

    cat >> "$tmp_ks" <<'PKGS_END'
%end

PKGS_END

    # --- Post-install (variable expansion required) ---
    cat >> "$tmp_ks" <<POSTEOF
%post --log=/root/ks-post.log
set -euo pipefail

${ks_nogpg_policy}

echo "Starting Satellite Pre-work..."

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

${ks_rhsm_register}

${ks_rhc_connect}

${ks_repo_enable_verify}

# 4. Satellite package installation
dnf install -y --nogpgcheck satellite
if ! rpm -q satellite >/dev/null 2>&1; then
    echo "ERROR: Satellite package installation verification failed (rpm -q satellite)."
    exit 1
fi

# 5. Satellite Installer
satellite-installer --scenario satellite --foreman-initial-organization "${SAT_ORG}" --foreman-initial-location "${SAT_LOC}" --foreman-initial-admin-username "${ADMIN_USER}" --foreman-initial-admin-password "${ADMIN_PASS}" --foreman-proxy-dns true --foreman-proxy-dns-interface eth1 --foreman-proxy-dhcp true --foreman-proxy-dhcp-interface eth1 --foreman-proxy-tftp true --foreman-proxy-tftp-managed true --enable-foreman-plugin-ansible --enable-foreman-proxy-plugin-ansible --enable-foreman-compute-ec2 --enable-foreman-compute-gce --enable-foreman-compute-azure --enable-foreman-compute-libvirt --enable-foreman-plugin-openscap --enable-foreman-proxy-plugin-openscap --register-with-insights true

# 5.1 RHIS CMDB single-pane dashboard (Satellite + AAP + IdM + RHIS container endpoint)
dnf install -y --nogpgcheck python3-pip sshpass
python3 -m pip install --upgrade pip setuptools wheel || true
python3 -m pip install ansible-cmdb || true

mkdir -p /etc/ansible /var/lib/rhis-cmdb/facts /var/www/rhis-cmdb

cat > /usr/local/bin/rhis-cmdb-refresh.sh <<CMDB_REFRESH
#!/usr/bin/env bash
set -euo pipefail

INV=/etc/ansible/rhis_inventory.ini
FACTS=/var/lib/rhis-cmdb/facts
OUT=/var/www/rhis-cmdb/index.html

cat > "\${INV}" <<INV_EOF
[rhis_linux]
${SAT_HOSTNAME} ansible_host=${SAT_IP}
${AAP_HOSTNAME} ansible_host=${AAP_IP}
${IDM_HOSTNAME} ansible_host=${IDM_IP}

[all:vars]
ansible_user=${ADMIN_USER}
ansible_password=${ADMIN_PASS}
ansible_become=true
ansible_become_password=${ADMIN_PASS}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
INV_EOF

mkdir -p "\${FACTS}"

# Gather facts from RHIS nodes (best effort so dashboard always refreshes)
ansible -i "\${INV}" rhis_linux -m setup --tree "\${FACTS}" || true

# Add synthetic container health node so RHIS container shows in the same pane
container_status="down"
if curl -ksSf --max-time 5 "http://${HOST_INT_IP}:3000/" >/dev/null 2>&1; then
    container_status="up"
fi

cat > "\${FACTS}/rhis-container" <<JSON
{
    "ansible_facts": {
        "nodename": "rhis-container",
        "fqdn": "rhis-container",
        "default_ipv4": {"address": "${HOST_INT_IP}"},
        "rhis_container_endpoint": "http://${HOST_INT_IP}:3000",
        "rhis_container_status": "\${container_status}"
    },
    "changed": false
}
JSON

ansible-cmdb -t html_fancy "\${FACTS}" > "\${OUT}"
CMDB_REFRESH

chmod 0755 /usr/local/bin/rhis-cmdb-refresh.sh

cat > /etc/systemd/system/rhis-cmdb-refresh.service <<'CMDB_REFRESH_SVC'
[Unit]
Description=Refresh RHIS ansible-cmdb dashboard data
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rhis-cmdb-refresh.sh
CMDB_REFRESH_SVC

cat > /etc/systemd/system/rhis-cmdb-refresh.timer <<'CMDB_REFRESH_TIMER'
[Unit]
Description=Periodic RHIS ansible-cmdb refresh timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=rhis-cmdb-refresh.service

[Install]
WantedBy=timers.target
CMDB_REFRESH_TIMER

cat > /etc/systemd/system/rhis-cmdb-http.service <<'CMDB_HTTP_SVC'
[Unit]
Description=RHIS CMDB Dashboard HTTP Server
After=network-online.target rhis-cmdb-refresh.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/var/www/rhis-cmdb
ExecStart=/usr/bin/python3 -m http.server 18080 --bind 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CMDB_HTTP_SVC

systemctl daemon-reload
systemctl enable --now rhis-cmdb-refresh.timer
systemctl start rhis-cmdb-refresh.service || true
systemctl enable --now rhis-cmdb-http.service

firewall-cmd --permanent --add-port=18080/tcp || true
firewall-cmd --reload || true

# 5. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true

echo "Post-install configuration complete."

# 6. Network verification snapshot (for ks-post.log troubleshooting)
echo "===== RHIS NETWORK SNAPSHOT ====="
date
ip -4 addr show eth0 || true
ip -4 addr show eth1 || true
ip route show || true
nmcli -f NAME,DEVICE,TYPE,STATE connection show || true
echo "===== END RHIS NETWORK SNAPSHOT ====="
%end
POSTEOF

    cp "$tmp_ks" "$tmp_oem"
    sudo mkdir -p "$KS_DIR"
    sudo install -m 0644 "$tmp_ks" "$ks_file"

    print_step "Packaging Satellite kickstart into OEMDRV ISO"
    if command -v genisoimage >/dev/null 2>&1; then
        sudo genisoimage -output "$OEMDRV_ISO" -volid "OEMDRV" -rational-rock -joliet -full-iso9660-filenames "$tmp_oem" >/dev/null 2>&1
    else
        sudo xorriso -as mkisofs -o "$OEMDRV_ISO" -V OEMDRV -r -J "$tmp_oem" >/dev/null 2>&1
    fi

    sudo chmod 0644 "$OEMDRV_ISO"
    sudo chown qemu:qemu "$OEMDRV_ISO" 2>/dev/null || true
    rm -rf "$tmpdir"

    print_success "Generated Satellite kickstart: $ks_file"
    print_success "Created OEMDRV ISO: $OEMDRV_ISO"
}

generate_satellite_oemdrv_only() {
    print_step "Generating Satellite kickstart and OEMDRV ISO only"
    generate_satellite_618_kickstart || return 1
    print_success "Satellite OEMDRV workflow complete"
}

print_aap_inventory_model_guide() {
    cat <<'EOF'

AAP Tested Deployment Model Guide (inventory templates)
======================================================

  [1] Single Node (Controller + PostgreSQL local)

      +------------------------------+
      | aap-26                       |
      |  - automationcontroller      |
      |  - postgres                  |
      +------------------------------+

            Templates:
                inventory.j2
                inventory-growth.j2

  [2] Growth / Multi-Node (Controller + DB + Execution)

      +------------------+     +------------------+     +------------------+
      | aap-controller   | --> | aap-database     | --> | aap-execution    |
      | automationctrl   |     | postgres         |     | execution_nodes  |
      +------------------+     +------------------+     +------------------+

            Templates:
                inventory-growth.j2
                inventory-growth.j2

  [3] DEMO (forced with --DEMO)

      +------------------------------+
      | aap-26 (single node demo)    |
      +------------------------------+

            Templates:
                DEMO-inventory.j2
                inventory-growth.j2

Docs: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/tested_deployment_models/index

EOF
}

resolve_aap_inventory_template_path() {
    local selected="$1"

    if [ -z "$selected" ]; then
        return 1
    fi

    if [ -f "$selected" ]; then
        printf '%s\n' "$selected"
        return 0
    fi

    if [ -f "${AAP_INVENTORY_TEMPLATE_DIR}/${selected}" ]; then
        printf '%s\n' "${AAP_INVENTORY_TEMPLATE_DIR}/${selected}"
        return 0
    fi

    return 1
}

aap_inventory_requires_pg_database() {
    local selected="${AAP_INVENTORY_TEMPLATE:-}"
    local base
    [ -n "$selected" ] || return 1
    base="$(basename "$selected")"
    [ "$base" = "inventory.j2" ]
}

ensure_aap_pg_database_if_needed() {
    if aap_inventory_requires_pg_database; then
        prompt_with_default AAP_PG_DATABASE "AAP PostgreSQL database name (pg_database)" "${AAP_PG_DATABASE:-awx}" 0 1 || return 1
    fi
    return 0
}

_rhis_show_about_inventory() {
    cat <<'ABOUT_INV'

+------------------------------------------------------------------------+
|  About: inventory (inventory.j2)                                       |
+------------------------------------------------------------------------+

  NAME
    AAP Containerized Enterprise / Multi-Node Deployment

  SYNOPSIS
    The enterprise topology distributes all AAP platform components
    across multiple dedicated virtual machines.  Each role -- Gateway,
    Controller, Automation Hub, EDA Controller, Execution Nodes, and
    Redis -- runs on its own host, enabling independent scaling, high
    availability, and fault isolation for production environments.
    This is the largest, most capable deployment model.

  ARCHITECTURE

                       Internet / clients
                               |
          +---------------------------------------------+
          |  [automationgateway]  (x2)                  |
          |   aap1.domain   aap2.domain                 |
          +-------------------+-------------------------+
                              |
             +----------------+--------------+
             |                |              |
     +-------+------+  +------+------+  +----+--------+
     |[automation   |  |[automation  |  |[automation  |
     | controller]  |  | hub]  (x2)  |  | eda]  (x2)  |
     |   (x2)       |  |             |  |             |
     +-------+------+  +-------------+  +-------------+
             |
     +-------+--------------------------------------------+
     |  [execution_nodes]  (x3)                           |
     |   aap1 (receptor_type=hop)   aap2   aap3           |
     +----------------------------------------------------+

     [redis]  (x6 -- distributed cache across the automation mesh)

  TEMPLATES USED
    AAP_INVENTORY_TEMPLATE        -> inventory.j2
    AAP_INVENTORY_GROWTH_TEMPLATE -> inventory-growth.j2

  HOW TO SET UP
    1. Provision the required libvirt VMs via Virt-Manager (menu 3/4/5):
         Gateway x2, Controller x2, Hub x2, EDA x2, Execution x3, Redis x6
    2. Ensure all FQDNs resolve in IdM DNS before running AAP installation.
    3. rhis-builder renders inventory.j2 into /root/aap-setup/inventory
       on the AAP host during kickstart %%post.
    4. Run the AAP containerized installer from the bundle defined in
       AAP_BUNDLE_URL; the rendered inventory drives the full install.

  WHY RED HAT SETS IT UP THIS WAY
    Separating components across VMs mirrors Red Hat's tested enterprise
    topology for scalable production workloads.  Independent scaling per
    service tier reduces blast radius of failures, allows maintenance
    windows per component, and enables horizontal scaling of execution
    capacity without touching the control plane.  Redis is distributed
    to avoid a single cache bottleneck across the automation mesh.

+------------------------------------------------------------------------+

ABOUT_INV
}

_rhis_show_about_inventory_growth() {
    cat <<'ABOUT_GROWTH'

+------------------------------------------------------------------------+
|  About: inventory-growth (inventory-growth.j2)                        |
+------------------------------------------------------------------------+

  NAME
    AAP Containerized Growth / Single-Node Deployment

  SYNOPSIS
    The growth topology co-locates all AAP platform components
    (Gateway, Controller, Automation Hub, EDA Controller, and a local
    database) onto a single virtual machine using containerized services.
    Redis runs in standalone mode.  This topology suits labs, proof-of-
    concept environments, smaller teams, or as a starting point before
    scaling to the enterprise multi-node model.

  ARCHITECTURE

    +----------------------------------------------------------+
    |                 aap.domain  (single VM)                  |
    |                                                          |
    |  +-------------------+   +-------------------+          |
    |  | [automationgate   |   | [automationctrl]  |          |
    |  |  way]  (Gateway)  |   |  (Controller)     |          |
    |  +-------------------+   +-------------------+          |
    |                                                          |
    |  +-------------------+   +-------------------+          |
    |  | [automationhub]   |   | [automationeda]   |          |
    |  |  (Private Hub)    |   |  (EDA Controller) |          |
    |  +-------------------+   +-------------------+          |
    |                                                          |
    |  +-------------------+   +-------------------+          |
    |  | [database]        |   |  redis            |          |
    |  |  (PostgreSQL)     |   |  (standalone mode)|          |
    |  +-------------------+   +-------------------+          |
    |                                                          |
    |  ansible_connection=local                                |
    +----------------------------------------------------------+

  TEMPLATES USED
    AAP_INVENTORY_TEMPLATE        -> inventory-growth.j2
    AAP_INVENTORY_GROWTH_TEMPLATE -> inventory-growth.j2

  HOW TO SET UP
    1. Provision a single AAP VM (16+ vCPU, 32+ GB RAM recommended)
       to host the full containerized stack.
    2. rhis-builder renders inventory-growth.j2 into
       /root/aap-setup/inventory on the AAP host during kickstart %%post.
    3. ansible_connection=local is used -- the installer runs directly
       on the target host; no remote SSH is needed for deployment.
    4. Run the AAP containerized installer from the bundle defined in
       AAP_BUNDLE_URL; the rendered inventory drives the install.

  WHY RED HAT SETS IT UP THIS WAY
    The growth topology is the recommended starting point in Red Hat's
    "Tested Deployment Models" documentation for containerized AAP.
    It reduces infrastructure overhead while providing a fully functional
    platform, making it ideal for labs and small-to-medium teams.  When
    capacity demands grow, the inventory can be migrated to the enterprise
    topology by adding dedicated hosts and re-running the installer.
    The name "growth" reflects its purpose as a scalable foundation.

+------------------------------------------------------------------------+

ABOUT_GROWTH
}

select_aap_inventory_templates() {
    # DEMO mode always uses the dedicated demo inventory template.
    if is_demo; then
        AAP_INVENTORY_TEMPLATE="DEMO-inventory.j2"
        AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-inventory-growth.j2}"
        ensure_aap_pg_database_if_needed || return 1
        echo ""
        echo "  [DEMO] This item was skipped because --DEMO was chosen."
        echo "         The smallest model (DEMO-inventory.j2) will be created"
        echo "         for Demo, PoC, or Educational purposes."
        return 0
    fi

    # If both are already set (env file or CLI), keep them.
    if [ -n "${AAP_INVENTORY_TEMPLATE:-}" ] && [ -n "${AAP_INVENTORY_GROWTH_TEMPLATE:-}" ]; then
        ensure_aap_pg_database_if_needed || return 1
        return 0
    fi

    # In non-interactive mode, provide deterministic defaults.
    if is_noninteractive; then
        AAP_INVENTORY_TEMPLATE="${AAP_INVENTORY_TEMPLATE:-inventory.j2}"
        AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-inventory-growth.j2}"
        ensure_aap_pg_database_if_needed || return 1
        return 0
    fi

    local inv_choice

    while true; do
        echo ""
        echo "+--------------------------------------------------------------+"
        echo "|       AAP Installer Inventory Architecture Selection         |"
        echo "+--------------------------------------------------------------+"
        echo ""
        echo "  0) Exit              -- Return to previous menu"
        echo "  1) inventory         -- Enterprise / Multi-Node deployment"
        echo "  2) About inventory   -- Name, synopsis, diagram & guidance"
        echo "  3) inventory-growth  -- Growth / Single-Node containerized"
        echo "  4) About inventory-growth"
        echo "                       -- Name, synopsis, diagram & guidance"
        echo ""
        read -r -p "  Choice [0-4]: " inv_choice

        case "${inv_choice}" in
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "  Exiting inventory selection."
                return 1
                ;;
            1)
                AAP_INVENTORY_TEMPLATE="inventory.j2"
                AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-inventory-growth.j2}"
                ensure_aap_pg_database_if_needed || return 1
                print_success "Selected: inventory.j2 (Enterprise / Multi-Node)"
                return 0
                ;;
            2)
                _rhis_show_about_inventory
                ;;
            3)
                AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
                AAP_INVENTORY_GROWTH_TEMPLATE="inventory-growth.j2"
                ensure_aap_pg_database_if_needed || return 1
                print_success "Selected: inventory-growth.j2 (Growth / Single-Node)"
                return 0
                ;;
            4)
                _rhis_show_about_inventory_growth
                ;;
            *)
                print_warning "Invalid choice '${inv_choice}'. Please enter 0, 1, 2, 3, or 4."
                ;;
        esac
    done
}

render_aap_inventory_template() {
    local template_selector="$1"
    local template_path
    local domain_e admin_user_e admin_pass_e pg_database_e aap_host_e aap_ip_e sat_host_e sat_ip_e idm_host_e idm_ip_e rh_user_e rh_pass_e

    template_path="$(resolve_aap_inventory_template_path "$template_selector")" || {
        print_warning "AAP inventory template not found: ${template_selector}"
        print_warning "Looked in: ${AAP_INVENTORY_TEMPLATE_DIR} and absolute path input"
        return 1
    }

    domain_e="$(sed_escape_replacement "${DOMAIN}")"
    admin_user_e="$(sed_escape_replacement "${ADMIN_USER}")"
    admin_pass_e="$(sed_escape_replacement "${AAP_ADMIN_PASS:-$ADMIN_PASS}")"
    pg_database_e="$(sed_escape_replacement "${AAP_PG_DATABASE:-awx}")"
    aap_host_e="$(sed_escape_replacement "${AAP_HOSTNAME}")"
    aap_ip_e="$(sed_escape_replacement "${AAP_IP}")"
    sat_host_e="$(sed_escape_replacement "${SAT_HOSTNAME}")"
    sat_ip_e="$(sed_escape_replacement "${SAT_IP}")"
    idm_host_e="$(sed_escape_replacement "${IDM_HOSTNAME}")"
    idm_ip_e="$(sed_escape_replacement "${IDM_IP}")"
    rh_user_e="$(sed_escape_replacement "${RH_USER}")"
    rh_pass_e="$(sed_escape_replacement "${RH_PASS}")"

    sed \
        -e "s|{{DOMAIN}}|${domain_e}|g" \
        -e "s|{{ADMIN_USER}}|${admin_user_e}|g" \
        -e "s|{{ADMIN_PASS}}|${admin_pass_e}|g" \
        -e "s|{{ pg_database }}|${pg_database_e}|g" \
        -e "s|{{pg_database}}|${pg_database_e}|g" \
        -e "s|{{AAP_HOSTNAME}}|${aap_host_e}|g" \
        -e "s|{{AAP_IP}}|${aap_ip_e}|g" \
        -e "s|{{SAT_HOSTNAME}}|${sat_host_e}|g" \
        -e "s|{{SAT_IP}}|${sat_ip_e}|g" \
        -e "s|{{IDM_HOSTNAME}}|${idm_host_e}|g" \
        -e "s|{{IDM_IP}}|${idm_ip_e}|g" \
        -e "s|{{RH_USER}}|${rh_user_e}|g" \
        -e "s|{{RH_PASS}}|${rh_pass_e}|g" \
        "$template_path"
}

prompt_aap_details() {
    normalize_shared_env_vars
    set_or_prompt RH_USER     "Red Hat CDN Username: "  || return 1
    set_or_prompt RH_PASS     "Red Hat CDN Password: " 1 || return 1
    set_or_prompt ADMIN_USER  "Shared Admin Username: " || return 1
    set_or_prompt ADMIN_PASS  "Shared Admin Password: " 1 || return 1
    echo -e "\n--- AAP Identity ---"
    set_or_prompt AAP_HOSTNAME   "AAP Hostname (FQDN): "   || return 1
    set_or_prompt AAP_ALIAS      "AAP Alias: "             || return 1
    set_or_prompt AAP_IP         "AAP Internal IP (eth1): " || return 1
    set_or_prompt AAP_NETMASK    "AAP Internal Netmask: "   || return 1
    set_or_prompt AAP_GW         "AAP Internal Gateway: "   || return 1
    echo -e "\n--- AAP Bundle Delivery (HTTP pre-flight) ---"
    set_or_prompt HUB_TOKEN  "Automation Hub Token (console.redhat.com/ansible/automation-hub/token): " 1 || return 1
    set_or_prompt HOST_INT_IP "Host bridge IP for bundle HTTP server (default 192.168.122.1): " || return 1
    # AAP_BUNDLE_URL is optional in interactive mode (user may have downloaded already)
    if [ -z "${AAP_BUNDLE_URL:-}" ] && ! is_noninteractive; then
        read -r -p "AAP bundle .tar.gz URL from access.redhat.com (blank to skip preflight download): " AAP_BUNDLE_URL || true
    fi
    select_aap_inventory_templates || return 1
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_aap_kickstart() {
    local ks_file="${KS_DIR}/aap-26.ks"
    local tmp_ks
    local aap_ssh_pub_key
    local aap_inventory_content
    local aap_inventory_growth_content
    local aap_ext_mac aap_int_mac
    local aap_prefix
    local bootstrap_ssh_keys
    local ks_nogpg_policy
    local ks_ssh_baseline
    local ks_user_sudo_bootstrap
    local ks_rhsm_register
    local ks_rhc_connect
    local ks_repo_enable_verify
    local ks_nm_dual_nic
    local ks_hosts_mapping
    local ks_trust_bootstrap_keys

    prompt_aap_details || return 1
    ensure_iso_vars || return 1
    ensure_ssh_keys || return 1

    aap_ext_mac="$(get_vm_external_mac "aap-26")"
    aap_int_mac="$(get_vm_internal_mac "aap-26")"
    aap_prefix="$(netmask_to_prefix "${AAP_NETMASK}")"
    ks_nogpg_policy="$(kickstart_nogpg_policy_block)"
    ks_ssh_baseline="$(kickstart_ssh_baseline_block)"
    ks_user_sudo_bootstrap="$(kickstart_user_sudo_bootstrap_block)"
    ks_rhsm_register="$(kickstart_rhsm_register_block 0)"
    ks_rhc_connect="$(kickstart_rhc_connect_block)"
    ks_repo_enable_verify="$(kickstart_repo_enable_verify_block "AAP" \
        "rhel-10-for-x86_64-baseos-rpms" \
        "rhel-10-for-x86_64-appstream-rpms" \
        "ansible-automation-platform-2.6-for-rhel-10-x86_64-rpms")"
    ks_nm_dual_nic="$(kickstart_networkmanager_dual_nic_block "${aap_ext_mac}" "${aap_int_mac}" "${AAP_IP}" "${aap_prefix}" "${AAP_GW}")"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "{{SAT_IP}}" "{{SAT_HOSTNAME}}" "{{SAT_SHORT}}" "{{AAP_IP}}" "{{AAP_HOSTNAME}}" "{{AAP_SHORT}}" "{{IDM_IP}}" "{{IDM_HOSTNAME}}" "{{IDM_SHORT}}")"
    ks_trust_bootstrap_keys="$(kickstart_trust_bootstrap_keys_block 0)"

    # Read the host's public key for SSH callback orchestration
    if [ ! -f "${AAP_SSH_PUBLIC_KEY}" ]; then
        print_warning "AAP SSH public key not found at ${AAP_SSH_PUBLIC_KEY}. Cannot inject into kickstart."
        return 1
    fi
    aap_ssh_pub_key="$(cat "${AAP_SSH_PUBLIC_KEY}")"
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"

    select_aap_inventory_templates || return 1
    aap_inventory_content="$(render_aap_inventory_template "${AAP_INVENTORY_TEMPLATE}")" || return 1
    aap_inventory_growth_content="$(render_aap_inventory_template "${AAP_INVENTORY_GROWTH_TEMPLATE}")" || return 1

    tmp_ks="$(mktemp)"

    sudo rm -f "$ks_file"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --plaintext "${ROOT_PASS}"
user --name="${ADMIN_USER}" --password="${ADMIN_PASS}" --plaintext --groups=wheel

network --bootproto=dhcp --device=eth0 --interfacename=eth0:${aap_ext_mac} --activate --onboot=yes

%include /tmp/network-eth1

HEADER

    build_internal_kickstart_network_line "eth1" "${aap_int_mac}" "${AAP_IP}" "${AAP_NETMASK}" "${AAP_GW}" "${AAP_HOSTNAME}" >> "$tmp_ks"
    echo "" >> "$tmp_ks"

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "AAP kickstart: DEMO partition layout (/boot 2G + swap 10G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 4 vCPU, 8152 MB RAM, 50 GB raw storage
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs"  --size=2048
part swap                   --size=10240
part /     --fstype="xfs"  --grow --size=1

DEMO_PART
    else
        print_step "AAP kickstart: production/best-practice LVM layout"
        cat >> "$tmp_ks" <<'STD_PART'
# Best Practice Partitioning for AAP 2.6 (LVM)
# Requirements: 8 vCPU, 16 GB RAM, 50 GB raw storage minimum
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs" --size=2048
part swap  --size=16384
part pv.01 --grow --size=1
volgroup vg_system pv.01
logvol /    --fstype="xfs" --name=lv_root --vgname=vg_system --size=20480
logvol /var --fstype="xfs" --name=lv_var  --vgname=vg_system --grow --size=1

STD_PART
    fi

    # --- Packages ---
    cat >> "$tmp_ks" <<'PKGS'
%packages
@Core
bash-completion
ansible-core
net-tools
bind-utils
tmux
chrony
qemu-guest-agent
tuned
-ntp
%end

PKGS

        # --- Post-install: write kickstart %post and substitute placeholders ---
        cat >> "$tmp_ks" <<POSTEOF
%post --log=/root/ks-post.log
set -euo pipefail

${ks_nogpg_policy}

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

${ks_rhsm_register}

${ks_rhc_connect}

${ks_repo_enable_verify}

# 4. Download the AAP bundle from the host HTTP server (started by run_rhis_install_sequence.sh)
mkdir -p /root/aap-setup
echo "Bundle download starting at $(date)" >> /var/log/aap-setup-ready.log
curl -fL --retry 5 --retry-delay 15 http://{{HOST_INT_IP}}:8080/aap-bundle.tar.gz -o /root/aap-bundle.tar.gz
tar -xzf /root/aap-bundle.tar.gz -C /root/aap-setup --strip-components=1
rm -f /root/aap-bundle.tar.gz
if [ ! -x /root/aap-setup/setup.sh ]; then
    echo "ERROR: AAP bundle extraction failed (missing /root/aap-setup/setup.sh)."
    exit 1
fi
echo "Bundle extracted. Ready for SSH callback." >> /var/log/aap-setup-ready.log

# 5. SSH callback key injection
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<SSH_KEYS
{{AAP_SSH_PUB_KEY}}
SSH_KEYS
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys || true
chmod 600 /root/.ssh/authorized_keys
if id "$target_user" >/dev/null 2>&1; then
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
    [ -n "$target_home" ] || target_home="/home/$target_user"
    install -d -m 700 -o "$target_user" -g "$target_user" "$target_home/.ssh"
    cat > "$target_home/.ssh/authorized_keys" <<'SSH_KEYS'
${bootstrap_ssh_keys}
SSH_KEYS
    chown "$target_user:$target_user" "$target_home/.ssh/authorized_keys"
    chmod 600 "$target_home/.ssh/authorized_keys"
fi

# Log setup readiness for debugging
echo "[aap-setup] Bundle ready at /root/aap-setup on $(date)" >> /var/log/aap-setup-ready.log

# 6. Automation Hub credentials so the containerized installer can pull collections
cat > /root/.ansible.cfg <<ANSIBLECFG
[defaults]
galaxy_server_list = automation_hub

[galaxy_server.automation_hub]
url=https://console.redhat.com/api/automation-hub/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token={{HUB_TOKEN}}
ANSIBLECFG
chmod 600 /root/.ansible.cfg

# 7. Installer inventories rendered from Jinja2 templates selected at prompt/CLI
cat > /root/aap-setup/inventory <<INVENTORY
${aap_inventory_content}
INVENTORY
chmod 600 /root/aap-setup/inventory
if [ "${DEMO_MODE:-0}" = "1" ]; then
    cp -f /root/aap-setup/inventory /root/aap-setup/DEMO-inventory
    chmod 600 /root/aap-setup/DEMO-inventory
fi

cat > /root/aap-setup/inventory-growth <<INVENTORY_GROWTH
${aap_inventory_growth_content}
INVENTORY_GROWTH
chmod 600 /root/aap-setup/inventory-growth
if [ ! -s /root/aap-setup/inventory ] || [ ! -s /root/aap-setup/inventory-growth ]; then
    echo "ERROR: AAP inventory rendering failed (inventory files missing/empty)."
    exit 1
fi

echo "Rendered AAP inventory file: /root/aap-setup/inventory"
echo "Preview (first 20 lines, passwords masked):"
sed -E 's/([A-Za-z0-9_]*password[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' /root/aap-setup/inventory | head -n 20 || true

echo "Rendered AAP inventory file: /root/aap-setup/inventory-growth"
echo "Preview (first 20 lines, passwords masked):"
sed -E 's/([A-Za-z0-9_]*password[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' /root/aap-setup/inventory-growth | head -n 20 || true

# 8. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
net.core.somaxconn = 4096
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true

# 9. Network verification snapshot (for ks-post.log troubleshooting)
echo "===== RHIS NETWORK SNAPSHOT ====="
date
ip -4 addr show eth0 || true
ip -4 addr show eth1 || true
ip route show || true
nmcli -f NAME,DEVICE,TYPE,STATE connection show || true
echo "===== END RHIS NETWORK SNAPSHOT ====="
%end
POSTEOF

    # Substitute placeholders with actual values in the temp kickstart
    sed -i "s|{{HOST_INT_IP}}|${HOST_INT_IP}|g" "$tmp_ks"
    sed -i "s|{{AAP_SSH_PUB_KEY}}|${aap_ssh_pub_key}|g" "$tmp_ks"
    sed -i "s|{{HUB_TOKEN}}|${HUB_TOKEN}|g" "$tmp_ks"
    sed -i "s|{{SAT_IP}}|${SAT_IP}|g" "$tmp_ks"
    sed -i "s|{{SAT_HOSTNAME}}|${SAT_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{AAP_IP}}|${AAP_IP}|g" "$tmp_ks"
    sed -i "s|{{AAP_HOSTNAME}}|${AAP_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{IDM_IP}}|${IDM_IP}|g" "$tmp_ks"
    sed -i "s|{{IDM_HOSTNAME}}|${IDM_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{SAT_SHORT}}|${SAT_HOSTNAME%%.*}|g" "$tmp_ks"
    sed -i "s|{{AAP_SHORT}}|${AAP_HOSTNAME%%.*}|g" "$tmp_ks"
    sed -i "s|{{IDM_SHORT}}|${IDM_HOSTNAME%%.*}|g" "$tmp_ks"

    sudo mkdir -p "$KS_DIR"
    sudo install -m 0644 "$tmp_ks" "$ks_file"
    rm -f "$tmp_ks"
    print_success "Generated AAP kickstart: $ks_file"
}

prompt_idm_details() {
    normalize_shared_env_vars
    set_or_prompt RH_USER  "Red Hat CDN Username: "  || return 1
    set_or_prompt RH_PASS  "Red Hat CDN Password: " 1 || return 1
    set_or_prompt ADMIN_PASS "Shared Admin Password: " 1 || return 1

    echo -e "\n--- IdM Network (eth1 — static) ---"
    set_or_prompt IDM_IP      "IdM Static IP for eth1: " || return 1
    set_or_prompt IDM_NETMASK "Subnet Mask: "            || return 1
    set_or_prompt IDM_GW      "Gateway: "                || return 1

    echo -e "\n--- IdM Identity ---"
    set_or_prompt IDM_HOSTNAME   "IdM Hostname (FQDN): "               || return 1
    set_or_prompt IDM_ALIAS      "IdM Alias: "                         || return 1
    set_or_prompt DOMAIN         "Shared Domain Name: "                || return 1
    IDM_ADMIN_PASS="${ADMIN_PASS}"
    set_or_prompt IDM_DS_PASS    "Directory Service Password: " 1      || return 1
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_idm_kickstart() {
    local ks_file="${KS_DIR}/idm.ks"
    local tmp_ks
    local idm_ext_mac idm_int_mac
    local idm_prefix
    local bootstrap_ssh_keys
    local ks_nogpg_policy
    local ks_ssh_baseline
    local ks_user_sudo_bootstrap
    local ks_rhsm_register
    local ks_rhc_connect
    local ks_repo_enable_verify
    local ks_nm_dual_nic
    local ks_hosts_mapping
    local ks_trust_bootstrap_keys

    prompt_idm_details || return 1
    ensure_iso_vars || return 1
    ensure_ssh_keys || return 1

    idm_ext_mac="$(get_vm_external_mac "idm")"
    idm_int_mac="$(get_vm_internal_mac "idm")"
    idm_prefix="$(netmask_to_prefix "${IDM_NETMASK}")"
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"
    ks_nogpg_policy="$(kickstart_nogpg_policy_block)"
    ks_ssh_baseline="$(kickstart_ssh_baseline_block)"
    ks_user_sudo_bootstrap="$(kickstart_user_sudo_bootstrap_block)"
    ks_rhsm_register="$(kickstart_rhsm_register_block 0)"
    ks_rhc_connect="$(kickstart_rhc_connect_block)"
    ks_repo_enable_verify="$(kickstart_repo_enable_verify_block "IdM" \
        "rhel-10-for-x86_64-baseos-rpms" \
        "rhel-10-for-x86_64-appstream-rpms")"
    ks_nm_dual_nic="$(kickstart_networkmanager_dual_nic_block "${idm_ext_mac}" "${idm_int_mac}" "${IDM_IP}" "${idm_prefix}" "${IDM_GW}")"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_HOSTNAME%%.*}" "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_HOSTNAME%%.*}" "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_HOSTNAME%%.*}")"
    ks_trust_bootstrap_keys="$(kickstart_trust_bootstrap_keys_block 1)"

    tmp_ks="$(mktemp)"

    sudo rm -f "$ks_file"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --plaintext "${ROOT_PASS}"
user --name="${ADMIN_USER}" --password="${ADMIN_PASS}" --plaintext --groups=wheel

network --bootproto=dhcp --device=eth0 --interfacename=eth0:${idm_ext_mac} --activate --onboot=yes

%include /tmp/network-eth1
HEADER

    # --- eth1 (always static for internal provisioning/management network) ---
    build_internal_kickstart_network_line "eth1" "${idm_int_mac}" "${IDM_IP}" "${IDM_NETMASK}" "${IDM_GW}" "${IDM_HOSTNAME}" >> "$tmp_ks"
    echo "" >> "$tmp_ks"

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "IdM kickstart: DEMO partition layout (/boot 2G + swap 4G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 2 vCPU, 4 GB RAM, 30 GB raw storage
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs"  --size=2048
part swap                   --size=4096
part /     --fstype="xfs"  --grow --size=1

DEMO_PART
    else
        print_step "IdM kickstart: production/best-practice LVM layout"
        cat >> "$tmp_ks" <<'STD_PART'
# Best Practice Partitioning for Red Hat IdM (LVM)
# Requirements: 4 vCPU, 16 GB RAM, 60 GB raw storage minimum
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs" --size=2048
part swap  --size=8192
part pv.01 --grow --size=1
volgroup vg_system pv.01
logvol /    --fstype="xfs" --name=lv_root --vgname=vg_system --size=10240
logvol /var --fstype="xfs" --name=lv_var  --vgname=vg_system --grow --size=1

STD_PART
    fi

    # --- Packages ---
    cat >> "$tmp_ks" <<'PKGS'
%packages
@Core
ipa-server
ipa-server-dns
bind-dyndb-ldap
bash-completion
net-tools
bind-utils
tmux
chrony
qemu-guest-agent
tuned
-ntp
%end

PKGS

    # --- Post-install (variable expansion required) ---
    cat >> "$tmp_ks" <<POSTEOF
%post --log=/root/ks-post.log
set -euo pipefail

${ks_nogpg_policy}

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

${ks_rhsm_register}

${ks_rhc_connect}

# 3. Hostname
hostnamectl set-hostname "${IDM_HOSTNAME}"

# 4. Repositories
${ks_repo_enable_verify}

# 4.1 Verify required IdM packages from kickstart payload are present
if ! rpm -q ipa-server ipa-server-dns bind-dyndb-ldap >/dev/null 2>&1; then
    echo "ERROR: Required IdM packages missing after kickstart package phase."
    rpm -qa | grep -E '^ipa-server|^bind-dyndb-ldap' || true
    exit 1
fi

# 5. IdM Server Installation (unattended)
ipa-server-install --unattended --realm="${IDM_REALM}" --domain="${IDM_DOMAIN}" --hostname="${IDM_HOSTNAME}" --admin-password="${IDM_ADMIN_PASS}" --ds-password="${IDM_DS_PASS}" --setup-dns --auto-forwarders --no-ntp

# 5. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true

# 6. Network verification snapshot (for ks-post.log troubleshooting)
echo "===== RHIS NETWORK SNAPSHOT ====="
date
ip -4 addr show eth0 || true
ip -4 addr show eth1 || true
ip route show || true
nmcli -f NAME,DEVICE,TYPE,STATE connection show || true
echo "===== END RHIS NETWORK SNAPSHOT ====="
%end
POSTEOF

    sudo mkdir -p "$KS_DIR"
    sudo install -m 0644 "$tmp_ks" "$ks_file"
    rm -f "$tmp_ks"
    print_success "Generated IdM kickstart: $ks_file"
}

cleanup_generated_kickstart_artifacts() {
    print_step "Removing generated kickstarts and OEMDRV artifacts"
    sudo rm -f \
        "${KS_DIR}/satellite-618.ks" \
        "${KS_DIR}/aap-26.ks" \
        "${KS_DIR}/idm.ks" \
        "${OEMDRV_ISO}" \
        /tmp/OEMDRV.iso \
        /tmp/ks.cfg || true
}

write_kickstarts() {
    cleanup_generated_kickstart_artifacts

    generate_satellite_618_kickstart || return 1
    generate_aap_kickstart || return 1
    generate_idm_kickstart || return 1
}

fix_qemu_permissions() {
    ensure_iso_vars || return 1
    sudo mkdir -p "$ISO_DIR" "$VM_DIR" "$KS_DIR"
    sudo chmod 0755 "$ISO_DIR" "$VM_DIR" "$KS_DIR"
    print_step "Verified libvirt image/kickstart directory permissions"
}

create_libvirt_storage_pool() {
    ensure_iso_vars || return 1

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping storage pool validation."
        return 0
    fi

    if sudo virsh pool-info default >/dev/null 2>&1; then
        sudo virsh pool-start default >/dev/null 2>&1 || true
        sudo virsh pool-autostart default >/dev/null 2>&1 || true
        print_step "Using existing libvirt storage pool: default"
        return 0
    fi

    print_step "Creating libvirt storage pool: default"
    sudo virsh pool-define-as default dir --target "$VM_DIR" >/dev/null 2>&1 || return 1
    sudo virsh pool-build default >/dev/null 2>&1 || true
    sudo virsh pool-start default >/dev/null 2>&1 || return 1
    sudo virsh pool-autostart default >/dev/null 2>&1 || true
}

create_vm_if_missing() {
	local vm_name="${1:-}"
	local disk_path="${2:-}"
	local disk_size="${3:-10G}"
	local mem_mb="${4:-4096}"
	local vcpus="${5:-2}"
	local ks_file="${6:-}"
    local ks_boot_location="${7:-}"
    local install_iso_path="${8:-${ISO_PATH}}"
    local extra_args
    local external_mac
    local internal_mac
    local -a virt_install_cmd

	[ -n "$vm_name" ] || { print_warning "vm_name required"; return 1; }
	[ -n "$disk_path" ] || disk_path="${VM_DIR}/${vm_name}.qcow2"
	[ -n "$ks_file" ] || ks_file="${KS_DIR}/${vm_name}.ks"
    external_mac="$(get_vm_external_mac "$vm_name")"
    internal_mac="$(get_vm_internal_mac "$vm_name")"

    if ! mkdir -p "$(dirname "$disk_path")" 2>/dev/null; then
        sudo mkdir -p "$(dirname "$disk_path")" || return 1
    fi

	if sudo virsh dominfo "$vm_name" >/dev/null 2>&1; then
		print_warning "VM already exists: $vm_name (skipping)"
		return 0
	fi

	if [ ! -f "$disk_path" ]; then
		print_step "Creating disk: $disk_path ($disk_size)"
        sudo qemu-img create -f qcow2 "$disk_path" "$disk_size" || { print_warning "qemu-img failed"; return 1; }
	fi

    if [ ! -f "${install_iso_path:-}" ]; then
        print_warning "ISO not found at ${install_iso_path:-}. Aborting VM create for ${vm_name}."
		return 1
	fi
	# Only require OEMDRV ISO for VMs booting via hd:LABEL=OEMDRV (e.g. Satellite)
	if [ -n "$ks_boot_location" ] && [ ! -f "${OEMDRV_ISO:-}" ]; then
		print_warning "OEMDRV ISO not found at ${OEMDRV_ISO:-}. Aborting VM create for ${vm_name}."
		return 1
	fi
	if [ ! -f "$ks_file" ]; then
		print_warning "Kickstart not found: $ks_file. Aborting VM create for ${vm_name}."
		return 1
	fi

	print_step "Creating VM: $vm_name (disk=$disk_path mem=${mem_mb}MB vcpus=${vcpus})"

    if [ -n "$ks_boot_location" ]; then
        extra_args="inst.ks=${ks_boot_location} console=tty0 console=ttyS0,115200n8"
    else
        extra_args="inst.ks=file:/$(basename "$ks_file") console=tty0 console=ttyS0,115200n8"
    fi

    # Disk I/O flags: "fast" = SSD/NVMe optimised; "safe" = conservative (HDD / shared storage).
    local disk_perf_flags
    if [[ "${VM_DISK_PERF_MODE:-fast}" == "fast" ]]; then
        disk_perf_flags="cache=none,discard=unmap,io=native"
    else
        disk_perf_flags="cache=writeback"
    fi

    virt_install_cmd=(
        sudo virt-install
        --connect qemu:///system
        --name "$vm_name"
        --ram "$mem_mb"
        --vcpus "$vcpus"
        --disk "path=$disk_path,format=qcow2,bus=virtio,${disk_perf_flags}"
        --network "network=external,model=virtio${external_mac:+,mac=${external_mac}}"
        --network "network=internal,model=virtio${internal_mac:+,mac=${internal_mac}}"
        --graphics "vnc,listen=127.0.0.1"
        --video vga
        --location "${install_iso_path}"
    )

    # Add os-variant only if one is resolved/supported on this host.
    if [ -n "${RH_OSINFO:-}" ]; then
        virt_install_cmd+=(--os-variant "${RH_OSINFO}")
    fi

    if [ -n "$ks_boot_location" ]; then
        # OEMDRV approach: Satellite reads kickstart from the attached OEMDRV ISO
        virt_install_cmd+=(--disk "path=${OEMDRV_ISO},device=cdrom,readonly=on")
    else
        # initrd-inject approach: AAP, IdM, and other non-OEMDRV VMs
        virt_install_cmd+=(--initrd-inject "$ks_file")
    fi

    virt_install_cmd+=(--extra-args "$extra_args" --noautoconsole)

    if ! "${virt_install_cmd[@]}"; then
        print_warning "VM creation failed for ${vm_name}."
        return 1
    fi

    sudo virsh autostart "$vm_name" >/dev/null 2>&1 || true

	print_success "VM creation requested: $vm_name"
}

demokill_cleanup() {
    print_step "DEMOKILL: destroying demo VMs and cleaning generated files"

    stop_vm_power_watchdog || true

    print_step "Stopping auto-launched VM console monitors"
    stop_vm_console_monitors || true
    force_kill_rhis_leftovers || true

    print_step "Stopping RHIS provisioner container"
    podman rm -f "${RHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true

    local vm
    local -a demo_vms=("satellite-618" "aap-26" "idm")

    for vm in "${demo_vms[@]}"; do
        if sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            print_step "Stopping VM if running: $vm"
            sudo virsh destroy "$vm" >/dev/null 2>&1 || true
            print_step "Undefining VM: $vm"
            sudo virsh undefine "$vm" --nvram >/dev/null 2>&1 || sudo virsh undefine "$vm" >/dev/null 2>&1 || true
        else
            print_step "VM not defined (skipping): $vm"
        fi
    done

    print_step "Removing demo qcow2 disks"
    sudo rm -f \
        "${VM_DIR}/satellite-618.qcow2" \
        "${VM_DIR}/aap-26.qcow2" \
        "${VM_DIR}/idm.qcow2" || true

    cleanup_generated_kickstart_artifacts

    print_step "Removing staged AAP bundle directory"
    sudo rm -rf "${AAP_BUNDLE_DIR}" || true

    print_step "Checking RHIS-related lock files"
    cleanup_rhis_lock_files || true

    print_step "Removing RHIS temporary/cache artifacts"
    sudo rm -f \
        /tmp/aap-setup-*.log \
        /tmp/default.xml \
        /tmp/internal.xml || true

    print_step "Stopping any leftover AAP bundle HTTP server"
    sudo pkill -f "python3 -m http.server 8080 --bind" >/dev/null 2>&1 || true
    close_aap_bundle_firewall

    print_step "Restarting libvirtd"
    sudo systemctl restart libvirtd || return 1

    print_step "Starting libvirt networks"
    sudo virsh net-start external >/dev/null 2>&1 || true
    sudo virsh net-autostart external >/dev/null 2>&1 || true
    sudo virsh net-start internal >/dev/null 2>&1 || true
    sudo virsh net-autostart internal >/dev/null 2>&1 || true

    print_step "Reconnecting qemu/kvm session"
    if sudo virsh -c qemu:///system list --all >/dev/null 2>&1; then
        print_success "qemu/kvm reconnected (qemu:///system reachable)"
    else
        print_warning "Initial qemu/kvm reconnect check failed; retrying after virtqemud/libvirtd refresh"
        sudo systemctl restart virtqemud >/dev/null 2>&1 || true
        sudo systemctl restart libvirtd >/dev/null 2>&1 || true
        if sudo virsh -c qemu:///system list --all >/dev/null 2>&1; then
            print_success "qemu/kvm reconnected after service refresh"
        else
            print_warning "qemu/kvm reconnect still failed; check 'sudo systemctl status libvirtd virtqemud'"
        fi
    fi

    print_step "Restarting virt-manager session"
    pkill -f "virt-manager" >/dev/null 2>&1 || true
    sleep 1
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if virsh -c qemu:///system list --all >/dev/null 2>&1; then
            nohup virt-manager >/dev/null 2>&1 &
            disown || true
            print_success "virt-manager restarted"
        else
            print_warning "Skipping virt-manager auto-start: current user cannot access qemu:///system (polkit access denied)."
            print_warning "Fix host policy (org.libvirt.unix.manage/monitor for libvirt group) to use virt-manager without sudo."
        fi
    else
        print_warning "No desktop session detected; virt-manager not auto-started"
    fi

    print_success "DEMOKILL complete. Demo VMs/files and RHIS temp artifacts removed; libvirtd restarted."
}

cleanup_rhis_lock_files() {
    local -a lock_candidates
    local -a existing_locks
    local lock_path

    lock_candidates=(
        "${VM_DIR}/satellite-618.qcow2.lock"
        "${VM_DIR}/aap-26.qcow2.lock"
        "${VM_DIR}/idm.qcow2.lock"
        "${VM_DIR}/satellite-618.qcow2.lck"
        "${VM_DIR}/aap-26.qcow2.lck"
        "${VM_DIR}/idm.qcow2.lck"
        "${KS_DIR}/satellite-618.ks.lock"
        "${KS_DIR}/aap-26.ks.lock"
        "${KS_DIR}/idm.ks.lock"
        "/var/lock/libvirt/qemu/satellite-618.lock"
        "/var/lock/libvirt/qemu/aap-26.lock"
        "/var/lock/libvirt/qemu/idm.lock"
    )

    for lock_path in "${lock_candidates[@]}"; do
        if [ -e "$lock_path" ]; then
            existing_locks+=("$lock_path")
        fi
    done

    if [ "${#existing_locks[@]}" -eq 0 ]; then
        print_step "No RHIS lock files found"
        return 0
    fi

    print_warning "Found ${#existing_locks[@]} RHIS lock file(s); removing..."
    for lock_path in "${existing_locks[@]}"; do
        print_step "Removing lock: $lock_path"
        sudo rm -f "$lock_path" || true
    done

    return 0
}

create_rhis_vms() {
    print_phase 1 8 "Provision VM artifacts and prerequisites"
    print_step "Preparing Satellite / AAP / IdM qcow2 VMs"
    prompt_use_existing_env
    normalize_shared_env_vars
    validate_resolved_kickstart_inputs || return 1

    local sat_disk sat_ram sat_vcpu
    local aap_disk aap_ram aap_vcpu
    local idm_disk idm_ram idm_vcpu
    local ssh_mesh_bootstrap_ok=0

    if is_demo; then
        print_step "DEMO mode: reduced VM specifications (PoC/learning environment)"
        sat_disk="100G"; sat_ram=24576; sat_vcpu=8
        aap_disk="50G";  aap_ram=8152;  aap_vcpu=4
        idm_disk="30G";  idm_ram=4096;  idm_vcpu=2
    else
        print_step "Standard mode: production/best-practice VM specifications"
        sat_disk="75G";  sat_ram=32768; sat_vcpu=8
        aap_disk="50G";  aap_ram=16384; aap_vcpu=8
        idm_disk="60G";  idm_ram=16384; idm_vcpu=4
    fi

    print_warning "Pre-flight lock check: stale lock files can block provisioning."
    cleanup_rhis_lock_files || true

    ensure_virtualization_tools || return 1
    ensure_iso_vars
    download_rhel10_iso || return 1
    download_rhel9_iso || return 1
    assert_satellite_install_iso_is_valid "${SAT_ISO_PATH}" || return 1
    assert_aap_install_iso_is_valid "${ISO_PATH}" || return 1
    assert_idm_install_iso_is_valid "${ISO_PATH}" || return 1
    fix_qemu_permissions
    create_libvirt_storage_pool || return 1

    write_kickstarts || return 1

    # Pre-flight: ensure SSH keys exist for post-boot AAP callback orchestration
    ensure_ssh_keys || {
        print_warning "Failed to generate SSH keys; AAP callback orchestration will not work."
        return 1
    }

    # Pre-flight: download the AAP bundle tarball to AAP_BUNDLE_DIR on the host.
    # The VM will curl it from there during %post via the HTTP server below.
    preflight_download_aap_bundle || print_warning "AAP bundle preflight skipped. Ensure aap-bundle.tar.gz is in ${AAP_BUNDLE_DIR} before the VM runs %post."

    # Build-order requirement: IdM must come first, then Satellite, then AAP.
    create_vm_if_missing "idm"           "${VM_DIR}/idm.qcow2"           "$idm_disk" "$idm_ram" "$idm_vcpu" "${KS_DIR}/idm.ks" || return 1

    create_vm_if_missing "satellite-618" "${VM_DIR}/satellite-618.qcow2" "$sat_disk" "$sat_ram" "$sat_vcpu" "${KS_DIR}/satellite-618.ks" "hd:LABEL=OEMDRV:/ks.cfg" "${SAT_ISO_PATH}" || return 1

    # Start the HTTP server before the AAP VM boots so the bundle is available
    # when anaconda runs %post.
    if [ -d "${AAP_BUNDLE_DIR}" ]; then
        serve_aap_bundle || print_warning "Could not start AAP bundle HTTP server; AAP %post bundle download will fail."
    fi

    create_vm_if_missing "aap-26"        "${VM_DIR}/aap-26.qcow2"        "$aap_disk" "$aap_ram" "$aap_vcpu" "${KS_DIR}/aap-26.ks" || return 1

    print_phase 2 8 "Guest settle and initial readiness"

    # Keep all VMs ON through installer reboot/power transitions while callbacks run.
    start_vm_power_watchdog 10800 || true

    if ! is_noninteractive; then
        launch_vm_console_monitors_auto || true
    fi

    if [ "${AAP_HTTP_PID:-0}" -gt 0 ] 2>/dev/null; then
        print_step "AAP callback is deferred until the AAP configuration phase so IdM/Satellite can proceed first."
    fi

    ensure_rhis_vms_powered_on
    wait_for_post_vm_settle || true
    sync_rhis_external_hosts_entries || true

    # As soon as VMs first come up, bootstrap SSH trust mesh before config-as-code.
    print_phase 3 8 "SSH mesh bootstrap"
    if setup_rhis_ssh_mesh; then
        ssh_mesh_bootstrap_ok=1
    else
        if is_enabled "${RHIS_ALLOW_DEFERRED_SSH_MESH:-0}"; then
            print_warning "SSH mesh bootstrap did not complete cleanly; deferred mode enabled (RHIS_ALLOW_DEFERRED_SSH_MESH=1), will retry after config-as-code once nodes are fully initialized."
        else
            print_warning "SSH mesh bootstrap is required before continuing. Aborting now."
            print_warning "If you intentionally want deferred behavior, set RHIS_ALLOW_DEFERRED_SSH_MESH=1 and re-run."
            stop_vm_power_watchdog || true
            return 1
        fi
    fi
    print_phase 4 8 "SSH mesh validation"
    if [ "${ssh_mesh_bootstrap_ok}" -eq 1 ]; then
        validate_rhis_ssh_mesh || print_warning "SSH mesh validation reported failures; continuing."
    else
        print_step "Skipping early SSH mesh validation because bootstrap was deferred."
    fi

    # Trigger config-as-code via the provisioner container after SSH baseline is in place.
    print_phase 5 8 "Config-as-code orchestration"
    run_rhis_config_as_code || print_warning "Config-as-code phase did not complete cleanly. VMs are running; re-run manually if needed."

    if [ "${ssh_mesh_bootstrap_ok}" -eq 0 ]; then
        print_step "Retrying deferred SSH mesh bootstrap/validation after config-as-code..."
        if setup_rhis_ssh_mesh; then
            validate_rhis_ssh_mesh || print_warning "Deferred SSH mesh validation still reported failures; continuing."
        else
            print_warning "Deferred SSH mesh bootstrap still did not complete cleanly; continuing."
        fi
    fi

    stop_vm_power_watchdog || true
    print_phase 6 8 "Root password normalization"
    fix_vm_root_passwords || print_warning "Root password fix step did not complete cleanly; continuing."
    print_phase 7 8 "Final health summary"
    print_rhis_health_summary
    print_phase 8 8 "Workflow complete"
}

# Fix the OS root password on all RHIS VMs using virsh set-user-password (via qemu-guest-agent).
# Called after VMs are powered on so the guest agent is running.
fix_vm_root_passwords() {
    local vm new_pass
    local -a vms=("satellite-618" "aap-26" "idm")

    # Re-load the vault so we always use the latest ADMIN_PASS value
    # Force-clear ADMIN_PASS so load_ansible_env_file picks up the updated vault
    ADMIN_PASS=""
    read_ansible_env_content 2>/dev/null || true
    load_ansible_env_file 2>/dev/null || true
    normalize_shared_env_vars

    new_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"

    print_step "Setting root password on all VMs via qemu-guest-agent (virsh set-user-password)"
    for vm in "${vms[@]}"; do
        if ! sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            print_warning "VM not defined, skipping password fix: $vm"
            continue
        fi
        if sudo virsh set-user-password "$vm" root "${new_pass}" 2>/dev/null; then
            print_success "Root password updated on: $vm"
        else
            print_warning "Could not set root password on $vm (guest agent may not be ready yet)"
        fi
    done
}

setup_rhis_ssh_mesh() {
    local root_pass installer_user installer_pass ip pub login_user login_pass
    local ssh_bootstrap_retries ssh_bootstrap_delay
    local local_installer_pub=""
    local local_root_pub=""
    local root_mesh_failures=0
    local root_mesh_required=0
    local -a node_ips all_pubs root_pubs node_names
    local bootstrap_cmd append_cmd bootstrap_root_cmd append_root_cmd
    local bootstrap_root_via_admin_cmd read_root_pub_via_admin_cmd

    root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    installer_user="${INSTALLER_USER:-${ADMIN_USER}}"
    installer_pass="${ADMIN_PASS:-}"
    ssh_bootstrap_retries="${RHIS_SSH_BOOTSTRAP_RETRIES:-45}"
    ssh_bootstrap_delay="${RHIS_SSH_BOOTSTRAP_DELAY:-10}"
    if is_enabled "${RHIS_REQUIRE_ROOT_SSH_MESH:-0}"; then
        root_mesh_required=1
    fi
    if [ -z "$installer_pass" ] && [ -z "$root_pass" ]; then
        print_warning "Cannot bootstrap SSH mesh: installer/admin and root passwords are both unset."
        return 1
    fi

    if ! command -v sshpass >/dev/null 2>&1; then
        print_step "Installing sshpass for automated SSH trust bootstrap"
        sudo dnf install -y --nogpgcheck sshpass >/dev/null 2>&1 || {
            print_warning "Failed to install sshpass; skipping SSH mesh bootstrap."
            return 1
        }
    fi

    node_ips=("${SAT_IP}" "${AAP_IP}" "${IDM_IP}")
    node_names=("satellite" "aap" "idm")

    # Rebuilds rotate SSH host keys on RHIS nodes; keep installer known_hosts clean.
    refresh_rhis_known_hosts || true

    # Ensure dedicated, persistent installer-host RHIS key exists.
    if ! ensure_rhis_installer_ssh_key; then
        print_warning "Could not prepare dedicated RHIS installer SSH key at ${RHIS_INSTALLER_SSH_PRIVATE_KEY}."
        return 1
    fi

    # Ensure local installer user has key + authorized_keys (install host).
    mkdir -p "${HOME}/.ssh" >/dev/null 2>&1 || true
    chmod 700 "${HOME}/.ssh" >/dev/null 2>&1 || true
    touch "${HOME}/.ssh/authorized_keys" >/dev/null 2>&1 || true
    chmod 600 "${HOME}/.ssh/authorized_keys" >/dev/null 2>&1 || true
    if [ -f "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        cat "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" >> "${HOME}/.ssh/authorized_keys"
        sort -u "${HOME}/.ssh/authorized_keys" -o "${HOME}/.ssh/authorized_keys" || true
        local_installer_pub="$(cat "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" 2>/dev/null || true)"
    fi

    # Explicit self trust requested: install-host user -> 127.0.0.1
    if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${installer_pass}" ] && [ -f "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        sshpass -p "${installer_pass}" ssh-copy-id -i "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "${installer_user}@127.0.0.1" >/dev/null 2>&1 || true
    fi

    # Ensure local root has key + authorized_keys (best effort).
    if command -v sudo >/dev/null 2>&1; then
        sudo bash -lc 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && [ -f /root/.ssh/id_rsa ] || ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa; touch /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; [ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/id_rsa 2>/dev/null || true; chmod 644 /root/.ssh/id_rsa.pub 2>/dev/null || true' >/dev/null 2>&1 || true
        local_root_pub="$(sudo cat /root/.ssh/id_rsa.pub 2>/dev/null || true)"
    fi

    # Explicit self trust requested: local root -> 127.0.0.1
    if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${root_pass}" ] && command -v sudo >/dev/null 2>&1; then
        sudo bash -lc "sshpass -p '${root_pass}' ssh-copy-id -i /root/.ssh/id_rsa.pub -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1 >/dev/null 2>&1 || true" || true
    fi

    bootstrap_cmd='set -e; target_user="'"${installer_user}"'"; if ! id "$target_user" >/dev/null 2>&1; then useradd -m -G wheel "$target_user" >/dev/null 2>&1 || useradd -m "$target_user" >/dev/null 2>&1 || true; fi; target_home="$(getent passwd "$target_user" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/$target_user"; install -d -m 700 -o "$target_user" -g "$target_user" "$target_home/.ssh"; if [ ! -f "$target_home/.ssh/id_rsa" ]; then sudo -u "$target_user" ssh-keygen -q -t rsa -b 4096 -N "" -f "$target_home/.ssh/id_rsa"; fi; touch "$target_home/.ssh/authorized_keys"; chown "$target_user:$target_user" "$target_home/.ssh/authorized_keys"; chmod 600 "$target_home/.ssh/authorized_keys"; cat > "$target_home/.ssh/config" <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chown "$target_user:$target_user" "$target_home/.ssh/config"; chmod 600 "$target_home/.ssh/config"; cat "$target_home/.ssh/id_rsa.pub" >> "$target_home/.ssh/authorized_keys"; sort -u "$target_home/.ssh/authorized_keys" -o "$target_home/.ssh/authorized_keys"'

    print_step "Bootstrapping installer-user SSH config/keys on RHIS nodes (${installer_user})"
    for ip in "${node_ips[@]}"; do
        local _bootstrap_ok=0
        local _attempt
        for _attempt in $(seq 1 "${ssh_bootstrap_retries}"); do
            login_user="${installer_user}"
            login_pass="${installer_pass}"
            if [ -n "${login_pass}" ] && sshpass -p "$login_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${login_user}@${ip}" "$bootstrap_cmd" >/dev/null 2>&1; then
                _bootstrap_ok=1
                break
            fi

            if [ -n "$root_pass" ] && sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@${ip}" "$bootstrap_cmd" >/dev/null 2>&1; then
                _bootstrap_ok=1
                break
            fi

            if [ "${_attempt}" -eq 1 ] || [ $(( _attempt % 6 )) -eq 0 ]; then
                print_step "SSH bootstrap waiting on ${ip} (attempt ${_attempt}/${ssh_bootstrap_retries})..."
            fi
            sleep "${ssh_bootstrap_delay}"
        done

        if [ "${_bootstrap_ok}" -ne 1 ]; then
            print_warning "SSH bootstrap failed for ${ip} as ${installer_user} and root after ${ssh_bootstrap_retries} attempts."
            return 1
        fi
    done

    # Ensure root keypair exists on every node.
    bootstrap_root_cmd='set -e; install -d -m 700 /root/.ssh; if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa; fi; touch /root/.ssh/authorized_keys; [ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/id_rsa 2>/dev/null || true; chmod 644 /root/.ssh/id_rsa.pub 2>/dev/null || true; chmod 600 /root/.ssh/authorized_keys'
    bootstrap_root_via_admin_cmd="sudo -n bash -lc '$(printf '%s' "${bootstrap_root_cmd}" | sed "s/'/'\\''/g")'"
    read_root_pub_via_admin_cmd="sudo -n cat /root/.ssh/id_rsa.pub"
    print_step "Bootstrapping root SSH keys on RHIS nodes"
    for ip in "${node_ips[@]}"; do
        if [ -n "$root_pass" ]; then
            if sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" "$bootstrap_root_cmd" >/dev/null 2>&1; then
                :
            elif [ -n "${installer_pass}" ] && sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" "${bootstrap_root_via_admin_cmd}" >/dev/null 2>&1; then
                print_step "Root SSH bootstrap on ${ip} completed via ${installer_user} + sudo fallback."
            else
                print_warning "Root SSH bootstrap failed for ${ip} via direct root and ${installer_user} + sudo fallback."
                if [ "${root_mesh_required}" -eq 1 ]; then
                    return 1
                fi
                root_mesh_failures=$((root_mesh_failures + 1))
                continue
            fi
        else
            if [ -n "${installer_pass}" ] && sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" "${bootstrap_root_via_admin_cmd}" >/dev/null 2>&1; then
                print_step "Root SSH bootstrap on ${ip} completed via ${installer_user} + sudo fallback."
            else
                print_warning "Root password unavailable and ${installer_user} + sudo fallback failed; cannot bootstrap root SSH keys on ${ip}."
                if [ "${root_mesh_required}" -eq 1 ]; then
                    return 1
                fi
                root_mesh_failures=$((root_mesh_failures + 1))
                continue
            fi
        fi
    done

    print_step "Collecting ${installer_user} public keys for full mesh trust"
    for ip in "${node_ips[@]}"; do
        pub="$(sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" 'target_home="$(getent passwd "'"${installer_user}"'" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/'"${installer_user}"'"; cat "$target_home/.ssh/id_rsa.pub"' 2>/dev/null || true)"
        if [ -z "$pub" ] && [ -n "$root_pass" ]; then
            pub="$(sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" 'target_home="$(getent passwd "'"${installer_user}"'" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/'"${installer_user}"'"; cat "$target_home/.ssh/id_rsa.pub"' 2>/dev/null || true)"
        fi
        if [ -z "$pub" ]; then
            print_warning "Could not read ${installer_user} SSH public key from ${ip}."
            return 1
        fi
        all_pubs+=("$pub")
    done

    [ -n "${local_installer_pub}" ] && all_pubs+=("${local_installer_pub}")

    print_step "Distributing trusted keys to all nodes (${installer_user}-to-${installer_user} mesh)"
    for ip in "${node_ips[@]}"; do
        for pub in "${all_pubs[@]}"; do
            append_cmd="target_home=\"\$(getent passwd '${installer_user}' | cut -d: -f6)\"; [ -n \"\$target_home\" ] || target_home=\"/home/${installer_user}\"; printf '%s\\n' '$pub' >> \"\$target_home/.ssh/authorized_keys\"; sort -u \"\$target_home/.ssh/authorized_keys\" -o \"\$target_home/.ssh/authorized_keys\"; chown '${installer_user}:${installer_user}' \"\$target_home/.ssh/authorized_keys\"; chmod 600 \"\$target_home/.ssh/authorized_keys\""
            if ! sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" "$append_cmd" >/dev/null 2>&1; then
                if [ -n "$root_pass" ]; then
                    sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" "$append_cmd" >/dev/null 2>&1 || {
                        print_warning "Failed to distribute SSH key to ${ip} as ${installer_user} and root."
                        return 1
                    }
                else
                    print_warning "Failed to distribute SSH key to ${ip} as ${installer_user}; root fallback unavailable."
                    return 1
                fi
            fi
        done
    done

    # Ensure install host installer user trusts all VM installer keys too.
    for pub in "${all_pubs[@]}"; do
        printf '%s\n' "$pub" >> "${HOME}/.ssh/authorized_keys"
    done
    sort -u "${HOME}/.ssh/authorized_keys" -o "${HOME}/.ssh/authorized_keys" || true
    chmod 600 "${HOME}/.ssh/authorized_keys" || true

    # Explicit install-host user trust push to admin@{satellite,idm,aap} and root@{satellite,idm,aap}
    if [ -n "${local_installer_pub}" ] && [ -f "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        local i push_ip push_name pub_b64
        pub_b64="$(printf '%s' "${local_installer_pub}" | base64 -w0 2>/dev/null || true)"
        for i in 0 1 2; do
            push_ip="${node_ips[$i]}"
            push_name="${node_names[$i]}"

            # install-host user -> admin
            if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${installer_pass}" ]; then
                sshpass -p "${installer_pass}" ssh-copy-id -i "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" \
                    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
                    "${installer_user}@${push_ip}" >/dev/null 2>&1 || true
            fi
            if [ -n "${pub_b64}" ]; then
                append_cmd="target_home=\"\$(getent passwd '${installer_user}' | cut -d: -f6)\"; [ -n \"\$target_home\" ] || target_home=\"/home/${installer_user}\"; install -d -m 700 -o '${installer_user}' -g '${installer_user}' \"\$target_home/.ssh\"; touch \"\$target_home/.ssh/authorized_keys\"; printf '%s' '${pub_b64}' | base64 -d >> \"\$target_home/.ssh/authorized_keys\"; sort -u \"\$target_home/.ssh/authorized_keys\" -o \"\$target_home/.ssh/authorized_keys\"; chown '${installer_user}:${installer_user}' \"\$target_home/.ssh/authorized_keys\"; chmod 600 \"\$target_home/.ssh/authorized_keys\""
                sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${push_ip}" "$append_cmd" >/dev/null 2>&1 || true
            fi

            # install-host user -> root
            if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${root_pass}" ]; then
                sshpass -p "${root_pass}" ssh-copy-id -i "${RHIS_INSTALLER_SSH_PUBLIC_KEY}" \
                    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
                    "root@${push_ip}" >/dev/null 2>&1 || true
            fi
            if [ -n "${pub_b64}" ] && [ -n "${root_pass}" ]; then
                append_root_cmd="install -d -m 700 /root/.ssh; touch /root/.ssh/authorized_keys; printf '%s' '${pub_b64}' | base64 -d >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys"
                sshpass -p "${root_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@${push_ip}" "$append_root_cmd" >/dev/null 2>&1 || true
            fi

            print_step "Install-host key synchronized to admin/root on ${push_name} (${push_ip})"
        done
    fi

    print_step "Collecting root public keys for full root mesh trust"
    for ip in "${node_ips[@]}"; do
        pub=""
        if [ -n "$root_pass" ]; then
            pub="$(sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" 'cat /root/.ssh/id_rsa.pub' 2>/dev/null || true)"
        fi
        if [ -z "$pub" ] && [ -n "${installer_pass}" ]; then
            pub="$(sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" "${read_root_pub_via_admin_cmd}" 2>/dev/null || true)"
            [ -n "$pub" ] && print_step "Collected root SSH public key from ${ip} via ${installer_user} + sudo fallback."
        fi
        if [ -z "$pub" ]; then
            print_warning "Could not read root SSH public key from ${ip}."
            if [ "${root_mesh_required}" -eq 1 ]; then
                return 1
            fi
            root_mesh_failures=$((root_mesh_failures + 1))
            continue
        fi
        root_pubs+=("$pub")
    done
    [ -n "${local_root_pub}" ] && root_pubs+=("${local_root_pub}")

    if [ "${#root_pubs[@]}" -gt 0 ]; then
        print_step "Distributing trusted root keys to all nodes (root-to-root mesh)"
        for ip in "${node_ips[@]}"; do
            for pub in "${root_pubs[@]}"; do
                append_root_cmd="printf '%s\\n' '$pub' >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys"
                if [ -n "$root_pass" ] && sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" "$append_root_cmd" >/dev/null 2>&1; then
                    :
                elif [ -n "${installer_pass}" ] && sshpass -p "${installer_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${installer_user}@${ip}" "sudo -n bash -lc '$(printf '%s' "${append_root_cmd}" | sed "s/'/'\\''/g")'" >/dev/null 2>&1; then
                    :
                else
                    print_warning "Failed to distribute root SSH key to ${ip} via direct root and ${installer_user} + sudo fallback."
                    if [ "${root_mesh_required}" -eq 1 ]; then
                        return 1
                    fi
                    root_mesh_failures=$((root_mesh_failures + 1))
                fi
            done
        done
    else
        print_warning "No root SSH public keys were collected; skipping root-to-root mesh distribution."
        root_mesh_failures=$((root_mesh_failures + 1))
    fi

    # Ensure install host root trusts all VM root keys too.
    if [ -n "${local_root_pub}" ] && command -v sudo >/dev/null 2>&1; then
        for pub in "${root_pubs[@]}"; do
            sudo bash -lc "printf '%s\\n' '$pub' >> /root/.ssh/authorized_keys" >/dev/null 2>&1 || true
        done
        sudo bash -lc 'sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys' >/dev/null 2>&1 || true
    fi

    if [ "${root_mesh_failures}" -gt 0 ]; then
        print_warning "RHIS SSH mesh configured with ${root_mesh_failures} root-mesh issue(s). Installer-user mesh is active; root mesh is best-effort."
    else
        print_success "RHIS SSH mesh configured: ${installer_user} and root SSH trust established across install host + all RHIS nodes."
    fi
    return 0
}

validate_rhis_ssh_mesh() {
    local root_pass installer_user installer_pass
    local src_name src_ip dst_name dst_ip
    local validation_cmd
    local failures=0
    local -a node_specs

    root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    installer_user="${INSTALLER_USER:-${ADMIN_USER}}"
    installer_pass="${ADMIN_PASS:-}"
    if [ -z "$installer_pass" ] && [ -z "$root_pass" ]; then
        print_warning "Cannot validate SSH mesh: installer/admin and root passwords are both unset."
        return 1
    fi

    node_specs=(
        "${SAT_HOSTNAME}:${SAT_IP}"
        "${AAP_HOSTNAME}:${AAP_IP}"
        "${IDM_HOSTNAME}:${IDM_IP}"
    )

    print_step "Validating RHIS SSH mesh (${installer_user}-to-${installer_user} key auth across all nodes)"
    for src in "${node_specs[@]}"; do
        src_name="${src%%:*}"
        src_ip="${src##*:}"
        for dst in "${node_specs[@]}"; do
            dst_name="${dst%%:*}"
            dst_ip="${dst##*:}"
            validation_cmd="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 ${installer_user}@${dst_ip} 'echo ok:${dst_name}'"
            if sshpass -p "$installer_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ${installer_user}@"$src_ip" "$validation_cmd" >/dev/null 2>&1; then
                print_step "SSH mesh OK: ${src_name} -> ${dst_name}"
            elif [ -n "$root_pass" ] && sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$src_ip" "$validation_cmd" >/dev/null 2>&1; then
                print_step "SSH mesh OK via root fallback: ${src_name} -> ${dst_name}"
            else
                print_warning "SSH mesh FAILED: ${src_name} -> ${dst_name}"
                failures=$((failures + 1))
            fi
        done
    done

    if [ -n "$root_pass" ]; then
        print_step "Validating RHIS root SSH mesh (root-to-root key auth across all nodes)"
        for src in "${node_specs[@]}"; do
            src_name="${src%%:*}"
            src_ip="${src##*:}"
            for dst in "${node_specs[@]}"; do
                dst_name="${dst%%:*}"
                dst_ip="${dst##*:}"
                validation_cmd="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@${dst_ip} 'echo ok-root:${dst_name}'"
                if sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$src_ip" "$validation_cmd" >/dev/null 2>&1; then
                    print_step "Root SSH mesh OK: ${src_name} -> ${dst_name}"
                else
                    print_warning "Root SSH mesh FAILED: ${src_name} -> ${dst_name}"
                    failures=$((failures + 1))
                fi
            done
        done
    fi

    if [ "$failures" -ne 0 ]; then
        print_warning "SSH mesh validation completed with ${failures} failure(s)."
        return 1
    fi

    print_success "SSH mesh validation complete: installer and root SSH trust is functional across RHIS nodes."
    return 0
}

ensure_rhis_vms_powered_on() {
    local vm state
    local -a vms=("satellite-618" "aap-26" "idm")

    print_step "Ensuring Satellite/AAP/IdM are ON and autostart-enabled"
    for vm in "${vms[@]}"; do
        if ! sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            print_warning "VM not defined (skipping power policy): $vm"
            continue
        fi

        sudo virsh autostart "$vm" >/dev/null 2>&1 || true
        state="$(sudo virsh domstate "$vm" 2>/dev/null | tr -d '[:space:]' || true)"
        if [ "$state" != "running" ]; then
            print_step "Starting VM: $vm"
            sudo virsh start "$vm" >/dev/null 2>&1 || true
        fi
        state="$(sudo virsh domstate "$vm" 2>/dev/null | tr -d '[:space:]' || true)"
        print_step "VM state: $vm => ${state:-unknown}"
    done
}

setup_virt_manager() {
    print_step "Setting up Virt-Manager"
    configure_libvirt_firewall_policy
    enable_virt_manager_xml_editor
    enable_virt_manager_resize_guest
    configure_libvirt_networks
    download_rhel10_iso || true

    if is_noninteractive; then
        build_vms="Y"
        print_step "NONINTERACTIVE mode: defaulting to create Satellite/AAP/IdM VMs now."
    else
        read -r -p "Create Satellite/AAP VMs now? [Y/n]: " build_vms
    fi
    case "${build_vms:-Y}" in
        Y|y|"") create_rhis_vms || print_warning "VM creation did not complete." ;;
        *) print_warning "Skipping VM creation." ;;
    esac

    print_success "Virt-Manager setup complete"
}

ensure_libvirtd() {
	if ! command -v libvirtd >/dev/null 2>&1; then
		print_warning "libvirtd not found. Installing..."
        sudo dnf install -y --nogpgcheck libvirt libvirt-daemon
	fi

	sudo systemctl enable libvirtd
	sudo systemctl start libvirtd

	if ! sudo systemctl is-active --quiet libvirtd; then
		print_warning "libvirtd is not running. Attempting restart..."
		sudo systemctl restart libvirtd || return 1
	fi

	print_success "libvirtd is installed, enabled, and running"
}

# ISO image tools check
ensure_iso_tools() {
	if command -v genisoimage >/dev/null 2>&1 || command -v xorriso >/dev/null 2>&1; then
		print_success "ISO image tools available (genisoimage or xorriso)"
		return 0
	fi

	print_step "Installing ISO image creation tools..."
    sudo dnf install -y --nogpgcheck genisoimage xorriso

	command -v genisoimage >/dev/null 2>&1 || command -v xorriso >/dev/null 2>&1
}

ensure_workspace_runtime_layout() {
    print_step "Ensuring generated RHIS runtime layout exists under ${SCRIPT_DIR}"

    mkdir -p "${RHIS_INVENTORY_DIR}" "${RHIS_HOST_VARS_DIR}" "${SCRIPT_DIR}/container/rhis-playbooks-from-container" "${SCRIPT_DIR}/Doc" || return 1

    # Placeholders are intentionally minimal; real content is generated on run.
    [ -f "${RHIS_INVENTORY_DIR}/README.md" ] || printf '%s\n' "# Generated by rhis_install.sh" > "${RHIS_INVENTORY_DIR}/README.md"
    [ -f "${RHIS_HOST_VARS_DIR}/README.md" ] || printf '%s\n' "# Generated by rhis_install.sh" > "${RHIS_HOST_VARS_DIR}/README.md"
    [ -f "${SCRIPT_DIR}/Doc/README.md" ] || printf '%s\n' "# Generated by rhis_install.sh" > "${SCRIPT_DIR}/Doc/README.md"

    return 0
}

ensure_platform_packages_for_virt_manager() {
    print_step "Ensuring installer-host platform packages for libvirt/virt-manager are installed"
    sudo dnf install -y --nogpgcheck \
        libvirt \
        libvirt-daemon \
        libvirt-client \
        qemu-kvm \
        virt-install \
        qemu-img \
        virt-manager \
        virt-viewer \
        python3-pip || return 1

    # Keep pip path available for optional Python helpers used by RHIS flows.
    python3 -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
    return 0
}

rhis_required_ansible_collections() {
    cat <<'EOF'
ansible.posix
community.general
freeipa.ansible_freeipa
infra.aap_configuration
infra.aap_utilities
infra.ah_configuration
infra.controller_configuration
infra.eda_configuration
infra.ee_utilities
redhat.rhel_system_roles
redhat.satellite
redhat.satellite_operations
EOF
}

check_missing_installer_host_ansible_collections() {
    local c
    local -a collections
    local -a missing=()
    local timeout_sec=20
    local collection_list_cache=""

    mapfile -t collections < <(rhis_required_ansible_collections)

    if ! command -v ansible-galaxy >/dev/null 2>&1; then
        print_warning "ansible-galaxy is not installed yet; collection visibility check skipped."
        print_warning "Expected required collections (${#collections[@]}):"
        for c in "${collections[@]}"; do
            echo "  - ${c}"
        done
        return 0
    fi

    print_step "Pre-flight: checking installer-host required collections (timeout: ${timeout_sec}s)"
    collection_list_cache="$(timeout ${timeout_sec} ansible-galaxy collection list 2>/dev/null | awk '{print $1}' || true)"

    for c in "${collections[@]}"; do
        if ! echo "${collection_list_cache}" | grep -qx "${c}"; then
            missing+=("${c}")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        print_success "Pre-flight collection visibility: all required collections are already installed."
    else
        print_warning "Pre-flight collection visibility: ${#missing[@]} missing collection(s):"
        for c in "${missing[@]}"; do
            echo "  - ${c}"
        done
    fi

    return 0
}

ensure_installer_host_ansible_collections() {
    local cfg
    local c
    local installed=0
    local failed=0
    local server
    local -a collections
    local collection_list_cache=""
    local timeout_sec=30

    print_step "Ensuring required Ansible collections are installed on installer host"

    if ! command -v ansible-galaxy >/dev/null 2>&1; then
        print_step "Installing ansible-core for host-side collection management"
        sudo dnf install -y --nogpgcheck ansible-core || return 1
    fi

    generate_rhis_ansible_cfg || true
    cfg="${RHIS_ANSIBLE_CFG_HOST}"

    # Required collections (normalized, unique, and alphabetically sorted).
    # NOTE: `eda_configuration` has been normalized to `infra.eda_configuration`.
    mapfile -t collections < <(rhis_required_ansible_collections)

    # Cache collection list once with timeout to avoid repeated Galaxy queries
    print_step "Querying local Ansible collection cache (timeout: ${timeout_sec}s)..."
    collection_list_cache="$(timeout ${timeout_sec} ansible-galaxy collection list 2>/dev/null | awk '{print $1}' || true)"

    for c in "${collections[@]}"; do
        # Check cached list first (no network)
        if echo "${collection_list_cache}" | grep -qx "${c}"; then
            continue
        fi

        # Try to install from each server with timeout
        for server in published validated community_galaxy; do
            print_step "Attempting to install ${c} from ${server}..."
            if timeout ${timeout_sec} bash -c "ANSIBLE_CONFIG='${cfg}' ansible-galaxy collection install '${c}' --server '${server}'" >/dev/null 2>&1; then
                installed=$((installed + 1))
                print_step "  ✓ Installed ${c}"
                break
            fi
        done

        # Final check with timeout to see if collection is now available
        if ! timeout ${timeout_sec} ansible-galaxy collection list 2>/dev/null | awk '{print $1}' | grep -qx "${c}"; then
            failed=$((failed + 1))
            print_warning "Collection install unresolved on installer host: ${c} (tried published/validated/community_galaxy)"
        fi
    done

    if [ "${failed}" -eq 0 ]; then
        print_success "Installer-host collections verified (installed new: ${installed})."
    else
        print_warning "Installer-host collection check complete with ${failed} unresolved collection(s). Consider installing manually: ansible-galaxy collection install -r requirements.yml"
    fi

    return 0
}

main() {
    init_rhis_run_logging

    parse_args "$@"
    apply_cli_overrides

    # CLI-only fast path: DEMOKILL should never require env/vault prompts.
    if [ -n "${CLI_DEMOKILL:-}" ]; then
        command -v clear >/dev/null 2>&1 && clear
        print_step "DEMOKILL requested from CLI; skipping credential prompts"
        demokill_cleanup || { print_warning "DEMOKILL failed"; exit 1; }
        command -v clear >/dev/null 2>&1 && clear
        print_success "Run complete"
        exit 0
    fi

    if [ ! -f "$ANSIBLE_ENV_FILE" ]; then
        load_preseed_env
    fi
    load_ansible_env_file
    normalize_shared_env_vars

    ensure_workspace_runtime_layout || {
        print_warning "Could not initialize generated workspace runtime layout."
        exit 1
    }

    if [ -n "${CLI_STATUS:-}" ]; then
        print_phase 1 1 "Read-only status snapshot"
        print_runtime_configuration
        print_rhis_health_summary
        RHIS_DASHBOARD_SINGLE_SHOT=1
        show_live_status_dashboard || true
        RHIS_DASHBOARD_SINGLE_SHOT=0
        print_success "Status snapshot complete"
        exit 0
    fi

    prompt_all_env_options_once
    RHIS_PROMPTS_COMPLETED=1
    FORCE_PROMPT_ALL=0
    normalize_shared_env_vars
    retire_preseed_env_file
    print_runtime_configuration

	print_step "Startup: Checking libvirtd"
	ensure_libvirtd || { print_warning "libvirtd check failed"; exit 1; }

	print_step "Startup: Checking ISO image tools"
	ensure_iso_tools || { print_warning "ISO image tools check failed"; exit 1; }

    print_step "Startup: Ensuring installer-host platform packages"
    ensure_platform_packages_for_virt_manager || { print_warning "Installer-host package check failed"; exit 1; }

    print_step "Startup: Pre-flight collection visibility"
    check_missing_installer_host_ansible_collections || true

    print_step "Startup: Ensuring installer-host Ansible collections"
    ensure_installer_host_ansible_collections || print_warning "Installer-host collection install encountered issues; continuing."

    if [ -n "${CLI_TEST:-}" ]; then
        if rhis_run_test_suite; then
            print_success "Run complete"
            exit 0
        fi
        exit 1
    fi

	while true; do
		show_menu
		case "$choice" in
			1) install_local ;;
            2) install_container; run_container_prescribed_sequence ;;
			3) setup_virt_manager ;;
			4) install_local; setup_virt_manager ;;
            5) install_container; setup_virt_manager ;;
            6) generate_satellite_oemdrv_only ;;
            7) run_container_config_only || { print_warning "Container config-only workflow failed"; exit 1; } ;;
            8) show_live_status_dashboard ;;
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "Exiting installation script"
                exit 0
                ;;
        *) print_warning "Invalid choice. Please select 0-8." ;;
		esac

        if is_noninteractive || [ "${RUN_ONCE:-0}" = "1" ]; then
            print_success "Run complete"
            exit 0
        fi

		echo ""
	done
}

main "$@"

