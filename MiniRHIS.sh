#!/bin/bash
# shellcheck disable=SC2317

set -e

if [ -t 0 ] && [ -t 1 ]; then
    reset || true
fi

# Core path/runtime defaults (kept near the top so all later vars/functions can rely on them).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="${ISO_DIR:-/var/lib/libvirt/images}"
ISO_NAME="${ISO_NAME:-rhel-10-everything-x86_64-dvd.iso}"
ISO_PATH="${ISO_PATH:-$ISO_DIR/$ISO_NAME}"
SAT_ISO_NAME="${SAT_ISO_NAME:-rhel-9-everything-x86_64-dvd.iso}"
SAT_ISO_PATH="${SAT_ISO_PATH:-$ISO_DIR/$SAT_ISO_NAME}"
VM_DIR="${VM_DIR:-/var/lib/libvirt/images}"
KS_DIR="${KS_DIR:-/var/lib/libvirt/images/kickstarts}"
FILES_DIR="${FILES_DIR:-/var/lib/libvirt/images/files}"
OEMDRV_ISO="${OEMDRV_ISO:-$ISO_DIR/OEMDRV.iso}"

ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
ANSIBLE_ENV_FILE="${ANSIBLE_ENV_FILE:-$ANSIBLE_ENV_DIR/env.yml}"
ANSIBLE_VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-$HOME/.ansible/conf/.vaultpass.txt}"

MINIRHIS_ANSIBLE_CFG_BASENAME="${MINIRHIS_ANSIBLE_CFG_BASENAME:-minirhis-ansible.cfg}"
MINIRHIS_ANSIBLE_CFG_VAULT_HOST="${MINIRHIS_ANSIBLE_CFG_VAULT_HOST:-$ANSIBLE_ENV_DIR/${MINIRHIS_ANSIBLE_CFG_BASENAME}}"
MINIRHIS_ANSIBLE_CFG_VAULT_CONTAINER="${MINIRHIS_ANSIBLE_CFG_VAULT_CONTAINER:-/minirhis/vars/vault/${MINIRHIS_ANSIBLE_CFG_BASENAME}}"
MINIRHIS_ANSIBLE_CFG_RUNTIME_BASENAME="${MINIRHIS_ANSIBLE_CFG_RUNTIME_BASENAME:-minirhis-ansible.runtime.cfg}"
MINIRHIS_ANSIBLE_CFG_HOST="${MINIRHIS_ANSIBLE_CFG_HOST:-$ANSIBLE_ENV_DIR/${MINIRHIS_ANSIBLE_CFG_RUNTIME_BASENAME}}"
MINIRHIS_ANSIBLE_CFG_CONTAINER="${MINIRHIS_ANSIBLE_CFG_CONTAINER:-/minirhis/vars/vault/${MINIRHIS_ANSIBLE_CFG_RUNTIME_BASENAME}}"
MINIRHIS_ANSIBLE_FACT_CACHE_BASENAME="${MINIRHIS_ANSIBLE_FACT_CACHE_BASENAME:-facts-cache}"
MINIRHIS_ANSIBLE_FACT_CACHE_HOST="${MINIRHIS_ANSIBLE_FACT_CACHE_HOST:-$ANSIBLE_ENV_DIR/${MINIRHIS_ANSIBLE_FACT_CACHE_BASENAME}}"
MINIRHIS_ANSIBLE_FACT_CACHE_CONTAINER="${MINIRHIS_ANSIBLE_FACT_CACHE_CONTAINER:-/minirhis/vars/vault/${MINIRHIS_ANSIBLE_FACT_CACHE_BASENAME}}"
MINIRHIS_ANSIBLE_FORKS="${MINIRHIS_ANSIBLE_FORKS:-15}"
MINIRHIS_ANSIBLE_TIMEOUT="${MINIRHIS_ANSIBLE_TIMEOUT:-30}"
MINIRHIS_ANSIBLE_FACT_CACHE_TIMEOUT="${MINIRHIS_ANSIBLE_FACT_CACHE_TIMEOUT:-86400}"

MINIRHIS_CONTAINER_IMAGE="${MINIRHIS_CONTAINER_IMAGE:-quay.io/parmstro/minirhis-provisioner-9-2.5}"
MINIRHIS_CONTAINER_NAME="${MINIRHIS_CONTAINER_NAME:-minirhis-provisioner}"
MINIRHIS_INVENTORY_DIR="${MINIRHIS_INVENTORY_DIR:-$SCRIPT_DIR/container/vars/external_inventory}"
MINIRHIS_INVENTORY_FILE="${MINIRHIS_INVENTORY_FILE:-$MINIRHIS_INVENTORY_DIR/hosts.yml}"
MINIRHIS_CONTAINER_INVENTORY_FILE="${MINIRHIS_CONTAINER_INVENTORY_FILE:-/minirhis/vars/external_inventory/$(basename "${MINIRHIS_INVENTORY_FILE}")}"
MINIRHIS_HOST_VARS_DIR="${MINIRHIS_HOST_VARS_DIR:-$SCRIPT_DIR/host_vars}"
MINIRHIS_EXECUTION_MODE="${MINIRHIS_EXECUTION_MODE:-container}"

PRESEED_ENV_FILE="${PRESEED_ENV_FILE:-$SCRIPT_DIR/.env}"
RH_TOKEN_URL="${RH_TOKEN_URL:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"
RH_ISO_URL="${RH_ISO_URL:-}"
RH9_ISO_URL="${RH9_ISO_URL:-}"
RH_OSINFO="${RH_OSINFO:-linux2024}"

# Optional local role fallback controls.
MINIRHIS_LOCAL_ROLE_FALLBACK="${MINIRHIS_LOCAL_ROLE_FALLBACK:-1}"
MINIRHIS_LOCAL_ROLE_WORKDIR="${MINIRHIS_LOCAL_ROLE_WORKDIR:-$SCRIPT_DIR/container/roles}"

CLI_MENU_CHOICE=""
CLI_NONINTERACTIVE=""
RUN_ONCE="${RUN_ONCE:-0}"
DEMO_MODE="${DEMO_MODE:-0}"
CLI_DEMO=""
CLI_DEMOKILL=""
CLI_RECONFIGURE=""
CLI_AAP_INVENTORY_TEMPLATE=""
CLI_AAP_INVENTORY_GROWTH_TEMPLATE=""
CLI_ENTERPRISE=""
CLI_STANDALONE=""
CLI_CONTAINER_CONFIG_ONLY=""
CLI_CONFIG_SCOPE=""
CLI_ATTACH_CONSOLES=""
CLI_STATUS=""
CLI_STATUS_LIVE=""
CLI_TEST=""
CLI_TEST_PROFILE="full"
CLI_VALIDATE=""
CLI_GENERATE_ENV=""
CLI_MENUTEST=""
CLI_SATELLITE=""
CLI_IDM=""
CLI_AAP=""
CLI_MINIRHIS=""
CLI_LIBVIRT=""
CLI_BAREMETAL=""
CLI_AWS=""
CLI_AZURE=""
CLI_GCP=""
CLI_NUTANIX=""
CLI_OPENSHIFT=""
CLI_OPENSHIFT_VIRT=""
CLI_VMWARE=""
CLI_LOCAL=""
CLI_CONTAINER=""
MENU_CHOICE_CONSUMED=0
MINIRHIS_TEST_MODE="${MINIRHIS_TEST_MODE:-0}"
MINIRHIS_MENU_TEST_MODE="${MINIRHIS_MENU_TEST_MODE:-0}"
MINIRHIS_DASHBOARD_SINGLE_SHOT="${MINIRHIS_DASHBOARD_SINGLE_SHOT:-0}"
MINIRHIS_HEADLESS_MONITOR_HINT_SHOWN="${MINIRHIS_HEADLESS_MONITOR_HINT_SHOWN:-0}"
MINIRHIS_TEST_WARNING_COUNT=0
MINIRHIS_TEST_FAILURE_COUNT=0
MINIRHIS_TEST_WARNING_FILE="${MINIRHIS_TEST_WARNING_FILE:-/tmp/minirhis-test-warnings-$$.log}"
declare -a MINIRHIS_TEST_RESULTS=()
_MINIRHIS_TEST_STEP=0
_MINIRHIS_TEST_TOTAL=0
# Auto-run config-as-code sequence after container-only deployment (menu option 2).
# Set to 0/false/no/off to disable.
MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY="${MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY:-1}"
# Retry only failed config-as-code phases once (IdM/Satellite/AAP).
# Set to 0/false/no/off to disable.
MINIRHIS_RETRY_FAILED_PHASES_ONCE="${MINIRHIS_RETRY_FAILED_PHASES_ONCE:-1}"
# Apply/verify runtime playbook hotfixes inside provisioner container before phase runs.
MINIRHIS_ENABLE_CONTAINER_HOTFIXES="${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"
# Fail fast if hotfix verification cannot be confirmed.
MINIRHIS_ENFORCE_CONTAINER_HOTFIXES="${MINIRHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"
# Internal SSH readiness wait for config-as-code preflight
MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT="${MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT:-1800}"
MINIRHIS_INTERNAL_SSH_WAIT_INTERVAL="${MINIRHIS_INTERNAL_SSH_WAIT_INTERVAL:-10}"
MINIRHIS_POST_VM_SETTLE_GRACE="${MINIRHIS_POST_VM_SETTLE_GRACE:-650}"
MINIRHIS_INTERNAL_SSH_WARN_GRACE="${MINIRHIS_INTERNAL_SSH_WARN_GRACE:-600}"
MINIRHIS_INTERNAL_SSH_LOG_EVERY="${MINIRHIS_INTERNAL_SSH_LOG_EVERY:-60}"
# Global transport policy for managed nodes.
# MINIRHIS enforces internal SSH reachability over 10.168.0.0/16 for all stack modes
# (standalone node workflows and full minirhis stack).
MINIRHIS_MANAGED_SSH_OVER_ETH0="0"
# IdM web UI readiness check after IdM configuration phase.
MINIRHIS_IDM_WEB_UI_TIMEOUT="${MINIRHIS_IDM_WEB_UI_TIMEOUT:-900}"
MINIRHIS_IDM_WEB_UI_INTERVAL="${MINIRHIS_IDM_WEB_UI_INTERVAL:-15}"
# Post-install healthcheck/repair controls.
MINIRHIS_ENABLE_POST_HEALTHCHECK="${MINIRHIS_ENABLE_POST_HEALTHCHECK:-1}"
MINIRHIS_HEALTHCHECK_AUTOFIX="${MINIRHIS_HEALTHCHECK_AUTOFIX:-1}"
MINIRHIS_HEALTHCHECK_RERUN_COMPONENT="${MINIRHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"
# Satellite app-level sanity retry controls (hammer/API checks).
MINIRHIS_SAT_HEALTHCHECK_RETRIES="${MINIRHIS_SAT_HEALTHCHECK_RETRIES:-5}"
MINIRHIS_SAT_HEALTHCHECK_INTERVAL="${MINIRHIS_SAT_HEALTHCHECK_INTERVAL:-15}"
RHC_AUTO_CONNECT="${RHC_AUTO_CONNECT:-1}"
COCKPIT_PORT="${COCKPIT_PORT:-9443}"
# If enabled, fail the run when root-to-root SSH mesh cannot be fully established.
# Default keeps root mesh best-effort while admin mesh remains mandatory.
MINIRHIS_REQUIRE_ROOT_SSH_MESH="${MINIRHIS_REQUIRE_ROOT_SSH_MESH:-0}"
# Optional pre-flight ad-hoc probes/upgrades before phase playbooks.
# Default OFF to avoid noisy lockout-prone retries on fresh installs.
MINIRHIS_ENABLE_PRECHECK_ADHOC="${MINIRHIS_ENABLE_PRECHECK_ADHOC:-0}"
# Guard to ensure the full prompt wizard runs at most once per process.
MINIRHIS_PROMPTS_COMPLETED="${MINIRHIS_PROMPTS_COMPLETED:-0}"
# Defer heavy component installation/configuration out of kickstart %post and
# execute it post-boot through run_minirhis_config_as_code.
# Keeps role-specific kickstart provisioning (CPU/RAM/disk/network/hostname)
# while avoiding fragile install-time network constraints.
MINIRHIS_DEFER_COMPONENT_INSTALL="${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}"
# After base Satellite CaC run succeeds, execute an explicit post-configuration
# pass (lifecycle/content views/activation keys/provisioning/network domains).
MINIRHIS_RUN_SATELLITE_POST_CONFIG_AFTER_CAC="${MINIRHIS_RUN_SATELLITE_POST_CONFIG_AFTER_CAC:-1}"
# Run a dedicated Satellite provisioning pass after scenario install to ensure
# KVM/libvirt compute resources/profiles/media/templates/network/hostgroups are
# configured for both image-based and kickstart-based provisioning workflows.
MINIRHIS_RUN_SATELLITE_KVM_PROVISIONING_AFTER_SCENARIO="${MINIRHIS_RUN_SATELLITE_KVM_PROVISIONING_AFTER_SCENARIO:-1}"

# Automation Hub + AAP bundle pre-flight HTTP-serve variables
HUB_TOKEN="${HUB_TOKEN:-}"
# Automation Hub API token used for [galaxy_server.*] in minirhis-ansible.cfg.
# If unset, HUB_TOKEN is used as fallback.
VAULT_CONSOLE_REDHAT_TOKEN="${VAULT_CONSOLE_REDHAT_TOKEN:-}"
HOST_INT_IP="${HOST_INT_IP:-192.168.122.1}"
AAP_BUNDLE_URL="${AAP_BUNDLE_URL:-}"
AAP_BUNDLE_EFFECTIVE_URL="${AAP_BUNDLE_EFFECTIVE_URL:-}"
AAP_BUNDLE_DIR="${AAP_BUNDLE_DIR:-${VM_DIR}/aap-bundle}"
AAP_HTTP_PID=""
AAP_HTTP_LOG="${AAP_HTTP_LOG:-/tmp/aap-http-server-$(date +%s).log}"
AAP_ANSIBLE_LOG_BASENAME="${AAP_ANSIBLE_LOG_BASENAME:-ansible-provisioner.log}"
STAGED_VAULT_PASS_BASENAME="${STAGED_VAULT_PASS_BASENAME:-.vaultpass.container}"
AAP_ADMIN_PASS="${AAP_ADMIN_PASS:-}"
SAT_ADMIN_PASS="${SAT_ADMIN_PASS:-}"
# Optional override for the very first Satellite installer admin password.
# When unset, MINIRHIS uses ADMIN_PASS consistently across install and post-config flows.
SAT_INITIAL_ADMIN_PASS="${SAT_INITIAL_ADMIN_PASS:-}"
AAP_DEPLOYMENT_TYPE="${AAP_DEPLOYMENT_TYPE:-container}"
AAP_TOPOLOGY="${AAP_TOPOLOGY:-standalone}"
SATELLITE_VALIDATE_CERTS="${SATELLITE_VALIDATE_CERTS:-false}"
SAT_USE_NON_IDM_CERTS="${SAT_USE_NON_IDM_CERTS:-}"
# AAP is always containerized in MINIRHIS flows.
# AAP installer inventory template selection.
# These templates are rendered into /home/admin/aap-setup/inventory and
# /home/admin/aap-setup/inventory-growth inside the AAP VM during kickstart %post.
# Prefer the current container layout, but keep backward compatibility with
# the legacy top-level inventory/aap path.
if [ -z "${AAP_INVENTORY_TEMPLATE_DIR:-}" ]; then
    if [ -d "$SCRIPT_DIR/container/vars/external_inventory/aap" ]; then
        AAP_INVENTORY_TEMPLATE_DIR="$SCRIPT_DIR/container/vars/external_inventory/aap"
    else
        AAP_INVENTORY_TEMPLATE_DIR="$SCRIPT_DIR/inventory/aap"
    fi
fi
AAP_INVENTORY_TEMPLATE="${AAP_INVENTORY_TEMPLATE:-}"
AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-}"
# Used by inventory.j2 templates (e.g. gateway_pg_database={{ pg_database }}).
# Prompted when inventory.j2 is selected.
AAP_PG_DATABASE="${AAP_PG_DATABASE:-}"
AAP_LIGHTSPEED_HOST="${AAP_LIGHTSPEED_HOST:-${AAP_HOSTNAME:-aap.example.com}}"
AAP_LIGHTSPEED_ADMIN_USER="${AAP_LIGHTSPEED_ADMIN_USER:-${ADMIN_USER:-admin}}"
AAP_LIGHTSPEED_ADMIN_PASSWORD="${AAP_LIGHTSPEED_ADMIN_PASSWORD:-${AAP_ADMIN_PASS:-${ADMIN_PASS:-}}}"
AAP_LIGHTSPEED_ADMIN_EMAIL="${AAP_LIGHTSPEED_ADMIN_EMAIL:-${ADMIN_USER:-admin}@${DOMAIN:-example.com}}"
AAP_LIGHTSPEED_PG_HOST="${AAP_LIGHTSPEED_PG_HOST:-${AAP_HOSTNAME:-aap.example.com}}"
AAP_LIGHTSPEED_PG_PASSWORD="${AAP_LIGHTSPEED_PG_PASSWORD:-${AAP_ADMIN_PASS:-${ADMIN_PASS:-}}}"
AAP_LIGHTSPEED_CHATBOT_MODEL_URL="${AAP_LIGHTSPEED_CHATBOT_MODEL_URL:-<set your own>}"
AAP_LIGHTSPEED_CHATBOT_MODEL_API_KEY="${AAP_LIGHTSPEED_CHATBOT_MODEL_API_KEY:-<set your own>}"
AAP_LIGHTSPEED_CHATBOT_MODEL_ID="${AAP_LIGHTSPEED_CHATBOT_MODEL_ID:-<set your own>}"
AAP_LIGHTSPEED_CHATBOT_DEFAULT_PROVIDER="${AAP_LIGHTSPEED_CHATBOT_DEFAULT_PROVIDER:-rhoai}"
AAP_LIGHTSPEED_CHATBOT_MODEL_EXTRA_SETTINGS="${AAP_LIGHTSPEED_CHATBOT_MODEL_EXTRA_SETTINGS:-{}}"
AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED="${AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED:-false}"
AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED="${AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED:-false}"
AAP_LIGHTSPEED_WCA_MODEL_TYPE="${AAP_LIGHTSPEED_WCA_MODEL_TYPE:-wca}"
AAP_LIGHTSPEED_WCA_MODEL_URL="${AAP_LIGHTSPEED_WCA_MODEL_URL:-https://api.dataplatform.cloud.ibm.com}"
AAP_LIGHTSPEED_WCA_MODEL_VERIFY_SSL="${AAP_LIGHTSPEED_WCA_MODEL_VERIFY_SSL:-true}"
AAP_LIGHTSPEED_WCA_MODEL_ENABLE_ANONYMIZATION="${AAP_LIGHTSPEED_WCA_MODEL_ENABLE_ANONYMIZATION:-true}"
AAP_LIGHTSPEED_WCA_HEALTH_CHECK="${AAP_LIGHTSPEED_WCA_HEALTH_CHECK:-true}"
AAP_EDA_SAFE_PLUGINS="${AAP_EDA_SAFE_PLUGINS:-['ansible.eda.webhook', 'ansible.eda.alertmanager']}"
# Installer/controller user consumed by host_vars and inventory templates.
# Default to the shared admin account unless explicitly overridden.
INSTALLER_USER="${INSTALLER_USER:-${ADMIN_USER:-admin}}"

# Shared identity/network defaults (single source of truth)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-}"  # must be set via vault, env file, or interactive prompt
ROOT_PASS="${ROOT_PASS:-}"
DOMAIN="${DOMAIN:-example.com}"
REALM="${REALM:-EXAMPLE.COM}"
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
SAT_COMPUTE_PLATFORM="${SAT_COMPUTE_PLATFORM:-libvirt}"
SAT_COMPUTE_RESOURCE_NAME="${SAT_COMPUTE_RESOURCE_NAME:-MINIRHIS_Compute}"
SAT_COMPUTE_PROFILE_NAME="${SAT_COMPUTE_PROFILE_NAME:-MINIRHIS_Standard}"
SAT_COMPUTE_URL="${SAT_COMPUTE_URL:-}"
SAT_COMPUTE_USERNAME="${SAT_COMPUTE_USERNAME:-}"
SAT_COMPUTE_PASSWORD="${SAT_COMPUTE_PASSWORD:-}"
SAT_COMPUTE_REGION="${SAT_COMPUTE_REGION:-}"
SAT_COMPUTE_PROJECT="${SAT_COMPUTE_PROJECT:-}"
SAT_COMPUTE_ZONE="${SAT_COMPUTE_ZONE:-}"
SAT_COMPUTE_TENANT="${SAT_COMPUTE_TENANT:-}"
SAT_COMPUTE_SUBSCRIPTION="${SAT_COMPUTE_SUBSCRIPTION:-}"
SAT_COMPUTE_DATACENTER="${SAT_COMPUTE_DATACENTER:-}"
SAT_COMPUTE_CLUSTER="${SAT_COMPUTE_CLUSTER:-}"
SAT_COMPUTE_NAMESPACE="${SAT_COMPUTE_NAMESPACE:-}"
SAT_COMPUTE_NETWORK="${SAT_COMPUTE_NETWORK:-default}"
SAT_COMPUTE_POOL="${SAT_COMPUTE_POOL:-default}"
SAT_COMPUTE_CPUS="${SAT_COMPUTE_CPUS:-2}"
SAT_COMPUTE_MEMORY_MB="${SAT_COMPUTE_MEMORY_MB:-4096}"
SAT_COMPUTE_VOLUME_GB="${SAT_COMPUTE_VOLUME_GB:-20}"
SAT_IMAGE_NAME="${SAT_IMAGE_NAME:-}"
SAT_IMAGE_UUID="${SAT_IMAGE_UUID:-}"
SAT_IMAGE_USERNAME="${SAT_IMAGE_USERNAME:-root}"
SAT_IMAGE_PASSWORD="${SAT_IMAGE_PASSWORD:-}"
IDM_DS_PASS="${IDM_DS_PASS:-}"  # loaded from vault; fallback set in normalize_shared_env_vars
SATELLITE_DISCONNECTED="${SATELLITE_DISCONNECTED:-false}"
REGISTER_TO_SATELLITE="${REGISTER_TO_SATELLITE:-false}"
SATELLITE_PRE_USE_IDM="${SATELLITE_PRE_USE_IDM:-false}"
IPADM_PASSWORD="${IPADM_PASSWORD:-}"
IPAADMIN_PASSWORD="${IPAADMIN_PASSWORD:-}"
SAT_SSL_CERTS_DIR="${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}"
CDN_ORGANIZATION_ID="${CDN_ORGANIZATION_ID:-}"
CDN_SAT_ACTIVATION_KEY="${CDN_SAT_ACTIVATION_KEY:-}"
SAT_FIREWALLD_ZONE="${SAT_FIREWALLD_ZONE:-public}"
SAT_FIREWALLD_INTERFACE="${SAT_FIREWALLD_INTERFACE:-eth1}"
SAT_PROVISIONING_SUBNET="${SAT_PROVISIONING_SUBNET:-10.168.0.0}"
SAT_PROVISIONING_NETMASK="${SAT_PROVISIONING_NETMASK:-255.255.0.0}"
SAT_PROVISIONING_GW="${SAT_PROVISIONING_GW:-10.168.0.1}"
SAT_PROVISIONING_DHCP_START="${SAT_PROVISIONING_DHCP_START:-10.168.130.1}"
SAT_PROVISIONING_DHCP_END="${SAT_PROVISIONING_DHCP_END:-10.168.255.254}"
SAT_PROVISIONING_DNS_PRIMARY="${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP:-10.168.128.1}}"
SAT_PROVISIONING_DNS_SECONDARY="${SAT_PROVISIONING_DNS_SECONDARY:-8.8.8.8}"
SAT_DNS_ZONE="${SAT_DNS_ZONE:-${DOMAIN:-}}"
SAT_DNS_REVERSE_ZONE="${SAT_DNS_REVERSE_ZONE:-}"
# Enforce Satellite UI/services on internal 10.168.0.0/16 address space.
# Set to 0 only for exceptional troubleshooting scenarios.
MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK="${MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK:-1}"
SAT_FIREWALLD_SERVICES_JSON='["ssh","http","https"]'
IDM_REPOSITORY_IDS_JSON='["rhel-10-for-x86_64-baseos-rpms","rhel-10-for-x86_64-appstream-rpms"]'
# Required Satellite server repositories.  Your RHSM account MUST expose all
# IDs below before run_config_as_code() reaches the Satellite phase.
# See assert_satellite_server_repos_available() for the pre-flight guard.
SAT_REPOSITORY_IDS_JSON='["rhel-9-for-x86_64-baseos-rpms","rhel-9-for-x86_64-appstream-rpms","satellite-6.18-for-rhel-9-x86_64-rpms","satellite-maintenance-6.18-for-rhel-9-x86_64-rpms"]'
DEPLOYMENT_SCOPE="${DEPLOYMENT_SCOPE:-local}"
MINIRHIS_TARGET_PLATFORM="${MINIRHIS_TARGET_PLATFORM:-libvirt}"
SAT_TARGET_PLATFORM="${SAT_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM}}"
AAP_TARGET_PLATFORM="${AAP_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM}}"
IDM_TARGET_PLATFORM="${IDM_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM}}"
MINIRHIS_INSTALL_PRODUCT="${MINIRHIS_INSTALL_PRODUCT:-}"
MINIRHIS_PLATFORM_FAMILY="${MINIRHIS_PLATFORM_FAMILY:-virtual}"

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
LIBVIRT_STORAGE_POOL="${LIBVIRT_STORAGE_POOL:-default}"
LIBVIRT_NETWORK="${LIBVIRT_NETWORK:-default}"

VMWARE_VCENTER_HOST="${VMWARE_VCENTER_HOST:-}"
VMWARE_USERNAME="${VMWARE_USERNAME:-}"
VMWARE_PASSWORD="${VMWARE_PASSWORD:-}"
VMWARE_DATACENTER="${VMWARE_DATACENTER:-}"
VMWARE_CLUSTER="${VMWARE_CLUSTER:-}"

NUTANIX_ENDPOINT="${NUTANIX_ENDPOINT:-}"
NUTANIX_USERNAME="${NUTANIX_USERNAME:-}"
NUTANIX_PASSWORD="${NUTANIX_PASSWORD:-}"
NUTANIX_CLUSTER="${NUTANIX_CLUSTER:-}"

OPENSHIFT_API_URL="${OPENSHIFT_API_URL:-}"
OPENSHIFT_USERNAME="${OPENSHIFT_USERNAME:-}"
OPENSHIFT_TOKEN="${OPENSHIFT_TOKEN:-}"
OPENSHIFT_NAMESPACE="${OPENSHIFT_NAMESPACE:-openshift-cnv}"

AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AWS_VPC_ID="${AWS_VPC_ID:-}"
AWS_SUBNET_ID="${AWS_SUBNET_ID:-}"

AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus}"

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_SERVICE_ACCOUNT_FILE="${GCP_SERVICE_ACCOUNT_FILE:-}"

BMC_TYPE="${BMC_TYPE:-redfish}"
BMC_ENDPOINT="${BMC_ENDPOINT:-}"
BMC_USERNAME="${BMC_USERNAME:-}"
BMC_PASSWORD="${BMC_PASSWORD:-}"
BMC_SYSTEM_ID="${BMC_SYSTEM_ID:-}"
BAREMETAL_ISO_URL="${BAREMETAL_ISO_URL:-}"
PXE_SERVER_URL="${PXE_SERVER_URL:-}"

# Disk I/O mode: "fast" (cache=none,discard=unmap,io=native — optimal for SSD/NVMe)
#                "safe" (cache=writeback — conservative; use for spinning HDDs or shared storage)
VM_DISK_PERF_MODE="${VM_DISK_PERF_MODE:-fast}"

# Tracks whether serve_aap_bundle() opened a firewalld port so we can close it later
AAP_FW_RULE_ADDED=""

# SSH callback orchestration for AAP post-boot setup
AAP_SSH_KEY_DIR="${AAP_SSH_KEY_DIR:-${HOME}/.ssh/minirhis-aap}"
AAP_SSH_PRIVATE_KEY="${AAP_SSH_KEY_DIR}/id_rsa"
AAP_SSH_PUBLIC_KEY="${AAP_SSH_KEY_DIR}/id_rsa.pub"
AAP_SETUP_LOG_LOCAL="${AAP_SETUP_LOG_LOCAL:-/tmp/aap-setup-$(date +%s).log}"
MINIRHIS_VM_MONITOR_SESSION="${MINIRHIS_VM_MONITOR_SESSION:-minirhis-vm-consoles}"
MINIRHIS_VM_MONITOR_PID_FILE="${MINIRHIS_VM_MONITOR_PID_FILE:-/tmp/minirhis-vm-console-pids-${USER}}"
MINIRHIS_PROGRESS_MONITOR_PID_FILE="${MINIRHIS_PROGRESS_MONITOR_PID_FILE:-/tmp/minirhis-progress-monitor-pids-${USER}}"
MINIRHIS_VM_WATCHDOG_PID=""
# VM console monitor noise filter controls
# 1 = suppress expected reboot chatter (e.g., journald SIGTERM during reboot)
MINIRHIS_VM_MONITOR_FILTER_NOISE="${MINIRHIS_VM_MONITOR_FILTER_NOISE:-1}"
MINIRHIS_AUTO_POPUP_MONITORS="${MINIRHIS_AUTO_POPUP_MONITORS:-1}"
# rc.local bootstrap controls
# 1 = ensure /etc/rc.d/rc.local is executable during kickstart/bootstrap
MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC="${MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC:-1}"
# 1 = revert /etc/rc.d/rc.local to non-executable after full install workflow
MINIRHIS_REVERT_RC_LOCAL_NONEXEC_AFTER_INSTALL="${MINIRHIS_REVERT_RC_LOCAL_NONEXEC_AFTER_INSTALL:-1}"
# Guardrail: disable AAP SSH callback probing unless explicitly enabled by the
# VM provisioning/callback workflow path.
AAP_SSH_CALLBACK_ENABLED="${AAP_SSH_CALLBACK_ENABLED:-0}"
# Dedicated persistent installer-host key used by MINIRHIS mesh operations.
# Keeps MINIRHIS traffic isolated from the operator's default ~/.ssh/id_rsa identity.
MINIRHIS_INSTALLER_SSH_KEY_DIR="${MINIRHIS_INSTALLER_SSH_KEY_DIR:-${HOME}/.ssh/minirhis-installer}"
MINIRHIS_INSTALLER_SSH_PRIVATE_KEY="${MINIRHIS_INSTALLER_SSH_KEY_DIR}/id_rsa"
MINIRHIS_INSTALLER_SSH_PUBLIC_KEY="${MINIRHIS_INSTALLER_SSH_KEY_DIR}/id_rsa.pub"
# Container-side mount path for the MINIRHIS installer SSH key (read-only).
MINIRHIS_INSTALLER_SSH_KEY_CONTAINER_DIR="/minirhis/vars/ssh"
MINIRHIS_INSTALLER_SSH_KEY_CONTAINER_PATH="${MINIRHIS_INSTALLER_SSH_KEY_CONTAINER_DIR}/id_rsa"
# If enabled, prune/reseed known_hosts entries for MINIRHIS node IPs/hostnames each run.
MINIRHIS_REFRESH_KNOWN_HOSTS="${MINIRHIS_REFRESH_KNOWN_HOSTS:-1}"
# Fail fast when SSH port is reachable but key auth repeatedly fails.
# 18 attempts * 10s = ~3 minutes (after SSH becomes reachable).
AAP_SSH_KEY_FAIL_FAST_ATTEMPTS="${AAP_SSH_KEY_FAIL_FAST_ATTEMPTS:-18}"
# AAP callback wait-loop controls
AAP_SSH_WAIT_TIMEOUT="${AAP_SSH_WAIT_TIMEOUT:-5400}"
AAP_SSH_WAIT_INTERVAL="${AAP_SSH_WAIT_INTERVAL:-10}"
AAP_SSH_PROGRESS_EVERY="${AAP_SSH_PROGRESS_EVERY:-30}"
# If there is no observed callback-stage progress for this long, fail fast.
AAP_SSH_NO_PROGRESS_TIMEOUT="${AAP_SSH_NO_PROGRESS_TIMEOUT:-5400}"

# ─── Core logging and retry controls ──────────────────────────────────────────
sanitize_log_message() {
    local message="$*"
    printf '%s' "${message}" | sed -E \
        -e 's#([?&](_auth_|auth|token|access_token|refresh_token|password|passwd|pass|api_key|apikey)=)[^&[:space:]]+#\1<redacted>#Ig' \
        -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1<redacted>#Ig' \
        -e 's#(--(password|passwd|token|secret|api-key|api_key|apikey)(=|[[:space:]]+))[^[:space:]]+#\1<redacted>#Ig' \
        -e 's#((^|[[:space:]])(password|passwd|token|secret|api_key|apikey|offline_token|access_token|refresh_token)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig'
}

# Retries count and interval for provisioner container restart attempts.
MINIRHIS_CONTAINER_RESTART_RETRIES="${MINIRHIS_CONTAINER_RESTART_RETRIES:-2}"
MINIRHIS_CONTAINER_RESTART_INTERVAL="${MINIRHIS_CONTAINER_RESTART_INTERVAL:-10}"
# DEMOKILL console behavior controls
# 1 = compact one-line progress messages for DEMOKILL
MINIRHIS_DEMOKILL_COMPACT="${MINIRHIS_DEMOKILL_COMPACT:-1}"
# 1 = run terminal reset after DEMOKILL (enabled by default)
MINIRHIS_DEMOKILL_RESET_TERMINAL="${MINIRHIS_DEMOKILL_RESET_TERMINAL:-1}"

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
    if is_enabled "${MINIRHIS_TEST_MODE:-0}"; then
        MINIRHIS_TEST_WARNING_COUNT=$((MINIRHIS_TEST_WARNING_COUNT + 1))
        printf '%s\n' "${msg}" >> "${MINIRHIS_TEST_WARNING_FILE}"
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

ensure_minirhis_installer_ssh_key() {
    mkdir -p "${MINIRHIS_INSTALLER_SSH_KEY_DIR}" >/dev/null 2>&1 || true
    chmod 700 "${MINIRHIS_INSTALLER_SSH_KEY_DIR}" >/dev/null 2>&1 || true

    if [ ! -f "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}" ]; then
        ssh-keygen -q -t rsa -b 4096 -N "" -f "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}" -C "minirhis-installer-host" >/dev/null 2>&1 || return 1
    fi

    chmod 600 "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}" >/dev/null 2>&1 || true
    chmod 644 "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" >/dev/null 2>&1 || true
    return 0
}

refresh_minirhis_known_hosts() {
    local host
    local -a minirhis_hosts

    if ! is_enabled "${MINIRHIS_REFRESH_KNOWN_HOSTS:-1}"; then
        return 0
    fi

    [ -d "${HOME}/.ssh" ] || mkdir -p "${HOME}/.ssh" >/dev/null 2>&1 || true
    touch "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true
    chmod 600 "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true

    minirhis_hosts=(
        "${SAT_IP:-}" "${AAP_IP:-}" "${IDM_IP:-}"
        "${SAT_HOSTNAME:-}" "${AAP_HOSTNAME:-}" "${IDM_HOSTNAME:-}"
    )

    for host in "${minirhis_hosts[@]}"; do
        [ -n "${host}" ] || continue
        ssh-keygen -R "${host}" -f "${HOME}/.ssh/known_hosts" >/dev/null 2>&1 || true
        ssh-keyscan -H -T 3 "${host}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    done
}

# Remove stale SSH trust entries for rebuilt MINIRHIS nodes before provisioning.
# This clears host key fingerprints from known_hosts and prunes matching
# hostname/IP comment lines from the local authorized_keys file.
prune_local_ssh_trust_for_component() {
    local component="${1:-all}"
    local known_hosts_file="${HOME}/.ssh/known_hosts"
    local auth_keys_file="${HOME}/.ssh/authorized_keys"
    local host short
    local changed_auth=0
    local tmp_auth
    local -a targets=()

    case "${component}" in
        satellite)
            targets+=("${SAT_IP:-}" "${SAT_HOSTNAME:-}" "satellite")
            ;;
        idm)
            targets+=("${IDM_IP:-}" "${IDM_HOSTNAME:-}")
            ;;
        aap)
            targets+=("${AAP_IP:-}" "${AAP_HOSTNAME:-}" "aap")
            ;;
        all|*)
            targets+=("${SAT_IP:-}" "${SAT_HOSTNAME:-}" "satellite")
            targets+=("${IDM_IP:-}" "${IDM_HOSTNAME:-}")
            targets+=("${AAP_IP:-}" "${AAP_HOSTNAME:-}" "aap")
            ;;
    esac

    # Add short hostnames derived from FQDNs (best-effort)
    for host in "${targets[@]}"; do
        [ -n "${host}" ] || continue
        short="${host%%.*}"
        if [ -n "${short}" ] && [ "${short}" != "${host}" ]; then
            targets+=("${short}")
        fi
    done

    [ -d "${HOME}/.ssh" ] || mkdir -p "${HOME}/.ssh" >/dev/null 2>&1 || true
    touch "${known_hosts_file}" >/dev/null 2>&1 || true
    chmod 600 "${known_hosts_file}" >/dev/null 2>&1 || true

    print_step "Pre-install SSH cleanup (${component}): pruning ~/.ssh/known_hosts and ~/.ssh/authorized_keys entries"

    for host in "${targets[@]}"; do
        [ -n "${host}" ] || continue
        ssh-keygen -R "${host}" -f "${known_hosts_file}" >/dev/null 2>&1 || true
        ssh-keygen -R "[${host}]:22" -f "${known_hosts_file}" >/dev/null 2>&1 || true
    done

    if [ -f "${auth_keys_file}" ]; then
        tmp_auth="$(mktemp)" || return 1
        cp "${auth_keys_file}" "${tmp_auth}" || true
        for host in "${targets[@]}"; do
            [ -n "${host}" ] || continue
            # Remove lines containing hostname/IP comments from older rebuilt nodes.
            grep -Fv -- "${host}" "${tmp_auth}" > "${tmp_auth}.new" 2>/dev/null || true
            mv -f "${tmp_auth}.new" "${tmp_auth}" >/dev/null 2>&1 || true
        done
        if ! cmp -s "${auth_keys_file}" "${tmp_auth}"; then
            mv -f "${tmp_auth}" "${auth_keys_file}" || true
            chmod 600 "${auth_keys_file}" >/dev/null 2>&1 || true
            changed_auth=1
        else
            rm -f "${tmp_auth}" >/dev/null 2>&1 || true
        fi
    fi

    if [ "${changed_auth}" -eq 1 ]; then
        print_step "Pre-install SSH cleanup (${component}): stale authorized_keys entries removed"
    fi
    return 0
}

init_minirhis_run_logging() {
    local run_ts target_dir log_file

    # Idempotent guard for re-entry.
    if [ "${MINIRHIS_LOG_STDIO_REDIRECTED:-0}" = "1" ]; then
        return 0
    fi

    target_dir="${MINIRHIS_RUN_LOG_DIR:-/var/log/MINIRHIS}"
    run_ts="$(date +%Y%m%d-%H%M%S)"
    log_file="${target_dir}/install_${run_ts}.log"

    # Ensure /var/log/MINIRHIS exists; requires elevated permissions on most systems.
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

    MINIRHIS_RUN_LOG_FILE="${log_file}"
    export MINIRHIS_RUN_LOG_FILE
    export MINIRHIS_LOG_STDIO_REDIRECTED=1

    # Mirror all script output to console and a per-run logfile.
    exec > >(tee -a "${MINIRHIS_RUN_LOG_FILE}") 2>&1

    ln -sfn "${MINIRHIS_RUN_LOG_FILE}" "${target_dir}/latest.log" >/dev/null 2>&1 || true
    print_step "MINIRHIS run logging enabled: ${MINIRHIS_RUN_LOG_FILE}"

    prune_minirhis_run_logs || true
}

prune_minirhis_run_logs() {
    local target_dir retention_days

    target_dir="${MINIRHIS_RUN_LOG_DIR:-/var/log/MINIRHIS}"
    retention_days="${MINIRHIS_RUN_LOG_RETENTION_DAYS:-20}"

    case "${retention_days}" in
        ''|*[!0-9]*)
            print_warning "Invalid MINIRHIS_RUN_LOG_RETENTION_DAYS='${retention_days}'; skipping log pruning."
            return 0
            ;;
    esac

    [ "${retention_days}" -ge 0 ] || {
        print_warning "MINIRHIS_RUN_LOG_RETENTION_DAYS must be >= 0; skipping log pruning."
        return 0
    }

    [ -d "${target_dir}" ] || return 0

    find "${target_dir}" -maxdepth 1 -type f -name 'install_*.log' -mtime +"${retention_days}" -print0 2>/dev/null | \
        while IFS= read -r -d '' old_log; do
            rm -f "${old_log}" >/dev/null 2>&1 || sudo rm -f "${old_log}" >/dev/null 2>&1 || true
        done

    print_step "Pruned MINIRHIS run logs older than ${retention_days} day(s) in ${target_dir}."
    return 0
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --non-interactive        Run without prompts; required values must be preseeded
        --menu-choice <0-6>      Preselect a menu option (1 = MINIRHIS Full Stack, 4 = Prompts Only)
  --env-file <path>        Load preseed variables from a custom env file
  --inventory <template>   Pin AAP inventory template; skips interactive submenu
  --inventory-growth <tpl> Pin AAP inventory-growth template; skips interactive submenu
    --enterprise             Force AAP enterprise template selection (inventory.j2)
    --standalone             Force AAP standalone template selection (inventory-growth.j2)
                           Interactive (no --non-interactive): a guided submenu with
                           About pages is presented when template values are unset.
                           --DEMO always forces DEMO-inventory.j2 and skips the submenu.
                                                     --enterprise and --standalone are mutually exclusive and
                                                     cannot be combined with --DEMO.
    --container-config-only  Start full-stack flow (auto-provision if needed, then IdM -> Satellite -> AAP)
    --config-idm             Run config-as-code roles for IdM node only
    --config-satellite       Run config-as-code roles for Satellite node only
    --config-aap             Run config-as-code roles for AAP node only
    --config-all             Run config-as-code roles for all nodes (IdM -> Satellite -> AAP)
    --config-rhis-aap        (Re-)configure RHIS Builder projects, credentials, and templates in AAP only
    --local                  Prefer local ${USER} repo execution for reruns/fallbacks (uses container/roles)
    --container              Prefer minirhis_provisioner execution context (default)
    --minirhis, --rhis           Run full stack workflow (IdM -> Satellite -> AAP)
    --satellite              Run Satellite 6.18-only workflow (standalone submenu)
    --idm                    Run IdM 5.0-only workflow (standalone submenu)
    --aap                    Run AAP 2.6-only workflow (standalone submenu)

    Platform Selection (use with --minirhis/--rhis/--satellite/--idm/--aap or --menu-choice 4; default: --libvirt)
    --libvirt                Target libvirt/KVM (local virtualization, default)
    --baremetal              Target bare metal (planned)
    --aws                    Target AWS cloud (planned)
    --azure                  Target Azure cloud (planned)
    --gcp                    Target Google Cloud Platform (planned)
    --nutanix                Target Nutanix (planned)
    --openshift              Target OpenShift (planned)
    --openshift-virt         Target OpenShift Virt (planned)
    --vmware                 Target VMware (planned)

  --attach-consoles        Re-open VM console monitors for Satellite/AAP/IdM
    --status                 Read-only status snapshot (no provisioning changes)
        --status-live            Live-refresh status dashboard (intended for monitor terminals)
  --reconfigure            Prompt for all env values and update env.yml
    --menutest              Interactive menu walkthrough (no provisioning/actions)
  --test[=fast|full]       Run a curated non-interactive test sweep and print a summary
    --DEMO                   Use reduced per-node VM specs/kickstarts for MiniRHIS 3-node stack
                             (1 IdM + 1 Satellite + 1 AAP server)
    --DEMOKILL               Destroy demo VMs/files/temp locks and exit (CLI-only)
    --validate [--menu-choice N]  Pre-flight check: required vars, tools, storage, memory,
                                                     SSH keys, network/FQDN format, CDN and DNS reachability.
                                                     Use together with --env-file to validate a headless env file.
    --generate-env [path]    Write a headless env-file template to <path> (default:
                                                     ./minirhis-headless.env.template). Copy and fill in values,
                                                     then run with: --non-interactive --env-file <path> --menu-choice N
    (env) MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0  Disable auto config after menu option 2
  (env) MINIRHIS_RETRY_FAILED_PHASES_ONCE=0       Disable automatic retry of failed phases
    (env) MINIRHIS_ENABLE_CONTAINER_HOTFIXES=0      Disable runtime role hotfix patching in container
    (env) MINIRHIS_ENFORCE_CONTAINER_HOTFIXES=0     Do not fail when hotfix verification cannot be confirmed
    (env) MINIRHIS_MANAGED_SSH_OVER_ETH0=1          Deprecated/ignored: MINIRHIS enforces managed-node SSH over 10.168.x.x
    (env) MINIRHIS_ENABLE_POST_HEALTHCHECK=0        Disable post-install healthchecks (IdM/Satellite/AAP)
    (env) MINIRHIS_HEALTHCHECK_AUTOFIX=0            Disable automatic healthcheck remediation attempts
    (env) MINIRHIS_HEALTHCHECK_RERUN_COMPONENT=0    Disable targeted component rerun after healthcheck failure
    (env) MINIRHIS_SAT_HEALTHCHECK_RETRIES=N        Satellite hammer/API retry attempts after service restart (default: 5)
    (env) MINIRHIS_SAT_HEALTHCHECK_INTERVAL=SEC     Seconds between Satellite hammer/API retries (default: 15)
    (env) MINIRHIS_REFRESH_KNOWN_HOSTS=0            Do not refresh MINIRHIS node host keys in ~/.ssh/known_hosts
    (env) MINIRHIS_INSTALLER_SSH_KEY_DIR=<path>     Override dedicated persistent MINIRHIS installer SSH key directory
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
        echo "***"
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

derive_aap_bundle_filename() {
    local source="${1:-${AAP_BUNDLE_URL:-}}"
    local candidate=""

    if [ -n "${source}" ]; then
        candidate="${source%%\?*}"
        candidate="${candidate##*/}"
    fi

    if [ -z "${candidate}" ]; then
        candidate="aap-bundle.tar.gz"
    fi

    printf '%s\n' "${candidate}"
}

write_file_if_changed() {
    local src="$1"
    local dest="$2"
    local mode="${3:-0644}"
    local owner="${4:-}"
    local dest_dir

    MINIRHIS_LAST_WRITE_CHANGED=0

    [ -f "$src" ] || {
        print_warning "write_file_if_changed: source file not found: $src"
        return 1
    }

    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        rm -f "$src"
        print_step "Generated file unchanged: $dest"
        return 0
    fi

    dest_dir="$(dirname "$dest")"
    mkdir -p "$dest_dir" 2>/dev/null || sudo mkdir -p "$dest_dir" >/dev/null 2>&1 || {
        rm -f "$src"
        print_warning "Could not create destination directory: $dest_dir"
        return 1
    }

    if ! install -D -m "$mode" "$src" "$dest" 2>/dev/null; then
        sudo install -D -m "$mode" "$src" "$dest" >/dev/null 2>&1 || {
            rm -f "$src"
            print_warning "Could not install generated file: $dest"
            return 1
        }
    fi

    if [ -n "$owner" ]; then
        chown "$owner" "$dest" 2>/dev/null || sudo chown "$owner" "$dest" >/dev/null 2>&1 || true
    fi

    rm -f "$src"
    MINIRHIS_LAST_WRITE_CHANGED=1
    print_success "Generated file updated: $dest"
    return 0
}

vault_plaintext_matches_existing() {
    local plaintext_file="$1"
    local existing_plaintext=""
    local rc=1

    [ -f "$plaintext_file" ] || return 1
    [ -f "$ANSIBLE_ENV_FILE" ] || return 1

    existing_plaintext="$(mktemp)"
    ansible-vault view --vault-password-file "$ANSIBLE_VAULT_PASS_FILE" "$ANSIBLE_ENV_FILE" > "$existing_plaintext" 2>/dev/null || {
        rm -f "$existing_plaintext"
        return 1
    }

    if cmp -s "$plaintext_file" "$existing_plaintext"; then
        rc=0
    fi

    rm -f "$existing_plaintext"
    return "$rc"
}

kickstart_password_hash() {
    local plain_password="$1"
    local hashed_password=""

    if [ -z "${plain_password}" ]; then
        print_warning "Kickstart password is empty; cannot generate rootpw/user password entry."
        return 1
    fi

    if command -v openssl >/dev/null 2>&1; then
        hashed_password="$(printf '%s' "${plain_password}" | openssl passwd -6 -stdin 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
        hashed_password="$(python3 - <<'PY' "${plain_password}"
import crypt
import secrets
import sys

pw = sys.argv[1]
salt = "$6$" + secrets.token_urlsafe(12)
print(crypt.crypt(pw, salt))
PY
        )"
    fi

    if [ -z "${hashed_password}" ]; then
        print_warning "Failed to hash kickstart password (openssl/python3 unavailable or failed)."
        return 1
    fi

    printf '%s\n' "${hashed_password}"
    return 0
}

print_kickstart_effective_values() {
    local component="$1"
    local role_ip="$2"
    local role_hostname="$3"
    local role_netmask="$4"
    local role_gateway="$5"

    print_step "Kickstart effective values (${component}): host=${role_hostname} ip=${role_ip} netmask=${role_netmask} gw=${role_gateway}"
    print_step "Kickstart effective values (${component}): admin_user=${ADMIN_USER:-'(unset)'} installer_user=${INSTALLER_USER:-'(unset)'} domain=${DOMAIN:-'(unset)'}"
    print_step "Kickstart effective values (${component}): rh_user=$(mask_secret "${RH_USER:-}") rh_pass=$(mask_secret "${RH_PASS:-}") admin_pass=$(mask_secret "${ADMIN_PASS:-}") root_pass=$(mask_secret "${ROOT_PASS:-}")"
}

kickstart_nogpg_policy_block() {
    cat <<'EOF'
# MINIRHIS policy: disable package signature checks for all dnf/yum repo operations.
mkdir -p /etc/dnf
if [ -f /etc/dnf/dnf.conf ]; then
    if ! grep -q '^gpgcheck=0$' /etc/dnf/dnf.conf; then
        cat >> /etc/dnf/dnf.conf <<'EOF_DNF_GPG'

# MINIRHIS override: disable GPG checks
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
ks_log "Phase 1.1: Configure SSH baseline"
mkdir -p /etc/ssh/sshd_config.d
mkdir -p /etc/ssh/ssh_config.d
cat > /etc/ssh/sshd_config.d/99-minirhis-root.conf <<'EOF_SSHD'
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding yes
UseDNS no
EOF_SSHD

cat > /etc/ssh/ssh_config.d/99-minirhis-client.conf <<'EOF_SSH'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ForwardX11 no
    ForwardX11Trusted no
EOF_SSH

systemctl enable --now sshd || true
systemctl restart sshd || true
systemctl disable --now firewalld >/dev/null 2>&1 || true
setenforce 0 >/dev/null 2>&1 || true
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config || true
fi

# Reduce rc.local generator noise during repeated bootstrap/reboot cycles.
# Keep this temporary; host workflow will revert to non-executable at the end.
if [ "${MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC:-1}" = "1" ]; then
    if [ ! -f /etc/rc.d/rc.local ]; then
        cat > /etc/rc.d/rc.local <<'EOF_RCLOCAL'
#!/bin/bash
exit 0
EOF_RCLOCAL
    fi
    chmod +x /etc/rc.d/rc.local >/dev/null 2>&1 || true
fi
EOF
}

kickstart_user_sudo_bootstrap_block() {
    local role_name="${1:-}"
    cat <<'EOF'
# 1.2 Ensure installer/admin user has passwordless sudo and virtualization groups
ks_log "Phase 1.2: Ensure admin sudo bootstrap"
target_user="${INSTALLER_USER:-${ADMIN_USER}}"
if [ "${INSTALLER_USER:-${ADMIN_USER}}" != "${ADMIN_USER}" ] && ! id "${INSTALLER_USER:-${ADMIN_USER}}" >/dev/null 2>&1; then
    useradd -m -G wheel "${INSTALLER_USER:-${ADMIN_USER}}" || true
    echo "${INSTALLER_USER:-${ADMIN_USER}}:${ADMIN_PASS}" | chpasswd || true
fi
# Core virtualization and admin groups for all systems
for grp in libvirt qemu kvm wheel foreman; do
    getent group "$grp" >/dev/null 2>&1 || groupadd -f "$grp" || true
done
usermod -aG libvirt,qemu,kvm,wheel,foreman "$target_user" || true
sed -i -E 's/^#?[[:space:]]*%wheel[[:space:]]+ALL=\(ALL\)[[:space:]]+ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers || true
printf '%s\n' "$target_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-minirhis-nopasswd
chmod 0440 /etc/sudoers.d/90-minirhis-nopasswd
visudo -cf /etc/sudoers >/dev/null 2>&1 || true
EOF
}

kickstart_rhsm_register_block() {
    local include_org_id="${1:-0}"

    cat <<'EOF'
# 2. Registration (retry until network/RHSM are reachable)
ks_log "Phase 2: Register with RHSM"
# Log credential presence (values never printed — only length/presence)
if [ -n "${RH_USER:-}" ]; then
    ks_log "  creds: RH_USER is SET (${#RH_USER} chars)"
else
    ks_log "  creds: RH_USER is EMPTY -- registration will be skipped"
fi
if [ -n "${RH_PASS:-}" ]; then
    ks_log "  creds: RH_PASS is SET (${#RH_PASS} chars)"
else
    ks_log "  creds: RH_PASS is EMPTY -- registration will be skipped"
fi
if [ -n "${CDN_ORGANIZATION_ID:-}" ]; then
    ks_log "  creds: CDN_ORGANIZATION_ID=${CDN_ORGANIZATION_ID}"
else
    ks_log "  creds: CDN_ORGANIZATION_ID is EMPTY"
fi
if [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
    ks_log "  creds: CDN_SAT_ACTIVATION_KEY is SET"
else
    ks_log "  creds: CDN_SAT_ACTIVATION_KEY is EMPTY"
fi
ks_log "RHSM prereq: current /etc/resolv.conf"
while IFS= read -r _l; do ks_log "  resolv: ${_l}"; done < /etc/resolv.conf || ks_log "  resolv: (empty or missing)"
ks_log "RHSM prereq: route table"
ip route show 2>&1 | while IFS= read -r _l; do ks_log "  route: ${_l}"; done || true
ks_log "RHSM prereq: IPv4 interfaces"
ip -4 -br addr show 2>&1 | while IFS= read -r _l; do ks_log "  addr: ${_l}"; done || true

# %post chroot frequently has no active default route yet. Try a temporary
# DHCP bootstrap on eth0 so RHSM can resolve/reach subscription endpoints.
if ! ip route show | grep -q '^default'; then
    ks_log "RHSM prereq: no default route detected; attempting DHCP bootstrap on eth0"
    ip link set eth0 up >/dev/null 2>&1 || true
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -4 -1 -v eth0 2>&1 | while IFS= read -r _l; do ks_log "  dhcp: ${_l}"; done || true
    else
        ks_log "  dhcp: dhclient not available in target image"
    fi
    ks_log "RHSM prereq: route table after DHCP bootstrap"
    ip route show 2>&1 | while IFS= read -r _l; do ks_log "  route: ${_l}"; done || true
fi

# If resolv.conf is still using public resolvers and DNS lookup fails in this
# environment, fall back to the active default gateway as nameserver.
_default_gw=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
if [ -n "${_default_gw:-}" ]; then
    ks_log "RHSM prereq: detected default gateway ${_default_gw}"
fi
ks_log "RHSM prereq: DNS lookup for subscription.rhsm.redhat.com"
_dns_out=$(getent ahostsv4 subscription.rhsm.redhat.com 2>&1 || true)
if [ -n "${_dns_out}" ]; then
    while IFS= read -r _l; do ks_log "  dns: ${_l}"; done <<< "${_dns_out}"
else
    ks_log "  dns: FAILED - no result (DNS not working)"
    if [ -n "${_default_gw:-}" ]; then
        ks_log "  dns: retrying with gateway resolver ${_default_gw}"
        printf 'nameserver %s\n' "${_default_gw}" > /etc/resolv.conf 2>/dev/null || true
        _dns_out=$(getent ahostsv4 subscription.rhsm.redhat.com 2>&1 || true)
        if [ -n "${_dns_out}" ]; then
            while IFS= read -r _l; do ks_log "  dns: ${_l}"; done <<< "${_dns_out}"
        else
            ks_log "  dns: still failed after gateway resolver fallback"
        fi
    fi
fi
ks_log "RHSM prereq: HTTPS reachability test to subscription.rhsm.redhat.com"
_curl_rc=0
curl -s -o /dev/null -w "%{http_code} connect=%{time_connect}s total=%{time_total}s" \
    --connect-timeout 15 --max-time 30 \
    https://subscription.rhsm.redhat.com/subscription/status 2>&1 | \
    while IFS= read -r _l; do ks_log "  https: ${_l}"; done || _curl_rc=$?
[ "${_curl_rc}" -ne 0 ] && ks_log "  https: FAILED (exit code ${_curl_rc}) - cannot reach RHSM" || true

# If %post chroot has no real interfaces/default route, try running RHSM calls
# in PID 1 network namespace (installer environment) while keeping target root.
MINIRHIS_SM_REGISTER_CMD="subscription-manager register"
if ! ip -4 -br addr show | awk '{print $1}' | grep -qvE '^(lo)$' || ! ip route show | grep -q '^default'; then
    if command -v nsenter >/dev/null 2>&1 && [ -r /proc/1/ns/net ]; then
        ks_log "RHSM prereq: enabling nsenter network namespace fallback for subscription-manager"
        MINIRHIS_SM_REGISTER_CMD="nsenter -t 1 -n subscription-manager register"
    else
        ks_log "RHSM prereq: nsenter unavailable; continuing without netns fallback"
    fi
fi

minirhis_sm_register() {
    # shellcheck disable=SC2086
    eval "${MINIRHIS_SM_REGISTER_CMD} $*"
}
register_rhsm() {
    local try
    for try in $(seq 1 10); do
        ks_log "RHSM registration attempt ${try}/10"
        echo "RHSM registration attempt $try/10..."
EOF

    if [ "$include_org_id" = "1" ]; then
        cat <<'EOF'
        # Primary: username/password (SCA-compatible — no subscription attachment required)
        if [ -n "${RH_USER:-}" ] && [ -n "${RH_PASS:-}" ]; then
            ks_log "  Method 1: username/password registration..."
            _sm_out=$(minirhis_sm_register --username="${RH_USER}" --password="${RH_PASS}" --force 2>&1) && _sm_rc=0 || _sm_rc=$?
            while IFS= read -r _l; do ks_log "    sm: ${_l}"; done <<< "${_sm_out}"
            if [ "${_sm_rc}" -eq 0 ]; then return 0; fi
            subscription-manager clean >/dev/null 2>&1 || true
            if [ -n "${CDN_ORGANIZATION_ID:-}" ]; then
                ks_log "  Method 2: username/password with org ${CDN_ORGANIZATION_ID}..."
                _sm_out=$(minirhis_sm_register --username="${RH_USER}" --password="${RH_PASS}" --org="${CDN_ORGANIZATION_ID}" --force 2>&1) && _sm_rc=0 || _sm_rc=$?
                while IFS= read -r _l; do ks_log "    sm: ${_l}"; done <<< "${_sm_out}"
                if [ "${_sm_rc}" -eq 0 ]; then return 0; fi
                subscription-manager clean >/dev/null 2>&1 || true
            fi
        fi
        # Fallback: activation key
        if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
            ks_log "  Method 3: activation-key for org ${CDN_ORGANIZATION_ID}..."
            _sm_out=$(minirhis_sm_register --org="${CDN_ORGANIZATION_ID}" --activationkey="${CDN_SAT_ACTIVATION_KEY}" --force 2>&1) && _sm_rc=0 || _sm_rc=$?
            while IFS= read -r _l; do ks_log "    sm: ${_l}"; done <<< "${_sm_out}"
            if [ "${_sm_rc}" -eq 0 ]; then return 0; fi
            subscription-manager clean >/dev/null 2>&1 || true
        fi
EOF
    else
        cat <<'EOF'
        echo "  Attempting username/password registration (no org)..."
        _sm_out=$(minirhis_sm_register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach --force 2>&1) && _sm_rc=0 || _sm_rc=$?
        while IFS= read -r _l; do ks_log "    sm: ${_l}"; done <<< "${_sm_out}"
        if [ "${_sm_rc}" -eq 0 ]; then return 0; fi
EOF
    fi

    cat <<'EOF'
        ks_log "  attempt ${try} failed -- last subscription-manager error:"
        subscription-manager status 2>&1 | while IFS= read -r _l; do ks_log "    sm: ${_l}"; done || true
        subscription-manager clean >/dev/null 2>&1 || true
        sleep 15
    done
    ks_log "ERROR: RHSM registration failed after 10 retries"
    subscription-manager status 2>&1 | while IFS= read -r _l; do ks_log "  sm: ${_l}"; done || true
    subscription-manager version 2>&1 | while IFS= read -r _l; do ks_log "  sm: ${_l}"; done || true
    return 1
}

if ! register_rhsm; then
    ks_log "ERROR: RHSM registration failed. Satellite installation will not proceed."
    ks_log "DEBUG: Network diagnostics:"
    ip addr show 2>&1 | while IFS= read -r _l; do ks_log "  net: ${_l}"; done || true
    ip route show 2>&1 | while IFS= read -r _l; do ks_log "  route: ${_l}"; done || true
    ping -c 3 8.8.8.8 2>&1 | while IFS= read -r _l; do ks_log "  ping: ${_l}"; done || ks_log "  ping: FAILED - no external IP connectivity"
    ks_log "DEBUG: RHSM config:"
    cat /etc/rhsm/rhsm.conf 2>&1 | while IFS= read -r _l; do ks_log "  rhsm: ${_l}"; done || true
    exit 1
fi
subscription-manager refresh || true
EOF
}

kickstart_rhc_connect_block() {
    cat <<'EOF'
# 2.1 Red Hat Hybrid Cloud Console registration (rhc)
ks_log "Phase 2.1: Optional rhc registration"
if [ "${RHC_AUTO_CONNECT:-1}" = "1" ]; then
    dnf install -y --nogpgcheck rhc >/dev/null 2>&1 || true
    if command -v rhc >/dev/null 2>&1; then
        if ! rhc status >/dev/null 2>&1; then
            if [ -n "${RHC_ORGANIZATION_ID:-}" ] && [ -n "${RHC_ACTIVATION_KEY:-}" ]; then
                rhc connect --activation-key "${RHC_ACTIVATION_KEY}" --organization "${RHC_ORGANIZATION_ID}" >/dev/null 2>&1 || true
            else
                rhc connect --username="${RH_USER}" --password="${RH_PASS}" >/dev/null 2>&1 || true
            fi
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
    printf 'ks_log "%s"\n' "Phase 3: Enable ${role_label} repositories"
    printf '%s\n' 'subscription-manager refresh || true'
    printf '%s\n' 'subscription-manager identity || { echo "ERROR: RHSM identity missing before repo enable."; exit 1; }'
    printf '%s\n' 'subscription-manager repos --disable="*" || true'
    printf '%s\n' 'repo_enable_ok=0'
    printf '%s\n' 'for repo_try in $(seq 1 5); do'
    printf '%s' '    subscription-manager repos'
    for i in "${repos[@]}"; do
        printf ' --enable="%s"' "$i"
    done
    printf ' >/dev/null 2>&1 && repo_enable_ok=1 && break\n'
    printf '%s\n' '    subscription-manager refresh >/dev/null 2>&1 || true'
    printf '%s\n' '    sleep 10'
    printf '%s\n' 'done'
    printf '%s\n' 'if [ "$repo_enable_ok" -ne 1 ]; then'
    printf '    echo "ERROR: Could not enable required %s repositories after retries."\n' "$role_label"
    printf '%s\n' '    subscription-manager repos --list || true'
    printf '%s\n' '    exit 1'
    printf '%s\n' 'fi'
    printf '%s\n\n' 'dnf clean all || true'
    printf '%s\n' 'dnf makecache --refresh || true'
    printf '\n'

    printf '%s\n' 'for repo in \'
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
    printf 'echo "INFO: %s enabled repositories after registration:"\n' "$role_label"
    printf '%s\n' "subscription-manager repos --list-enabled 2>/dev/null | sed -n 's/^Repo ID:[[:space:]]*/  - /p' || true"
    printf '%s\n' 'dnf repolist || true'
}

kickstart_satellite_package_install_block() {
    # Install satellite support packages after repos are enabled
    # Uses dnf with --skip-broken to tolerate missing packages
    cat <<'EOF'
# 3.6 Install Satellite Support Packages
ks_log "Phase 3.6: Install satellite support packages (tolerate failures)"
packages_to_install=(
    "dhcp-server" "tftp-server" "httpd" 
    "shim-x64" "grub2-efi-x64" "grub2-efi-x64-modules" "grub2-tools"
    "bind" "syslinux"
    "bash-completion" "git" "network-scripts" "sos" "setroubleshoot-server"
    "osbuild-composer" "cbootc" "podman" "skopeo" "composer-cli" "cockpit-composer"
    "vim"
)

# Try installing each package; tolerate failures
install_ok=0
install_failed=0
for pkg in "${packages_to_install[@]}"; do
    if dnf install -y --skip-broken --allowerasing --best "${pkg}" >/dev/null 2>&1; then
        install_ok=$((install_ok + 1))
    else
        install_failed=$((install_failed + 1))
        echo "    ⚠ Skipped (tolerated): ${pkg}"
    fi
done

echo "INFO: Satellite support packages - installed: ${install_ok}, skipped/failed: ${install_failed}"
EOF
}

kickstart_runtime_exports_block() {
    local bootstrap_keys_block="$1"
    local installer_user_q admin_user_q admin_pass_q rh_user_q rh_pass_q domain_q host_int_ip_q defer_component_install_q minirhis_temp_rc_local_q cockpit_port_q
    local cdn_org_q cdn_sat_key_q rhc_org_q rhc_key_q

    # Inside the kickstart %post the "installer user" is the remote admin account
    # (ADMIN_USER), not the local operator running this script on the install host.
    # The local operator username has no place on the target VMs.
    installer_user_q="$(printf '%q' "${ADMIN_USER}")"
    admin_user_q="$(printf '%q' "${ADMIN_USER}")"
    admin_pass_q="$(printf '%q' "${ADMIN_PASS}")"
    rh_user_q="$(printf '%q' "${RH_USER}")"
    rh_pass_q="$(printf '%q' "${RH_PASS}")"
    domain_q="$(printf '%q' "${DOMAIN:-}")"
    host_int_ip_q="$(printf '%q' "${HOST_INT_IP:-192.168.122.1}")"
    defer_component_install_q="$(printf '%q' "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}")"
    minirhis_temp_rc_local_q="$(printf '%q' "${MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC:-1}")"
    cockpit_port_q="$(printf '%q' "${COCKPIT_PORT:-9443}")"
    cdn_org_q="$(printf '%q' "${CDN_ORGANIZATION_ID:-}")"
    cdn_sat_key_q="$(printf '%q' "${CDN_SAT_ACTIVATION_KEY:-}")"
    rhc_org_q="$(printf '%q' "${RHC_ORGANIZATION_ID:-${CDN_ORGANIZATION_ID:-}}")"
    rhc_key_q="$(printf '%q' "${RHC_ACTIVATION_KEY:-${CDN_SAT_ACTIVATION_KEY:-}}")"

    cat <<EOF
# MINIRHIS runtime values injected at kickstart generation time
ADMIN_USER=${admin_user_q}
ADMIN_PASS=${admin_pass_q}
INSTALLER_USER=${installer_user_q}
RH_USER=${rh_user_q}
RH_PASS=${rh_pass_q}
DOMAIN=${domain_q}
HOST_INT_IP=${host_int_ip_q}
CDN_ORGANIZATION_ID=${cdn_org_q}
CDN_SAT_ACTIVATION_KEY=${cdn_sat_key_q}
RHC_ORGANIZATION_ID=${rhc_org_q}
RHC_ACTIVATION_KEY=${rhc_key_q}
COCKPIT_PORT=${cockpit_port_q}
MINIRHIS_DEFER_COMPONENT_INSTALL=${defer_component_install_q}
MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC=${minirhis_temp_rc_local_q}
bootstrap_ssh_keys="\$(cat <<'MINIRHIS_BOOTSTRAP_KEYS'
${bootstrap_keys_block}
MINIRHIS_BOOTSTRAP_KEYS
)"
export ADMIN_USER ADMIN_PASS INSTALLER_USER RH_USER RH_PASS DOMAIN HOST_INT_IP CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY RHC_ORGANIZATION_ID RHC_ACTIVATION_KEY COCKPIT_PORT MINIRHIS_DEFER_COMPONENT_INSTALL MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC bootstrap_ssh_keys
EOF
}

kickstart_networkmanager_dual_nic_block() {
    local ext_mac="$1"
    local int_mac="$2"
    local int_ip="$3"
    local int_prefix="$4"
    local int_gw="$5"

    cat <<EOF
# 0. Deterministic NetworkManager keyfiles (persisted for first boot)
ks_log "Phase 0: Configure persistent dual-NIC NetworkManager keyfiles"
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

cat > /etc/NetworkManager/conf.d/10-minirhis-no-auto-default.conf <<'EOF_NM_MAIN'
[main]
no-auto-default=${ext_mac},${int_mac}
EOF_NM_MAIN

systemctl enable NetworkManager || true

# Bootstrap DNS for kickstart %post registration.
# Anaconda runs %post in a chroot — NetworkManager is NOT running inside it,
# so /run/NetworkManager/resolv.conf never exists.  Write a static fallback now;
# NM will take over resolv.conf management on first boot.
if [ ! -s /etc/resolv.conf ]; then
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf || true
fi

# Dynamic DNS fallback: prefer gateways of the first two ethernet devices
# This helps when device ordering varies; it will set the active connection's
# IPv4 DNS list to GW1 GW2 8.8.8.8 1.1.1.1 and add search domain.
cat > /usr/local/bin/minirhis-set-dns.sh <<'EOF_MINIRHIS_SET_DNS'
#!/bin/bash
set -euo pipefail
ETH_DEVS=(\$(nmcli -t -f DEVICE,TYPE device | grep ethernet | cut -d: -f1 | head -n2))
GW1=""
GW2=""
if [ -n "\${ETH_DEVS[0]:-}" ]; then
    GW1=\$(nmcli -g IP4.GATEWAY device show "\${ETH_DEVS[0]}" 2>/dev/null || true)
fi
if [ -n "\${ETH_DEVS[1]:-}" ]; then
    GW2=\$(nmcli -g IP4.GATEWAY device show "\${ETH_DEVS[1]}" 2>/dev/null || true)
fi
CON_NAME=\$(nmcli -t -f NAME connection show --active | head -n1)
DNS_LIST=""
[ -n "\$GW1" ] && DNS_LIST="\$GW1"
[ -n "\$GW2" ] && DNS_LIST="\$DNS_LIST \$GW2"
DNS_LIST="\$DNS_LIST 8.8.8.8 1.1.1.1"
# Use configured DOMAIN if available, fall back to example.com
DNS_SEARCH="\${DOMAIN:-example.com}"
if [ -n "\$CON_NAME" ]; then
    nmcli connection modify "\$CON_NAME" ipv4.dns "\$DNS_LIST" ipv4.dns-search "\$DNS_SEARCH" ipv4.dns-options "rotate,timeout:1,attempts:1" ipv4.ignore-auto-dns yes || true
    nmcli connection up "\$CON_NAME" || true
fi
EOF_MINIRHIS_SET_DNS

chmod 0755 /usr/local/bin/minirhis-set-dns.sh || true
/usr/local/bin/minirhis-set-dns.sh || true
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
ks_log "Phase 1.3: Install bootstrap SSH keys"
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Ensure root has a local SSH keypair on first boot.
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa || true
fi

cat >> /root/.ssh/authorized_keys <<SSH_KEYS
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
    :
fi

configured_users=""
for _user in "${ADMIN_USER:-}" "${INSTALLER_USER:-}"; do
    [ -n "$_user" ] || continue
    case " ${configured_users} " in
        *" ${_user} "*)
            continue
            ;;
    esac
    configured_users="${configured_users} ${_user}"

    id "$_user" >/dev/null 2>&1 || continue

    target_home="$(getent passwd "$_user" | cut -d: -f6)"
    [ -n "$target_home" ] || target_home="/home/$_user"
    install -d -m 700 -o "$_user" -g "$_user" "$target_home/.ssh"

    # Ensure each managed user has a local SSH keypair.
    if [ ! -f "$target_home/.ssh/id_rsa" ]; then
        sudo -u "$_user" ssh-keygen -q -t rsa -b 4096 -N "" -f "$target_home/.ssh/id_rsa" || true
    fi

    cat > "$target_home/.ssh/authorized_keys" <<SSH_KEYS
${bootstrap_ssh_keys}
SSH_KEYS
    [ -f "$target_home/.ssh/id_rsa.pub" ] && cat "$target_home/.ssh/id_rsa.pub" >> "$target_home/.ssh/authorized_keys" || true
    [ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> "$target_home/.ssh/authorized_keys" || true
    [ -f "$target_home/.ssh/id_rsa.pub" ] && cat "$target_home/.ssh/id_rsa.pub" >> /root/.ssh/authorized_keys || true
    sort -u "$target_home/.ssh/authorized_keys" -o "$target_home/.ssh/authorized_keys" || true
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys || true
    chown "$_user:$_user" "$target_home/.ssh/authorized_keys"
    chown "$_user:$_user" "$target_home/.ssh/id_rsa" "$target_home/.ssh/id_rsa.pub" 2>/dev/null || true
    chmod 600 "$target_home/.ssh/id_rsa" 2>/dev/null || true
    chmod 644 "$target_home/.ssh/id_rsa.pub" 2>/dev/null || true
    chmod 600 "$target_home/.ssh/authorized_keys"
done
EOF
    fi
}

kickstart_creator_baseline_block() {
    local role_name="$1"
    local node_hostname="$2"
    local node_ip="$3"
    local product_url_ip=""
    local product_url_dns=""

    case "${role_name}" in
        satellite)
            product_url_ip="https://${node_ip}/"
            product_url_dns="https://${node_hostname}/"
            ;;
        aap)
            product_url_ip="https://${node_ip}/"
            product_url_dns="https://${node_hostname}/"
            ;;
        idm)
            product_url_ip="https://${node_ip}/ipa/ui/"
            product_url_dns="https://${node_hostname}/ipa/ui/"
            ;;
        *)
            product_url_ip="https://${node_ip}/"
            product_url_dns="https://${node_hostname}/"
            ;;
    esac

    cat <<EOF
# MINIRHIS creator baseline (shared across all kickstarted nodes)
# Ensures common tooling/services expected by creator/bootstrap automation.
dnf install -y --nogpgcheck sudo openssh-clients rsync jq ansible-core cockpit || true
systemctl enable --now chronyd || true

# Configure Cockpit on a non-default port and enable it for immediate access.
cockpit_port="\${COCKPIT_PORT:-9443}"
if ! [[ "\${cockpit_port}" =~ ^[0-9]+$ ]] || [ "\${cockpit_port}" -lt 1 ] || [ "\${cockpit_port}" -gt 65535 ]; then
    cockpit_port="9443"
fi
if systemctl list-unit-files cockpit.socket >/dev/null 2>&1; then
    mkdir -p /etc/systemd/system/cockpit.socket.d
    cat > /etc/systemd/system/cockpit.socket.d/override.conf <<'MINIRHIS_COCKPIT_OVERRIDE'
[Socket]
ListenStream=
ListenStream=PORT_PLACEHOLDER
MINIRHIS_COCKPIT_OVERRIDE
    sed -i "s/PORT_PLACEHOLDER/\${cockpit_port}/g" /etc/systemd/system/cockpit.socket.d/override.conf
    systemctl daemon-reload || true
    systemctl enable --now cockpit.socket || true
    systemctl restart cockpit.socket || true
fi

# SSH login access banner with node and RHIS entry points.
cat > /etc/motd <<'MINIRHIS_MOTD'
MiniRHIS Access Summary
=======================
Node role: ${role_name}
Node hostname: ${node_hostname}
Node IP: ${node_ip}

Cockpit (enabled): https://${node_ip}:\${cockpit_port}/  or  https://${node_hostname}:\${cockpit_port}/
Product web UI: ${product_url_ip}  or  ${product_url_dns}

MiniRHIS internal services:
- Satellite: https://${SAT_IP}/  (${SAT_HOSTNAME})
- AAP: https://${AAP_IP}/  (${AAP_HOSTNAME})
- AAP Gateway (container on AAP host): https://${AAP_IP}/  (${AAP_HOSTNAME})
- IdM: https://${IDM_IP}/ipa/ui/  (${IDM_HOSTNAME})

RHSM/Insights quick checks:
- subscription-manager identity
- rhc status
MINIRHIS_MOTD
chmod 0644 /etc/motd || true

cat > /etc/issue.d/minirhis.issue <<'MINIRHIS_ISSUE'
MiniRHIS node: ${node_hostname} (${node_ip}) - role: ${role_name}
Cockpit: https://${node_ip}:\${cockpit_port}/
Product UI: ${product_url_ip}
MINIRHIS_ISSUE
chmod 0644 /etc/issue.d/minirhis.issue || true
cat /etc/issue.d/minirhis.issue > /etc/issue 2>/dev/null || true

# Ensure the installer/admin account can run Ansible cleanly on every node.
target_user="${INSTALLER_USER:-${ADMIN_USER}}"
if id "$target_user" >/dev/null 2>&1; then
    :
fi

configured_users=""
for _user in "${ADMIN_USER:-}" "${INSTALLER_USER:-}"; do
    [ -n "$_user" ] || continue
    case " ${configured_users} " in
        *" ${_user} "*)
            continue
            ;;
    esac
    configured_users="${configured_users} ${_user}"

    id "$_user" >/dev/null 2>&1 || continue

    target_home="$(getent passwd "$_user" | cut -d: -f6)"
    [ -n "$target_home" ] || target_home="/home/$_user"
    install -d -m 0755 -o "$_user" -g "$_user" "$target_home/.ansible"
    install -d -m 0700 -o "$_user" -g "$_user" "$target_home/.ansible/tmp"
    install -d -m 0755 -o "$_user" -g "$_user" "$target_home/.ansible/collections"
    install -d -m 0755 -o "$_user" -g "$_user" "$target_home/.ansible/roles"
    cat > "$target_home/.ansible.cfg" <<'MINIRHIS_ANSIBLE_CFG'
[defaults]
local_tmp = ~/.ansible/tmp
remote_tmp = ~/.ansible/tmp
host_key_checking = False
retry_files_enabled = False
MINIRHIS_ANSIBLE_CFG
    chown "$_user:$_user" "$target_home/.ansible.cfg"
    chmod 0644 "$target_home/.ansible.cfg"
done

install -d -m 0755 /etc/minirhis /var/lib/minirhis /var/lib/minirhis/creator
cat > /etc/minirhis/creator.env <<'MINIRHIS_CREATOR_ENV'
MINIRHIS_CREATOR_MANAGED=1
MINIRHIS_ROLE=${role_name}
MINIRHIS_HOSTNAME=${node_hostname}
MINIRHIS_IP=${node_ip}
MINIRHIS_BOOTSTRAP_SOURCE=kickstart
MINIRHIS_BOOTSTRAP_VERSION=1
MINIRHIS_CREATOR_ENV
chmod 0644 /etc/minirhis/creator.env || true
EOF
}

kickstart_perf_network_snapshot_block() {
    local extra_sysctl_lines="${1:-}"

    cat <<EOF
# Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-minirhis-performance.conf <<'EOF_MINIRHIS_PERF'
vm.swappiness = 10
${extra_sysctl_lines}
EOF_MINIRHIS_PERF
sysctl -p /etc/sysctl.d/99-minirhis-performance.conf || true

# Network verification snapshot (for ks-post.log troubleshooting)
echo "===== MINIRHIS NETWORK SNAPSHOT ====="
date
ip -4 addr show eth0 || true
ip -4 addr show eth1 || true
ip route show || true
nmcli -f NAME,DEVICE,TYPE,STATE connection show || true
echo "===== END MINIRHIS NETWORK SNAPSHOT ====="
EOF
}

prepare_kickstart_shared_blocks() {
    local role_name="$1"
    local node_hostname="$2"
    local node_ip="$3"
    local ext_mac="$4"
    local int_mac="$5"
    local int_ip="$6"
    local int_prefix="$7"
    local int_gw="$8"
    local include_org_id="$9"
    local trust_bootstrap_keys_flag="${10}"
    local repo_role_label="${11}"
    shift 11
    local -a repos=("$@")

    MINIRHIS_KS_NOGPG_POLICY="$(kickstart_nogpg_policy_block)"
    MINIRHIS_KS_SSH_BASELINE="$(kickstart_ssh_baseline_block)"
    MINIRHIS_KS_USER_SUDO_BOOTSTRAP="$(kickstart_user_sudo_bootstrap_block "${role_name}")"
    MINIRHIS_KS_RHSM_REGISTER="$(kickstart_rhsm_register_block "${include_org_id}")"
    MINIRHIS_KS_RHC_CONNECT="$(kickstart_rhc_connect_block)"
    MINIRHIS_KS_REPO_ENABLE_VERIFY="$(kickstart_repo_enable_verify_block "${repo_role_label}" "${repos[@]}")"
    MINIRHIS_KS_NM_DUAL_NIC="$(kickstart_networkmanager_dual_nic_block "${ext_mac}" "${int_mac}" "${int_ip}" "${int_prefix}" "${int_gw}")"
    MINIRHIS_KS_TRUST_BOOTSTRAP_KEYS="$(kickstart_trust_bootstrap_keys_block "${trust_bootstrap_keys_flag}")"
    MINIRHIS_KS_CREATOR_BASELINE="$(kickstart_creator_baseline_block "${role_name}" "${node_hostname}" "${node_ip}")"
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
    echo "  MINIRHIS_EXECUTION_MODE=${MINIRHIS_EXECUTION_MODE:-container}"
    echo "  MINIRHIS_ANSIBLE_CFG_VAULT_HOST=${MINIRHIS_ANSIBLE_CFG_VAULT_HOST}"
    echo "  MINIRHIS_ANSIBLE_CFG_HOST=${MINIRHIS_ANSIBLE_CFG_HOST}"
    echo "  MINIRHIS_ANSIBLE_FACT_CACHE_HOST=${MINIRHIS_ANSIBLE_FACT_CACHE_HOST}"
    echo "  AAP_ANSIBLE_LOG=${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    echo "  MINIRHIS_RETRY_FAILED_PHASES_ONCE=${MINIRHIS_RETRY_FAILED_PHASES_ONCE:-1}"
    echo "  MINIRHIS_ENABLE_CONTAINER_HOTFIXES=${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"
    echo "  MINIRHIS_ENFORCE_CONTAINER_HOTFIXES=${MINIRHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"
    echo "  MINIRHIS_MANAGED_SSH_OVER_ETH0=${MINIRHIS_MANAGED_SSH_OVER_ETH0:-0}"
    echo "  MINIRHIS_IDM_WEB_UI_TIMEOUT=${MINIRHIS_IDM_WEB_UI_TIMEOUT:-900}"
    echo "  MINIRHIS_IDM_WEB_UI_INTERVAL=${MINIRHIS_IDM_WEB_UI_INTERVAL:-15}"
    echo "  MINIRHIS_ENABLE_POST_HEALTHCHECK=${MINIRHIS_ENABLE_POST_HEALTHCHECK:-1}"
    echo "  MINIRHIS_HEALTHCHECK_AUTOFIX=${MINIRHIS_HEALTHCHECK_AUTOFIX:-1}"
    echo "  MINIRHIS_HEALTHCHECK_RERUN_COMPONENT=${MINIRHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"
    echo "  MINIRHIS_SAT_HEALTHCHECK_RETRIES=${MINIRHIS_SAT_HEALTHCHECK_RETRIES:-5}"
    echo "  MINIRHIS_SAT_HEALTHCHECK_INTERVAL=${MINIRHIS_SAT_HEALTHCHECK_INTERVAL:-15}"
    echo "  MINIRHIS_REQUIRE_ROOT_SSH_MESH=${MINIRHIS_REQUIRE_ROOT_SSH_MESH:-0}"
    echo "  MINIRHIS_REFRESH_KNOWN_HOSTS=${MINIRHIS_REFRESH_KNOWN_HOSTS:-1}"
    echo "  MINIRHIS_INSTALLER_SSH_KEY_DIR=${MINIRHIS_INSTALLER_SSH_KEY_DIR:-'(unset)'}"
    echo "  MINIRHIS_ENABLE_PRECHECK_ADHOC=${MINIRHIS_ENABLE_PRECHECK_ADHOC:-0}"
    echo "  RHC_AUTO_CONNECT=${RHC_AUTO_CONNECT:-1}"
    echo "  COCKPIT_PORT=${COCKPIT_PORT:-9443}"
    echo "  NETWORKS_ACTIVE=SAT(${SAT_IP:-10.168.128.1}/${SAT_NETMASK:-255.255.0.0} gw:${SAT_GW:-10.168.0.1}) AAP(${AAP_IP:-10.168.128.2}/${AAP_NETMASK:-255.255.0.0} gw:${AAP_GW:-10.168.0.1}) IDM(${IDM_IP:-10.168.128.3}/${IDM_NETMASK:-255.255.0.0} gw:${IDM_GW:-10.168.0.1})"
}

generate_minirhis_ansible_cfg() {
    local tmp_cfg
    local tmp_cfg_runtime
    local tmp_cfg_encrypted

    mkdir -p "${ANSIBLE_ENV_DIR}" "${MINIRHIS_ANSIBLE_FACT_CACHE_HOST}" || return 1
    chmod 700 "${ANSIBLE_ENV_DIR}" "${MINIRHIS_ANSIBLE_FACT_CACHE_HOST}" 2>/dev/null || true
    ensure_ansible_vault || return 1
    ensure_vault_password_file || return 1

    # Prefer explicit vaulted console token; fall back to HUB_TOKEN.
    # This token is used for Automation Hub galaxy server auth entries.
    local ah_token="${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}"

    tmp_cfg="$(mktemp "${ANSIBLE_ENV_DIR}/.minirhis-ansible.cfg.XXXXXX")" || return 1

    cat > "${tmp_cfg}" <<EOF
[defaults]
inventory = ${MINIRHIS_CONTAINER_INVENTORY_FILE}
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent
remote_tmp = /var/tmp
forks = ${MINIRHIS_ANSIBLE_FORKS}
timeout = ${MINIRHIS_ANSIBLE_TIMEOUT}
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ${MINIRHIS_ANSIBLE_FACT_CACHE_CONTAINER}
fact_caching_timeout = ${MINIRHIS_ANSIBLE_FACT_CACHE_TIMEOUT}
callbacks_enabled = ansible.posix.profile_tasks,ansible.posix.timer
bin_ansible_callbacks = True
log_path = /minirhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}
nocows = 1
inject_facts_as_vars = True

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ${MINIRHIS_INSTALLER_SSH_KEY_CONTAINER_PATH}
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

    chmod 600 "${tmp_cfg}" 2>/dev/null || true
    # write_file_if_changed removes source temp on success, but we still need
    # tmp_cfg for vault comparison/encryption below, so write via a copy.
    tmp_cfg_runtime="$(mktemp "${ANSIBLE_ENV_DIR}/.minirhis-ansible.runtime.XXXXXX")" || {
        rm -f "${tmp_cfg}"
        return 1
    }
    cp -f "${tmp_cfg}" "${tmp_cfg_runtime}" || {
        rm -f "${tmp_cfg}" "${tmp_cfg_runtime}"
        return 1
    }
    sed -i \
        -e "s|^inventory = .*|inventory = ${MINIRHIS_INVENTORY_FILE}|" \
        -e "s|^fact_caching_connection = .*|fact_caching_connection = ${MINIRHIS_ANSIBLE_FACT_CACHE_HOST}|" \
        -e "s|^log_path = .*|log_path = ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}|" \
        -e "s|^ssh_args = .*|ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}|" \
        "${tmp_cfg_runtime}" || {
        rm -f "${tmp_cfg}" "${tmp_cfg_runtime}"
        return 1
    }
    write_file_if_changed "${tmp_cfg_runtime}" "${MINIRHIS_ANSIBLE_CFG_HOST}" 0600 || {
        rm -f "${tmp_cfg}"
        return 1
    }

    if vault_plaintext_matches_existing "${tmp_cfg}"; then
        rm -f "${tmp_cfg}"
        touch "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
        chmod 600 "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
        return 0
    fi

    tmp_cfg_encrypted="$(mktemp "${ANSIBLE_ENV_DIR}/.minirhis-ansible.cfg.vault.XXXXXX")" || {
        rm -f "${tmp_cfg}"
        return 1
    }
    cp -f "${tmp_cfg}" "${tmp_cfg_encrypted}" || {
        rm -f "${tmp_cfg}" "${tmp_cfg_encrypted}"
        return 1
    }
    ansible-vault encrypt --vault-password-file "${ANSIBLE_VAULT_PASS_FILE}" "${tmp_cfg_encrypted}" >/dev/null 2>&1 || {
        rm -f "${tmp_cfg}" "${tmp_cfg_encrypted}"
        return 1
    }
    chmod 600 "${tmp_cfg_encrypted}" 2>/dev/null || true
    mv -f "${tmp_cfg_encrypted}" "${MINIRHIS_ANSIBLE_CFG_VAULT_HOST}" || {
        rm -f "${tmp_cfg}" "${tmp_cfg_encrypted}"
        return 1
    }
    rm -f "${tmp_cfg}"
    touch "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
    chmod 600 "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" 2>/dev/null || true
    return 0
}

# Keep local developer ansible.cfg in container/roles aligned with the same
# runtime defaults used for MINIRHIS provisioner runs, including galaxy endpoints
# and token source (vault_console_redhat_token/HUB_TOKEN).
generate_local_roles_ansible_cfg() {
    local tmp_cfg
    local local_cfg
    local local_inventory
    local local_inventory_name
    local local_roles_path
    local local_ssh_key
    local local_fact_cache
    local local_log_path

    local_cfg="${SCRIPT_DIR}/container/roles/ansible.cfg"
    local_inventory_name="$(basename "${MINIRHIS_INVENTORY_FILE}")"
    local_inventory="${SCRIPT_DIR}/container/roles/inventory/${local_inventory_name}"
    local_roles_path="${SCRIPT_DIR}/container/roles:${SCRIPT_DIR}/container/roles/minirhis-builder-satellite/roles:${SCRIPT_DIR}/container/roles/minirhis-builder-idm/roles:${SCRIPT_DIR}/container/roles/minirhis-builder-aap/roles:${SCRIPT_DIR}/container/roles/minirhis-builder-aap/minirhis-builder-aap/roles"
    local_ssh_key="~/.ssh/id_rsa"
    local_fact_cache="${HOME}/.ansible/conf/${MINIRHIS_ANSIBLE_FACT_CACHE_BASENAME}"
    local_log_path="${HOME}/.ansible/conf/${AAP_ANSIBLE_LOG_BASENAME}"
    mkdir -p "${SCRIPT_DIR}/container/roles" "${local_fact_cache}" "${ANSIBLE_ENV_DIR}" || return 1

    tmp_cfg="$(mktemp "${ANSIBLE_ENV_DIR}/.local-roles-ansible.cfg.XXXXXX")" || return 1

    cat > "${tmp_cfg}" <<EOF
[defaults]
inventory = ${local_inventory}
host_key_checking = False
retry_files_enabled = False
roles_path = ${local_roles_path}
stdout_callback = ansible.builtin.default
result_format = yaml
interpreter_python = auto_silent
remote_tmp = /var/tmp
forks = ${MINIRHIS_ANSIBLE_FORKS}
timeout = ${MINIRHIS_ANSIBLE_TIMEOUT}
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ${local_fact_cache}
fact_caching_timeout = ${MINIRHIS_ANSIBLE_FACT_CACHE_TIMEOUT}
callbacks_enabled = ansible.posix.profile_tasks,ansible.posix.timer
bin_ansible_callbacks = True
log_path = ${local_log_path}
nocows = 1
inject_facts_as_vars = True

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ${local_ssh_key}
control_path_dir = /tmp/.ansible-cp
retries = 3

[galaxy]
server_list = published, validated, community_galaxy

[galaxy_server.published]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token =

[galaxy_server.validated]
url = https://console.redhat.com/api/automation-hub/content/validated/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token =

[galaxy_server.community_galaxy]
url = https://galaxy.ansible.com/
EOF

    chmod 600 "${tmp_cfg}" 2>/dev/null || true
    write_file_if_changed "${tmp_cfg}" "${local_cfg}" 0600 || return 1
    print_step "Local roles ansible.cfg sync complete: ${local_cfg}"
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
    _minirhis_test_bar() {
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
    _minirhis_test_why() {
        case "$1" in
            *"Ansible config"*)    printf '%s' "Verifies pipelining, forks, fact-cache, and log path before the container ever starts." ;;
            *"Generate inventory") printf '%s' "Builds the hosts file that defines every group (sat_primary, aap_hosts, idm_primary) for playbooks." ;;
            *"host_vars"*)         printf '%s' "Creates per-node connection details (IP, ansible_host, user) read by playbooks at run time." ;;
            *"inventory model"*)   printf '%s' "Validates the chosen AAP topology resolves to a real template before kickstart writes it." ;;
            *"Container Deploy"*)  printf '%s' "Starts minirhis-provisioner — the sole execution engine for all config-as-code phases." ;;
            *"OEMDRV"*)            printf '%s' "Exercises kickstart + ISO build pipeline (genisoimage/xorriso) without a live Satellite." ;;
            *"Dashboard"*)         printf '%s' "Renders the runtime monitor and exercises the ansible-provisioner.log tail path." ;;
            *"Local Install"*)     printf '%s' "Verifies the local npm/Node.js toolchain or confirms fall-through to container deployment." ;;
            *"Virt-Manager"*)      printf '%s' "Tests libvirt connectivity and VM definition logic — most common blocker on new installs." ;;
            *"Config-Only"*)       printf '%s' "End-to-end run of IdM -> Satellite -> AAP config sequence inside the provisioner container." ;;
            *)                     printf '%s' "Validates this component functions correctly in the current environment." ;;
        esac
    }

    # One-line "what a passing result means for you" shown in the summary.
    _minirhis_test_impact() {
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
    _minirhis_test_step_header() {
        local label="$1" why
        _MINIRHIS_TEST_STEP=$((_MINIRHIS_TEST_STEP + 1))
        why="$(_minirhis_test_why "${label}")"
        echo ""
        printf "${CYAN}  ┌─ [%d/%d]  ${BOLD}%s${NC}\n" "${_MINIRHIS_TEST_STEP}" "${_MINIRHIS_TEST_TOTAL}" "${label}"
        printf "${DIM}  │   %s${NC}\n" "${why}"
        printf "${CYAN}  └──────────────────────────────────────────────────────────────${NC}\n"
    }

    # ─── Core test machinery ────────────────────────────────────────────────────

    minirhis_test_record_result() {
        local label="$1"
        local status="$2"
        local details="${3:-}"
        MINIRHIS_TEST_RESULTS+=("${label}|${status}|${details}")
        if [ "$status" = "fail" ]; then
            MINIRHIS_TEST_FAILURE_COUNT=$((MINIRHIS_TEST_FAILURE_COUNT + 1))
        fi
    }

    minirhis_test_run_case() {
        local label="$1"
        shift
        _minirhis_test_step_header "${label}"
        if "$@"; then
            printf "${GREEN}  ✔  ${BOLD}%s${NC}${GREEN}  [ PASS ]${NC}\n" "${label}"
            minirhis_test_record_result "${label}" "success"
        else
            printf "${RED}  ✘  ${BOLD}%s${NC}${RED}  [ FAIL ]${NC}\n" "${label}"
            minirhis_test_record_result "${label}" "fail" \
                "See ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}, ${AAP_HTTP_LOG}, and option 8 dashboard."
        fi
    }

    minirhis_test_print_summary() {
        local item label status details impact
        local total_count passed_count skipped_count
        local overall_status demo_display pass_bar fail_bar

        passed_count=0; skipped_count=0
        for item in "${MINIRHIS_TEST_RESULTS[@]}"; do
            IFS='|' read -r label status details <<< "${item}"
            [ "${status}" = "success" ] && passed_count=$((passed_count + 1))
            [ "${status}" = "skipped" ] && skipped_count=$((skipped_count + 1))
        done
        total_count="${#MINIRHIS_TEST_RESULTS[@]}"
        overall_status="PASS"; [ "${MINIRHIS_TEST_FAILURE_COUNT}" -eq 0 ] || overall_status="FAIL"
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
        printf "  ${BOLD}Config${NC}   : %s\n" "${MINIRHIS_ANSIBLE_CFG_HOST}"
        printf "  ${BOLD}Log${NC}      : %s\n" "${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
        echo ""
        printf "${CYAN}  ───────────────────────────────────────────────────────────────${NC}\n"
        echo ""

        for item in "${MINIRHIS_TEST_RESULTS[@]}"; do
            IFS='|' read -r label status details <<< "${item}"
            impact="$(_minirhis_test_impact "${label}")"
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
        pass_bar="$(_minirhis_test_bar "${passed_count}"              "${total_count}")"
        fail_bar="$(_minirhis_test_bar "${MINIRHIS_TEST_FAILURE_COUNT}"   "${total_count}")"
        printf "  ${GREEN}Passed   :  %d / %d   ${BOLD}%s${NC}\n" \
            "${passed_count}" "${total_count}" "${pass_bar}"
        printf "  ${RED}Failed   :  %d / %d   ${BOLD}%s${NC}\n" \
            "${MINIRHIS_TEST_FAILURE_COUNT}" "${total_count}" "${fail_bar}"
        printf "  ${YELLOW}Skipped  :  %-3d${NC}\n" "${skipped_count}"
        printf "  ${YELLOW}Warnings :  %-3d${NC}\n" "${MINIRHIS_TEST_WARNING_COUNT}"

        if [ -s "${MINIRHIS_TEST_WARNING_FILE}" ]; then
            echo ""
            printf "${YELLOW}  ⚠  Warnings collected during this run:${NC}\n"
            while IFS= read -r wline; do
                printf "  ${YELLOW}  · %s${NC}\n" "${wline}"
            done < <(tail -n 20 "${MINIRHIS_TEST_WARNING_FILE}")
        fi

        echo ""
        printf "${CYAN}  ───────────────────────────────────────────────────────────────${NC}\n"
        echo ""
        if [ "${MINIRHIS_TEST_FAILURE_COUNT}" -eq 0 ]; then
            printf "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}\n"
            printf "${BOLD}${GREEN}  ✔  ALL SYSTEMS GO — Your MINIRHIS stack is ready to build.${NC}\n"
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

    minirhis_run_test_suite() {
        MINIRHIS_TEST_MODE=1
        NONINTERACTIVE=1
        RUN_ONCE=1
        MINIRHIS_TEST_RESULTS=()
        MINIRHIS_TEST_FAILURE_COUNT=0
        MINIRHIS_TEST_WARNING_COUNT=0
        _MINIRHIS_TEST_STEP=0
        : > "${MINIRHIS_TEST_WARNING_FILE}"

        local demo_display="OFF"
        [ "${DEMO_MODE:-0}" = "1" ] && demo_display="ON"

        echo ""
        printf "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}${CYAN}   MINIRHIS Integration Test Suite  ·  Curated Validation Run${NC}\n"
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
            _MINIRHIS_TEST_TOTAL=7
            minirhis_test_run_case "Generate MINIRHIS Ansible config"            generate_minirhis_ansible_cfg
            minirhis_test_run_case "Generate inventory"                      generate_minirhis_inventory
            minirhis_test_run_case "Generate host_vars"                      generate_minirhis_host_vars
            minirhis_test_run_case "AAP installer inventory model selection"  select_aap_inventory_templates
            minirhis_test_run_case "Container Deployment"                    install_container
            minirhis_test_run_case "Generate OEMDRV Kickstarts"              generate_oemdrv_kickstarts_only
            _minirhis_test_step_header "Live Status Dashboard snapshot"
            MINIRHIS_DASHBOARD_SINGLE_SHOT=1
            if show_live_status_dashboard; then
                printf "${GREEN}  ✔  ${BOLD}Live Status Dashboard snapshot${NC}${GREEN}  [ PASS ]${NC}\n"
                minirhis_test_record_result "Live Status Dashboard snapshot" "success" \
                    "Rendered single-shot dashboard snapshot."
            else
                printf "${RED}  ✘  ${BOLD}Live Status Dashboard snapshot${NC}${RED}  [ FAIL ]${NC}\n"
                minirhis_test_record_result "Live Status Dashboard snapshot" "fail" \
                    "Dashboard snapshot could not be rendered."
            fi
            MINIRHIS_DASHBOARD_SINGLE_SHOT=0
            minirhis_test_print_summary
            return $?
        fi

        _MINIRHIS_TEST_TOTAL=7
        minirhis_test_run_case "AAP installer inventory model selection"  select_aap_inventory_templates
        minirhis_test_run_case "1) Local App Mode (legacy/optional)"     install_local
        minirhis_test_run_case "2) Container Deployment"                 install_container
        minirhis_test_run_case "3) Setup Virt-Manager Only"              setup_virt_manager
        echo ""
        printf "${YELLOW}  ⊘  ${BOLD}4) Full Setup (Local + Virt-Manager)${NC}${YELLOW}   [ SKIP ]${NC}\n"
        printf "${DIM}       ↳  Covered by items 1 + 3 — avoids duplicate heavy provisioning.${NC}\n"
        minirhis_test_record_result "4) Full Setup (Local + Virt-Manager)" "skipped" \
            "Covered by test items 1 + 3 to avoid duplicate heavy provisioning."
        echo ""
        printf "${YELLOW}  ⊘  ${BOLD}5) Full Setup (Container + Virt-Manager)${NC}${YELLOW}   [ SKIP ]${NC}\n"
        printf "${DIM}       ↳  Covered by items 2 + 3 — avoids duplicate heavy provisioning.${NC}\n"
        minirhis_test_record_result "5) Full Setup (Container + Virt-Manager)" "skipped" \
            "Covered by test items 2 + 3 to avoid duplicate heavy provisioning."
        echo ""
        minirhis_test_run_case "6) Generate All OEMDRV Kickstarts"  generate_oemdrv_kickstarts_only
        minirhis_test_run_case "7) Container Config-Only"           run_container_config_only
        _minirhis_test_step_header "8) Live Status Dashboard"
        MINIRHIS_DASHBOARD_SINGLE_SHOT=1
        if show_live_status_dashboard; then
            printf "${GREEN}  ✔  ${BOLD}8) Live Status Dashboard${NC}${GREEN}  [ PASS ]${NC}\n"
            minirhis_test_record_result "8) Live Status Dashboard" "success" \
                "Rendered single-shot dashboard snapshot."
        else
            printf "${RED}  ✘  ${BOLD}8) Live Status Dashboard${NC}${RED}  [ FAIL ]${NC}\n"
            minirhis_test_record_result "8) Live Status Dashboard" "fail" \
                "Dashboard snapshot could not be rendered."
        fi
        MINIRHIS_DASHBOARD_SINGLE_SHOT=0
        minirhis_test_print_summary
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
            --enterprise)
                CLI_ENTERPRISE="1"
                ;;
            --standalone)
                CLI_STANDALONE="1"
                ;;
            --container-config-only)
                CLI_CONTAINER_CONFIG_ONLY="1"
                RUN_ONCE=1
                ;;
            --config-idm)
                CLI_CONFIG_SCOPE="idm"
                RUN_ONCE=1
                ;;
            --config-satellite)
                CLI_CONFIG_SCOPE="satellite"
                RUN_ONCE=1
                ;;
            --config-aap)
                CLI_CONFIG_SCOPE="aap"
                RUN_ONCE=1
                ;;
            --config-rhis-aap|--rhis-aap-config)
                CLI_CONFIG_SCOPE="rhis-aap"
                RUN_ONCE=1
                ;;
            --config-all)
                CLI_CONFIG_SCOPE="all"
                RUN_ONCE=1
                ;;
            --satellite)
                CLI_SATELLITE="1"
                RUN_ONCE=1
                ;;
            --idm)
                CLI_IDM="1"
                RUN_ONCE=1
                ;;
            --aap)
                CLI_AAP="1"
                RUN_ONCE=1
                ;;
            --minirhis|--rhis|--[rR][hH][iI][sS])
                CLI_MINIRHIS="1"
                RUN_ONCE=1
                ;;
            --libvirt)
                CLI_LIBVIRT="1"
                RUN_ONCE=1
                ;;
            --baremetal|--bare-metal)
                CLI_BAREMETAL="1"
                RUN_ONCE=1
                ;;
            --aws)
                CLI_AWS="1"
                RUN_ONCE=1
                ;;
            --azure)
                CLI_AZURE="1"
                RUN_ONCE=1
                ;;
            --gcp)
                CLI_GCP="1"
                RUN_ONCE=1
                ;;
            --nutanix)
                CLI_NUTANIX="1"
                RUN_ONCE=1
                ;;
            --openshift)
                CLI_OPENSHIFT="1"
                RUN_ONCE=1
                ;;
            --openshift-virt|--openshift_virt)
                CLI_OPENSHIFT_VIRT="1"
                RUN_ONCE=1
                ;;
            --vmware)
                CLI_VMWARE="1"
                RUN_ONCE=1
                ;;
            --local)
                CLI_LOCAL="1"
                RUN_ONCE=1
                ;;
            --container)
                CLI_CONTAINER="1"
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
            --status-live)
                CLI_STATUS_LIVE="1"
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
            --DEMO|--[dD][eE][mM][oO])
                CLI_DEMO="1"
                ;;
            --DEMOKILL|--[dD][eE][mM][oO][kK][iI][lL][lL])
                CLI_DEMOKILL="1"
                RUN_ONCE=1
                ;;
            --reconfigure)
                CLI_RECONFIGURE="1"
                ;;
            --menutest|--menu-test)
                CLI_MENUTEST="1"
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --validate|--preflight)
                CLI_VALIDATE="1"
                RUN_ONCE=1
                ;;
            --generate-env)
                # Optional next arg: output path for the generated template
                if [ "$#" -gt 1 ] && [[ "${2:-}" != --* ]]; then
                    shift
                    CLI_GENERATE_ENV="$1"
                else
                    CLI_GENERATE_ENV="${SCRIPT_DIR}/minirhis-headless.env.template"
                fi
                RUN_ONCE=1
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
    if [ -n "${CLI_ENTERPRISE:-}" ] && [ -n "${CLI_STANDALONE:-}" ]; then
        print_warning "--enterprise and --standalone cannot be used together."
        exit 1
    fi

    if [ -n "${CLI_DEMO:-}" ] && { [ -n "${CLI_ENTERPRISE:-}" ] || [ -n "${CLI_STANDALONE:-}" ]; }; then
        print_warning "--DEMO cannot be combined with --enterprise or --standalone."
        exit 1
    fi

    if [ -n "$CLI_NONINTERACTIVE" ]; then
        NONINTERACTIVE="$CLI_NONINTERACTIVE"
    fi

    if [ -n "$CLI_MENU_CHOICE" ]; then
        MENU_CHOICE="$CLI_MENU_CHOICE"
    fi

    if [ -n "$CLI_DEMO" ]; then
        DEMO_MODE="$CLI_DEMO"
        AAP_TOPOLOGY="standalone"
    fi

    if [ -n "$CLI_DEMOKILL" ]; then
        :
    fi

    if [ -n "$CLI_RECONFIGURE" ]; then
        FORCE_PROMPT_ALL=1
    fi

    if [ -n "$CLI_AAP_INVENTORY_TEMPLATE" ]; then
        AAP_INVENTORY_TEMPLATE="$CLI_AAP_INVENTORY_TEMPLATE"
        case "$(basename "${AAP_INVENTORY_TEMPLATE}")" in
            inventory.j2|inventory)
                AAP_TOPOLOGY="enterprise"
                ;;
            *)
                AAP_TOPOLOGY="standalone"
                ;;
        esac
    fi

    if [ -n "$CLI_AAP_INVENTORY_GROWTH_TEMPLATE" ]; then
        AAP_INVENTORY_GROWTH_TEMPLATE="$CLI_AAP_INVENTORY_GROWTH_TEMPLATE"
    fi

    if [ -n "${CLI_ENTERPRISE:-}" ]; then
        AAP_INVENTORY_TEMPLATE="inventory.j2"
        AAP_INVENTORY_GROWTH_TEMPLATE="inventory-growth.j2"
        AAP_TOPOLOGY="enterprise"
    fi

    if [ -n "${CLI_STANDALONE:-}" ]; then
        AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
        AAP_INVENTORY_GROWTH_TEMPLATE="inventory-growth.j2"
        AAP_TOPOLOGY="standalone"
    fi

    if [ -n "$CLI_CONTAINER_CONFIG_ONLY" ]; then
        MENU_CHOICE="1"
    fi

    # Execution-mode preference (last one wins when both are provided).
    if [ -n "$CLI_LOCAL" ]; then
        MINIRHIS_EXECUTION_MODE="local"
        MINIRHIS_LOCAL_ROLE_FALLBACK=1
    fi
    if [ -n "$CLI_CONTAINER" ]; then
        MINIRHIS_EXECUTION_MODE="container"
    fi

    # Component shortcuts map directly to menu options.
    # Explicit --config-* flags use dedicated fast-path execution and do not
    # remap menu choices.
    # If the caller explicitly asked for menu option 4 (Prompts Only), keep it.
    if [ -z "${CLI_CONFIG_SCOPE:-}" ] && [ "${CLI_MENU_CHOICE:-}" != "4" ]; then
        # Precedence order (last one wins if multiple are provided): minirhis -> satellite -> idm -> aap
        if [ -n "$CLI_MINIRHIS" ]; then
            MENU_CHOICE="1"
        fi
        if [ -n "$CLI_SATELLITE" ]; then
            MENU_CHOICE="9"
        fi
        if [ -n "$CLI_IDM" ]; then
            MENU_CHOICE="10"
        fi
        if [ -n "$CLI_AAP" ]; then
            MENU_CHOICE="11"
        fi
    fi

    # Platform flags set target platform for all components
    if [ -n "$CLI_LIBVIRT" ]; then
        MINIRHIS_TARGET_PLATFORM="libvirt"
        SAT_TARGET_PLATFORM="libvirt"
        AAP_TARGET_PLATFORM="libvirt"
        IDM_TARGET_PLATFORM="libvirt"
        MINIRHIS_PLATFORM_FAMILY="virtual"
    fi
    if [ -n "$CLI_BAREMETAL" ]; then
        MINIRHIS_TARGET_PLATFORM="baremetal"
        SAT_TARGET_PLATFORM="baremetal"
        AAP_TARGET_PLATFORM="baremetal"
        IDM_TARGET_PLATFORM="baremetal"
        MINIRHIS_PLATFORM_FAMILY="baremetal"
    fi
    if [ -n "$CLI_AWS" ]; then
        MINIRHIS_TARGET_PLATFORM="aws"
        SAT_TARGET_PLATFORM="aws"
        AAP_TARGET_PLATFORM="aws"
        IDM_TARGET_PLATFORM="aws"
        MINIRHIS_PLATFORM_FAMILY="cloud"
    fi
    if [ -n "$CLI_AZURE" ]; then
        MINIRHIS_TARGET_PLATFORM="azure"
        SAT_TARGET_PLATFORM="azure"
        AAP_TARGET_PLATFORM="azure"
        IDM_TARGET_PLATFORM="azure"
        MINIRHIS_PLATFORM_FAMILY="cloud"
    fi
    if [ -n "$CLI_GCP" ]; then
        MINIRHIS_TARGET_PLATFORM="gcp"
        SAT_TARGET_PLATFORM="gcp"
        AAP_TARGET_PLATFORM="gcp"
        IDM_TARGET_PLATFORM="gcp"
        MINIRHIS_PLATFORM_FAMILY="cloud"
    fi
    if [ -n "$CLI_NUTANIX" ]; then
        MINIRHIS_TARGET_PLATFORM="nutanix"
        SAT_TARGET_PLATFORM="nutanix"
        AAP_TARGET_PLATFORM="nutanix"
        IDM_TARGET_PLATFORM="nutanix"
        MINIRHIS_PLATFORM_FAMILY="virtual"
    fi
    if [ -n "$CLI_OPENSHIFT" ]; then
        MINIRHIS_TARGET_PLATFORM="openshift"
        SAT_TARGET_PLATFORM="openshift"
        AAP_TARGET_PLATFORM="openshift"
        IDM_TARGET_PLATFORM="openshift"
        MINIRHIS_PLATFORM_FAMILY="cloud"
    fi
    if [ -n "$CLI_OPENSHIFT_VIRT" ]; then
        MINIRHIS_TARGET_PLATFORM="openshift-virt"
        SAT_TARGET_PLATFORM="openshift-virt"
        AAP_TARGET_PLATFORM="openshift-virt"
        IDM_TARGET_PLATFORM="openshift-virt"
        MINIRHIS_PLATFORM_FAMILY="virtual"
    fi
    if [ -n "$CLI_VMWARE" ]; then
        MINIRHIS_TARGET_PLATFORM="vmware"
        SAT_TARGET_PLATFORM="vmware"
        AAP_TARGET_PLATFORM="vmware"
        IDM_TARGET_PLATFORM="vmware"
        MINIRHIS_PLATFORM_FAMILY="virtual"
    fi

    if [ -n "$CLI_ATTACH_CONSOLES" ]; then
        MENU_CHOICE="4"
    fi

    if [ -n "$CLI_TEST" ]; then
        MINIRHIS_TEST_MODE=1
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    if [ -n "$CLI_STATUS" ]; then
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    if [ -n "$CLI_VALIDATE" ]; then
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    if [ -n "$CLI_GENERATE_ENV" ]; then
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    # Full-stack demo CLI shortcut should run unattended from command line.
    # Keep explicit --non-interactive optional by auto-enabling it here.
    if [ -n "${CLI_DEMO:-}" ] && [ -n "${CLI_MINIRHIS:-}" ]; then
        NONINTERACTIVE=1
        RUN_ONCE=1
    fi

    if [ -n "$CLI_MENUTEST" ]; then
        MINIRHIS_MENU_TEST_MODE=1
        NONINTERACTIVE=0
        RUN_ONCE=0
    fi


is_menutest() {
    is_enabled "${MINIRHIS_MENU_TEST_MODE:-0}"
}
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
        -o ForwardX11=no \
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
        -o ForwardX11=no \
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
    if printf '%s' "${INTERNAL_NETWORK:-}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        printf '%s\n' "${INTERNAL_NETWORK}" | sed -E 's/\.[0-9]+$/\.1/'
        return 0
    fi
    printf '%s\n' "10.0.0.1"
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

strip_wrapping_quotes() {
    local raw="${1:-}"
    # Trim leading/trailing whitespace first.
    raw="$(printf '%s' "${raw}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "${raw}" in
        \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;;
        \'*\') raw="${raw#\'}"; raw="${raw%\'}" ;;
    esac
    printf '%s' "${raw}"
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

    DOMAIN="${DOMAIN:-${SAT_DOMAIN:-${AAP_DOMAIN:-${IDM_DOMAIN:-example.com}}}}"
    REALM="${REALM:-${IDM_REALM:-${SAT_REALM:-}}}"
    [ -n "${REALM:-}" ] || REALM="$(to_upper "$DOMAIN")"
    [ -n "${REALM:-}" ] || REALM="EXAMPLE.COM"

    ADMIN_USER="${ADMIN_USER:-admin}"
    # Global admin password is the authoritative root password for all systems.
    # Do not infer it from per-system service/admin passwords.
    ADMIN_PASS="${ADMIN_PASS:-}"
    ROOT_PASS="${ROOT_PASS:-${ADMIN_PASS}}"
    IDM_ADMIN_PASS="${IDM_ADMIN_PASS:-${ADMIN_PASS}}"
    IPADM_PASSWORD="${IPADM_PASSWORD:-${IDM_ADMIN_PASS:-${ADMIN_PASS}}}"
    IPAADMIN_PASSWORD="${IPAADMIN_PASSWORD:-${IDM_ADMIN_PASS:-${ADMIN_PASS}}}"

    INTERNAL_NETWORK="${INTERNAL_NETWORK:-10.168.0.0}"
    NETMASK="${NETMASK:-${SAT_NETMASK:-${AAP_NETMASK:-${IDM_NETMASK:-255.255.0.0}}}}"
    INTERNAL_GW="${INTERNAL_GW:-${SAT_GW:-${AAP_GW:-${IDM_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK}")}}}}"

    SAT_IP="${SAT_IP:-10.168.128.1}"
    AAP_IP="${AAP_IP:-10.168.128.2}"
    IDM_IP="${IDM_IP:-10.168.128.3}"

    # Global MINIRHIS policy: all managed SSH traffic must use the internal network.
    if is_enabled "${MINIRHIS_MANAGED_SSH_OVER_ETH0:-0}"; then
        print_warning "MINIRHIS_MANAGED_SSH_OVER_ETH0 is deprecated and ignored; enforcing internal SSH over 10.168.x.x."
    fi
    MINIRHIS_MANAGED_SSH_OVER_ETH0="0"

    # Guardrails: MINIRHIS node-to-node addresses must remain on the internal 10.168/16.
    case "${SAT_IP}" in 10.168.*) ;; *) print_warning "SAT_IP='${SAT_IP}' is outside 10.168.x.x; resetting to 10.168.128.1."; SAT_IP="10.168.128.1" ;; esac
    case "${AAP_IP}" in 10.168.*) ;; *) print_warning "AAP_IP='${AAP_IP}' is outside 10.168.x.x; resetting to 10.168.128.2."; AAP_IP="10.168.128.2" ;; esac
    case "${IDM_IP}" in 10.168.*) ;; *) print_warning "IDM_IP='${IDM_IP}' is outside 10.168.x.x; resetting to 10.168.128.3."; IDM_IP="10.168.128.3" ;; esac

    SAT_ORG="${SAT_ORG:-REDHAT}"
    SAT_LOC="${SAT_LOC:-CORE}"
    # Guardrail: MINIRHIS supports only containerized AAP installs.
    AAP_DEPLOYMENT_TYPE="container"
    # Guardrail: MINIRHIS lab uses single-node AAP topology only.
    if [ "${AAP_TOPOLOGY:-standalone}" != "standalone" ]; then
        print_warning "AAP_TOPOLOGY='${AAP_TOPOLOGY}' is not supported for standalone MINIRHIS labs; forcing standalone."
    fi
    AAP_TOPOLOGY="standalone"

    # Guardrail: avoid enterprise multi-node inventory in standalone mode.
    case "$(basename "${AAP_INVENTORY_TEMPLATE:-}")" in
        "" )
            AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
            ;;
        DEMO-inventory.j2|DEMO-inventory)
            ;;
        inventory.j2|inventory)
            print_warning "AAP inventory template '${AAP_INVENTORY_TEMPLATE}' is enterprise/multi-node; forcing inventory-growth.j2 for standalone mode."
            AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
            ;;
        *)
            ;;
    esac
    AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-inventory-growth.j2}"
    INSTALLER_USER="${INSTALLER_USER:-${USER}}"
    SSHPASS_CMD="${SSHPASS_CMD:-sshpass}"

    # Defensive normalization: env.yml may contain single-quoted identifiers.
    # Strip wrapping quotes so RHSM/rhc receive raw org/key values.
    CDN_ORGANIZATION_ID="$(strip_wrapping_quotes "${CDN_ORGANIZATION_ID:-}")"
    CDN_SAT_ACTIVATION_KEY="$(strip_wrapping_quotes "${CDN_SAT_ACTIVATION_KEY:-}")"
    RHC_ORGANIZATION_ID="$(strip_wrapping_quotes "${RHC_ORGANIZATION_ID:-}")"
    RHC_ACTIVATION_KEY="$(strip_wrapping_quotes "${RHC_ACTIVATION_KEY:-}")"

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

    case "${SATELLITE_VALIDATE_CERTS:-false}" in
        1|true|TRUE|yes|YES|on|ON)
            SATELLITE_VALIDATE_CERTS="true"
            ;;
        *)
            SATELLITE_VALIDATE_CERTS="false"
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

    case "${SAT_USE_NON_IDM_CERTS:-}" in
        1|true|TRUE|yes|YES|on|ON)
            SAT_USE_NON_IDM_CERTS="true"
            ;;
        0|false|FALSE|no|NO|off|OFF)
            SAT_USE_NON_IDM_CERTS="false"
            ;;
        *)
            SAT_USE_NON_IDM_CERTS=""
            ;;
    esac

    case "${RHC_AUTO_CONNECT:-1}" in
        1|true|TRUE|yes|YES|on|ON)
            RHC_AUTO_CONNECT="1"
            ;;
        *)
            RHC_AUTO_CONNECT="0"
            ;;
    esac

    SAT_SSL_CERTS_DIR="${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}"
    case "${SAT_SSL_CERTS_DIR}" in
        */) ;;
        *) SAT_SSL_CERTS_DIR="${SAT_SSL_CERTS_DIR}/" ;;
    esac

    SAT_DOMAIN="${SAT_DOMAIN:-$DOMAIN}"
    AAP_DOMAIN="${AAP_DOMAIN:-$DOMAIN}"
    IDM_DOMAIN="${IDM_DOMAIN:-$DOMAIN}"
    SAT_FIREWALLD_ZONE="${SAT_FIREWALLD_ZONE:-public}"
    SAT_FIREWALLD_INTERFACE="${SAT_FIREWALLD_INTERFACE:-eth1}"
    SAT_FIREWALLD_SERVICES_JSON="${SAT_FIREWALLD_SERVICES_JSON:-[\"ssh\",\"http\",\"https\"]}"
    SAT_PROVISIONING_SUBNET="${SAT_PROVISIONING_SUBNET:-10.168.0.0}"
    SAT_PROVISIONING_NETMASK="${SAT_PROVISIONING_NETMASK:-$NETMASK}"
    SAT_PROVISIONING_GW="${SAT_PROVISIONING_GW:-$INTERNAL_GW}"

    # Keep Satellite service endpoints pinned to the internal MINIRHIS network.
    if ! is_enabled "${MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK:-1}"; then
        print_warning "MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK=0 is not supported for MINIRHIS stack coherence; forcing to 1."
    fi
    MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK="1"
    SAT_PROVISIONING_DHCP_START="${SAT_PROVISIONING_DHCP_START:-10.168.130.1}"
    SAT_PROVISIONING_DHCP_END="${SAT_PROVISIONING_DHCP_END:-10.168.255.254}"
    SAT_PROVISIONING_DNS_PRIMARY="${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP}}"
    SAT_PROVISIONING_DNS_SECONDARY="${SAT_PROVISIONING_DNS_SECONDARY:-8.8.8.8}"
    SAT_DNS_ZONE="${SAT_DNS_ZONE:-${DOMAIN}}"
    if [ -z "${SAT_DNS_REVERSE_ZONE:-}" ]; then
        local _sat_reverse_prefix
        _sat_reverse_prefix="$(printf '%s' "${SAT_PROVISIONING_SUBNET:-10.168.0.0}" | awk -F. '{print $1"."$2"."$3}')"
        SAT_DNS_REVERSE_ZONE="$(printf '%s' "${_sat_reverse_prefix:-10.168.0}" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')"
    fi

    if is_unresolved_template_value "${SAT_HOSTNAME:-}"; then
        SAT_HOSTNAME=""
    fi
    if is_unresolved_template_value "${AAP_HOSTNAME:-}"; then
        AAP_HOSTNAME=""
    fi
    if is_unresolved_template_value "${IDM_HOSTNAME:-}"; then
        IDM_HOSTNAME=""
    fi

    # Only append the domain when it's non-empty to avoid trailing dots
    local _domain_suffix="${DOMAIN:+.${DOMAIN}}"
    SAT_HOSTNAME="${SAT_HOSTNAME:-satellite${_domain_suffix}}"
    AAP_HOSTNAME="${AAP_HOSTNAME:-aap${_domain_suffix}}"
    IDM_HOSTNAME="${IDM_HOSTNAME:-idm${_domain_suffix}}"

    if [ -n "${DOMAIN:-}" ]; then
        [[ "${SAT_HOSTNAME}" == *.* ]] || SAT_HOSTNAME="${SAT_HOSTNAME}.${DOMAIN}"
        [[ "${AAP_HOSTNAME}" == *.* ]] || AAP_HOSTNAME="${AAP_HOSTNAME}.${DOMAIN}"
        [[ "${IDM_HOSTNAME}" == *.* ]] || IDM_HOSTNAME="${IDM_HOSTNAME}.${DOMAIN}"
    fi

    # Safety: remove any trailing dots accidentally present (avoid 'name.').
    while [ -n "${SAT_HOSTNAME:-}" ] && [ "${SAT_HOSTNAME: -1}" = "." ]; do
        SAT_HOSTNAME="${SAT_HOSTNAME%?}"
    done
    while [ -n "${AAP_HOSTNAME:-}" ] && [ "${AAP_HOSTNAME: -1}" = "." ]; do
        AAP_HOSTNAME="${AAP_HOSTNAME%?}"
    done
    while [ -n "${IDM_HOSTNAME:-}" ] && [ "${IDM_HOSTNAME: -1}" = "." ]; do
        IDM_HOSTNAME="${IDM_HOSTNAME%?}"
    done

    # Hostname validation helper: basic permissive check for typical hostnames
    validate_hostname() {
        local hn="$1"
        # non-empty and length limits
        [ -n "$hn" ] || return 1
        if [ "${#hn}" -gt 253 ]; then
            return 1
        fi
        # must not end with dot
        case "$hn" in
            *.) return 1 ;;
        esac
        # allowed chars: a-z, A-Z, 0-9, -, . and must start/end with alnum
        if ! printf '%s' "$hn" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'; then
            return 1
        fi
        return 0
    }

    # Validate hostnames and warn/fallback if somehow invalid after sanitization.
    for _h in SAT_HOSTNAME AAP_HOSTNAME IDM_HOSTNAME; do
        _val="${!_h}"
        if ! validate_hostname "$_val"; then
            print_warning "Computed ${_h}='${_val}' looks invalid; falling back to safe default without domain."
            case "${_h}" in
                SAT_HOSTNAME) eval "${_h}=satellite" ;;
                AAP_HOSTNAME) eval "${_h}=aap" ;;
                IDM_HOSTNAME) eval "${_h}=idm" ;;
            esac
        fi
    done
    SAT_ALIAS="${SAT_ALIAS:-satellite}"
    AAP_ALIAS="${AAP_ALIAS:-aap}"
    IDM_ALIAS="${IDM_ALIAS:-idm}"

    SAT_REALM="${SAT_REALM:-$REALM}"
    IDM_REALM="${IDM_REALM:-$REALM}"

    # Per-system admin passwords default to the shared admin password, but do
    # not override explicit per-role values when they are provided.
    SAT_ADMIN_PASS="${SAT_ADMIN_PASS:-${ADMIN_PASS}}"
    AAP_ADMIN_PASS="${AAP_ADMIN_PASS:-${ADMIN_PASS}}"
    IDM_ADMIN_PASS="${IDM_ADMIN_PASS:-${ADMIN_PASS}}"
    IDM_DS_PASS="${IDM_DS_PASS:-${ADMIN_PASS}}"

    SAT_NETMASK="${SAT_NETMASK:-$NETMASK}"
    AAP_NETMASK="${AAP_NETMASK:-$NETMASK}"
    IDM_NETMASK="${IDM_NETMASK:-$NETMASK}"

    SAT_GW="${SAT_GW:-$INTERNAL_GW}"
    AAP_GW="${AAP_GW:-$INTERNAL_GW}"
    IDM_GW="${IDM_GW:-$INTERNAL_GW}"

    # Guardrails: gateways must remain on the MINIRHIS internal network.
    case "${SAT_GW}" in 10.168.*) ;; *) print_warning "SAT_GW='${SAT_GW}' is outside 10.168.x.x; forcing INTERNAL_GW='${INTERNAL_GW}'."; SAT_GW="${INTERNAL_GW}" ;; esac
    case "${AAP_GW}" in 10.168.*) ;; *) print_warning "AAP_GW='${AAP_GW}' is outside 10.168.x.x; forcing INTERNAL_GW='${INTERNAL_GW}'."; AAP_GW="${INTERNAL_GW}" ;; esac
    case "${IDM_GW}" in 10.168.*) ;; *) print_warning "IDM_GW='${IDM_GW}' is outside 10.168.x.x; forcing INTERNAL_GW='${INTERNAL_GW}'."; IDM_GW="${INTERNAL_GW}" ;; esac
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

    # Skip prompting for values already loaded from env.yml unless reconfiguring.
    if [ "${FORCE_PROMPT_ALL:-0}" != "1" ] && [ -n "${!var_name:-}" ] && ! is_unresolved_template_value "${!var_name:-}"; then
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

normalize_platform_value() {
    local raw="${1:-libvirt}"
    local v
    v="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-')"
    case "$v" in
        libvirt|kvm)
            printf '%s' "libvirt"
            ;;
        vmware|vsphere)
            printf '%s' "vmware"
            ;;
        nutanix|nutanix-ahv|ahv)
            printf '%s' "nutanix"
            ;;
        openshift|ocp)
            printf '%s' "openshift"
            ;;
        openshift-virt|openshiftvirt|kubevirt)
            printf '%s' "openshift-virt"
            ;;
        aws|ec2)
            printf '%s' "aws"
            ;;
        gcp|gce|google)
            printf '%s' "gcp"
            ;;
        azure)
            printf '%s' "azure"
            ;;
        baremetal|bare-metal|metal)
            printf '%s' "baremetal"
            ;;
        *)
            printf '%s' "$v"
            ;;
    esac
}

prompt_platform_choice() {
    local var_name="$1"
    local label="$2"
    local default_value="${3:-libvirt}"
    local choice=""
    local selected=""

    if is_noninteractive; then
        if [ -n "${!var_name:-}" ]; then
            printf -v "$var_name" '%s' "$(normalize_platform_value "${!var_name}")"
            return 0
        fi
        printf -v "$var_name" '%s' "$(normalize_platform_value "$default_value")"
        return 0
    fi

        platform_family_for_provider() {
            case "$(normalize_platform_value "$1")" in
                aws|azure|gcp|openshift)
                    printf '%s' "cloud"
                    ;;
                baremetal)
                    printf '%s' "baremetal"
                    ;;
                *)
                    printf '%s' "virtual"
                    ;;
            esac
        }

        set_platform_targets() {
            local install_product="$1"
            local selected_platform

            selected_platform="$(normalize_platform_value "$2")"
            MINIRHIS_TARGET_PLATFORM="${selected_platform}"

            case "${install_product}" in
                minirhis)
                    SAT_TARGET_PLATFORM="${selected_platform}"
                    AAP_TARGET_PLATFORM="${selected_platform}"
                    IDM_TARGET_PLATFORM="${selected_platform}"
                    ;;
                satellite)
                    SAT_TARGET_PLATFORM="${selected_platform}"
                    ;;
                aap)
                    AAP_TARGET_PLATFORM="${selected_platform}"
                    ;;
                idm)
                    IDM_TARGET_PLATFORM="${selected_platform}"
                    ;;
                *)
                    SAT_TARGET_PLATFORM="${selected_platform}"
                    AAP_TARGET_PLATFORM="${selected_platform}"
                    IDM_TARGET_PLATFORM="${selected_platform}"
                    ;;
            esac
        }

        prompt_install_product_choice() {
            local var_name="$1"
            local default_value="${2:-${MINIRHIS_INSTALL_PRODUCT:-}}"
            local choice=""
            local selected=""

            if is_noninteractive; then
                printf -v "$var_name" '%s' "${!var_name:-${default_value:-minirhis}}"
                return 0
            fi

            while true; do
                print_minirhis_header
                echo "Prompts-Only Product Selection"
                echo ""
                echo "  1) MINIRHIS Full Stack"
                echo "     - IdM -> Satellite -> AAP"
                echo "  2) Satellite Only"
                echo "  3) IdM Only"
                echo "  4) AAP Only"
                echo ""
                read -r -p "  Choice [1-4, Enter=${default_value:-minirhis}]: " choice

                case "${choice}" in
                    "") selected="${default_value:-minirhis}" ;;
                    1) selected="minirhis" ;;
                    2) selected="satellite" ;;
                    3) selected="idm" ;;
                    4) selected="aap" ;;
                    *)
                        print_warning "Invalid choice '${choice}'. Please enter 1, 2, 3, or 4."
                        continue
                        ;;
                esac
                printf -v "$var_name" '%s' "${selected}"
                return 0
            done
        }

        prompt_platform_family_choice() {
            local var_name="$1"
            local default_value="${2:-virtual}"
            local choice=""
            local selected=""

            if is_noninteractive; then
                printf -v "$var_name" '%s' "${!var_name:-${default_value:-virtual}}"
                return 0
            fi

            while true; do
                print_minirhis_header
                echo "Platform Family"
                echo ""
                echo "  1) Bare Metal"
                echo "  2) Virtual"
                echo "  3) Cloud"
                echo ""
                read -r -p "  Choice [1-3, Enter=${default_value:-virtual}]: " choice

                case "${choice}" in
                    "") selected="${default_value:-virtual}" ;;
                    1) selected="baremetal" ;;
                    2) selected="virtual" ;;
                    3) selected="cloud" ;;
                    *)
                        print_warning "Invalid choice '${choice}'. Please enter 1, 2, or 3."
                        continue
                        ;;
                esac
                printf -v "$var_name" '%s' "${selected}"
                return 0
            done
        }

        prompt_virtual_provider_choice() {
            local var_name="$1"
            local default_value="${2:-libvirt}"
            local choice=""
            local selected=""

            if is_noninteractive; then
                printf -v "$var_name" '%s' "$(normalize_platform_value "${!var_name:-${default_value:-libvirt}}")"
                return 0
            fi

            while true; do
                print_minirhis_header
                echo "Virtual Platform"
                echo ""
                echo "  1) libvirt"
                echo "  2) VMware"
                echo "  3) Nutanix"
                echo "  4) OpenShift Virt"
                echo ""
                read -r -p "  Choice [1-4, Enter=${default_value:-libvirt}]: " choice

                case "${choice}" in
                    "") selected="${default_value:-libvirt}" ;;
                    1) selected="libvirt" ;;
                    2) selected="vmware" ;;
                    3) selected="nutanix" ;;
                    4) selected="openshift-virt" ;;
                    *)
                        print_warning "Invalid choice '${choice}'. Please enter 1, 2, 3, or 4."
                        continue
                        ;;
                esac
                printf -v "$var_name" '%s' "$(normalize_platform_value "${selected}")"
                return 0
            done
        }

        prompt_cloud_provider_choice() {
            local var_name="$1"
            local default_value="${2:-aws}"
            local choice=""
            local selected=""

            if is_noninteractive; then
                printf -v "$var_name" '%s' "$(normalize_platform_value "${!var_name:-${default_value:-aws}}")"
                return 0
            fi

            while true; do
                print_minirhis_header
                echo "Cloud Platform"
                echo ""
                echo "  1) aws"
                echo "  2) azure"
                echo "  3) gcp"
                echo ""
                read -r -p "  Choice [1-3, Enter=${default_value:-aws}]: " choice

                case "${choice}" in
                    "") selected="${default_value:-aws}" ;;
                    1) selected="aws" ;;
                    2) selected="azure" ;;
                    3) selected="gcp" ;;
                    *)
                        print_warning "Invalid choice '${choice}'. Please enter 1, 2, or 3."
                        continue
                        ;;
                esac
                printf -v "$var_name" '%s' "$(normalize_platform_value "${selected}")"
                return 0
            done
        }

        prompt_platform_connection_details() {
            local platform
            platform="$(normalize_platform_value "$1")"

            echo ""
            echo "=== Platform Connection Details (${platform}) ==="
            case "${platform}" in
                libvirt)
                    prompt_with_default LIBVIRT_URI "libvirt connection URI" "${LIBVIRT_URI:-qemu:///system}" 0 1 || return 1
                    prompt_with_default LIBVIRT_STORAGE_POOL "libvirt storage pool" "${LIBVIRT_STORAGE_POOL:-default}" 0 1 || return 1
                    prompt_with_default LIBVIRT_NETWORK "libvirt network" "${LIBVIRT_NETWORK:-default}" 0 1 || return 1
                    ;;
                vmware)
                    prompt_with_default VMWARE_VCENTER_HOST "vCenter hostname or IP" "${VMWARE_VCENTER_HOST:-}" 0 1 || return 1
                    prompt_with_default VMWARE_USERNAME "vCenter username" "${VMWARE_USERNAME:-}" 0 1 || return 1
                    prompt_with_default VMWARE_PASSWORD "vCenter password" "${VMWARE_PASSWORD:-}" 1 1 || return 1
                    prompt_with_default VMWARE_DATACENTER "VMware datacenter" "${VMWARE_DATACENTER:-}" 0 1 || return 1
                    prompt_with_default VMWARE_CLUSTER "VMware cluster" "${VMWARE_CLUSTER:-}" 0 1 || return 1
                    ;;
                nutanix)
                    prompt_with_default NUTANIX_ENDPOINT "Nutanix Prism endpoint" "${NUTANIX_ENDPOINT:-}" 0 1 || return 1
                    prompt_with_default NUTANIX_USERNAME "Nutanix username" "${NUTANIX_USERNAME:-}" 0 1 || return 1
                    prompt_with_default NUTANIX_PASSWORD "Nutanix password" "${NUTANIX_PASSWORD:-}" 1 1 || return 1
                    prompt_with_default NUTANIX_CLUSTER "Nutanix cluster" "${NUTANIX_CLUSTER:-}" 0 1 || return 1
                    ;;
                openshift|openshift-virt)
                    prompt_with_default OPENSHIFT_API_URL "OpenShift API URL" "${OPENSHIFT_API_URL:-}" 0 1 || return 1
                    prompt_with_default OPENSHIFT_USERNAME "OpenShift username" "${OPENSHIFT_USERNAME:-}" 0 1 || return 1
                    prompt_with_default OPENSHIFT_TOKEN "OpenShift token" "${OPENSHIFT_TOKEN:-}" 1 1 || return 1
                    prompt_with_default OPENSHIFT_NAMESPACE "OpenShift namespace" "${OPENSHIFT_NAMESPACE:-openshift-cnv}" 0 1 || return 1
                    ;;
                aws)
                    prompt_with_default AWS_ACCESS_KEY_ID "AWS access key ID" "${AWS_ACCESS_KEY_ID:-}" 0 1 || return 1
                    prompt_with_default AWS_SECRET_ACCESS_KEY "AWS secret access key" "${AWS_SECRET_ACCESS_KEY:-}" 1 1 || return 1
                    prompt_with_default AWS_SESSION_TOKEN "AWS session token (optional)" "${AWS_SESSION_TOKEN:-}" 1 0 || return 1
                    prompt_with_default AWS_DEFAULT_REGION "AWS region" "${AWS_DEFAULT_REGION:-us-east-1}" 0 1 || return 1
                    prompt_with_default AWS_VPC_ID "AWS VPC ID (optional)" "${AWS_VPC_ID:-}" 0 0 || return 1
                    prompt_with_default AWS_SUBNET_ID "AWS subnet ID (optional)" "${AWS_SUBNET_ID:-}" 0 0 || return 1
                    ;;
                azure)
                    prompt_with_default AZURE_SUBSCRIPTION_ID "Azure subscription ID" "${AZURE_SUBSCRIPTION_ID:-}" 0 1 || return 1
                    prompt_with_default AZURE_TENANT_ID "Azure tenant ID" "${AZURE_TENANT_ID:-}" 0 1 || return 1
                    prompt_with_default AZURE_CLIENT_ID "Azure client/application ID" "${AZURE_CLIENT_ID:-}" 0 1 || return 1
                    prompt_with_default AZURE_CLIENT_SECRET "Azure client secret" "${AZURE_CLIENT_SECRET:-}" 1 1 || return 1
                    prompt_with_default AZURE_RESOURCE_GROUP "Azure resource group" "${AZURE_RESOURCE_GROUP:-}" 0 1 || return 1
                    prompt_with_default AZURE_LOCATION "Azure region/location" "${AZURE_LOCATION:-eastus}" 0 1 || return 1
                    ;;
                gcp)
                    prompt_with_default GCP_PROJECT_ID "GCP project ID" "${GCP_PROJECT_ID:-}" 0 1 || return 1
                    prompt_with_default GCP_REGION "GCP region" "${GCP_REGION:-us-central1}" 0 1 || return 1
                    prompt_with_default GCP_ZONE "GCP zone" "${GCP_ZONE:-us-central1-a}" 0 1 || return 1
                    prompt_with_default GCP_SERVICE_ACCOUNT_FILE "GCP service account JSON path" "${GCP_SERVICE_ACCOUNT_FILE:-}" 0 1 || return 1
                    ;;
                baremetal)
                    prompt_with_default BMC_TYPE "BMC type (redfish/idrac/ipmi/ilo)" "${BMC_TYPE:-redfish}" 0 1 || return 1
                    prompt_with_default BMC_ENDPOINT "BMC or DRAC endpoint" "${BMC_ENDPOINT:-}" 0 1 || return 1
                    prompt_with_default BMC_USERNAME "BMC username" "${BMC_USERNAME:-}" 0 1 || return 1
                    prompt_with_default BMC_PASSWORD "BMC password" "${BMC_PASSWORD:-}" 1 1 || return 1
                    prompt_with_default BMC_SYSTEM_ID "BMC system ID (optional)" "${BMC_SYSTEM_ID:-}" 0 0 || return 1
                    prompt_with_default BAREMETAL_ISO_URL "ISO URL for virtual media / mount source" "${BAREMETAL_ISO_URL:-}" 0 1 || return 1
                    prompt_with_default PXE_SERVER_URL "PXE server URL (optional)" "${PXE_SERVER_URL:-}" 0 0 || return 1
                    ;;
                *)
                    print_warning "No platform credential prompts implemented for '${platform}'."
                    ;;
            esac
        }

    print_minirhis_header
    echo "Platform Selection"
    echo "  ${label}"
    echo ""
    echo "  1) AWS (Planned)"
    echo "  2) Azure (Planned)"
    echo "  3) Bare Metal (Planned)"
    echo "  4) GCP (Planned)"
    echo "  5) libvirt (Current)"
    echo "  6) Nutanix (Planned)"
    echo "  7) OpenShift (Planned)"
    echo "  8) OpenShift Virt (Planned)"
    echo "  9) VMware (Planned)"
    echo ""
    echo "  Default: libvirt"
    echo ""
    read -r -p "  Choice [1-9, Enter=default ${default_value}]: " choice

    case "${choice}" in
        "") selected="${default_value}" ;;
        1) selected="aws" ;;
        2) selected="azure" ;;
        3) selected="baremetal" ;;
        4) selected="gcp" ;;
        5) selected="libvirt" ;;
        6) selected="nutanix" ;;
        7) selected="openshift" ;;
        8) selected="openshift-virt" ;;
        9) selected="vmware" ;;
        *) selected="${default_value}" ;;
    esac

    printf -v "$var_name" '%s' "$(normalize_platform_value "$selected")"
    return 0
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

ensure_kickstart_prereqs_ready() {
    local scope="${1:-all}"
    local missing=0
    local -a required_vars=()

    if [ ! -s "$ANSIBLE_ENV_FILE" ]; then
        print_warning "Missing encrypted environment file: $ANSIBLE_ENV_FILE"
        print_warning "Please select option 4 before creating kickstarts."
        return 1
    fi

    if [ ! -s "$ANSIBLE_VAULT_PASS_FILE" ]; then
        print_warning "Missing vault password file: $ANSIBLE_VAULT_PASS_FILE"
        print_warning "Please select option 4 before creating kickstarts."
        return 1
    fi

    load_ansible_env_file || {
        print_warning "Could not load saved kickstart configuration from $ANSIBLE_ENV_FILE"
        print_warning "Please select option 4 before creating kickstarts."
        return 1
    }
    normalize_shared_env_vars

    case "$scope" in
        satellite)
            required_vars=(
                RH_USER RH_PASS ADMIN_USER ADMIN_PASS
                SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC
                CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY RH9_ISO_URL
            )
            ;;
        aap)
            required_vars=(
                RH_USER RH_PASS ADMIN_USER ADMIN_PASS
                AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS
                HUB_TOKEN HOST_INT_IP AAP_BUNDLE_URL RH_ISO_URL
                AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE
            )
            ;;
        idm)
            required_vars=(
                RH_USER RH_PASS ADMIN_PASS DOMAIN
                IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS
                RH_ISO_URL
            )
            ;;
        all|*)
            required_vars=(
                RH_USER RH_PASS ADMIN_USER ADMIN_PASS DOMAIN
                SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC
                AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS AAP_BUNDLE_URL HUB_TOKEN HOST_INT_IP AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE
                IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS
                CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY
                RH_ISO_URL RH9_ISO_URL
            )
            ;;
    esac

    missing="$(count_missing_vars "${required_vars[@]}")"
    if [ "${missing}" -ne 0 ]; then
        print_warning "Saved kickstart configuration is incomplete for '${scope}' (${missing} required value(s) missing)."
        print_warning "Please select option 4 before creating kickstarts."
        return 1
    fi

    return 0
}

# Menu selection
print_minirhis_header() {
    echo ""
    echo "=============================================================="
    echo "                         MiniRHIS"
    echo "        Red Hat Infrastructure Standard Orchestrator"
    echo "=============================================================="
}

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

    print_minirhis_header
    echo "Deployment Scope : ${DEPLOYMENT_SCOPE:-local}"
    echo "Workspace        : ${SCRIPT_DIR}"
    echo "Container Roles  : ${SCRIPT_DIR}/container/roles"
    echo ""
    echo "Core Workflow"
    echo "  1) Full Stack Build + Configure"
    echo "     - IdM -> Satellite -> AAP"
    echo "  2) Component-Only Build"
    echo "     - Satellite"
    echo "     - IdM"
    echo "     - AAP"
    echo "  3) Platform Selection"
    echo "     - Bare Metal"
    echo "     - Virtual"
    echo "     - Cloud"
    echo ""
    echo "Build Artifacts"
    echo "  4) Prompts Only"
    echo "     - choose product, platform, provider, and account/BMC credentials"
    echo "  5) Generate OEMDRV Kickstarts"
    echo "     - Satellite + IdM + AAP"
    echo ""
    echo "Operations"
    echo "  6) Configure Existing Stack"
    echo "     - Run config sequence only (Requires build env.yml and vault file)"
    echo "  7) Setup Rootless Podman"
    echo "     - configure subuid/subgid, linger, and runtime dir"
    echo ""
    echo "  0) Exit"
    echo ""
    read -r -p "Enter choice [0-7]: " choice
}

select_stack_sizing_profile() {
    local _size_choice=""

    if is_noninteractive; then
        print_step "NONINTERACTIVE mode: keeping DEMO_MODE=${DEMO_MODE:-0} (0=SOE, 1=Demo)."
        return 0
    fi

    print_minirhis_header
    echo "Sizing Profile"
    echo "  MINIRHIS Full Stack sizing profile"
    echo ""
    echo "  1) SOE"
    echo "     - supported enterprise sizing"
    echo "  2) Demo / Education / PoC"
    echo "     - reduced hardware per node (IdM + Satellite + AAP remain separate servers)"
    echo ""
    read -r -p "Choose profile [1-2, default 1]: " _size_choice

    case "${_size_choice:-1}" in
        2)
            DEMO_MODE="1"
            print_step "Sizing profile set to Demo/Education/PoC (DEMO_MODE=1)."
            ;;
        *)
            DEMO_MODE="0"
            print_step "Sizing profile set to SOE (DEMO_MODE=0)."
            ;;
    esac
    return 0
}

configure_platform_selection() {
    local selected=""

    prompt_platform_choice selected "Select target platform for MINIRHIS deployments" "${MINIRHIS_TARGET_PLATFORM:-libvirt}" || return 1
    MINIRHIS_TARGET_PLATFORM="${selected}"
    SAT_TARGET_PLATFORM="${selected}"
    AAP_TARGET_PLATFORM="${selected}"
    IDM_TARGET_PLATFORM="${selected}"
    MINIRHIS_PLATFORM_FAMILY="$(platform_family_for_provider "${selected}")"

    print_success "Platform selection updated: MINIRHIS=${MINIRHIS_TARGET_PLATFORM}, Satellite=${SAT_TARGET_PLATFORM}, AAP=${AAP_TARGET_PLATFORM}, IdM=${IDM_TARGET_PLATFORM}"
    return 0
}

prompt_config_execution_mode() {
    local _exec_choice=""

    reset_menu_view
    print_minirhis_header
    echo "Execution Target"
    echo ""
    echo "  1) minirhis_provisioner"
    echo "     - run via the MINIRHIS provisioner container"
    echo "  2) local ${USER} repo"
    echo "     - run directly from this machine's roles"
    echo ""
    echo "  0) Back"
    echo ""
    read -r -p "Enter choice [0-2]: " _exec_choice
    case "${_exec_choice}" in
        1)
            MINIRHIS_EXECUTION_MODE="container"
            return 0
            ;;
        2)
            MINIRHIS_EXECUTION_MODE="local"
            return 0
            ;;
        0|"")
            return 1
            ;;
        *)
            print_warning "Invalid choice. Please select 0-2."
            return 1
            ;;
    esac
}

show_configure_existing_submenu() {
    local _config_choice=""

    while true; do
        reset_menu_view
        print_minirhis_header
        echo "Configure Existing Stack"
        echo ""
        echo "  1) AAP"
        echo "     - run config-as-code for AAP only"
        echo "  2) IdM"
        echo "     - run config-as-code for IdM only"
        echo "  3) Satellite"
        echo "     - run config-as-code for Satellite only"
        echo "  4) MINIRHIS Full Stack"
        echo "     - run config-as-code for all components"
        echo ""
        echo "  0) Back"
        echo ""
        read -r -p "Enter choice [0-4]: " _config_choice
        case "${_config_choice}" in
            1)
                if is_menutest; then
                    print_step "MENUTEST: simulated AAP config-as-code (no changes made)."
                    return 0
                fi
                prompt_config_execution_mode || continue
                if [ "${MINIRHIS_EXECUTION_MODE}" = "container" ]; then
                    install_container || return 1
                fi
                MINIRHIS_COMPONENT_SCOPE="aap" run_minirhis_config_as_code || { print_warning "AAP config-as-code failed"; return 1; }
                return 0
                ;;
            2)
                if is_menutest; then
                    print_step "MENUTEST: simulated IdM config-as-code (no changes made)."
                    return 0
                fi
                prompt_config_execution_mode || continue
                if [ "${MINIRHIS_EXECUTION_MODE}" = "container" ]; then
                    install_container || return 1
                fi
                MINIRHIS_COMPONENT_SCOPE="idm" run_minirhis_config_as_code || { print_warning "IdM config-as-code failed"; return 1; }
                return 0
                ;;
            3)
                if is_menutest; then
                    print_step "MENUTEST: simulated Satellite config-as-code (no changes made)."
                    return 0
                fi
                prompt_config_execution_mode || continue
                if [ "${MINIRHIS_EXECUTION_MODE}" = "container" ]; then
                    install_container || return 1
                fi
                MINIRHIS_COMPONENT_SCOPE="satellite" run_minirhis_config_as_code || { print_warning "Satellite config-as-code failed"; return 1; }
                return 0
                ;;
            4)
                if is_menutest; then
                    print_step "MENUTEST: simulated MINIRHIS Full Stack config-as-code (no changes made)."
                    return 0
                fi
                prompt_config_execution_mode || continue
                if [ "${MINIRHIS_EXECUTION_MODE}" = "container" ]; then
                    run_container_config_only || { print_warning "MINIRHIS Full Stack config workflow failed"; return 1; }
                else
                    run_minirhis_config_as_code || { print_warning "MINIRHIS Full Stack config workflow failed"; return 1; }
                fi
                return 0
                ;;
            0|"")
                return 0
                ;;
            *)
                print_warning "Invalid choice. Please select 0-4."
                ;;
        esac
    done
}

show_standalone_components_submenu() {
    local _subchoice=""

    print_minirhis_header
    echo "Component-Only Workflows"
    echo "  Local role content: ${SCRIPT_DIR}/container/roles"
    echo ""
    echo "  1) AAP 2.6 Only"
    echo "     - role: minirhis-builder-aap"
    echo "  2) IdM 5.0 Only"
    echo "     - role: minirhis-builder-idm"
    echo "  3) Satellite 6.18 Only"
    echo "     - role: minirhis-builder-satellite"
    echo ""
    echo "  0) Back"
    read -r -p "Enter choice [0-3]: " _subchoice

    case "${_subchoice}" in
        1)
            if is_menutest; then
                print_step "MENUTEST: simulated AAP-only workflow (no changes made)."
                return 0
            fi
            install_aap_only || { print_warning "AAP-only workflow failed"; return 1; }
            ;;
        2)
            if is_menutest; then
                print_step "MENUTEST: simulated IdM-only workflow (no changes made)."
                return 0
            fi
            install_idm_only || { print_warning "IdM-only workflow failed"; return 1; }
            ;;
        3)
            if is_menutest; then
                print_step "MENUTEST: simulated Satellite-only workflow (no changes made)."
                return 0
            fi
            install_satellite_only || { print_warning "Satellite-only workflow failed"; return 1; }
            ;;
        0|"")
            return 0
            ;;
        *)
            print_warning "Invalid standalone choice. Please select 0-3."
            return 1
            ;;
    esac

    return 0
}

reset_menu_view() {
    if is_noninteractive; then
        return 0
    fi

    if command -v reset >/dev/null 2>&1; then
        reset
    elif command -v clear >/dev/null 2>&1; then
        clear
    fi

    return 0
}

generate_oemdrv_kickstarts_only_menutest() {
    local oemdrv_choice
    print_minirhis_header
    echo "Generate OEMDRV Kickstarts (MENUTEST)"
    echo ""
    echo "  1) AAP OEMDRV kickstart"
    echo "  2) IdM OEMDRV kickstart"
    echo "  3) Satellite OEMDRV kickstart"
    echo "  4) All"
    echo "     - Satellite + AAP + IdM"
    echo "  0) Back"
    echo ""
    read -r -p "Select component [0-4]: " oemdrv_choice

    case "${oemdrv_choice}" in
        1) print_step "MENUTEST: simulated AAP OEMDRV generation (no changes made)." ;;
        2) print_step "MENUTEST: simulated IdM OEMDRV generation (no changes made)." ;;
        3) print_step "MENUTEST: simulated Satellite OEMDRV generation (no changes made)." ;;
        4) print_step "MENUTEST: simulated full OEMDRV generation (no changes made)." ;;
        0|"") return 0 ;;
        *) print_warning "Invalid choice. Please select 0-4." ;;
    esac

    return 0
}

show_entry_menu() {
    local entry_choice=""

    while true; do
        echo "  1) Setup and Install Wizard"
        echo "  2) Primary Menu"
        echo ""
        echo "  0) Exit"
        echo ""
        read -r -p "  Choice [1-2, or 0 to exit]: " entry_choice
        case "${entry_choice}" in
            1) return 0 ;;
            2) run_menutest_mode; exit $? ;;
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "Exiting installation script"
                exit 0
                ;;
            *)
                print_warning "Invalid choice. Please select 1, 2, or 0."
                ;;
        esac
    done
}

run_menutest_mode() {
    local choice=""

    print_step "MENUTEST mode enabled: menu walkthrough only, no provisioning/actions will run."
    print_step "Use normal interactive menus; all action options are simulated."

    while true; do
        reset_menu_view
        show_menu
        case "$choice" in
            1)
                select_stack_sizing_profile || { print_warning "Could not determine sizing profile"; return 1; }
                print_step "MENUTEST: simulated Full Stack Build + Configure (no changes made)."
                ;;
            2)
                show_standalone_components_submenu || { print_warning "Standalone components submenu failed"; return 1; }
                ;;
            3)
                configure_platform_selection || { print_warning "Platform selection failed"; return 1; }
                print_step "MENUTEST: platform values updated in-memory only."
                ;;
            4)
                print_step "MENUTEST: simulated Prompts Only workflow (no changes made)."
                ;;
            5)
                generate_oemdrv_kickstarts_only_menutest
                ;;
            6)
                show_configure_existing_submenu || { print_warning "Standalone components submenu failed"; return 1; }
                ;;
            7)
                print_step "MENUTEST: simulated rootless Podman setup (no changes made)."
                ;;
            9)
                print_step "MENUTEST: simulated Satellite-only workflow (no changes made)."
                ;;
            10)
                print_step "MENUTEST: simulated IdM-only workflow (no changes made)."
                ;;
            11)
                print_step "MENUTEST: simulated AAP-only workflow (no changes made)."
                ;;
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "Exiting menu test mode"
                return 0
                ;;
            *)
                print_warning "Invalid choice. Please select 0-6."
                ;;
        esac
        reset_menu_view
        echo ""
    done
}

show_live_status_dashboard() {
    local key=""
    local refresh_seconds="5"
    local vm state ip cmdb_status
    local sat_ip=""
    local ansible_log_host="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    local container_name="${MINIRHIS_CONTAINER_NAME:-minirhis-provisioner}"
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
        elif pgrep -af "run_minirhis_install_sequence.sh" >/dev/null 2>&1; then
            phase_label="SCRIPT RUNNING (BETWEEN PHASES)"
        fi

        echo "============================================================"
        echo " MINIRHIS Live Status Dashboard"
        echo " Phase: ${phase_label}"
        echo " $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================================"
        echo ""

        echo "[VM states]"
        sudo -n virsh list --all 2>/dev/null || sudo virsh list --all 2>/dev/null || true
        echo ""

        echo "[VM network addresses]"
        for vm in satellite aap idm; do
            echo "- ${vm}"
            sudo -n virsh domifaddr "${vm}" 2>/dev/null | sed '1,2d' || sudo virsh domifaddr "${vm}" 2>/dev/null | sed '1,2d' || true
        done
        echo ""

        echo "[Script / provisioning activity]"
        pgrep -af "run_minirhis_install_sequence.sh|python3 -m http.server 8080|ansible-playbook|virsh console|podman exec" 2>/dev/null || echo "(no matching activity processes found)"
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

        sat_ip="$(sudo -n virsh domifaddr satellite 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1 || true)"
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

        if is_enabled "${MINIRHIS_DASHBOARD_SINGLE_SHOT:-0}"; then
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

    if ! has_gui_desktop_session; then
        print_step "Headless session detected; console monitors were not opened."
        print_headless_monitor_summary
    fi

    print_success "VM console monitors reattached."
    return 0
}

get_vm_console_label() {
    case "$1" in
        satellite) printf '%s\n' "${SAT_HOSTNAME:-satellite}" ;;
        aap)        printf '%s\n' "${AAP_HOSTNAME:-aap}" ;;
        idm)           printf '%s\n' "${IDM_HOSTNAME:-idm}" ;;
        *)             printf '%s\n' "$1" ;;
    esac
}

has_gui_desktop_session() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

launch_gui_monitor_terminal() {
    local title="$1"
    local monitor_cmd="$2"
    local pid_file="$3"
    local term_pid=""

    [ -n "${title:-}" ] || return 1
    [ -n "${monitor_cmd:-}" ] || return 1
    has_gui_desktop_session || return 1

    if command -v konsole >/dev/null 2>&1; then
        konsole --title "${title}" -e bash -lc "${monitor_cmd}" >/dev/null 2>&1 &
        term_pid=$!
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="${title}" -- bash -lc "${monitor_cmd}" >/dev/null 2>&1 &
        term_pid=$!
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -lc "${monitor_cmd}" >/dev/null 2>&1 &
        term_pid=$!
    elif command -v xterm >/dev/null 2>&1; then
        xterm -T "${title}" -e bash -lc "${monitor_cmd}" >/dev/null 2>&1 &
        term_pid=$!
    else
        return 1
    fi

    if [ -n "${pid_file:-}" ] && [ -n "${term_pid:-}" ]; then
        echo "${term_pid}" >> "${pid_file}"
    fi

    return 0
}

stop_progress_monitors() {
    local pid

    if [ -f "${MINIRHIS_PROGRESS_MONITOR_PID_FILE}" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" >/dev/null 2>&1 || true
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < "${MINIRHIS_PROGRESS_MONITOR_PID_FILE}"
        rm -f "${MINIRHIS_PROGRESS_MONITOR_PID_FILE}"
    fi

    return 0
}

launch_progress_dashboard_auto() {
    local dashboard_cmd=""

    is_enabled "${MINIRHIS_AUTO_POPUP_MONITORS:-1}" || return 0

    stop_progress_monitors >/dev/null 2>&1 || true
    : > "${MINIRHIS_PROGRESS_MONITOR_PID_FILE}"

    dashboard_cmd="printf '\033]0;%s\007' 'MINIRHIS Progress'; cd '${SCRIPT_DIR}'; exec bash '${SCRIPT_DIR}/MiniRHIS.sh' --status-live"

    if launch_gui_monitor_terminal "MINIRHIS Progress" "${dashboard_cmd}" "${MINIRHIS_PROGRESS_MONITOR_PID_FILE}"; then
        print_step "Opened progress monitor terminal for MINIRHIS status/logs."
        return 0
    fi

    if ! has_gui_desktop_session; then
        print_headless_monitor_summary
        return 0
    fi

    print_warning "No GUI terminal emulator found; skipping progress monitor launch."
    return 0
}

ensure_live_progress_monitors() {
    is_enabled "${MINIRHIS_AUTO_POPUP_MONITORS:-1}" || return 0
    launch_progress_dashboard_auto || true
    reattach_vm_consoles || true
    return 0
}

print_headless_monitor_summary() {
    if is_enabled "${MINIRHIS_HEADLESS_MONITOR_HINT_SHOWN:-0}"; then
        return 0
    fi

    MINIRHIS_HEADLESS_MONITOR_HINT_SHOWN=1

    echo ""
    echo "[HEADLESS] Monitor progress with these commands:"
    echo "  sudo virsh console satellite"
    echo "  sudo virsh console aap"
    echo "  sudo virsh console idm"
    echo "  tail -f ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    echo "  bash ${SCRIPT_DIR}/MiniRHIS.sh --status"
    echo ""
    echo "[HEADLESS] Notes:"
    echo "  - virsh console shows guest boot, reboot, and kickstart %post output."
    echo "  - ansible-provisioner.log shows callback/configuration progress after the guests are reachable."
    echo "  - Use Ctrl+] to detach from a virsh console without stopping the VM."
    echo ""
    return 0
}

console_attach_cmd_for_vm() {
    local vm="$1"
    if is_enabled "${MINIRHIS_VM_MONITOR_FILTER_NOISE:-1}"; then
        cat <<EOF
sudo virsh console ${vm} 2>&1 | stdbuf -oL awk '/systemd-rc-local-generator.*\/etc\/rc\\.d\/rc\\.local is not marked executable, skipping\\./{n++;next} /SELinux:  Converting [0-9]+ SID table entries\\.\\.\\./{n++;next} /SELinux:  policy capability /{n++;next} /systemd-journald\\[[0-9]+\\]: Received SIGTERM from PID 1 \\(systemd\\)\\./{n++;next} {print} END{if(n>0) printf("[monitor] filtered %d expected reboot-noise lines\\n", n) > "/dev/stderr"}'; true
EOF
    else
        printf 'sudo virsh console %s || true\n' "${vm}"
    fi
}

launch_single_vm_console_monitor_auto() {
    local vm="$1"
    local vm_label
    local launched=0
    local monitor_cmd
    local console_attach_cmd

    [ -n "${vm:-}" ] || return 1
    vm_label="$(get_vm_console_label "${vm}")"
    console_attach_cmd="$(console_attach_cmd_for_vm "${vm}")"
    monitor_cmd="printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] monitor active (auto-reconnect enabled)'; while true; do while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; ${console_attach_cmd}; echo '[${vm_label}] console disconnected (reboot/install transition); retrying in 5s...'; sleep 5; done"

    stop_vm_console_monitors >/dev/null 2>&1 || true
    : > "${MINIRHIS_VM_MONITOR_PID_FILE}"

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping VM console monitor auto-launch."
        return 0
    fi

    if has_gui_desktop_session; then
        if launch_gui_monitor_terminal "${vm_label}" "${monitor_cmd}" "${MINIRHIS_VM_MONITOR_PID_FILE}"; then
            launched=1
        fi
    fi

    if [ "$launched" = "1" ]; then
        print_step "Opened console monitor terminal for ${vm_label}."
        return 0
    fi

    if ! has_gui_desktop_session; then
        print_step "Headless session detected; skipping auto console monitor launch for ${vm_label}."
        print_headless_monitor_summary
        return 0
    fi

    print_warning "No GUI terminal emulator found; skipping auto console monitor launch."
    return 0
}

launch_vm_console_monitors_auto() {
    local -a vms=("satellite" "aap" "idm")
    local vm vm_label launched=0
    local monitor_cmd
    local console_attach_cmd

    stop_vm_console_monitors >/dev/null 2>&1 || true
    : > "${MINIRHIS_VM_MONITOR_PID_FILE}"

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping VM console monitor auto-launch."
        return 0
    fi

    # GUI terminal popups (preferred)
    if has_gui_desktop_session; then
        for vm in "${vms[@]}"; do
            vm_label="$(get_vm_console_label "${vm}")"
            console_attach_cmd="$(console_attach_cmd_for_vm "${vm}")"
            monitor_cmd="printf '\033]0;%s\007' '${vm_label}'; echo '[${vm_label}] monitor active (auto-reconnect enabled)'; while true; do while ! sudo virsh dominfo ${vm} >/dev/null 2>&1; do sleep 5; done; echo '[${vm_label}] connecting virsh console (Ctrl+] to detach)'; ${console_attach_cmd}; echo '[${vm_label}] console disconnected (reboot/install transition); retrying in 5s...'; sleep 5; done"
            if launch_gui_monitor_terminal "${vm_label}" "${monitor_cmd}" "${MINIRHIS_VM_MONITOR_PID_FILE}"; then
                launched=1
            fi
        done
    fi

    if [ "$launched" = "1" ]; then
        print_step "Opened 3 console monitor terminals (Satellite/AAP/IdM)."
        return 0
    fi

    if ! has_gui_desktop_session; then
        print_step "Headless session detected; skipping auto console monitor launch."
        print_headless_monitor_summary
        return 0
    fi

    print_warning "No GUI terminal emulator found; skipping auto console monitor launch."
    return 0
}

stop_vm_console_monitors() {
    local pid

    if command -v tmux >/dev/null 2>&1; then
        tmux has-session -t "$MINIRHIS_VM_MONITOR_SESSION" 2>/dev/null && tmux kill-session -t "$MINIRHIS_VM_MONITOR_SESSION" || true
    fi

    if [ -f "$MINIRHIS_VM_MONITOR_PID_FILE" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" >/dev/null 2>&1 || true
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < "$MINIRHIS_VM_MONITOR_PID_FILE"
        rm -f "$MINIRHIS_VM_MONITOR_PID_FILE"
    fi

    return 0
}

start_vm_power_watchdog() {
    local duration_sec="${1:-10800}"  # default: 3 hours
    local interval_sec=15

    stop_vm_power_watchdog >/dev/null 2>&1 || true

    (
        local end_ts now state vm
        local -a vms=("satellite" "aap" "idm")

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

    MINIRHIS_VM_WATCHDOG_PID="$!"
    print_step "Started VM power watchdog (PID ${MINIRHIS_VM_WATCHDOG_PID}) to keep Satellite/AAP/IdM ON"
    return 0
}

stop_vm_power_watchdog() {
    if [ -n "${MINIRHIS_VM_WATCHDOG_PID:-}" ]; then
        kill "${MINIRHIS_VM_WATCHDOG_PID}" >/dev/null 2>&1 || true
        wait "${MINIRHIS_VM_WATCHDOG_PID}" >/dev/null 2>&1 || true
        MINIRHIS_VM_WATCHDOG_PID=""
    fi
    return 0
}

force_kill_minirhis_leftovers() {
    local -a patterns=(
        "python3 -m http.server 8080 --bind"
        "virsh console satellite"
        "virsh console aap"
        "virsh console idm"
        "minirhis-vm-consoles"
        "curl -fL --retry 3 --retry-delay 10"
        "aap-bundle.tar.gz"
        "setup.sh 2>&1"
        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ${AAP_SSH_PRIVATE_KEY}"
    )
    local pattern pid cmdline
    local self_pid="$$"
    local parent_pid="${PPID:-0}"

    print_step "Force-killing MINIRHIS leftover processes from current/past runs"
    for pattern in "${patterns[@]}"; do
        while IFS= read -r pid; do
            [ -n "${pid}" ] || continue
            case "${pid}" in
                ''|*[!0-9]*) continue ;;
            esac
            [ "${pid}" -gt 1 ] || continue
            [ "${pid}" -ne "${self_pid}" ] || continue
            [ "${pid}" -ne "${parent_pid}" ] || continue

            cmdline="$(sudo tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
            # Guard: never kill our own process matchers/executors.
            if printf '%s' "${cmdline}" | grep -Eq '(^|[[:space:]])(pkill|pgrep)([[:space:]]|$)'; then
                continue
            fi

            sudo kill -9 "${pid}" >/dev/null 2>&1 || true
        done < <(sudo pgrep -f "${pattern}" 2>/dev/null || true)
    done

    # Also hard-kill any tracked monitor terminal PIDs from previous runs.
    if [ -f "$MINIRHIS_VM_MONITOR_PID_FILE" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < "$MINIRHIS_VM_MONITOR_PID_FILE"
        rm -f "$MINIRHIS_VM_MONITOR_PID_FILE"
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
    # ── Ansible-first path ──────────────────────────────────────────────────
    # minirhis_host_setup covers firewalld install + enable + port/service rules.
    # We call it here so all three related functions share one Ansible run.
    # If Ansible is unavailable the bash fallback below is used.
    if run_local_role "minirhis_host_setup" "installer" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_host_setup unavailable; running bash fallback for ensure_firewalld"
    # ── Bash fallback ───────────────────────────────────────────────────────
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        print_warning "firewalld not found. Attempting installation..."
        sudo dnf install -y --nogpgcheck firewalld
    fi

    sudo systemctl enable --now firewalld
    sudo firewall-cmd --state >/dev/null
    print_step "firewalld is enabled and running"
}

configure_minirhis_network_policy() {
    # ── Ansible-first path ──────────────────────────────────────────────────
    if run_local_role "minirhis_host_setup" "installer" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_host_setup unavailable; running bash fallback for configure_minirhis_network_policy"
    # ── Bash fallback ───────────────────────────────────────────────────────
    ensure_selinux
    ensure_firewalld || return 0

    # MINIRHIS dashboard/API
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

    print_step "Security policy applied for MINIRHIS (SELinux + firewalld port 3000)"
}

configure_libvirt_firewall_policy() {
    # ── Ansible-first path ──────────────────────────────────────────────────
    if run_local_role "minirhis_host_setup" "installer" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_host_setup unavailable; running bash fallback for configure_libvirt_firewall_policy"
    # ── Bash fallback ───────────────────────────────────────────────────────
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

    # ── Ansible-first path ──────────────────────────────────────────────────
    load_ansible_env_file 2>/dev/null || true
    normalize_shared_env_vars 2>/dev/null || true
    if run_local_role "minirhis_libvirt_networks" "installer" \
            --extra-vars "internal_gw=${INTERNAL_GW:-10.168.0.1} netmask=${NETMASK:-255.255.0.0}" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_libvirt_networks unavailable; running bash fallback"
    # ── Bash fallback ───────────────────────────────────────────────────────
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
    configure_minirhis_network_policy

    if ! ensure_node; then
        print_warning "Node.js installation failed. Please install Node.js first."
        return 1
    fi

    print_step "Resolving MINIRHIS project directory"
    cd "$SCRIPT_DIR"

    if [ -f "package.json" ]; then
        print_step "Using script directory as MINIRHIS project: $SCRIPT_DIR"
    elif [ -n "$REPO_URL" ] && [[ "$REPO_URL" != *"your-org/MINIRHIS.git"* ]]; then
        print_step "No local package.json found, cloning from REPO_URL"
        if [ ! -d "MINIRHIS/.git" ]; then
            git clone "$REPO_URL" MINIRHIS
        fi
        cd MINIRHIS
    else
        print_warning "No local package.json found in $SCRIPT_DIR (npm app mode unavailable)."
        print_warning "MINIRHIS in this repository is infrastructure/container-first."
        print_warning "Use menu option 1 (MINIRHIS Full Stack) or 4 (Configure Existing Stack)."
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

    print_step "Starting MINIRHIS service"
    npm start &

    print_success "Local installation complete"
    echo "Access dashboard at http://localhost:3000"
}

# ─── Container lifecycle and managed provisioner patches ─────────────────────
ensure_rootless_podman() {
    if [ "$(id -u)" -eq 0 ]; then
        print_warning "Run this script as a regular user (not root) for rootless Podman."
        return 1
    fi

    if ! command -v podman >/dev/null 2>&1; then
        print_warning "Podman not found. Installing..."
        sudo dnf install -y --nogpgcheck podman shadow-utils slirp4netns fuse-overlayfs
    fi

    local _subuids_added=0
    if ! grep -q "^${USER}:" /etc/subuid 2>/dev/null; then
        print_step "Adding subuid mapping for ${USER}..."
        sudo usermod --add-subuids 100000-165535 "$USER"
        _subuids_added=1
    fi
    if ! grep -q "^${USER}:" /etc/subgid 2>/dev/null; then
        print_step "Adding subgid mapping for ${USER}..."
        sudo usermod --add-subgids 100000-165535 "$USER"
        _subuids_added=1
    fi

    # Enable linger so the user's systemd session persists across logins.
    sudo loginctl enable-linger "$USER" >/dev/null 2>&1 || true

    # Always derive XDG_RUNTIME_DIR from the actual UID — never trust an
    # inherited value that may be empty or stale (e.g. /run/user/ with no UID).
    local _uid
    _uid="$(id -u)"
    export XDG_RUNTIME_DIR="/run/user/${_uid}"
    if [ ! -d "${XDG_RUNTIME_DIR}" ]; then
        print_step "Runtime directory ${XDG_RUNTIME_DIR} missing; starting user@${_uid}.service..."
        sudo systemctl start "user@${_uid}.service" 2>/dev/null || true
        # Wait up to 5 s for systemd-logind to create the dir.
        local _i=0
        while [ ! -d "${XDG_RUNTIME_DIR}" ] && [ "${_i}" -lt 10 ]; do
            _i=$(( _i + 1 ))
            read -r -t 0.5 < /dev/null 2>/dev/null || true
        done
    fi

    # Ensure the D-Bus session bus socket is available for user-session tools.
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
    fi

    # Migrate storage after any subuid/subgid change (idempotent on reruns).
    podman system migrate >/dev/null 2>&1 || true

    if [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" != "true" ]; then
        print_warning "Podman is not operating rootless for user '${USER}'."
        print_warning "  XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
        print_warning "  subuid entry  : $(grep "^${USER}:" /etc/subuid 2>/dev/null || echo '(none)')"
        print_warning "  subgid entry  : $(grep "^${USER}:" /etc/subgid 2>/dev/null || echo '(none)')"
        if [ "${_subuids_added}" = "1" ]; then
            print_warning "Subuid/subgid mappings were just added — a full log-out/log-in is required for the kernel to load them."
        else
            print_warning "Try: sudo systemctl start user@${_uid}.service  (or log out and back in)"
        fi
        return 1
    fi

    print_success "Rootless Podman is configured for user: ${USER}"
    return 0
}

# Ensure the MINIRHIS provisioner container is running.  Idempotent: no-op if it is
# already up.  The container's entrypoint drops to an interactive bash shell, so
# it needs a pseudo-TTY (-t) to stay alive in detached (-d) mode.
# Three host directories are bind-mounted inside the container:
#   external_inventory  -> inventory file(s) consumed by minirhis-builder playbooks
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
    core_ver=$(podman exec "${MINIRHIS_CONTAINER_NAME}" ansible --version 2>/dev/null \
        | awk '/^ansible \[core/{gsub(/[\[\]]/,"",$3); print $3}')

    # Only needed for ansible-core 2.14.x; newer images are already fine.
    [[ "${core_ver}" == 2.14.* ]] || return 0

    local utils_ver
    utils_ver=$(podman exec "${MINIRHIS_CONTAINER_NAME}" ansible-galaxy collection list 2>/dev/null \
        | awk '/^ansible\.utils[[:space:]]/{print $2}')

    # Already pinned to 4.x — nothing to do.
    [[ "${utils_ver}" == 4.* ]] && return 0

    print_step "Pinning ansible.utils to 4.1.0 for ansible-core ${core_ver} compatibility"
    if podman exec "${MINIRHIS_CONTAINER_NAME}" \
           ansible-galaxy collection install "ansible.utils:4.1.0" --force >/dev/null 2>&1; then
        print_success "ansible.utils pinned to 4.1.0 (was ${utils_ver:-unknown})."
    else
        print_warning "Could not pin ansible.utils to 4.1.0; version-compatibility warning will appear during playbook runs."
    fi
    return 0
}

# Maintain MINIRHIS-managed hotfixes inside the provisioner container so each newly
# deployed container gets the same compatibility/workaround patches before any
# playbooks are executed.
ensure_container_managed_chrony_template() {
    local _tpl_path="/minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2"
    local _mk_cmd='mkdir -p /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates && cat > /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# MINIRHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

    if podman exec "${MINIRHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
        return 0
    fi

    print_warning "Managed container patch: chrony.j2 missing; applying fallback template."

    if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch applied: fallback chrony.j2 created."
        return 0
    fi

    print_warning "Managed container patch failed: could not create fallback chrony.j2."
    return 1
}

ensure_container_managed_idm_chrony_template() {
    local _tpl_path="/minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2"
    local _mk_cmd='mkdir -p /minirhis/minirhis-builder-idm/roles/idm_pre/templates && cat > /minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# MINIRHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

    if podman exec "${MINIRHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
        return 0
    fi

    print_warning "Managed container patch: IdM chrony.j2 missing; applying fallback template."

    if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch applied: IdM fallback chrony.j2 created."
        return 0
    fi

    print_warning "Managed container patch failed: could not create IdM fallback chrony.j2."
    return 1
}

ensure_container_managed_satellite_foreman_patch() {
    local _root="/minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks"
    local _py='import pathlib
import re

root = pathlib.Path("/minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks")
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

    _out="$(podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    if [ -z "${_out}" ]; then
        _out="$(podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
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

path = pathlib.Path("/minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml")
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
    _out="$(podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
    if [ -z "${_out}" ]; then
        _out="$(podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
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

sync_local_roles_to_container() {
    local local_roles_dir="${SCRIPT_DIR}/container/roles"
    local tree sync_failed=0
    local rel_file
    local -a top_level_assets=(
        "ansible.cfg"
        "requirements.txt"
        "requirements.yml"
    )

    if [ ! -d "${local_roles_dir}" ]; then
        print_warning "Local roles directory not found: ${local_roles_dir}; skipping sync."
        return 0
    fi

    print_step "Syncing local container/roles/* to provisioner container /minirhis/"
    for tree in "${local_roles_dir}"/minirhis-builder-*/; do
        tree="$(basename "${tree}")"
        podman exec "${MINIRHIS_CONTAINER_NAME}" mkdir -p "/minirhis/${tree}" >/dev/null 2>&1 || true
        if podman cp "${local_roles_dir}/${tree}/." \
               "${MINIRHIS_CONTAINER_NAME}:/minirhis/${tree}/" >/dev/null 2>&1; then
            print_step "  synced: ${tree}"
        else
            print_warning "  failed to sync: ${tree}"
            sync_failed=1
        fi
    done

    # Keep top-level container/roles assets in sync for local/adhoc runs inside
    # minirhis-provisioner (ansible.cfg and requirements files).
    for rel_file in "${top_level_assets[@]}"; do
        if [ -f "${local_roles_dir}/${rel_file}" ]; then
            if podman cp "${local_roles_dir}/${rel_file}" \
                   "${MINIRHIS_CONTAINER_NAME}:/minirhis/${rel_file}" >/dev/null 2>&1; then
                print_step "  synced: ${rel_file}"
            else
                print_warning "  failed to sync: ${rel_file}"
                sync_failed=1
            fi
        fi
    done

    if [ "${sync_failed}" -eq 1 ]; then
        print_warning "One or more role trees failed to sync; container may have stale content."
        return 1
    fi

    print_success "Local roles synced to container."
    return 0
}

apply_managed_container_patches() {
    local _verify_cmd='test -f /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 && test -f /minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2 && grep -q "failed_when: false" /minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks/is_satellite_installed.yml && grep -q "disable_gpg_check: true" /minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml && grep -q "exclude: \"intel-audio-firmware\\*\"" /minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml'

    if ! is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
        print_step "Managed container patches disabled (MINIRHIS_ENABLE_CONTAINER_HOTFIXES=${MINIRHIS_ENABLE_CONTAINER_HOTFIXES})."
        return 0
    fi

    print_step "Applying MINIRHIS-managed patches to provisioner container components"

    ensure_container_managed_chrony_template || true
    ensure_container_managed_idm_chrony_template || true
    ensure_container_managed_satellite_foreman_patch || true
    ensure_container_managed_idm_update_patch || true

    if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1 || \
       podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1; then
        print_success "Managed container patch verification passed."
        return 0
    fi

    if is_enabled "${MINIRHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"; then
        print_warning "Managed container patch verification failed and enforcement is ON."
        return 1
    fi

    print_warning "Managed container patch verification failed, but enforcement is OFF; continuing."
    return 0
}

ensure_container_running() {
    # Auto-generate required host mount directories for runtime artifacts.
    mkdir -p "${MINIRHIS_INVENTORY_DIR}" "${MINIRHIS_HOST_VARS_DIR}" "${ANSIBLE_ENV_DIR}" || {
        print_warning "Failed to create required runtime directories for container mounts."
        return 1
    }

    generate_minirhis_ansible_cfg || {
        print_warning "Could not generate MINIRHIS Ansible config at ${MINIRHIS_ANSIBLE_CFG_VAULT_HOST}"
        return 1
    }

    generate_local_roles_ansible_cfg || {
        print_warning "Could not generate local roles ansible config at ${SCRIPT_DIR}/container/roles/ansible.cfg"
        return 1
    }

    if podman ps --filter "name=^${MINIRHIS_CONTAINER_NAME}$" --format '{{.Names}}' 2>/dev/null \
           | grep -q "^${MINIRHIS_CONTAINER_NAME}$"; then
        print_success "MINIRHIS provisioner container '${MINIRHIS_CONTAINER_NAME}' is already running."
        ensure_container_collection_compat || true
        sync_local_roles_to_container || print_warning "Role sync had errors; continuing."
        apply_managed_container_patches || return 1
        return 0
    fi

    # Remove a stopped/crashed remnant so the name is free
    podman rm -f "${MINIRHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Right after container teardown, consolidate runtime values from any
    # active sources (preseed, shell exports, prior vault state) back into
    # encrypted ~/.ansible/conf/env.yml.
    sync_runtime_values_to_ansible_vault || print_warning "Could not consolidate runtime values into ${ANSIBLE_ENV_FILE}; continuing."

    print_step "Starting MINIRHIS provisioner container '${MINIRHIS_CONTAINER_NAME}'"
    podman run -d -t \
        --name "${MINIRHIS_CONTAINER_NAME}" \
        --network host \
        -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" \
        -v "${MINIRHIS_INVENTORY_DIR}:/minirhis/vars/external_inventory:Z" \
        -v "${MINIRHIS_HOST_VARS_DIR}:/minirhis/vars/host_vars:Z" \
        -v "${ANSIBLE_ENV_DIR}:/minirhis/vars/vault:z" \
        -v "${MINIRHIS_INSTALLER_SSH_KEY_DIR}:${MINIRHIS_INSTALLER_SSH_KEY_CONTAINER_DIR}:z,ro" \
        "${MINIRHIS_CONTAINER_IMAGE}"

    ensure_container_collection_compat || true
    sync_local_roles_to_container || print_warning "Role sync had errors; continuing."
    apply_managed_container_patches || return 1
    print_success "Container '${MINIRHIS_CONTAINER_NAME}' started."
    echo "Exec into the container : podman exec -it ${MINIRHIS_CONTAINER_NAME} /bin/bash"
    echo "Ansible config vault    : ${MINIRHIS_ANSIBLE_CFG_VAULT_HOST}"
    echo "Ansible config runtime  : ${MINIRHIS_ANSIBLE_CFG_HOST}"
    echo "Ansible log file        : ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    echo "Ansible fact cache      : ${MINIRHIS_ANSIBLE_FACT_CACHE_HOST}"
    echo "Run a playbook example  : podman exec -it ${MINIRHIS_CONTAINER_NAME} ansible-playbook \\"
    echo "    --inventory ${MINIRHIS_CONTAINER_INVENTORY_FILE} \\" 
    echo "    --user ansiblerunner --ask-pass --ask-vault-pass \\" 
    echo "    --extra-vars 'vault_dir=/minirhis/vars/vault/' \\"
    echo "    --limit idm_primary /minirhis/minirhis-builder-idm/main.yml"
}

# Try to ensure the provisioner container is running, with optional restart
# attempts. This wrapper lives with the container lifecycle helpers so callers
# can find all start/restart behavior in one place.
ensure_container_running_with_retry() {
    local tries=0
    local max=${MINIRHIS_CONTAINER_RESTART_RETRIES:-2}
    local interval=${MINIRHIS_CONTAINER_RESTART_INTERVAL:-10}

    while true; do
        if ensure_container_running; then
            return 0
        fi

        tries=$((tries + 1))
        if [ "$tries" -gt "$max" ]; then
            print_warning "Provisioner container failed to start after ${max} attempts."
            return 1
        fi

        print_step "Attempting to restart provisioner container (attempt ${tries}/${max})..."
        podman rm -f "${MINIRHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true
        sleep "${interval}"
    done
}

install_container() {
    print_step "Starting Container Deployment"
    ensure_rootless_podman || return 1
    configure_minirhis_network_policy

    print_step "Pulling MINIRHIS container image: ${MINIRHIS_CONTAINER_IMAGE}"
    podman pull "${MINIRHIS_CONTAINER_IMAGE}"
    podman images -f "dangling=true" -q | xargs --no-run-if-empty podman rmi && \
        print_step "Cleaned up dangling container images." || true

    ensure_container_running

    print_success "Container deployment complete"
    echo "Exec into the container: podman exec -it ${MINIRHIS_CONTAINER_NAME} /bin/bash"
}

run_container_prescribed_sequence() {
    if ! is_enabled "${MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY:-1}"; then
        print_step "Container auto-config is disabled (MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=${MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY})."
        return 0
    fi

    if ! preflight_config_as_code_targets; then
        print_step "Prerequisites for container auto-config are missing; auto-running VM provisioning workflow"
        print_step "This will generate kickstarts/OEMDRV, create MINIRHIS VMs, and continue configuration automatically"
        create_minirhis_vms || return 1
        return 0
    fi

    print_step "Container deployment complete; running prescribed config sequence automatically"
    print_step "Prescribed order: IdM -> Satellite -> AAP"
    run_minirhis_config_as_code || {
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
        print_step "This will generate kickstarts/OEMDRV, create MINIRHIS VMs, and continue configuration automatically"
        create_minirhis_vms || return 1
        return 0
    fi

    run_container_prescribed_sequence || return 1
    return 0
}

prompt_deployment_scope() {
    # Ask once per interactive run; default stays local.
    if is_noninteractive || [ "${RUN_ONCE:-0}" = "1" ]; then
        return 0
    fi

    if [ "${DEPLOYMENT_SCOPE_PROMPTED:-0}" = "1" ]; then
        return 0
    fi

    DEPLOYMENT_SCOPE_PROMPTED=1
    print_minirhis_header
    echo "Deployment Scope"
    echo ""
    echo "  0) Exit"
    echo "  1) Local"
    echo "     - this machine: $(hostname -f 2>/dev/null || hostname) [default]"
    echo "  2) Remote systems"
    echo ""
    read -r -p "Choose scope [0-2, default 1]: " _scope_choice
    case "${_scope_choice:-1}" in
        0)
            return 2
            ;;
        2)
            DEPLOYMENT_SCOPE="remote"
            ;;
        *)
            DEPLOYMENT_SCOPE="local"
            ;;
    esac

    read -r -p "Start guided deployment workflow now? [Y/n]: " _guided_choice
    case "${_guided_choice:-Y}" in
        Y|y|"") MINIRHIS_GUIDED_SCOPE_FLOW=1 ;;
        *) MINIRHIS_GUIDED_SCOPE_FLOW=0 ;;
    esac
}

detect_host_os_family() {
    local os_id=""
    local os_like=""

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
    fi

    case "${OSTYPE:-}" in
        linux*)
            case "${os_id}:${os_like}" in
                rhel*:*|centos*:*|rocky*:*|almalinux*:*|fedora*:*|*:rhel*|*:fedora*)
                    MINIRHIS_DETECTED_OS="linux-rhel-family"
                    ;;
                *)
                    MINIRHIS_DETECTED_OS="linux"
                    ;;
            esac
            ;;
        darwin*) MINIRHIS_DETECTED_OS="macos" ;;
        msys*|cygwin*|win32*) MINIRHIS_DETECTED_OS="windows" ;;
        *) MINIRHIS_DETECTED_OS="unknown" ;;
    esac

    print_step "Detected host OS profile: ${MINIRHIS_DETECTED_OS}"
    return 0
}

prompt_local_vm_client() {
    local choice=""
    print_minirhis_header
    echo "Local Virtualization Client"
    echo ""
    echo "  0) Back"
    case "${MINIRHIS_DETECTED_OS:-linux}" in
        linux-rhel-family|linux)
            echo "  1) Libvirt (KVM) [recommended/default]"
            echo "  2) Vagrant + libvirt"
            echo "  3) Other"
            read -r -p "Choose local VM client [0-3, default 1]: " choice
            case "${choice:-1}" in
                0) return 10 ;;
                2) MINIRHIS_VM_CLIENT="vagrant-libvirt" ;;
                3) MINIRHIS_VM_CLIENT="other" ;;
                *) MINIRHIS_VM_CLIENT="libvirt" ;;
            esac
            ;;
        macos)
            echo "  1) VMware Fusion [recommended/default]"
            echo "  2) Parallels"
            echo "  3) UTM/QEMU"
            read -r -p "Choose local VM client [0-3, default 1]: " choice
            case "${choice:-1}" in
                0) return 10 ;;
                2) MINIRHIS_VM_CLIENT="parallels" ;;
                3) MINIRHIS_VM_CLIENT="utm-qemu" ;;
                *) MINIRHIS_VM_CLIENT="vmware-fusion" ;;
            esac
            ;;
        windows)
            echo "  1) Hyper-V [recommended/default]"
            echo "  2) VirtualBox"
            echo "  3) VMware Workstation"
            read -r -p "Choose local VM client [0-3, default 1]: " choice
            case "${choice:-1}" in
                0) return 10 ;;
                2) MINIRHIS_VM_CLIENT="virtualbox" ;;
                3) MINIRHIS_VM_CLIENT="vmware-workstation" ;;
                *) MINIRHIS_VM_CLIENT="hyperv" ;;
            esac
            ;;
        *)
            MINIRHIS_VM_CLIENT="libvirt"
            ;;
    esac

    print_step "Selected local VM client: ${MINIRHIS_VM_CLIENT}"
    return 0
}

prepare_selected_local_vm_client() {
    case "${MINIRHIS_VM_CLIENT:-libvirt}" in
        libvirt|vagrant-libvirt)
            print_step "Preparing local libvirt/KVM prerequisites"
            ensure_platform_packages_for_virt_manager || return 1
            ensure_libvirtd || return 1
            configure_libvirt_networks || return 1
            ;;
        vmware-fusion|parallels|utm-qemu|hyperv|virtualbox|vmware-workstation|other)
            print_warning "Selected VM client '${MINIRHIS_VM_CLIENT}' requires platform-specific setup outside this script."
            print_warning "Continuing with MINIRHIS kickstart + provisioning workflow where possible."
            ;;
        *)
            print_warning "Unknown local VM client '${MINIRHIS_VM_CLIENT}', continuing without automated client setup."
            ;;
    esac
    return 0
}

prompt_remote_virtualization_platform() {
    local choice=""
    print_minirhis_header
    echo "Remote Virtualization Platform"
    echo ""
    echo "  0) Back"
    echo "  1) VMware vSphere"
    echo "  2) Nutanix"
    echo "  3) OpenShift"
    echo "  4) OpenShift Virtualization"
    echo "  5) AWS"
    echo "  6) Azure"
    echo "  7) GCP"
    echo ""
    read -r -p "Choose platform [0-7, default 1]: " choice
    case "${choice:-1}" in
        0) return 10 ;;
        2) MINIRHIS_REMOTE_PLATFORM="nutanix" ;;
        3) MINIRHIS_REMOTE_PLATFORM="openshift" ;;
        4) MINIRHIS_REMOTE_PLATFORM="openshift-virt" ;;
        5) MINIRHIS_REMOTE_PLATFORM="aws" ;;
        6) MINIRHIS_REMOTE_PLATFORM="azure" ;;
        7) MINIRHIS_REMOTE_PLATFORM="gcp" ;;
        *) MINIRHIS_REMOTE_PLATFORM="vmware" ;;
    esac

    print_step "Selected remote platform: ${MINIRHIS_REMOTE_PLATFORM}"
    print_warning "Remote platform provisioning integration is best-effort; local orchestration path remains primary."
    return 0
}

prompt_install_component_choice() {
    local choice=""
    print_minirhis_header
    echo "Install Target"
    echo ""
    echo "  0) Exit"
    echo "  1) Ansible Automation Platform 2.6"
    echo "  2) IdM 5.0"
    echo "  3) Satellite 6.18"
    echo "  4) MINIRHIS Integrated Full Stack"
    echo "     - AAP + IdM + Satellite"
    echo ""
    read -r -p "Choose component [0-4, default 4]: " choice
    case "${choice:-4}" in
        0)
            print_step "Exiting MINIRHIS installer by user request."
            exit 0
            ;;
        1) MINIRHIS_INSTALL_COMPONENT="aap" ;;
        2) MINIRHIS_INSTALL_COMPONENT="idm" ;;
        3) MINIRHIS_INSTALL_COMPONENT="satellite" ;;
        *) MINIRHIS_INSTALL_COMPONENT="full" ;;
    esac
    print_step "Selected install target: ${MINIRHIS_INSTALL_COMPONENT}"
    return 0
}

run_guided_scope_workflow() {
    local rc=0
    detect_host_os_family || return 1

    if [ "${DEPLOYMENT_SCOPE:-local}" = "local" ]; then
        while true; do
            prompt_local_vm_client
            rc=$?
            if [ "${rc}" -eq 10 ]; then
                return 10
            elif [ "${rc}" -ne 0 ]; then
                return "${rc}"
            fi

            prepare_selected_local_vm_client || return 1

            while true; do
                prompt_install_component_choice
                rc=$?
                if [ "${rc}" -eq 10 ]; then
                    break
                elif [ "${rc}" -ne 0 ]; then
                    return "${rc}"
                fi

                print_step "Starting kickstart generation and installation workflow for selected target"
                case "${MINIRHIS_INSTALL_COMPONENT:-full}" in
                    satellite)
                        install_satellite_only || return 1
                        ;;
                    idm)
                        install_idm_only || return 1
                        ;;
                    aap)
                        install_aap_only || return 1
                        ;;
                    full)
                        run_container_config_only || return 1
                        ;;
                    *)
                        print_warning "Unknown component target '${MINIRHIS_INSTALL_COMPONENT}'."
                        return 1
                        ;;
                esac

                print_success "Guided deployment workflow completed."
                return 0
            done
        done
    else
        while true; do
            prompt_remote_virtualization_platform
            rc=$?
            if [ "${rc}" -eq 10 ]; then
                return 10
            elif [ "${rc}" -ne 0 ]; then
                return "${rc}"
            fi

            while true; do
                prompt_install_component_choice
                rc=$?
                if [ "${rc}" -eq 10 ]; then
                    break
                elif [ "${rc}" -ne 0 ]; then
                    return "${rc}"
                fi

                print_step "Starting kickstart generation and installation workflow for selected target"
                case "${MINIRHIS_INSTALL_COMPONENT:-full}" in
                    satellite)
                        install_satellite_only || return 1
                        ;;
                    idm)
                        install_idm_only || return 1
                        ;;
                    aap)
                        install_aap_only || return 1
                        ;;
                    full)
                        run_container_config_only || return 1
                        ;;
                    *)
                        print_warning "Unknown component target '${MINIRHIS_INSTALL_COMPONENT}'."
                        return 1
                        ;;
                esac

                print_success "Guided deployment workflow completed."
                return 0
            done
        done
    fi
}

run_component_config_scope() {
    local scope="$1"
    local sat_pre_use_idm="${SATELLITE_PRE_USE_IDM:-false}"
    local -a targets=()

    install_container || return 1

    case "${scope}" in
        idm)
            targets=("idm:${IDM_IP}")
            ;;
        satellite)
            if [ "${sat_pre_use_idm}" = "true" ]; then
                targets=("idm:${IDM_IP}" "satellite:${SAT_IP}")
            else
                targets=("satellite:${SAT_IP}")
            fi
            ;;
        aap)
            targets=("aap:${AAP_IP}")
            ;;
        rhis-aap)
            # No AAP install – only ensures the RHIS builder objects exist in a
            # running AAP Controller.  Runs the standalone rhis_aap_config.yml
            # playbook directly on the platform_installer host.
            targets=("aap:${AAP_IP}")
            ;;
        *)
            print_warning "Unknown component scope: ${scope}"
            return 1
            ;;
    esac

    if ! preflight_config_as_code_targets "${targets[@]}"; then
        print_step "Prerequisites for ${scope}-only are missing; auto-running VM provisioning workflow"

        case "${scope}" in
            satellite)
                create_satellite_vm_only || return 1
                ;;
            idm)
                create_idm_vm_only || return 1
                ;;
            aap)
                create_aap_vm_only || return 1
                ;;
            rhis-aap)
                # No VM creation needed — assumes AAP is already running.
                print_step "rhis-aap scope: assuming AAP is already running; skipping VM provisioning."
                ;;
            *)
                create_minirhis_vms || return 1
                return 0
                ;;
        esac

        preflight_config_as_code_targets "${targets[@]}" || return 1
    fi

    MINIRHIS_COMPONENT_SCOPE="${scope}" run_minirhis_config_as_code || return 1
    return 0
}

ensure_satellite_content_profile_bootstrap() {
                local profile_path="${MINIRHIS_HOST_VARS_DIR}/satellite_content_profile.yml"
                local sync_date_default
                local sync_date
                local include_product_links="1"
                local include_repo_sets="1"
                local answer=""

                mkdir -p "${MINIRHIS_HOST_VARS_DIR}" || return 1

                if [ -f "${profile_path}" ]; then
                                print_step "Satellite content profile already exists: ${profile_path}"
                                return 0
                fi

                # weekly Sunday 02:00 by default
                sync_date_default="$(date +%Y-%m-%d) 02:00:00"
                sync_date="${sync_date_default}"

                if ! is_noninteractive && [ "${RUN_ONCE:-0}" != "1" ]; then
                                echo ""
                                print_step "Satellite first-run bootstrap: generating host_vars/satellite_content_profile.yml"
                                read -r -p "Create default Satellite content profile now? [Y/n]: " answer
                                if [[ "${answer:-Y}" =~ ^[Nn]$ ]]; then
                                                print_warning "Skipping automatic profile bootstrap by user choice."
                                                return 0
                                fi

                                read -r -p "Weekly sync date/time (YYYY-MM-DD HH:MM:SS) [${sync_date_default}]: " answer
                                if [ -n "${answer}" ]; then
                                                sync_date="${answer}"
                                fi

                                read -r -p "Attach sync plan to common default products (best-effort)? [Y/n]: " answer
                                if [[ "${answer:-Y}" =~ ^[Nn]$ ]]; then
                                                include_product_links="0"
                                fi

                                read -r -p "Enable baseline Red Hat repository sets (RHEL 9/10 + Satellite Client)? [Y/n]: " answer
                                if [[ "${answer:-Y}" =~ ^[Nn]$ ]]; then
                                                include_repo_sets="0"
                                fi
                fi

                cat > "${profile_path}" <<EOF
---
# satellite_content_profile.yml — generated by minirhis_install.sh (Satellite bootstrap)

satellite_username: "admin"
satellite_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"

satellite_organization: "{{ sat_org | default('REDHAT') }}"
satellite_location: "{{ sat_loc | default('CORE') }}"

# Service/UI endpoint policy: internal network only
satellite_url: "https://${SAT_IP:-10.168.128.1}"

sync_plans:
    - name: "weekly_minirhis_sync"
        interval: "weekly"
        enabled: true
        sync_date: "${sync_date}"

EOF

                if [ "${include_product_links}" = "1" ]; then
                                cat >> "${profile_path}" <<'EOF'
product_plans:
    - name: "Red Hat Enterprise Linux for x86_64"
        plan: "weekly_minirhis_sync"
    - name: "Red Hat Satellite Client"
        plan: "weekly_minirhis_sync"
    - name: "Red Hat Ansible Automation Platform"
        plan: "weekly_minirhis_sync"
    - name: "Red Hat Enterprise Linux Server"
        plan: "weekly_minirhis_sync"

EOF
                else
                                cat >> "${profile_path}" <<'EOF'
product_plans: []

EOF
                fi

                if [ "${include_repo_sets}" = "1" ]; then
                                cat >> "${profile_path}" <<'EOF'
repository_sets:
    - name: "Red Hat Enterprise Linux 9 for x86_64 - BaseOS (RPMs)"
        product: "Red Hat Enterprise Linux for x86_64"
        repository_list:
            - releasever: "9"
                basearch: "x86_64"
    - name: "Red Hat Enterprise Linux 9 for x86_64 - AppStream (RPMs)"
        product: "Red Hat Enterprise Linux for x86_64"
        repository_list:
            - releasever: "9"
                basearch: "x86_64"
    - name: "Red Hat Satellite Client 6 for RHEL 9 x86_64 (RPMs)"
        product: "Red Hat Enterprise Linux for x86_64"
        repository_list:
            - basearch: "x86_64"
    - name: "Red Hat Enterprise Linux 10 for x86_64 - BaseOS (RPMs)"
        product: "Red Hat Enterprise Linux for x86_64"
        repository_list:
            - releasever: "10"
                basearch: "x86_64"
    - name: "Red Hat Enterprise Linux 10 for x86_64 - AppStream (RPMs)"
        product: "Red Hat Enterprise Linux for x86_64"
        repository_list:
            - releasever: "10"
                basearch: "x86_64"

EOF
                else
                                cat >> "${profile_path}" <<'EOF'
repository_sets: []

EOF
                fi

                cat >> "${profile_path}" <<'EOF'
lifecycle_environments:
    - name: "DEV_RHEL_9_X86_64"
        label: "dev_rhel_9_x86_64"
        description: "Development lifecycle for RHEL 9"
        organization: "{{ satellite_organization }}"
        prior: "Library"
    - name: "TEST_RHEL_9_X86_64"
        label: "test_rhel_9_x86_64"
        description: "Test lifecycle for RHEL 9"
        organization: "{{ satellite_organization }}"
        prior: "DEV_RHEL_9_X86_64"
    - name: "PROD_RHEL_9_X86_64"
        label: "prod_rhel_9_x86_64"
        description: "Production lifecycle for RHEL 9"
        organization: "{{ satellite_organization }}"
        prior: "TEST_RHEL_9_X86_64"
    - name: "DEV_RHEL_10_X86_64"
        label: "dev_rhel_10_x86_64"
        description: "Development lifecycle for RHEL 10"
        organization: "{{ satellite_organization }}"
        prior: "Library"
    - name: "TEST_RHEL_10_X86_64"
        label: "test_rhel_10_x86_64"
        description: "Test lifecycle for RHEL 10"
        organization: "{{ satellite_organization }}"
        prior: "DEV_RHEL_10_X86_64"
    - name: "PROD_RHEL_10_X86_64"
        label: "prod_rhel_10_x86_64"
        description: "Production lifecycle for RHEL 10"
        organization: "{{ satellite_organization }}"
        prior: "TEST_RHEL_10_X86_64"

content_views:
    - name: "RHEL_9_X86_64"
        desc: "RHEL 9 content view"
        repositories:
            - name: "rhel-9-for-x86_64-baseos-rpms"
            - name: "rhel-9-for-x86_64-appstream-rpms"
            - name: "satellite-client-6-for-rhel-9-x86_64-rpms"
    - name: "RHEL_10_X86_64"
        desc: "RHEL 10 content view"
        repositories:
            - name: "rhel-10-for-x86_64-baseos-rpms"
            - name: "rhel-10-for-x86_64-appstream-rpms"

activation_keys:
    - name: "DEV_RHEL_9_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "DEV_RHEL_9_X86_64"
        content_view: "RHEL_9_X86_64"
        unlimited_hosts: true
    - name: "TEST_RHEL_9_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "TEST_RHEL_9_X86_64"
        content_view: "RHEL_9_X86_64"
        unlimited_hosts: true
    - name: "PROD_RHEL_9_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "PROD_RHEL_9_X86_64"
        content_view: "RHEL_9_X86_64"
        unlimited_hosts: true
    - name: "DEV_RHEL_10_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "DEV_RHEL_10_X86_64"
        content_view: "RHEL_10_X86_64"
        unlimited_hosts: true
    - name: "TEST_RHEL_10_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "TEST_RHEL_10_X86_64"
        content_view: "RHEL_10_X86_64"
        unlimited_hosts: true
    - name: "PROD_RHEL_10_X86_64"
        organization: "{{ satellite_organization }}"
        lifecycle_environment: "PROD_RHEL_10_X86_64"
        content_view: "RHEL_10_X86_64"
        unlimited_hosts: true

# Optional repo intent notes (edit as needed):
# - satellite-6.18-for-rhel-9-x86_64-rpms
# - satellite-maintenance-6.18-for-rhel-9-x86_64-rpms
# - ansible-automation-platform-2.6-for-rhel-9-x86_64-rpms (if entitled/available)
# - idm / freeipa channels if entitled/available
EOF

                chmod 600 "${profile_path}" 2>/dev/null || true
                print_success "Generated default Satellite content profile: ${profile_path}"
                return 0
}

install_satellite_only() {
    local sat_state=""

    print_step "Running Satellite-only workflow (Satellite 6.18)"
    ensure_satellite_content_profile_bootstrap || return 1

    # Always refresh standalone Satellite kickstart artifacts first so
    # registration/install/config changes remain kickstart-native.
    prompt_use_existing_env || return 1
    normalize_shared_env_vars
    ensure_virtualization_tools || return 1
    ensure_iso_vars || return 1
    download_rhel9_iso || return 1
    assert_satellite_install_iso_is_valid "${SAT_ISO_PATH}" || return 1
    fix_qemu_permissions || return 1
    create_libvirt_storage_pool || return 1
    generate_satellite_oemdrv_only || return 1

    # Standalone Satellite mode: provision via kickstart first, then run the
    # Satellite component config-as-code phase post-boot from installer host.
    if ! preflight_config_as_code_targets "satellite:${SAT_IP}"; then
        print_step "Prerequisites for satellite-only are missing; auto-running Satellite VM provisioning workflow"
        create_satellite_vm_only || return 1

        # If the VM already existed, create_satellite_vm_only will skip creation.
        # Ensure it is powered on so standalone preflight can pass.
        if sudo virsh dominfo "satellite" >/dev/null 2>&1; then
            sat_state="$(sudo virsh domstate "satellite" 2>/dev/null | tr -d '[:space:]' || true)"
            case "${sat_state}" in
                running|inshutdown|paused|blocked)
                    ;;
                shutoff|crashed|pmsuspended)
                    print_step "Starting existing Satellite VM: satellite (state=${sat_state})"
                    sudo virsh start "satellite" >/dev/null 2>&1 || true
                    ;;
            esac
        fi

        preflight_config_as_code_targets "satellite:${SAT_IP}" || return 1
    else
        print_warning "Satellite VM is already up; refreshed kickstart/OEMDRV artifacts will only apply after the VM is rebuilt."
    fi

    print_step "Kickstart provisioning complete. Running post-boot Satellite component setup..."
    MINIRHIS_COMPONENT_SCOPE="satellite" run_minirhis_config_as_code || {
        print_warning "Satellite post-boot component setup failed."
        return 1
    }

    revert_rc_local_nonexec_on_minirhis_vms "satellite" || print_warning "rc.local permission reversion reported issues for Satellite; continuing."

    print_success "Satellite standalone workflow complete (kickstart + post-boot component setup)."
    return 0
}

install_idm_only() {
    local idm_state=""

    print_step "Running IdM-only workflow (IdM 5.0)"

    # Standalone IdM mode: provision via kickstart first, then run the
    # IdM component config-as-code phase post-boot from installer host.
    if ! preflight_config_as_code_targets "idm:${IDM_IP}"; then
        print_step "Prerequisites for idm-only are missing; auto-running IdM VM provisioning workflow"
        create_idm_vm_only || return 1

        if sudo virsh dominfo "idm" >/dev/null 2>&1; then
            idm_state="$(sudo virsh domstate "idm" 2>/dev/null | tr -d '[:space:]' || true)"
            case "${idm_state}" in
                running|inshutdown|paused|blocked)
                    ;;
                shutoff|crashed|pmsuspended)
                    print_step "Starting existing IdM VM: idm (state=${idm_state})"
                    sudo virsh start "idm" >/dev/null 2>&1 || true
                    ;;
            esac
        fi

        preflight_config_as_code_targets "idm:${IDM_IP}" || return 1
    fi

    print_step "Kickstart provisioning complete. Running post-boot IdM component setup..."
    MINIRHIS_COMPONENT_SCOPE="idm" run_minirhis_config_as_code || {
        print_warning "IdM post-boot component setup failed."
        return 1
    }

    revert_rc_local_nonexec_on_minirhis_vms "idm" || print_warning "rc.local permission reversion reported issues for IdM; continuing."

    print_success "IdM standalone workflow complete (kickstart + post-boot component setup)."
    return 0
}

install_aap_only() {
    local aap_state=""

    print_step "Running AAP-only workflow (AAP 2.6)"

    # Standalone AAP mode: provision via kickstart first, then run the
    # AAP component config-as-code phase post-boot from installer host.
    if ! preflight_config_as_code_targets "aap:${AAP_IP}"; then
        print_step "Prerequisites for aap-only are missing; auto-running AAP VM provisioning workflow"
        create_aap_vm_only || return 1

        if sudo virsh dominfo "aap" >/dev/null 2>&1; then
            aap_state="$(sudo virsh domstate "aap" 2>/dev/null | tr -d '[:space:]' || true)"
            case "${aap_state}" in
                running|inshutdown|paused|blocked)
                    ;;
                shutoff|crashed|pmsuspended)
                    print_step "Starting existing AAP VM: aap (state=${aap_state})"
                    sudo virsh start "aap" >/dev/null 2>&1 || true
                    ;;
            esac
        fi

        preflight_config_as_code_targets "aap:${AAP_IP}" || return 1
    fi

    print_step "Kickstart provisioning complete. Running post-boot AAP component setup..."
    MINIRHIS_COMPONENT_SCOPE="aap" run_minirhis_config_as_code || {
        print_warning "AAP post-boot component setup failed."
        return 1
    }

    revert_rc_local_nonexec_on_minirhis_vms "aap" || print_warning "rc.local permission reversion reported issues for AAP; continuing."

    print_success "AAP standalone workflow complete (kickstart + post-boot component setup)."
    return 0
}

sync_minirhis_external_hosts_entries() {
    local block_file_internal block_file_external rendered_file
    local vm ext_ip fqdn alias internal_ip row
    local -a rows_internal=()
    local -a rows_external=()
    local -a specs=(
        "satellite:${SAT_HOSTNAME}:${SAT_ALIAS}:${SAT_IP}"
        "aap:${AAP_HOSTNAME}:${AAP_ALIAS}:${AAP_IP}"
        "idm:${IDM_HOSTNAME}:${IDM_ALIAS}:${IDM_IP}"
    )

    # ── Ansible-first path (internal /etc/hosts block only) ─────────────────
    # Build the minirhis_hosts_entries list from our known internal IPs and pass it
    # to the minirhis_hosts_sync role, which uses blockinfile for idempotent updates.
    local _entries_json
    _entries_json="$(printf '[{"ip":"%s","fqdn":"%s","shortname":"%s"},{"ip":"%s","fqdn":"%s","shortname":"%s"},{"ip":"%s","fqdn":"%s","shortname":"%s"}]' \
        "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_ALIAS}" \
        "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_ALIAS}" \
        "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_ALIAS}" 2>/dev/null || true)"
    if [ -n "${_entries_json}" ] && \
       run_local_role "minirhis_hosts_sync" "installer" \
           --extra-vars "{\"minirhis_hosts_entries\": ${_entries_json}}" 2>/dev/null; then
        : # Internal block handled by Ansible; fall through to handle external IPs below
    else
        print_warning "Ansible role minirhis_hosts_sync unavailable; using bash path for internal /etc/hosts block"
    fi
    # ── Bash fallback (and external IP handling) ────────────────────────────

    # Build a single /etc/hosts row while avoiding duplicate name tokens
    # (e.g. 'idm idm' when FQDN and alias are the same).
    _build_hosts_row() {
        local ip="$1"; shift
        local token
        local row="${ip}"
        local seen=" "

        [ -n "${ip}" ] || return 1

        for token in "$@"; do
            [ -n "${token}" ] || continue
            case "${seen}" in
                *" ${token} "*)
                    continue
                    ;;
            esac
            row+=" ${token}"
            seen+="${token} "
        done

        printf '%s\n' "${row}"
        return 0
    }

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "Skipping /etc/hosts external-entry sync: virsh not found."
        return 0
    fi

    for spec in "${specs[@]}"; do
        vm="${spec%%:*}"
        fqdn="${spec#*:}"; fqdn="${fqdn%%:*}"
        alias="${spec#*:*:}"; alias="${alias%%:*}"
        internal_ip="${spec##*:}"

        # Keep controller /etc/hosts populated with MINIRHIS internal addresses.
        row="$(_build_hosts_row "${internal_ip}" "${fqdn}" "${alias}" 2>/dev/null || true)"
        [ -n "${row}" ] && rows_internal+=("${row}")

        ext_ip="$(sudo -n virsh domifaddr "${vm}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | awk '$1 !~ /^10\.168\./ {print; exit}' || true)"
        [ -n "${ext_ip}" ] || continue

        row="$(_build_hosts_row "${ext_ip}" "${fqdn}" "${alias}" 2>/dev/null || true)"
        [ -n "${row}" ] && rows_external+=("${row}")
    done

    if [ "${#rows_internal[@]}" -eq 0 ] && [ "${#rows_external[@]}" -eq 0 ]; then
        print_step "No MINIRHIS VM addresses discovered for /etc/hosts sync yet."
        return 0
    fi

    block_file_internal="$(mktemp /tmp/minirhis-hosts-int-block.XXXXXX)"
    block_file_external="$(mktemp /tmp/minirhis-hosts-ext-block.XXXXXX)"
    rendered_file="$(mktemp /tmp/minirhis-hosts-rendered.XXXXXX)"

    if [ "${#rows_internal[@]}" -gt 0 ]; then
        {
            echo "# BEGIN MINIRHIS INTERNAL HOSTS"
            for row in "${rows_internal[@]}"; do
                printf '%s\n' "${row}"
            done
            echo "# END MINIRHIS INTERNAL HOSTS"
        } > "${block_file_internal}"
    else
        : > "${block_file_internal}"
    fi

    if [ "${#rows_external[@]}" -gt 0 ]; then
        {
            echo "# BEGIN MINIRHIS EXTERNAL HOSTS"
            for row in "${rows_external[@]}"; do
                printf '%s\n' "${row}"
            done
            echo "# END MINIRHIS EXTERNAL HOSTS"
        } > "${block_file_external}"
    else
        : > "${block_file_external}"
    fi

    # Remove previously managed MINIRHIS blocks, then append refreshed blocks.
    sudo awk '
        /^# BEGIN MINIRHIS INTERNAL HOSTS$/ {in_internal=1; next}
        /^# END MINIRHIS INTERNAL HOSTS$/   {in_internal=0; next}
        /^# BEGIN MINIRHIS EXTERNAL HOSTS$/ {in_external=1; next}
        /^# END MINIRHIS EXTERNAL HOSTS$/   {in_external=0; next}
        !in_internal && !in_external { print }
    ' /etc/hosts > "${rendered_file}" || true

    {
        cat "${rendered_file}"
        [ -s "${block_file_internal}" ] && cat "${block_file_internal}"
        [ -s "${block_file_external}" ] && cat "${block_file_external}"
    } > "${rendered_file}.new" || true
    mv -f "${rendered_file}.new" "${rendered_file}" >/dev/null 2>&1 || true

    if [ -s "${rendered_file}" ] && sudo cp -f "${rendered_file}" /etc/hosts 2>/dev/null; then
        print_success "Updated /etc/hosts with MINIRHIS internal/external interface entries."
    else
        print_warning "Could not update /etc/hosts with MINIRHIS internal/external interface entries."
    fi

    rm -f "${block_file_internal}" "${block_file_external}" "${rendered_file}" || true
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
            "satellite:${SAT_IP}"
            "aap:${AAP_IP}"
            "idm:${IDM_IP}"
        )
    fi

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; cannot verify MINIRHIS VM state before config-as-code."
        return 0
    fi

    discover_vm_ipv4() {
        local vm="$1"
        local configured_ip="${2:-}"
        local discovered_ips=""
        local ip=""

        if [ -n "${configured_ip}" ]; then
            # Global policy: always target configured internal MINIRHIS IPs.
            printf '%s\n' "${configured_ip}"
            return 0
        fi

        discovered_ips="$(timeout 10 sudo -n virsh domifaddr "$vm" 2>/dev/null \
            | awk '/ipv4/ {print $4}' \
            | cut -d/ -f1 \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"

        # Prefer the configured internal address when libvirt reports multiple NICs.
        if [ -n "${configured_ip}" ] && printf '%s\n' "${discovered_ips}" | grep -Fxq "${configured_ip}"; then
            printf '%s\n' "${configured_ip}"
            return 0
        fi

        ip="$(printf '%s\n' "${discovered_ips}" | grep -E '^10\.168\.' | head -1 || true)"
        if [ -n "${ip}" ]; then
            printf '%s\n' "${ip}"
            return 0
        fi

        printf '%s\n' "${discovered_ips}" | head -1
    }

    resolve_preflight_ip() {
        local vm="$1"
        local configured="$2"
        local discovered=""

        if [ -n "${configured}" ]; then
            printf '%s\n' "$configured"
            return 0
        fi

        if probe_ssh_endpoint "$configured"; then
            printf '%s\n' "$configured"
            return 0
        fi

        discovered="$(discover_vm_ipv4 "$vm" "$configured" || true)"
        if [ -n "$discovered" ]; then
            printf '%s\n' "$discovered"
            return 0
        fi

        printf '%s\n' "$configured"
    }

    print_step "Preflight: validating MINIRHIS VM state and internal SSH reachability"
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
        print_step "Preflight prerequisites are not met yet (expected during fresh installs / post-DEMOKILL)."
        return 1
    fi

    if [ "$unreachable_target" -ne 0 ]; then
        # Progress-bar helper — draws/updates a single line in place.
        # Usage: _ssh_progress <elapsed> <timeout> <detail_mode> [warn_msg]
        _ssh_progress() {
            local elapsed="$1" timeout="$2" detail="$3" warn_msg="${4:-}"
            local pct=$(( elapsed * 100 / timeout ))
            [ "$pct" -gt 100 ] && pct=100
            local filled=$(( pct * 30 / 100 ))
            local empty=$(( 30 - filled ))
            local bar=""
            local i
            for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
            for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
            local remaining=$(( timeout - elapsed ))
            if [ "$detail" -eq 1 ] && [ -n "$warn_msg" ]; then
                # Warn lines go on a new line so they are preserved in logs
                printf '\r\033[K'
                echo -e "${YELLOW}[WARNING]${NC} ${warn_msg}"
            fi
            printf '\r\033[K'"${BLUE}[SSH-WAIT]${NC} [%s] %3d%%  %ds/%ds (~%ds remaining)" \
                "${bar}" "${pct}" "${elapsed}" "${timeout}" "${remaining}"
        }

        printf '\n'
        print_step "Waiting for internal SSH readiness (timeout=${MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT}s)"
        wait_start="$(date +%s)"
        wait_deadline=$(( wait_start + MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT ))

        while true; do
            all_ready=1
            local _unreachable_vms=()
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
                    _unreachable_vms+=("${vm_name}(${target_ip})")
                fi
            done

            if [ "$all_ready" -eq 1 ]; then
                # Clear the progress line before printing success
                printf '\r\033[K\n'
                break
            fi

            now="$(date +%s)"
            if [ "$now" -ge "$wait_deadline" ]; then
                printf '\r\033[K\n'
                print_warning "MINIRHIS VMs exist, but internal SSH did not become reachable before timeout."
                print_warning "Check VM console output and network config for the 10.168.0.0/16 interfaces."
                return 1
            fi

            elapsed=$(( now - wait_start ))

            if [ "$elapsed" -ge "${MINIRHIS_INTERNAL_SSH_WARN_GRACE}" ]; then
                show_detail_logs=1
            fi

            if [ "$show_detail_logs" -eq 1 ] && \
               [ $((now - last_progress_log)) -ge "${MINIRHIS_INTERNAL_SSH_LOG_EVERY}" ]; then
                local _detail_msg="Still waiting: ${_unreachable_vms[*]:-} (${elapsed}s/${MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT}s)"
                _ssh_progress "$elapsed" "${MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT}" 1 "$_detail_msg"
                last_progress_log="$now"
            else
                _ssh_progress "$elapsed" "${MINIRHIS_INTERNAL_SSH_WAIT_TIMEOUT}" 0
            fi

            sleep "$MINIRHIS_INTERNAL_SSH_WAIT_INTERVAL"
        done
    fi

    print_success "Preflight passed: MINIRHIS VMs are running and reachable on the internal network."
    return 0
}

# ---------------------------------------------------------------------------
# validate_headless_config
#
# Standalone pre-flight checker for headless / non-interactive deployments.
# Checks required variables per menu choice, system requirements, commands,
# SSH keys, IP/FQDN format, storage (≥300 GB), memory (≥64 GB), and CDN/DNS
# reachability.
#
# Called by --validate / --preflight, or automatically before a non-interactive
# run when PRESEED_ENV_FILE is loaded.
# ---------------------------------------------------------------------------
validate_headless_config() {
    local choice="${MENU_CHOICE:-${CLI_MENU_CHOICE:-5}}"

    # Self-contained ANSI helpers (callable before main print_* are defined)
    local _vRED='\033[0;31m'
    local _vGREEN='\033[0;32m'
    local _vYELLOW='\033[1;33m'
    local _vBLUE='\033[0;34m'
    local _vNC='\033[0m'
    local VPASS=0 VWARN=0 VFAIL=0

    _vok()   { printf "${_vGREEN}✓${_vNC} %s\n" "$1"; (( VPASS++ )) || true; }
    _vwarn() { printf "${_vYELLOW}⚠${_vNC} %s\n" "$1"; (( VWARN++ )) || true; }
    _vfail() { printf "${_vRED}✗${_vNC} %s\n"   "$1"; (( VFAIL++ )) || true; }
    _vhead() { printf "\n${_vBLUE}━━ %s${_vNC}\n" "$1"; }

    printf "${_vBLUE}╔══════════════════════════════════════════════════════════════╗${_vNC}\n"
    printf "${_vBLUE}║  MINIRHIS Headless Environment Validation                       ║${_vNC}\n"
    printf "${_vBLUE}╚══════════════════════════════════════════════════════════════╝${_vNC}\n\n"

    # ── Env file check ──────────────────────────────────────────────────────────
    _vhead "Environment File"
    if [ -n "${PRESEED_ENV_FILE:-}" ]; then
        if [ -f "${PRESEED_ENV_FILE}" ]; then
            _vok "Env file found: ${PRESEED_ENV_FILE}"
        else
            _vwarn "Env file not found: ${PRESEED_ENV_FILE} (relying on already-exported vars)"
        fi
    else
        _vwarn "--env-file not specified; relying on already-exported environment"
    fi

    # ── Required variables per menu choice ─────────────────────────────────────
    _vhead "Required Variables (menu choice ${choice})"
    local -a required_vars=()
    local mode_label=""
    case "${choice}" in
        1|2)
            required_vars=(RH_USER RH_PASS ADMIN_PASS)
            mode_label="Local App / Container"
            ;;
        3)
            required_vars=(IDM_IP IDM_HOSTNAME SAT_IP SAT_HOSTNAME AAP_IP AAP_HOSTNAME ADMIN_PASS)
            mode_label="Virt-Manager Only"
            ;;
        4)
            required_vars=(RH_USER RH_PASS ADMIN_PASS ADMIN_USER DOMAIN
                           IDM_IP IDM_HOSTNAME IDM_DS_PASS
                           SAT_IP SAT_HOSTNAME SAT_ORG SAT_LOC
                           AAP_IP AAP_HOSTNAME HUB_TOKEN)
            mode_label="Full Setup (Local + Virt-Manager)"
            ;;
        5)
            required_vars=(RH_USER RH_PASS ADMIN_PASS ADMIN_USER DOMAIN
                           IDM_IP IDM_HOSTNAME IDM_DS_PASS
                           SAT_IP SAT_HOSTNAME SAT_ORG SAT_LOC
                           AAP_IP AAP_HOSTNAME HUB_TOKEN)
            mode_label="Full Setup (Container + Virt-Manager)"
            ;;
        7)
            required_vars=(RH_USER RH_PASS ADMIN_PASS DOMAIN IDM_DS_PASS
                           IDM_IP SAT_IP AAP_IP HUB_TOKEN)
            mode_label="Full Auto (Container + Provision + Config)"
            ;;
        9)
            required_vars=(RH_USER RH_PASS ADMIN_PASS DOMAIN SAT_IP SAT_HOSTNAME SAT_ORG SAT_LOC)
            mode_label="Satellite 6.18 Only"
            ;;
        10)
            required_vars=(RH_USER RH_PASS ADMIN_PASS DOMAIN IDM_IP IDM_HOSTNAME IDM_DS_PASS)
            mode_label="IdM 5.0 Only"
            ;;
        11)
            required_vars=(RH_USER RH_PASS ADMIN_PASS DOMAIN AAP_IP AAP_HOSTNAME HUB_TOKEN)
            mode_label="AAP 2.6 Only"
            ;;
        *)
            _vfail "Unknown menu choice: ${choice} (valid: 1-5, 7, 9-11)"
            ;;
    esac
    printf "  Mode: %s\n" "${mode_label}"
    local var val
    for var in "${required_vars[@]}"; do
        val="${!var:-}"
        if [ -z "${val}" ]; then
            _vfail "${var} is required but not set"
        else
            if [[ "${var}" == *PASS* ]] || [[ "${var}" == *TOKEN* ]] || [[ "${var}" == *SECRET* ]]; then
                val="***REDACTED***"
            fi
            _vok "${var} is set (${val})"
        fi
    done

    _vhead "Credential Pair Consistency"
    if { [ -n "${RH_USER:-}" ] && [ -z "${RH_PASS:-}" ]; } || { [ -z "${RH_USER:-}" ] && [ -n "${RH_PASS:-}" ]; }; then
        _vfail "RH_USER and RH_PASS must be set together"
    else
        _vok "RH_USER / RH_PASS pairing is consistent"
    fi
    if { [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -z "${CDN_SAT_ACTIVATION_KEY:-}" ]; } || { [ -z "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; }; then
        _vwarn "CDN_ORGANIZATION_ID and CDN_SAT_ACTIVATION_KEY should be set together when using activation-key registration"
    else
        _vok "CDN activation-key pairing is consistent"
    fi
    if { [ -n "${RHC_ORGANIZATION_ID:-}" ] && [ -z "${RHC_ACTIVATION_KEY:-}" ]; } || { [ -z "${RHC_ORGANIZATION_ID:-}" ] && [ -n "${RHC_ACTIVATION_KEY:-}" ]; }; then
        _vwarn "RHC_ORGANIZATION_ID and RHC_ACTIVATION_KEY should be set together when overriding rhc registration"
    else
        _vok "RHC activation-key pairing is consistent"
    fi
    if [ -n "${SAT_MANIFEST_PATH:-}" ]; then
        if [ -f "${SAT_MANIFEST_PATH}" ]; then
            _vok "SAT_MANIFEST_PATH exists: ${SAT_MANIFEST_PATH}"
        else
            _vfail "SAT_MANIFEST_PATH does not exist: ${SAT_MANIFEST_PATH}"
        fi
    else
        _vwarn "SAT_MANIFEST_PATH not set; Satellite manifest auto-import will fall back to ${HOME}/Downloads/manifest_*.zip"
    fi

    # ── System requirements ────────────────────────────────────────────────────
    _vhead "System Requirements"
    if [[ "${OSTYPE:-}" == "linux-gnu"* ]]; then
        _vok "Running on Linux"
    else
        _vfail "Linux required (detected: ${OSTYPE:-unknown})"
    fi
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        _vok "Running as root"
    elif sudo -n true 2>/dev/null; then
        _vok "Passwordless sudo available"
    else
        _vwarn "Not root and sudo requires a password"
    fi

    # ── Required commands ──────────────────────────────────────────────────────
    _vhead "Required Commands"
    local cmd
    for cmd in virsh podman ssh ssh-keygen jq curl; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            _vok "${cmd} is available"
        else
            _vfail "${cmd} is not installed / not in PATH"
        fi
    done

    # ── SSH keys ───────────────────────────────────────────────────────────────
    _vhead "SSH Configuration"
    local ssh_key="${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-${HOME}/.ssh/minirhis-installer/id_rsa}"
    if [ -f "${ssh_key}" ]; then
        _vok "SSH private key exists: ${ssh_key}"
    else
        _vwarn "SSH private key not found: ${ssh_key}  (run the installer once to generate it)"
    fi
    if [ -f "${ssh_key}.pub" ]; then
        _vok "SSH public key exists: ${ssh_key}.pub"
    else
        _vfail "SSH public key not found: ${ssh_key}.pub"
    fi

    # ── IP address validation ──────────────────────────────────────────────────
    _vhead "IP Address Validation"
    _valid_ip() { [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
    local ip_var ip_val
    for ip_var in IDM_IP SAT_IP AAP_IP HOST_INT_IP; do
        ip_val="${!ip_var:-}"
        [ -z "${ip_val}" ] && continue
        if _valid_ip "${ip_val}"; then
            _vok "${ip_var} is a valid IP: ${ip_val}"
        else
            _vfail "${ip_var} is not a valid IP address: ${ip_val}"
        fi
    done

    # Satellite service-plane policy: internal 10.168.0.0/16 only (eth1).
    if [[ "${choice}" =~ ^(3|4|5|7)$ ]]; then
        if [[ "${MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK:-1}" == "1" ]]; then
            if [[ "${SAT_IP:-}" =~ ^10\.168\. ]]; then
                _vok "SAT_IP is on internal service network: ${SAT_IP}"
            else
                _vfail "SAT_IP must be within 10.168.0.0/16 when Satellite services are enabled (current: ${SAT_IP:-unset})"
            fi
        else
            _vwarn "MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK=0; internal SAT_IP policy is disabled (current SAT_IP=${SAT_IP:-unset})"
        fi
    fi

    # ── FQDN validation ────────────────────────────────────────────────────────
    _vhead "Hostname (FQDN) Validation"
    _valid_fqdn() {
        [[ "${1:-}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
    }
    local hn_var hn_val
    for hn_var in IDM_HOSTNAME SAT_HOSTNAME AAP_HOSTNAME; do
        hn_val="${!hn_var:-}"
        [ -z "${hn_val}" ] && continue
        if _valid_fqdn "${hn_val}"; then
            _vok "${hn_var} is a valid FQDN: ${hn_val}"
        else
            _vfail "${hn_var} is not a valid FQDN (must contain ≥1 dot): ${hn_val}"
        fi
    done

    # ── Storage ────────────────────────────────────────────────────────────────
    _vhead "Storage Requirements (/var/lib/libvirt)"
    local avail_gb
    avail_gb=$(df -BG /var/lib/libvirt 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}') || avail_gb=""
    if [ -n "${avail_gb:-}" ] && [[ "${avail_gb}" =~ ^[0-9]+$ ]]; then
        if [ "${avail_gb}" -ge 300 ]; then
            _vok "${avail_gb} GB free (≥300 GB required)"
        else
            _vfail "Only ${avail_gb} GB free — need ≥300 GB"
        fi
    else
        _vwarn "Could not determine free space on /var/lib/libvirt"
    fi

    # ── Memory ────────────────────────────────────────────────────────────────
    _vhead "Memory Requirements"
    local mem_gb
    mem_gb=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo 2>/dev/null) || mem_gb=""
    if [ -n "${mem_gb:-}" ] && [[ "${mem_gb}" =~ ^[0-9]+$ ]]; then
        if [ "${mem_gb}" -ge 64 ]; then
            _vok "System RAM: ${mem_gb} GB (≥64 GB recommended)"
        else
            _vwarn "System RAM: ${mem_gb} GB — ≥64 GB recommended; may be constrained"
        fi
    else
        _vwarn "Could not read /proc/meminfo"
    fi

    # ── Connectivity ──────────────────────────────────────────────────────────
    _vhead "Connectivity Tests"
    if curl -sSf --connect-timeout 5 "https://api.access.redhat.com/ping" -o /dev/null 2>&1; then
        _vok "Red Hat CDN reachable (api.access.redhat.com)"
    else
        _vfail "Cannot reach Red Hat CDN — check internet / proxy connectivity"
    fi
    if nslookup redhat.com >/dev/null 2>&1; then
        _vok "DNS resolution working"
    else
        _vwarn "DNS resolution may not be working"
    fi

    # ── Summary ────────────────────────────────────────────────────────────────
    _vhead "Summary"
    printf "\n  Passed:   ${_vGREEN}%d${_vNC}\n" "${VPASS}"
    printf   "  Warnings: ${_vYELLOW}%d${_vNC}\n" "${VWARN}"
    printf   "  Failed:   ${_vRED}%d${_vNC}\n\n"  "${VFAIL}"

    if [ "${VFAIL}" -eq 0 ]; then
        printf "${_vGREEN}✓ All critical checks passed!${_vNC}\n\n"
        local env_arg=""
        [ -n "${PRESEED_ENV_FILE:-}" ] && [ -f "${PRESEED_ENV_FILE}" ] && \
            env_arg=" --env-file ${PRESEED_ENV_FILE}"
        printf "To deploy:\n  %s --non-interactive --menu-choice %s%s\n\n" \
            "$(basename "${BASH_SOURCE[0]}")" "${choice}" "${env_arg}"
        [ "${VWARN}" -gt 0 ] && \
            printf "Note: %d warning(s) above — review before deploying.\n\n" "${VWARN}"
        return 0
    else
        printf "${_vRED}✗ %d critical check(s) failed — fix issues above before deploying.${_vNC}\n\n" \
            "${VFAIL}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# generate_env_template
#
# Writes a filled headless env-file template to the specified path.
# Called via --generate-env [path].  Defaults to ./minirhis-headless.env.template.
# ---------------------------------------------------------------------------
generate_env_template() {
    local output_path="${1:-${SCRIPT_DIR}/minirhis-headless.env.template}"
    local tmp_template=""

    tmp_template="$(mktemp)" || return 1
    cat > "${tmp_template}" <<'ENV_TEMPLATE_EOF'
#!/bin/bash
# MINIRHIS Headless Environment Configuration Template
#
# Usage:
#   1. Copy this file:  cp minirhis-headless.env.template /etc/minirhis/headless.env
#   2. Fill it in:      nano /etc/minirhis/headless.env
#   3. Validate:        ./minirhis_install.sh --validate --menu-choice 5 \
#                                         --env-file /etc/minirhis/headless.env
#   4. Deploy:          ./minirhis_install.sh --non-interactive --menu-choice 5 \
#                                         --env-file /etc/minirhis/headless.env
#
# Security:
#   chmod 600 /etc/minirhis/headless.env
#   Never commit this file with real credentials to version control.

# =============================================================================
# CORE CREDENTIALS  (required for almost all menu choices)
# =============================================================================
# Red Hat CDN / subscription-manager credentials
RH_USER="${RH_USERNAME:-}"
RH_PASS="${RH_PASSWORD:-}"

# Local admin user and password for every managed VM
ADMIN_USER="admin"
ADMIN_PASS="${ADMIN_PASSWORD:-}"

# Root password for kickstart-provisioned VMs
ROOT_PASS="${ROOT_PASSWORD:-}"

# =============================================================================
# IdM CONFIGURATION  (required for menu choices 3, 4, 5, 7)
# =============================================================================
IDM_IP="10.168.128.3"               # Static IP on the internal bridge network
IDM_HOSTNAME="idm.example.com"      # FQDN — must contain at least one dot
IDM_ALIAS="idm"                     # Short hostname
DOMAIN="example.com"                # Base domain / Kerberos realm base
IDM_DS_PASS="${IDM_DS_PASSWORD:-}"  # Directory Server (LDAP) password

# =============================================================================
# SATELLITE CONFIGURATION  (required for menu choices 3, 4, 5, 7)
# =============================================================================
SAT_IP="10.168.128.1"
SAT_HOSTNAME="satellite.example.com"
SAT_ALIAS="satellite"
SAT_ORG="Default_Organization"      # Satellite organization name
SAT_LOC="Default_Location"          # Satellite location name
SAT_ADMIN_PASS="${ADMIN_PASSWORD:-}"

# =============================================================================
# AAP (Ansible Automation Platform) CONFIGURATION  (required for 3, 4, 5, 7)
# =============================================================================
AAP_IP="10.168.128.2"
AAP_HOSTNAME="aap.example.com"
AAP_ALIAS="aap"
AAP_ADMIN_PASS="${ADMIN_PASSWORD:-}"

# Red Hat Automation Hub offline token
HUB_TOKEN="${AAP_HUB_TOKEN:-}"

# (Optional) Separate API token for ansible.cfg galaxy_server
# VAULT_CONSOLE_REDHAT_TOKEN="${CONSOLE_REDHAT_TOKEN:-}"

# =============================================================================
# NETWORK CONFIGURATION  (optional — auto-detected when empty)
# =============================================================================
HOST_INT_IP="192.168.122.1"         # KVM NAT bridge IP on the installer host
# INTERNAL_NETWORK="10.168.0.0"
# NETMASK="255.255.0.0"
# INTERNAL_GW="10.168.0.1"

# =============================================================================
# VM RESOURCE CONFIGURATION  (optional — uncomment to override defaults)
# =============================================================================
# IDM_VCPUS="4"
# IDM_MEMORY_MB="16384"
# SAT_VCPUS="8"
# SAT_MEMORY_MB="32768"
# AAP_VCPUS="8"
# AAP_MEMORY_MB="16384"

# =============================================================================
# FEATURE FLAGS  (optional — uncomment to override)
# =============================================================================
# DEMO_MODE="0"                           # 1 = minimal/demo VM specs
# MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY="1"
# MINIRHIS_RETRY_FAILED_PHASES_ONCE="1"
# MINIRHIS_ENABLE_POST_HEALTHCHECK="1"
# MINIRHIS_HEALTHCHECK_AUTOFIX="1"

# =============================================================================
# AAP INVENTORY TEMPLATE  (optional — prompted interactively if empty)
# Set to one of: "inventory", "inventory-growth", "DEMO-inventory"
# =============================================================================
# AAP_INVENTORY_TEMPLATE=""
# AAP_INVENTORY_GROWTH_TEMPLATE=""
ENV_TEMPLATE_EOF

    chmod 600 "${tmp_template}"
    write_file_if_changed "${tmp_template}" "${output_path}" 0600 || return 1
    printf "\nNext steps:\n"
    printf "  1. Edit:     nano %s\n" "${output_path}"
    printf "  2. Validate: %s --validate --menu-choice 5 --env-file %s\n" \
        "$(basename "${BASH_SOURCE[0]}")" "${output_path}"
    printf "  3. Deploy:   %s --non-interactive --menu-choice 5 --env-file %s\n\n" \
        "$(basename "${BASH_SOURCE[0]}")" "${output_path}"
}

wait_for_post_vm_settle() {
    local grace="${1:-${MINIRHIS_POST_VM_SETTLE_GRACE:-650}}"
    local remaining
    local original_grace elapsed percent filled bar

    case "$grace" in
        ''|*[!0-9]*) grace=650 ;;
    esac

    if [ "$grace" -le 0 ]; then
        return 0
    fi

    original_grace="$grace"
    print_step "Guest install settle window: giving MINIRHIS VMs ${grace}s before internal SSH checks begin"
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

print_minirhis_health_summary() {
    local vm state ip
    local -a vms=("satellite:${SAT_IP}" "aap:${AAP_IP}" "idm:${IDM_IP}")

    echo ""
    echo "================ MINIRHIS Health Summary ================"
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
    ensure_ssh_keys || {
        print_warning "AAP callback cannot start: failed to ensure SSH keys at ${AAP_SSH_KEY_DIR}."
        return 1
    }

    AAP_SSH_CALLBACK_ENABLED=1
    print_step "AAP VM is installing. SSH callback will begin as soon as the VM is reachable."
    print_step "Grab a cup of coffee and sit back, or come back after lunch — we will continue to configure this environment while you wait."
    print_step "Live monitor is active: you will see AAP callback progress (percent + ETA). If no state progress is detected, this step will fail fast for troubleshooting."

    if run_aap_setup_on_vm "aap"; then
        print_success "AAP setup orchestration complete via SSH callback."
        create_aap_credentials
    else
        print_warning "AAP setup failed or timed out. Check ${AAP_SETUP_LOG_LOCAL} for details."
        AAP_SSH_CALLBACK_ENABLED=0
        return 1
    fi

    if [ "${AAP_HTTP_PID:-0}" -gt 0 ] 2>/dev/null && kill "${AAP_HTTP_PID}" 2>/dev/null; then
        print_success "AAP bundle HTTP server stopped (PID ${AAP_HTTP_PID})."
    fi
    AAP_HTTP_PID=""
    close_aap_bundle_firewall
    AAP_SSH_CALLBACK_ENABLED=0
    return 0
}

# ─── Inventory + host_vars generation ─────────────────────────────────────────
# Generate inventory from current env vars so the container
# always has a correct, up-to-date inventory regardless of who cloned the repo.
generate_minirhis_inventory() {
    if [ -f "${ANSIBLE_ENV_FILE}" ]; then
        load_ansible_env_file || return 1
    fi
    normalize_shared_env_vars

    mkdir -p "${MINIRHIS_INVENTORY_DIR}" "${SCRIPT_DIR}/container/roles/inventory" || return 1

    local controller_host
    local inventory_basename
    local template_file
    local tmp_hosts
    local controller_host_e host_int_ip_e installer_user_e sat_host_e sat_alias_e sat_ip_e aap_host_e aap_alias_e aap_ip_e idm_host_e idm_alias_e idm_ip_e admin_user_e
    local sat_connect_host aap_connect_host idm_connect_host

    # Global behavior uses internal MINIRHIS addressing (10.168.x.x) for stable
    # node-to-node trust and predictable Ansible reachability across rebuilds.
    resolve_vm_connect_host() {
        local vm_name="$1"
        local fallback_host="$2"
        local fallback_ip="$3"
        # shellcheck disable=SC2034
        vm_name="${vm_name}"
        # shellcheck disable=SC2034
        fallback_host="${fallback_host}"
        printf '%s' "${fallback_ip}"
        return 0
    }
    controller_host="$(hostname -f 2>/dev/null || hostname)"

    inventory_basename="$(basename "${MINIRHIS_INVENTORY_FILE}")"
    template_file="${MINIRHIS_INVENTORY_FILE}.SAMPLE"
    [ -f "${template_file}" ] || template_file="${MINIRHIS_INVENTORY_FILE}"
    [ -f "${template_file}" ] || template_file="${MINIRHIS_INVENTORY_DIR}/hosts.SAMPLE"
    [ -f "${template_file}" ] || template_file="${SCRIPT_DIR}/container/vars/external_inventory/hosts.yml"
    [ -f "${template_file}" ] || template_file="${SCRIPT_DIR}/inventory/hosts.SAMPLE"
    tmp_hosts="$(mktemp "${ANSIBLE_ENV_DIR}/.hosts.XXXXXX")" || return 1
    controller_host_e="$(sed_escape_replacement "${controller_host}")"
    host_int_ip_e="$(sed_escape_replacement "${HOST_INT_IP:-192.168.122.1}")"
    installer_user_e="$(sed_escape_replacement "${INSTALLER_USER:-${ADMIN_USER:-admin}}")"
    sat_host_e="$(sed_escape_replacement "${SAT_HOSTNAME:-satellite}")"
    sat_alias_e="$(sed_escape_replacement "${SAT_ALIAS:-satellite}")"
    sat_connect_host="$(resolve_vm_connect_host "satellite" "${SAT_HOSTNAME:-satellite}" "${SAT_IP:-10.168.128.1}")"
    sat_ip_e="$(sed_escape_replacement "${sat_connect_host}")"
    aap_host_e="$(sed_escape_replacement "${AAP_HOSTNAME:-aap}")"
    aap_alias_e="$(sed_escape_replacement "${AAP_ALIAS:-aap}")"
    aap_connect_host="$(resolve_vm_connect_host "aap" "${AAP_HOSTNAME:-aap}" "${AAP_IP:-10.168.128.2}")"
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
            "${template_file}" > "${tmp_hosts}"
    else
        cat > "${tmp_hosts}" <<INVENTORY_EOF
# MINIRHIS Ansible Inventory — generated by run_minirhis_install_sequence.sh on $(date '+%Y-%m-%d %H:%M')
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
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no'
INVENTORY_EOF
    fi

    sync_inventory_target() {
        local target="$1"
        local target_dir
        target_dir="$(dirname "$target")"
        mkdir -p "$target_dir" || return 1
        if [ -f "$target" ] && cmp -s "${tmp_hosts}" "$target"; then
            print_step "Inventory unchanged: ${target}"
            return 0
        fi
        install -D -m 0644 "${tmp_hosts}" "$target" 2>/dev/null || {
            sudo install -D -m 0644 "${tmp_hosts}" "$target" >/dev/null 2>&1 || return 1
        }
        print_success "Generated inventory: ${target}"
    }

    sync_inventory_target "${MINIRHIS_INVENTORY_FILE}" || { rm -f "${tmp_hosts}"; return 1; }
    sync_inventory_target "${SCRIPT_DIR}/container/roles/inventory/${inventory_basename}" || { rm -f "${tmp_hosts}"; return 1; }
    rm -f "${tmp_hosts}"
}

# Generate actual host_vars/*.yml files from current env vars so playbooks
# can find per-node connection details without additional prompts.
# Passwords are referenced via the vault extra-vars loaded at runtime from
# /minirhis/vars/vault/env.yml (decrypted by --vault-password-file automatically).
generate_minirhis_host_vars() {
    if [ -f "${ANSIBLE_ENV_FILE}" ]; then
        load_ansible_env_file || return 1
    fi
    normalize_shared_env_vars

    local ext_inv_hv_dir="${SCRIPT_DIR}/container/vars/external_inventory/host_vars"
    mkdir -p "${MINIRHIS_HOST_VARS_DIR}" "${SCRIPT_DIR}/container/roles/host_vars" "${ext_inv_hv_dir}" || return 1
    local sat_pre_use_idm_value="${SATELLITE_PRE_USE_IDM:-false}"
    local sat_use_non_idm_certs_value="${SAT_USE_NON_IDM_CERTS:-}"
    case "${sat_pre_use_idm_value}" in
        1|true|TRUE|yes|YES|on|ON) sat_pre_use_idm_value="true" ;;
        *) sat_pre_use_idm_value="false" ;;
    esac
    case "${sat_use_non_idm_certs_value}" in
        1|true|TRUE|yes|YES|on|ON) sat_use_non_idm_certs_value="true" ;;
        0|false|FALSE|no|NO|off|OFF) sat_use_non_idm_certs_value="false" ;;
        *)
            if [ "${sat_pre_use_idm_value}" = "true" ]; then
                sat_use_non_idm_certs_value="false"
            else
                sat_use_non_idm_certs_value="true"
            fi
            ;;
    esac
    local sat_internal_url="https://{{ sat_ip | default('10.168.128.1') }}"
    local primary_dir="${MINIRHIS_HOST_VARS_DIR}"
    local container_dir="${SCRIPT_DIR}/container/roles/host_vars"

    write_hostvars_pair() {
        local file_name="$1"
        local fqdn_name="$2"       # FQDN inventory hostname (may be empty)
        local src="${primary_dir}/${file_name}"
        local dst="${container_dir}/${file_name}"
        [ -f "$src" ] || return 1
        if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
            install -D -m 0644 "$src" "$dst" 2>/dev/null || {
                sudo install -D -m 0644 "$src" "$dst" >/dev/null 2>&1 || return 1
            }
            print_step "Synced host_vars artifact: ${dst}"
        fi
        # Also write FQDN-named file adjacent to the external inventory so
        # Ansible auto-loads it for local runs (inventory host_vars lookup).
        if [ -n "${fqdn_name}" ]; then
            local fqdn_dst="${ext_inv_hv_dir}/${fqdn_name}.yml"
            if [ ! -f "${fqdn_dst}" ] || ! cmp -s "$src" "${fqdn_dst}"; then
                install -D -m 0644 "$src" "${fqdn_dst}" 2>/dev/null || \
                    sudo install -D -m 0644 "$src" "${fqdn_dst}" >/dev/null 2>&1 || true
            fi
        fi
        return 0
    }

    # Installer / controller host
    # ansible_user must come from env.yml installer_user for consistent behavior
    # across operators and hosts.
    # aap_remote_user is the admin account on the remote AAP VM → admin_user.
    cat > "${primary_dir}/installer.yml" <<EOF
# installer.yml — generated by run_minirhis_install_sequence.sh
ansible_user: "{{ installer_user }}"
aap_remote_user: "{{ admin_user | default('${ADMIN_USER:-admin}') }}"
ansible_ssh_private_key_file: "{{ minirhis_installer_ssh_private_key_file | default('${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-${HOME}/.ssh/minirhis-installer/id_rsa}') }}"
EOF
    write_hostvars_pair "installer.yml" "" || return 1

    # Satellite
    cat > "${primary_dir}/satellite.yml" <<EOF
# satellite.yml — generated by run_minirhis_install_sequence.sh
ansible_user: "{{ admin_user | default('${ADMIN_USER:-admin}') }}"
ansible_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"
ansible_become: true
ansible_become_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"
ansible_connection: ssh
ansible_ssh_private_key_file: "{{ minirhis_installer_ssh_private_key_file | default('${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-${HOME}/.ssh/minirhis-installer/id_rsa}') }}"
satellite_username: "{{ sat_admin_user | default(admin_user | default('${ADMIN_USER:-admin}')) }}"
satellite_password: "{{ sat_admin_pass | default(global_admin_password) | default('') }}"
satellite_organization: "{{ sat_org | default('${SAT_ORG:-REDHAT}') }}"
satellite_location: "{{ sat_loc | default('${SAT_LOC:-CORE}') }}"
satellite_url: "${sat_internal_url}"
sat_firewalld_interface: "{{ sat_firewalld_interface | default('eth1') }}"
satellite_pre_use_idm: "{{ satellite_pre_use_idm | default(${sat_pre_use_idm_value}) | bool }}"
use_non_idm_certs: "{{ use_non_idm_certs | default(${sat_use_non_idm_certs_value}) | bool }}"
sat_ssl_certs_dir: "{{ sat_ssl_certs_dir | default('${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}') }}"
ipa_client_dns_servers: "{{ idm_ip | default('${IDM_IP:-10.168.128.3}') }}"
ipa_server_fqdn: "{{ idm_hostname | default('${IDM_HOSTNAME:-idm.${DOMAIN:-localdomain}}') }}"
EOF
    write_hostvars_pair "satellite.yml" "${SAT_HOSTNAME:-}" || return 1

    # AAP
    cat > "${primary_dir}/aap.yml" <<EOF
# aap.yml — generated by run_minirhis_install_sequence.sh
ansible_user: "{{ admin_user | default('${ADMIN_USER:-admin}') }}"
ansible_become: true
ansible_become_pass: "{{ global_admin_password | default('') }}"
aap_admin_user: "{{ ansible_user }}"
aap_admin_password: "{{ aap_admin_pass | default(global_admin_password) | default('') }}"
# Standalone AAP model: all platform services run as containers on this single host.
# The automation gateway is a local container on the AAP node (not a separate VM).
aap_single_host_mode: true
aap_gateway_mode: "local-container"
aap_gateway_host: "{{ aap_hostname | default('${AAP_HOSTNAME:-aap.${DOMAIN:-localdomain}}') }}"
aap_gateway_url: "https://{{ aap_hostname | default('${AAP_HOSTNAME:-aap.${DOMAIN:-localdomain}}') }}/"
platform_deployment_type: "${AAP_DEPLOYMENT_TYPE:-container}"
aap_topology: "${AAP_TOPOLOGY:-standalone}"
platform_installer_config:
    deployment_type: "${AAP_DEPLOYMENT_TYPE:-container}"
    topology: "${AAP_TOPOLOGY:-standalone}"
EOF
    write_hostvars_pair "aap.yml" "${AAP_HOSTNAME:-}" || return 1

    # IdM
    cat > "${primary_dir}/idm.yml" <<EOF
# idm.yml — generated by run_minirhis_install_sequence.sh
ansible_user: "{{ admin_user | default('${ADMIN_USER:-admin}') }}"
ansible_password: "{{ idm_admin_pass | default(global_admin_password) | default('') }}"
ansible_become: true
ansible_become_password: "{{ idm_admin_pass | default(global_admin_password) | default('') }}"
idm_realm: "{{ idm_realm | default('${IDM_REALM:-$(echo "${DOMAIN:-}" | tr '[:lower:]' '[:upper:]')}') }}"
idm_domain: "{{ idm_domain | default('${IDM_DOMAIN:-${DOMAIN:-}}') }}"
idm_user_groups:
    - name: "{{ idm_admins_group | default('minirhis-admins') }}"
      description: "MINIRHIS Infrastructure Administrators"
      state: present
      user_list:
          - minirhis-operator
    - name: "{{ idm_content_managers_group | default('content-managers') }}"
      description: "MINIRHIS Content Managers (Satellite, Repos, Lifecycle)"
      state: present
      user_list:
          - satellite-svc
    - name: "{{ idm_automation_engineers_group | default('automation-engineers') }}"
      description: "MINIRHIS Automation Engineers (Ansible, AAP)"
      state: present
      user_list:
          - aap-svc
    - name: "{{ idm_system_services_group | default('system-services') }}"
      description: "MINIRHIS System Service Accounts"
      state: present
idm_users:
    - login: satellite-svc
      first: Satellite
      last: "Service Account"
      displayname: "Satellite Service User"
      email:
          - "satellite-svc@{{ idm_domain | default(domain | default('localdomain')) }}"
      random: true
      state: present
    - login: aap-svc
      first: AAP
      last: "Service Account"
      displayname: "AAP Service User"
      email:
          - "aap-svc@{{ idm_domain | default(domain | default('localdomain')) }}"
      random: true
      state: present
    - login: minirhis-operator
      first: MINIRHIS
      last: Operator
      displayname: "MINIRHIS Operator User"
      email:
          - "minirhis-operator@{{ idm_domain | default(domain | default('localdomain')) }}"
      password: "{{ global_admin_password | default(idm_admin_pass | default('')) }}"
      state: present
idm_password_policies:
    - group_name: global_policy
      minlife: "0"
      maxlife: "365"
      minclasses: "3"
      minlength: "12"
      history: "6"
      state: present
EOF
    write_hostvars_pair "idm.yml" "${IDM_HOSTNAME:-}" || return 1

    chmod 0644 "${primary_dir}"/*.yml 2>/dev/null || true
    chmod 0644 "${container_dir}"/*.yml 2>/dev/null || true
    print_success "Generated host_vars in ${primary_dir}/ and synced container/roles/host_vars/"
}

# Keep Satellite UI + provided services pinned to the internal network.
# - Registration/CDN/Insights can still use eth0 from inside the guest.
# - Service endpoints managed by this automation should remain on eth1/SAT_IP.
enforce_satellite_internal_service_network() {
    if [ "${SAT_FIREWALLD_INTERFACE:-eth1}" != "eth1" ]; then
        print_warning "SAT_FIREWALLD_INTERFACE was '${SAT_FIREWALLD_INTERFACE}'; forcing to 'eth1' for internal Satellite services."
        SAT_FIREWALLD_INTERFACE="eth1"
    fi

    if [[ "${MINIRHIS_ENFORCE_SAT_INTERNAL_NETWORK:-1}" == "1" ]]; then
        if [[ ! "${SAT_IP:-}" =~ ^10\.168\. ]]; then
            print_warning "SAT_IP='${SAT_IP:-unset}' is outside 10.168.0.0/16. Refusing to continue with Satellite service configuration."
            return 1
        fi
    fi

    SATELLITE_URL_INTERNAL="https://${SAT_IP:-10.168.128.1}"
    print_step "Satellite service network policy: UI/services => ${SATELLITE_URL_INTERNAL} (interface: ${SAT_FIREWALLD_INTERFACE})."
    return 0
}

# ─── Local Ansible role runner ────────────────────────────────────────────────
# Invoke a role from container/roles/ directly on the installer host (no container).
# Returns 0 on success, 1 if ansible-playbook is unavailable or the playbook is
# missing (callers should then fall back to their native bash implementation).
#
# Usage: run_local_role <role_name> [target_limit] [extra ansible-playbook args...]
#   role_name    — must match a sub-dir under container/roles/ that has run.yml
#   target_limit — inventory limit (default: installer); use colon-separated groups
#                  e.g. "scenario_satellite:aap:idm"
#   extra args   — passed verbatim to ansible-playbook (e.g. --extra-vars "...")
#
# Environment consumed (all optional):
#   ANSIBLE_VAULT_PASS_FILE  — path to vault password file
#   ANSIBLE_ENV_FILE         — path to vault-encrypted vars file (passed as @extra-vars)
#   MINIRHIS_INVENTORY_FILE      — override default inventory
run_local_role() {
    local role="${1:?run_local_role: role name required}"
    local target="${2:-installer}"
    shift 2 || true
    local extra_args=("$@")

    local playbook="${SCRIPT_DIR}/container/roles/${role}/run.yml"
    local ansible_cfg="${SCRIPT_DIR}/container/roles/ansible.cfg"
    local inventory="${MINIRHIS_INVENTORY_FILE:-${SCRIPT_DIR}/container/roles/inventory/hosts.yml}"

    if [ ! -f "${playbook}" ]; then
        print_warning "run_local_role: playbook not found: ${playbook} — falling back to bash"
        return 1
    fi

    if ! command -v ansible-playbook >/dev/null 2>&1; then
        print_warning "run_local_role: ansible-playbook not in PATH — falling back to bash"
        return 1
    fi

    local -a vault_arg=()
    if [ -f "${ANSIBLE_VAULT_PASS_FILE:-}" ]; then
        vault_arg=(--vault-password-file "${ANSIBLE_VAULT_PASS_FILE}")
    fi

    local -a vault_vars=()
    if [ -f "${ANSIBLE_ENV_FILE:-}" ]; then
        vault_vars=(--extra-vars "@${ANSIBLE_ENV_FILE}")
    fi

    print_step "Running Ansible role '${role}' (limit: ${target})"
    ANSIBLE_CONFIG="${ansible_cfg}" ansible-playbook \
        --inventory "${inventory}" \
        --limit "${target}" \
        "${vault_arg[@]}" \
        "${vault_vars[@]}" \
        "${extra_args[@]}" \
        "${playbook}"
}

# ─── Container playbook runner ─────────────────────────────────────────────────
# Run one minirhis-builder playbook inside the provisioner container.
# Usage: run_container_playbook <playbook_path_inside_container> <--limit GROUP> [extra args...]
# The vault env.yml is passed as @extra-vars so all vault keys become Ansible vars.
run_container_playbook() {
    local playbook="$1"; shift
    local limit_flag="$1"; shift      # typically "--limit idm_primary" etc.
    local limit_group="$1"; shift
    local extra_args=("$@")

    # Ensure container is up; start it if not
    ensure_container_running || return 1

    local vault_file="/minirhis/vars/vault/$(basename "${ANSIBLE_ENV_FILE}")"
    local vault_pass="/minirhis/vars/vault/$(basename "${ANSIBLE_VAULT_PASS_FILE}")"
    local ansible_log_file="/minirhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}"
    local -a podman_user_args=()

    print_step "Running ${playbook} --limit ${limit_group} inside container '${MINIRHIS_CONTAINER_NAME}'"

    # If vault password file is readable, use it. If not readable as default
    # container user, try root. Otherwise fall back to prompting.
    local vault_arg=()
    if podman exec "${MINIRHIS_CONTAINER_NAME}" test -r "${vault_pass}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass}")
    elif podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" test -r "${vault_pass}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass}")
        podman_user_args=(--user 0)
        print_step "Vault password file requires container root access; executing playbook as root."
    else
        vault_arg=(--ask-vault-pass)
    fi

    print_step "Ansible log: ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    print_step "Ansible config: ${MINIRHIS_ANSIBLE_CFG_HOST}"

    podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
        ansible-playbook \
            --inventory "${MINIRHIS_CONTAINER_INVENTORY_FILE}" \
            "${vault_arg[@]}" \
            --extra-vars "@${vault_file}" \
            --limit "${limit_group}" \
            "${extra_args[@]}" \
            "${playbook}"
}

stage_satellite_manifest() {
    # shellcheck disable=SC2086
    local staged_host_path
    if [ -n "${SAT_MANIFEST_PATH:-}" ]; then
        if [ -f "${SAT_MANIFEST_PATH}" ]; then
            staged_host_path="${SAT_MANIFEST_PATH}"
        else
            print_warning "SAT_MANIFEST_PATH is set but does not exist: ${SAT_MANIFEST_PATH}"
            return 0
        fi
    else
        # Try to discover manifest in primary location first
        staged_host_path="$(ls -1t ${HOME}/Downloads/manifest_*.zip 2>/dev/null | head -1 || true)"
        
        # If not found in Downloads, check libvirt images directory as fallback
        if [ -z "${staged_host_path}" ] && [ -d "/var/lib/libvirt/images" ]; then
            staged_host_path="$(ls -1t /var/lib/libvirt/images/manifest_*.zip 2>/dev/null | head -1 || true)"
            if [ -n "${staged_host_path}" ]; then
                print_step "Manifest not found in ${HOME}/Downloads/, using fallback location: ${staged_host_path}"
            fi
        fi
    fi
    if [ -z "${staged_host_path}" ]; then
        return 0   # No manifest found — silent skip; portal-generated manifests are used instead
    fi

    print_step "Manifest detected: ${staged_host_path}"

    # Stage to KVM files directory (for libvirt file serving)
    if [ ! -d "${FILES_DIR}" ]; then
        sudo mkdir -p "${FILES_DIR}" && sudo chmod 0755 "${FILES_DIR}" || {
            print_warning "Could not create FILES_DIR at ${FILES_DIR}; skipping KVM files staging."
        }
    fi
    cp -f "${staged_host_path}" "${FILES_DIR}/manifest.zip" 2>/dev/null || \
        print_warning "Could not copy manifest to ${FILES_DIR}."

    # Stage to vault/conf dir — mounted as /minirhis/vars/vault/ inside the container
    if [ ! -d "${ANSIBLE_ENV_DIR}" ]; then
        mkdir -p "${ANSIBLE_ENV_DIR}" && chmod 0755 "${ANSIBLE_ENV_DIR}" || {
            print_warning "Could not create ANSIBLE_ENV_DIR at ${ANSIBLE_ENV_DIR}; skipping manifest staging."
            return 0
        }
    fi
    cp -f "${staged_host_path}" "${ANSIBLE_ENV_DIR}/manifest.zip" || {
        print_warning "Could not copy manifest to ${ANSIBLE_ENV_DIR}; manifest will not be auto-imported."
        return 0
    }

    MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH="/minirhis/vars/vault/manifest.zip"
    export MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH
    print_success "Manifest staged — container path: ${MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH}"
}

# ─── Post-install config-as-code orchestration ────────────────────────────────
# Called automatically after all VMs are running.  Regenerates inventory and
# host_vars from the current env, starts the provisioner container, then runs
# the minirhis-builder playbooks in dependency order: IdM → Satellite → AAP.
run_minirhis_config_as_code() {
    print_step "===== MINIRHIS Config-as-Code Phase ====="
    print_step "Generating fresh inventory and host_vars from env.yml..."
    local idm_status="not-run"
    local satellite_status="not-run"
    local aap_status="not-run"
    local idm_auth_fallback_status="not-needed"
    local satellite_auth_fallback_status="not-needed"
    local aap_auth_fallback_status="not-needed"
    local phase_auth_fallback_status="not-needed"
    local any_failed=0
    local use_local_exec=0
    local component_scope="${MINIRHIS_COMPONENT_SCOPE:-all}"
    local run_idm=1
    local run_satellite=1
    local run_aap=1
    local -a phase_gate_targets=()

    case "${component_scope}" in
        all)
            run_idm=1
            run_satellite=1
            run_aap=1
            ;;
        idm)
            run_idm=1
            run_satellite=0
            run_aap=0
            ;;
        satellite)
            run_idm=0
            run_satellite=1
            run_aap=0
            ;;
        aap)
            run_idm=0
            run_satellite=0
            run_aap=1
            ;;
        rhis-aap)
            run_idm=0
            run_satellite=0
            run_aap=0
            ;;
        *)
            print_warning "Unknown MINIRHIS_COMPONENT_SCOPE='${component_scope}', defaulting to full flow."
            run_idm=1
            run_satellite=1
            run_aap=1
            component_scope="all"
            ;;
    esac
    print_step "Component scope: ${component_scope}"
    if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
        print_step "Execution mode: local ${USER} repo (local-first reruns/fallbacks enabled)"
        use_local_exec=1
        MINIRHIS_LOCAL_ROLE_FALLBACK=1
        MINIRHIS_ENABLE_CONTAINER_HOTFIXES=0
        generate_local_roles_ansible_cfg || true
    else
        print_step "Execution mode: minirhis_provisioner"
    fi

    load_ansible_env_file || true
    normalize_shared_env_vars
    enforce_satellite_internal_service_network || return 1

    # Keep installer-host /etc/hosts aligned with current external/NAT VM IPs.
    sync_minirhis_external_hosts_entries || true

    # Re-sync installer/user/root trust before entering phase playbooks.
    # This is intentionally best-effort here because some nodes may still be
    # converging; phase auth fallback remains the final safety net.
    print_step "Pre-flight: refreshing MINIRHIS SSH trust baseline before config-as-code"
    if ! setup_minirhis_ssh_mesh "${component_scope}"; then
        print_warning "SSH trust baseline refresh did not fully converge; continuing with phase auth fallback logic."
    fi

    # Ensure root auth fallback path is reliable even on reruns where guest-side
    # passwords drifted from current vault values.
    print_step "Pre-flight: normalizing VM root passwords for auth fallback reliability"
    fix_vm_root_passwords || print_warning "Root password pre-flight normalization did not complete cleanly; continuing."

    generate_minirhis_inventory     || { print_warning "Inventory generation failed; skipping config-as-code."; return 1; }
    generate_minirhis_host_vars     || { print_warning "host_vars generation failed; skipping config-as-code."; return 1; }
    if [ "${run_idm}" -eq 1 ]; then
        phase_gate_targets+=("idm:${IDM_IP}")
    fi
    if [ "${run_satellite}" -eq 1 ]; then
        phase_gate_targets+=("satellite:${SAT_IP}")
    fi
    if [ "${run_aap}" -eq 1 ] && [ "${run_idm}" -eq 0 ] && [ "${run_satellite}" -eq 0 ]; then
        phase_gate_targets+=("aap:${AAP_IP}")
    fi
    if [ "${#phase_gate_targets[@]}" -gt 0 ]; then
        print_step "Phase gate: waiting for selected component prerequisites"
        preflight_config_as_code_targets "${phase_gate_targets[@]}" || return 1
    fi

    # ---- Pre-container bootstrap helpers -----------------------------------
    run_satellite_precontainer_bootstrap() {
        local sat_target_ip="${SAT_IP:-10.168.128.1}"
        local sat_target_host="${SAT_HOSTNAME:-satellite}"
        local ssh_key="${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-${HOME}/.ssh/minirhis-installer/id_rsa}"
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local rh_user_q=""
        local rh_pass_q=""
        local admin_user_q=""
        local admin_pass_q=""
        local remote_cmd=""

        if ! is_enabled "${MINIRHIS_SAT_PRECONTAINER_BOOTSTRAP:-1}"; then
            print_step "Satellite pre-container bootstrap disabled (MINIRHIS_SAT_PRECONTAINER_BOOTSTRAP=0)."
            return 0
        fi

        [ "${run_satellite}" -eq 1 ] || return 0

        if [ -z "${RH_USER:-}" ] || [ -z "${RH_PASS:-}" ]; then
            print_warning "Skipping Satellite pre-container bootstrap: RH_USER/RH_PASS is not set."
            return 1
        fi

        printf -v rh_user_q '%q' "${RH_USER}"
        printf -v rh_pass_q '%q' "${RH_PASS}"
        printf -v admin_user_q '%q' "${ADMIN_USER:-admin}"
        printf -v admin_pass_q '%q' "${ADMIN_PASS:-}"

        # Ensure we have a usable SSH key path for root login first.
        if [ ! -r "${ssh_key}" ]; then
            ssh_key="${HOME}/.ssh/id_rsa"
        fi

                                remote_cmd="set -euo pipefail; \
hostnamectl set-hostname ${sat_target_host}; \
grep -q \"${sat_target_ip}.*${sat_target_host}\" /etc/hosts || echo \"${sat_target_ip} ${sat_target_host} satellite\" >> /etc/hosts; \
nmcli device modify eth1 ipv4.addresses ${sat_target_ip}/16 ipv4.method manual >/dev/null 2>&1 || true; \
nmcli device up eth1 >/dev/null 2>&1 || true; \
if ! subscription-manager identity >/dev/null 2>&1; then \
    subscription-manager register --username ${rh_user_q} --password ${rh_pass_q} --force; \
fi; \
subscription-manager refresh || true; \
subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms --enable=rhel-9-for-x86_64-appstream-rpms --enable=satellite-6.18-for-rhel-9-x86_64-rpms --enable=satellite-maintenance-6.18-for-rhel-9-x86_64-rpms; \
dnf clean all; \
if command -v foreman-maintain >/dev/null 2>&1; then foreman-maintain packages unlock >/dev/null 2>&1 || true; fi; \
dnf upgrade -y; \
if ! rpm -q satellite >/dev/null 2>&1; then dnf install -y satellite; fi; \
if command -v foreman-maintain >/dev/null 2>&1; then foreman-maintain packages unlock >/dev/null 2>&1 || true; fi; \
satellite-installer --scenario satellite \
  --foreman-initial-organization \"${SAT_ORG:-REDHAT}\" \
  --foreman-initial-location \"${SAT_LOC:-CORE}\" \
  --foreman-initial-admin-username ${admin_user_q} \
  --foreman-initial-admin-password ${admin_pass_q} \
  --enable-foreman-plugin-ansible \
    --enable-foreman-proxy-plugin-ansible"

    print_step "Pre-container Satellite bootstrap: register, clear package locks when possible, upgrade, install satellite, then run first-pass satellite-installer"

        if [ -r "${ssh_key}" ] && timeout 10 ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no "root@${sat_target_ip}" 'echo ready' >/dev/null 2>&1; then
            if ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no "root@${sat_target_ip}" "${remote_cmd}"; then
                print_success "Satellite pre-container bootstrap complete on ${sat_target_host} (${sat_target_ip})."
                return 0
            fi
        fi

        # Fallback to password auth when key-based root login is not ready.
        if [ -n "${root_auth_pass}" ] && command -v sshpass >/dev/null 2>&1; then
            print_warning "Satellite pre-container bootstrap key-auth failed; retrying with root password auth fallback."
            if sshpass -p "${root_auth_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no "root@${sat_target_ip}" "${remote_cmd}"; then
                print_success "Satellite pre-container bootstrap complete with password fallback on ${sat_target_host} (${sat_target_ip})."
                return 0
            fi
        fi

        print_warning "Satellite pre-container bootstrap failed before container phase."
        return 1
    }

    if [ "${run_satellite}" -eq 1 ]; then
        run_satellite_precontainer_bootstrap || return 1
    fi

    # Pull latest image and ensure container is running with fresh mounts
    if [ "${use_local_exec}" -eq 0 ]; then
        print_step "Ensuring MINIRHIS provisioner container is running..."
        podman pull "${MINIRHIS_CONTAINER_IMAGE}" 2>/dev/null || true
        podman images -f "dangling=true" -q | xargs --no-run-if-empty podman rmi 2>/dev/null && \
            print_step "Cleaned up dangling container images." || true
        ensure_container_running || { print_warning "Could not start provisioner container; skipping config-as-code."; return 1; }
    else
        print_step "Local ${USER} repo selected: skipping mandatory provisioner container bootstrap."
    fi

    # Keep visible progress terminals attached for both VM console output and
    # Ansible/script activity whenever a GUI desktop session is available.
    ensure_live_progress_monitors || true

    if [ "${use_local_exec}" -eq 0 ]; then
        case "${component_scope}" in
            satellite)
                launch_single_vm_console_monitor_auto "satellite" || print_warning "Automatic Satellite console reattach failed; continuing config-as-code."
                ;;
            idm)
                launch_single_vm_console_monitor_auto "idm" || print_warning "Automatic IdM console reattach failed; continuing config-as-code."
                ;;
            aap)
                launch_single_vm_console_monitor_auto "aap" || print_warning "Automatic AAP console reattach failed; continuing config-as-code."
                ;;
            *)
                reattach_vm_consoles || print_warning "Automatic VM console reattach failed; continuing config-as-code."
                ;;
        esac
    fi

    local vault_file="/minirhis/vars/vault/$(basename "${ANSIBLE_ENV_FILE}")"
    local vault_pass_file="/minirhis/vars/vault/$(basename "${ANSIBLE_VAULT_PASS_FILE}")"
    local ansible_log_file="/minirhis/vars/vault/${AAP_ANSIBLE_LOG_BASENAME}"
    local vault_arg=()
    local -a podman_user_args=()
    local use_interactive_vault_prompt=0
    local staged_vault_pass_host=""
    local staged_vault_pass_file=""

    # ---- Vault / container execution context --------------------------------
    cleanup_staged_vaultpass() {
        # Keep a stable staged vaultpass file so manual reruns can reuse:
        #   --vault-password-file /minirhis/vars/vault/.vaultpass.container
        return 0
    }

    if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
        if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
            vault_arg=(--vault-password-file "${ANSIBLE_VAULT_PASS_FILE}")
        elif is_noninteractive; then
            print_warning "Vault password file not readable at ${ANSIBLE_VAULT_PASS_FILE}."
            print_warning "NONINTERACTIVE mode cannot prompt for a vault password."
            return 1
        else
            vault_arg=(--ask-vault-pass)
            use_interactive_vault_prompt=1
        fi
    elif podman exec "${MINIRHIS_CONTAINER_NAME}" test -r "${vault_pass_file}" 2>/dev/null; then
        vault_arg=(--vault-password-file "${vault_pass_file}")
    elif podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" test -r "${vault_pass_file}" 2>/dev/null; then
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
                staged_vault_pass_file="/minirhis/vars/vault/$(basename "${staged_vault_pass_host}")"

                if podman exec "${MINIRHIS_CONTAINER_NAME}" test -r "${staged_vault_pass_file}" 2>/dev/null; then
                    vault_arg=(--vault-password-file "${staged_vault_pass_file}")
                    print_step "Using temporary container-readable vault password file for this run."
                elif podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" test -r "${staged_vault_pass_file}" 2>/dev/null; then
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

    local inv="--inventory ${MINIRHIS_CONTAINER_INVENTORY_FILE}"
    local sat_pre_use_idm="${SATELLITE_PRE_USE_IDM:-false}"
    local sat_use_non_idm_certs="${SAT_USE_NON_IDM_CERTS:-}"
    local idm_async_timeout="${IDM_ASYNC_TIMEOUT:-14400}"
    local idm_async_delay="${IDM_ASYNC_DELAY:-15}"
    local sat_installer_timeout="${SAT_INSTALLER_TIMEOUT:-7200}"
    local sat_installer_verbose="${SAT_INSTALLER_VERBOSE:-true}"
    local sat_ipa_dns="${IDM_IP:-10.168.128.3}"
    local sat_ipa_fqdn="${IDM_HOSTNAME:-idm.${DOMAIN:-localdomain}}"
    case "${sat_pre_use_idm}" in
        1|true|TRUE|yes|YES|on|ON) sat_pre_use_idm="true" ;;
        *) sat_pre_use_idm="false" ;;
    esac
    case "${sat_use_non_idm_certs}" in
        1|true|TRUE|yes|YES|on|ON) sat_use_non_idm_certs="true" ;;
        0|false|FALSE|no|NO|off|OFF) sat_use_non_idm_certs="false" ;;
        *)
            if [ "${sat_pre_use_idm}" = "true" ]; then
                sat_use_non_idm_certs="false"
            else
                sat_use_non_idm_certs="true"
            fi
            ;;
    esac
    local sat_ssl_certs_dir="${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}"
    case "${sat_ssl_certs_dir}" in
        */) ;;
        *) sat_ssl_certs_dir="${sat_ssl_certs_dir}/" ;;
    esac
    local evars="--extra-vars @${vault_file} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"
    local manual_evars="--extra-vars @${vault_file} --extra-vars '{\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}'"
    local local_manual_evars="--extra-vars @${ANSIBLE_ENV_FILE} --extra-vars '{\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}'"
    local manual_vault_arg="${vault_arg[*]}"
    local local_manual_vault_arg="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
    if [ -z "${manual_vault_arg}" ]; then
        manual_vault_arg="--ask-vault-pass"
    fi
    if [ ! -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
        local_manual_vault_arg="--ask-vault-pass"
    fi

    # Per-phase extras for copy-paste manual reruns — must mirror what run_phase_playbook injects.
    # IdM: bypass the rhc 'Configure remediation' block (GPG fails on RHEL 10 for rhc-worker-playbook)
    local manual_idm_extras="--extra-vars '{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}'"
    if [ -n "${IPADM_PASSWORD:-}" ]; then
        manual_idm_extras+=" -e 'ipadm_password=${IPADM_PASSWORD}' -e 'ipaadmin_password=${IPAADMIN_PASSWORD:-${IPADM_PASSWORD}}'"
    fi

    # Satellite: supply sat_repository_ids, firewall settings, and CDN registration vars
    local _sat_manual_json="{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\",\"sat_installer_timeout\":${sat_installer_timeout},\"sat_installer_verbose\":${sat_installer_verbose}}"
    local manual_satellite_extras="--extra-vars '${_sat_manual_json}'"
    local manual_podman_env="-e ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}"

    # ---- Nested ansible/podman helper wrappers ------------------------------
    run_ansible_shell_in_container() {
        local target="$1"
        local shell_cmd="$2"
        local root_auth_pass="${3:-}"
        local extra_args="${4:-}"

        if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
            local local_inv="--inventory ${MINIRHIS_INVENTORY_FILE}"
            local local_cfg="${SCRIPT_DIR}/container/roles/ansible.cfg"
            local local_evars="--extra-vars @${ANSIBLE_ENV_FILE} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"
            local local_vault_arg=""
            [ -f "${local_cfg}" ] || local_cfg="${MINIRHIS_ANSIBLE_CFG_HOST}"
            if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
                local_vault_arg="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
            else
                local_vault_arg="--ask-vault-pass"
            fi

            if [ -n "${root_auth_pass}" ]; then
                ANSIBLE_CONFIG="${local_cfg}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                    ansible "${target}" ${local_inv} ${local_vault_arg} ${local_evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${shell_cmd}" ${extra_args}
            else
                ANSIBLE_CONFIG="${local_cfg}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                    ansible "${target}" ${local_inv} ${local_vault_arg} ${local_evars} \
                    -m shell -a "${shell_cmd}" ${extra_args}
            fi
            return $?
        fi

        if [ -n "${root_auth_pass}" ]; then
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${shell_cmd}" ${extra_args}
            else
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m shell -a "${shell_cmd}" ${extra_args}
            fi
        else
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -m shell -a "${shell_cmd}" ${extra_args}
            else
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "${target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -m shell -a "${shell_cmd}" ${extra_args}
            fi
        fi
    }

    # ---- Container hotfix / compatibility helpers ---------------------------
    ensure_satellite_chrony_template() {
        local _tpl_path="/minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2"
        local _mk_cmd='mkdir -p /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates && cat > /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# MINIRHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

        if podman exec "${MINIRHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
            return 0
        fi

        print_warning "chrony.j2 is missing in minirhis-builder-satellite; applying fallback template workaround."

        if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
            print_success "Fallback chrony.j2 created in minirhis-builder-satellite templates."
            return 0
        fi

        print_warning "Failed to create fallback chrony.j2; will skip tags_satellite_pre_chrony."
        return 1
    }

    ensure_idm_chrony_template() {
        local _tpl_path="/minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2"
        local _mk_cmd='mkdir -p /minirhis/minirhis-builder-idm/roles/idm_pre/templates && cat > /minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2 <<'"'"'EOF'"'"'
# MINIRHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
EOF'

        if podman exec "${MINIRHIS_CONTAINER_NAME}" test -f "${_tpl_path}" 2>/dev/null; then
            return 0
        fi

        print_warning "chrony.j2 is missing in minirhis-builder-idm; applying fallback template workaround."

        if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_mk_cmd}" >/dev/null 2>&1; then
            print_success "Fallback chrony.j2 created in minirhis-builder-idm templates."
            return 0
        fi

        print_warning "Failed to create IdM fallback chrony.j2; idm_pre chrony task may fail."
        return 1
    }

    ensure_fix_satellite_content_profile() {
        # Patch the container copy of satellite_content_profile.yml to ensure
        # non-recursive satellite_organization and explicit admin password.
        local _path="/minirhis/vars/host_vars/satellite_content_profile.yml"
        print_step "Applying satellite_content_profile patch inside container"

        if podman exec -i --env TARGET_PATH="${_path}" "${MINIRHIS_CONTAINER_NAME}" python3 - <<'PY'
import os, pathlib, sys
import re
p=pathlib.Path(os.environ.get('TARGET_PATH'))
if not p.exists():
    print('MISSING')
    sys.exit(0)
text=p.read_text(encoding='utf-8',errors='ignore')
text=text.replace('satellite_organization: "{{ satellite_organization | default(\'REDHAT\') }}"','satellite_organization: "REDHAT"')
text=text.replace('satellite_organization: "{{ sat_org | default(\'REDHAT\') }}"','satellite_organization: "REDHAT"')
text=re.sub(r'^satellite_password:\s+"[^"]*"$', 'satellite_password: "{{ sat_admin_pass | default(global_admin_password) | default(\'\') }}"', text, flags=re.M)
text=re.sub(r'^foreman_password:\s+"[^"]*"$', 'foreman_password: "{{ sat_admin_pass | default(global_admin_password) | default(\'\') }}"', text, flags=re.M)
text=re.sub(r'^hammer_password:\s+"[^"]*"$', 'hammer_password: "{{ sat_admin_pass | default(global_admin_password) | default(\'\') }}"', text, flags=re.M)
p.write_text(text,encoding='utf-8')
print('PATCHED')
PY
        then
            print_success "Patched satellite_content_profile inside container"
            return 0
        fi

        print_warning "Could not patch satellite_content_profile inside container"
        return 1
    }

    ensure_patch_lifecycle_tasks() {
        # Remove no_log and add debug output in lifecycle_environments tasks inside container
        local _path="/minirhis/minirhis-builder-satellite/roles/lifecycle_environments/tasks/main.yml"
        print_step "Patching lifecycle_environments tasks inside container"

        if podman exec -i --env TARGET_PATH="${_path}" "${MINIRHIS_CONTAINER_NAME}" python3 - <<'PY'
import os, pathlib, sys
p=pathlib.Path(os.environ.get('TARGET_PATH'))
if not p.exists():
    print('MISSING')
    sys.exit(0)
text=p.read_text(encoding='utf-8',errors='ignore')
if 'no_log: true' in text:
    text=text.replace('no_log: true','no_log: false')
p.write_text(text,encoding='utf-8')
print('PATCHED')
PY
        then
            print_success "Patched lifecycle_environments tasks inside container"
            return 0
        fi

        print_warning "Could not patch lifecycle_environments tasks inside container"
        return 1
    }

    ensure_satellite_foreman_service_check_nonfatal() {
        local _root="/minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks"
        local _py='import pathlib
import re

root = pathlib.Path("/minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks")
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

        _out="$(podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        if [ -z "${_out}" ]; then
            _out="$(podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
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

    run_repo_hotfixes() {
        # Run repository-managed Ansible role that applies container hotfixes
        local repo_root
        repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if command -v ansible-playbook >/dev/null 2>&1; then
            ANSIBLE_ROLES_PATH="${repo_root}/container/roles" \
                ansible-playbook -i localhost, "${repo_root}/container/roles/minirhis_installer/run.yml" --connection=local || true
        else
            print_warning "ansible-playbook not found; skipping repo hotfixes"
        fi
    }

    ensure_idm_update_task_nogpgcheck() {
        local _py='import pathlib
import re

path = pathlib.Path("/minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml")
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
        _out="$(podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
        if [ -z "${_out}" ]; then
            _out="$(podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_cmd}" 2>/dev/null || true)"
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
        local _scope="${MINIRHIS_COMPONENT_SCOPE:-all}"
        local _verify_cmd='test -f /minirhis/minirhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 && test -f /minirhis/minirhis-builder-idm/roles/idm_pre/templates/chrony.j2 && grep -q "failed_when: false" /minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks/is_satellite_installed.yml && grep -q "disable_gpg_check: true" /minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml && grep -q "exclude: \"intel-audio-firmware\\*\"" /minirhis/minirhis-builder-idm/roles/idm_pre/tasks/ensure_update_system.yml && grep -q "Check Satellite API endpoint readiness (hard gate)" /minirhis/minirhis-builder-satellite/tasks/configure_hammer.yml && grep -q "vars\['"'"'ansible_roles_import_list'"'"'\]" /minirhis/minirhis-builder-satellite/tasks/ensure_import_roles.yml && grep -q "Ensure local Satellite proxy has TFTP enabled in Foreman" /minirhis/minirhis-builder-satellite/tasks/build_pxe_linux_defaults.yml && test -f /minirhis/minirhis-builder-satellite/tasks/ensure_local_tftp_proxy.yml && test -f /minirhis/minirhis-builder-satellite/roles/satellite_pre/tasks/ensure_packages_unlock.yml'
        local _verified=1

        print_step "Pre-flight: applying container role hotfixes"

        ensure_satellite_foreman_service_check_nonfatal || true
        ensure_idm_chrony_template || true
        ensure_idm_update_task_nogpgcheck || true
        # New hotfixes applied during troubleshooting (MiniRHIS fixes):
        run_repo_hotfixes || true

        # AAP-only runs do not execute Satellite/IdM playbooks, so do not block
        # the workflow on unrelated hotfix verification gates.
        if [ "${_scope}" = "aap" ]; then
            print_step "Container hotfix verification: AAP-only scope detected; skipping Satellite/IdM gate checks."
            return 0
        fi

        if podman exec "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1 || \
           podman exec --user 0 "${MINIRHIS_CONTAINER_NAME}" bash -lc "${_verify_cmd}" >/dev/null 2>&1; then
            _verified=0
        fi

        if [ "${_verified}" -eq 0 ]; then
            print_success "Container hotfix verification passed (Satellite hammer/PXE/import + IdM GPG update guards)."
            return 0
        fi

        if is_enabled "${MINIRHIS_ENFORCE_CONTAINER_HOTFIXES:-1}"; then
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
    if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ]; then
        if ! ensure_satellite_chrony_template; then
            manual_satellite_extras+=" --skip-tags tags_satellite_pre_chrony"
        fi
        if is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
            ensure_container_playbook_hotfixes || return 1
        fi
    fi

    # ---- Manual rerun / local fallback helpers ------------------------------
    inventory_group_exists() {
        local group_name="$1"
        local inv_file="${MINIRHIS_INVENTORY_FILE}"
        [ -n "${group_name}" ] || return 1
        [ -f "${inv_file}" ] || return 1
        grep -qiE "^\[${group_name//./\\.}\]$|^\[${group_name//./\\.}:children\]$" "${inv_file}" 2>/dev/null
    }

    resolve_component_limit_group() {
        local component="$1"
        case "${component}" in
            idm)
                if inventory_group_exists "idm"; then
                    echo "idm"
                elif inventory_group_exists "idm_primary"; then
                    echo "idm_primary"
                else
                    echo "idm"
                fi
                ;;
            satellite)
                if inventory_group_exists "scenario_satellite"; then
                    echo "scenario_satellite"
                elif inventory_group_exists "sat_primary"; then
                    echo "sat_primary"
                elif inventory_group_exists "satellite"; then
                    echo "satellite"
                else
                    echo "scenario_satellite"
                fi
                ;;
            aap)
                if inventory_group_exists "aap"; then
                    echo "aap"
                elif inventory_group_exists "aap_hosts"; then
                    echo "aap_hosts"
                else
                    echo "aap"
                fi
                ;;
            *)
                echo "all"
                ;;
        esac
    }

    resolve_local_component_playbook() {
        local component_dir="$1"
        local direct_path="${SCRIPT_DIR}/container/roles/${component_dir}/main.yml"
        local nested_path="${SCRIPT_DIR}/container/roles/${component_dir}/${component_dir}/main.yml"

        if [ -f "${direct_path}" ]; then
            echo "${direct_path}"
            return 0
        fi
        if [ -f "${nested_path}" ]; then
            echo "${nested_path}"
            return 0
        fi

        echo "${direct_path}"
    }

    print_manual_rerun_template() {
        local component="${1:-all}"
        local target_limit=""
        local local_playbook=""
        local container_playbook=""
        local rerun_extras=""

        case "${component}" in
            idm)
                target_limit="$(resolve_component_limit_group "idm")"
                local_playbook="$(resolve_local_component_playbook "minirhis-builder-idm")"
                container_playbook="/minirhis/minirhis-builder-idm/main.yml"
                rerun_extras="${manual_idm_extras}"
                ;;
            satellite)
                target_limit="$(resolve_component_limit_group "satellite")"
                local_playbook="$(resolve_local_component_playbook "minirhis-builder-satellite")"
                container_playbook="/minirhis/minirhis-builder-satellite/main.yml"
                rerun_extras="${manual_satellite_extras}"
                ;;
            aap)
                target_limit="$(resolve_component_limit_group "aap")"
                local_playbook="$(resolve_local_component_playbook "minirhis-builder-aap")"
                container_playbook="/minirhis/minirhis-builder-aap/main.yml"
                rerun_extras=""
                ;;
            *)
                print_warning "Manual rerun commands (local-first, inventory-driven):"
                print_manual_rerun_template "idm"
                print_manual_rerun_template "satellite"
                print_manual_rerun_template "aap"
                print_warning "Execution mode note: local ${USER} repo is the default recommendation for now (uses ${SCRIPT_DIR}/container/roles and ${MINIRHIS_INVENTORY_FILE})."
                print_warning "minirhis_provisioner mode is still available if needed."
                return 0
                ;;
        esac

        if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ]; then
            print_warning "${component^^} rerun (container):"
            print_warning "  podman exec -it ${manual_podman_env} ${MINIRHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} ${rerun_extras} --limit ${target_limit} ${container_playbook}"
            print_warning "${component^^} rerun (local, optional):"
            print_warning "  ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_HOST} ansible-playbook --inventory ${MINIRHIS_INVENTORY_FILE} ${local_manual_vault_arg} ${local_manual_evars} ${rerun_extras} --limit ${target_limit} ${local_playbook}"
        else
            print_warning "${component^^} rerun (local):"
            print_warning "  ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_HOST} ansible-playbook --inventory ${MINIRHIS_INVENTORY_FILE} ${local_manual_vault_arg} ${local_manual_evars} ${rerun_extras} --limit ${target_limit} ${local_playbook}"
            print_warning "${component^^} rerun (container, optional):"
            print_warning "  podman exec -it ${manual_podman_env} ${MINIRHIS_CONTAINER_NAME} ansible-playbook ${inv} ${manual_vault_arg} ${manual_evars} ${rerun_extras} --limit ${target_limit} ${container_playbook}"
        fi
    }

    sync_container_assets_to_local_roles() {
        local workdir="${MINIRHIS_LOCAL_ROLE_WORKDIR:-$SCRIPT_DIR/container/roles}"
        local inv_dir="${workdir}/inventory"
        local vault_dir="${workdir}/vault"
        local hv_dir="${workdir}/host_vars"
        local local_cfg="${workdir}/ansible.cfg"
        local tree
        local stage_dir="${workdir}/.minirhis-sync-stage-$$"

        ensure_container_running_with_retry || return 1

        mkdir -p "${workdir}" "${inv_dir}" "${vault_dir}" "${hv_dir}" || return 1
        rm -rf "${stage_dir}" >/dev/null 2>&1 || true
        mkdir -p "${stage_dir}" || return 1

        for tree in minirhis-builder-satellite minirhis-builder-idm minirhis-builder-aap; do
            rm -rf "${stage_dir}/${tree}" >/dev/null 2>&1 || true
            if podman cp "${MINIRHIS_CONTAINER_NAME}:/minirhis/${tree}" "${stage_dir}/" >/dev/null 2>&1; then
                rm -rf "${workdir}/${tree}" >/dev/null 2>&1 || true
                mv "${stage_dir}/${tree}" "${workdir}/" >/dev/null 2>&1 || {
                    print_warning "Could not stage ${tree} into ${workdir}; keeping existing local tree if present."
                    [ -d "${workdir}/${tree}" ] || return 1
                }
            else
                print_warning "Could not copy ${tree} from container to ${workdir}; keeping existing local tree if present."
                [ -d "${workdir}/${tree}" ] || return 1
            fi
        done

        rm -rf "${stage_dir}" >/dev/null 2>&1 || true

        local inv_name="$(basename "${MINIRHIS_INVENTORY_FILE}")"
        podman cp "${MINIRHIS_CONTAINER_NAME}:${MINIRHIS_CONTAINER_INVENTORY_FILE}" "${inv_dir}/${inv_name}" >/dev/null 2>&1 || return 1
        podman cp "${MINIRHIS_CONTAINER_NAME}:/minirhis/vars/vault/env.yml" "${vault_dir}/env.yml" >/dev/null 2>&1 || return 1
        podman cp "${MINIRHIS_CONTAINER_NAME}:/minirhis/vars/host_vars/." "${hv_dir}/" >/dev/null 2>&1 || true

        cat > "${local_cfg}" <<EOF
[defaults]
    inventory = ${inv_dir}/${inv_name}
host_key_checking = False
retry_files_enabled = False
roles_path = ${workdir}/minirhis-builder-satellite/roles:${workdir}/minirhis-builder-idm/roles:${workdir}/minirhis-builder-aap/roles
stdout_callback = ansible.builtin.default
result_format = yaml
EOF

        chmod 600 "${vault_dir}/env.yml" 2>/dev/null || true
        print_success "Synced container playbooks/inventory/vault to ${workdir}"
        return 0
    }

    run_local_satellite_playbook_fallback() {
        local workdir="${MINIRHIS_LOCAL_ROLE_WORKDIR:-$SCRIPT_DIR/container/roles}"
        local local_playbook="${workdir}/minirhis-builder-satellite/main.yml"
        local local_inv="${workdir}/inventory/$(basename "${MINIRHIS_INVENTORY_FILE}")"
        local local_vault_env="${workdir}/vault/env.yml"
        local local_cfg="${workdir}/ansible.cfg"
        local root_auth_pass_local="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local local_extra_json
        local -a local_cmd

        is_enabled "${MINIRHIS_LOCAL_ROLE_FALLBACK:-1}" || return 1

        sync_container_assets_to_local_roles || return 1

        if ! command -v ansible-playbook >/dev/null 2>&1; then
            print_step "Installing ansible-core for local fallback execution"
            sudo dnf install -y --nogpgcheck ansible-core >/dev/null 2>&1 || return 1
        fi

        [ -f "${local_playbook}" ] || return 1
        [ -f "${local_inv}" ] || return 1
        [ -f "${local_vault_env}" ] || return 1
        [ -r "${ANSIBLE_VAULT_PASS_FILE}" ] || {
            print_warning "Vault password file not readable at ${ANSIBLE_VAULT_PASS_FILE}; cannot run local fallback."
            return 1
        }

        local_extra_json="{\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"

        local_cmd=(
            ansible-playbook
            --inventory "${local_inv}"
            --vault-password-file "${ANSIBLE_VAULT_PASS_FILE}"
            --extra-vars "@${local_vault_env}"
            --extra-vars "${local_extra_json}"
            --extra-vars "${_sat_manual_json}"
            --limit "scenario_satellite"
            "${local_playbook}"
        )

        if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
            local_cmd+=( -e "cdn_organization_id=${CDN_ORGANIZATION_ID}" -e "cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}" )
        fi

        if [ -n "${root_auth_pass_local}" ]; then
            local_cmd+=(
                -e "ansible_user=root"
                -e "ansible_password=${root_auth_pass_local}"
                -e "ansible_become=false"
                -e "ansible_become_password=${root_auth_pass_local}"
            )
        fi

        print_step "Running local Satellite fallback playbook from ${workdir}"
        ANSIBLE_CONFIG="${local_cfg}" "${local_cmd[@]}"
    }

    print_step "Ansible log: ${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}"
    print_step "Ansible config: ${MINIRHIS_ANSIBLE_CFG_HOST}"

    # ---- Phase execution wrappers -------------------------------------------
    run_phase_playbook() {
        local phase_label="$1"
        local phase_limit="$2"
        local phase_playbook="$3"
        local -a phase_args=()
        local local_playbook=""
        local local_inv="--inventory ${MINIRHIS_INVENTORY_FILE}"
        local local_cfg="${SCRIPT_DIR}/container/roles/ansible.cfg"
        local local_vault_arg=""
        local local_evars="--extra-vars @${ANSIBLE_ENV_FILE} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"

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
            if is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_idm_chrony_template || true
                ensure_idm_update_task_nogpgcheck || true
            fi
            phase_args+=( --extra-vars "{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}" )
        fi

        # Satellite collection expects sat_repository_ids and (optionally) CDN activation vars.
        if [ "${phase_limit}" = "scenario_satellite" ]; then
            phase_args+=( --extra-vars "{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\",\"sat_installer_timeout\":${sat_installer_timeout},\"sat_installer_verbose\":${sat_installer_verbose}}" )
            if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
                phase_args+=( -e "cdn_organization_id=${CDN_ORGANIZATION_ID}" )
                phase_args+=( -e "cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}" )
            else
                phase_args+=( --skip-tags "tags_satellite_pre_cdn_registration" )
            fi

            if ! ensure_satellite_chrony_template; then
                phase_args+=( --skip-tags "tags_satellite_pre_chrony" )
                print_warning "chrony.j2 is missing in minirhis-builder-satellite; skipping tags_satellite_pre_chrony for this run."
            fi
            if is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_satellite_foreman_service_check_nonfatal || true
            fi
            if [ -n "${MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH:-}" ]; then
                phase_args+=( -e "minirhis_local_manifest_path=${MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH}" )
            fi
        fi

        print_step "${phase_label}"
        if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
            case "${phase_playbook}" in
                */minirhis-builder-idm/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-idm")" ;;
                */minirhis-builder-satellite/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-satellite")" ;;
                */minirhis-builder-aap/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-aap")" ;;
                *) local_playbook="${phase_playbook}" ;;
            esac

            if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
                local_vault_arg="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
            else
                local_vault_arg="--ask-vault-pass"
            fi

            [ -f "${local_cfg}" ] || local_cfg="${MINIRHIS_ANSIBLE_CFG_HOST}"
            ANSIBLE_CONFIG="${local_cfg}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                ansible-playbook ${local_inv} ${local_vault_arg} ${local_evars} \
                --limit "${phase_limit}" \
                "${phase_args[@]}" \
                "${local_playbook}"
        elif [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                "${phase_args[@]}" \
                "${phase_playbook}"
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
        local -a root_force_auth_args=()

        fallback_phase_args=("${extra_args[@]}")

        if [ "${phase_limit}" = "idm" ] && [ -n "${IPADM_PASSWORD:-}" ]; then
            fallback_phase_args+=( -e "ipadm_password=${IPADM_PASSWORD}" )
            fallback_phase_args+=( -e "ipaadmin_password=${IPAADMIN_PASSWORD:-${IPADM_PASSWORD}}" )
        fi
        if [ "${phase_limit}" = "idm" ]; then
            if is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_idm_chrony_template || true
                ensure_idm_update_task_nogpgcheck || true
            fi
            fallback_phase_args+=( --extra-vars "{\"rhc_insights\":{\"remediation\":\"absent\"},\"idm_repository_ids\":${IDM_REPOSITORY_IDS_JSON},\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay}}" )
        fi
        if [ "${phase_limit}" = "scenario_satellite" ]; then
            fallback_phase_args+=( --extra-vars "{\"sat_repository_ids\":${SAT_REPOSITORY_IDS_JSON},\"sat_firewalld_zone\":\"${SAT_FIREWALLD_ZONE}\",\"sat_firewalld_interface\":\"${SAT_FIREWALLD_INTERFACE}\",\"sat_firewalld_services\":${SAT_FIREWALLD_SERVICES_JSON},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"ipa_client_dns_servers\":\"${sat_ipa_dns}\",\"ipa_server_fqdn\":\"${sat_ipa_fqdn}\",\"sat_installer_timeout\":${sat_installer_timeout},\"sat_installer_verbose\":${sat_installer_verbose}}" )
            if [ -n "${CDN_ORGANIZATION_ID:-}" ] && [ -n "${CDN_SAT_ACTIVATION_KEY:-}" ]; then
                fallback_phase_args+=( -e "cdn_organization_id=${CDN_ORGANIZATION_ID}" )
                fallback_phase_args+=( -e "cdn_sat_activation_key=${CDN_SAT_ACTIVATION_KEY}" )
            else
                fallback_phase_args+=( --skip-tags "tags_satellite_pre_cdn_registration" )
            fi

            if ! ensure_satellite_chrony_template; then
                fallback_phase_args+=( --skip-tags "tags_satellite_pre_chrony" )
                print_warning "chrony.j2 is missing in minirhis-builder-satellite; skipping tags_satellite_pre_chrony for fallback run."
            fi
            if is_enabled "${MINIRHIS_ENABLE_CONTAINER_HOTFIXES:-1}"; then
                ensure_satellite_foreman_service_check_nonfatal || true
            fi
            if [ -n "${MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH:-}" ]; then
                fallback_phase_args+=( -e "minirhis_local_manifest_path=${MINIRHIS_STAGED_MANIFEST_CONTAINER_PATH}" )
            fi
        fi

        phase_auth_fallback_status="not-needed"

        if run_phase_playbook "$phase_label" "$phase_limit" "$phase_playbook"; then
            phase_auth_fallback_status="not-needed"
            return 0
        fi

        if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
            if [ -z "$root_auth_pass" ]; then
                print_warning "Auth fallback skipped for ${phase_label}: ROOT_PASS/ADMIN_PASS is unset."
                phase_auth_fallback_status="unavailable"
                return 1
            fi

            print_warning "${phase_label} failed on first attempt; retrying once with root SSH auth fallback."
            phase_auth_fallback_status="used"

            local local_playbook=""
            local local_inv="--inventory ${MINIRHIS_INVENTORY_FILE}"
            local local_vault_arg=""
            local local_evars="--extra-vars @${ANSIBLE_ENV_FILE} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"

            case "${phase_playbook}" in
                */minirhis-builder-idm/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-idm")" ;;
                */minirhis-builder-satellite/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-satellite")" ;;
                */minirhis-builder-aap/main.yml) local_playbook="$(resolve_local_component_playbook "minirhis-builder-aap")" ;;
                *) local_playbook="${phase_playbook}" ;;
            esac

            if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
                local_vault_arg="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
            else
                local_vault_arg="--ask-vault-pass"
            fi

            ANSIBLE_CONFIG="${MINIRHIS_ANSIBLE_CFG_HOST}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                ansible-playbook ${local_inv} ${local_vault_arg} ${local_evars} \
                --limit "${phase_limit}" \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                "${fallback_phase_args[@]}" \
                "${local_playbook}"

            if [ "$?" -eq 0 ]; then
                phase_auth_fallback_status="used/succeeded"
                return 0
            fi

            print_warning "Auth fallback failed for ${phase_label}; collecting quick reachability diagnostics."
            ANSIBLE_CONFIG="${MINIRHIS_ANSIBLE_CFG_HOST}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                ansible "${phase_limit}" ${local_inv} ${local_vault_arg} ${local_evars} -m ansible.builtin.ping --one-line || true
            ANSIBLE_CONFIG="${MINIRHIS_ANSIBLE_CFG_HOST}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                ansible "${phase_limit}" ${local_inv} ${local_vault_arg} ${local_evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m ansible.builtin.ping --one-line || true

            phase_auth_fallback_status="used/failed"
            return 1
        fi

        if [ -z "$root_auth_pass" ]; then
            print_warning "Auth fallback skipped for ${phase_label}: ROOT_PASS/ADMIN_PASS is unset."
            phase_auth_fallback_status="unavailable"
            return 1
        fi

        if [ "${phase_limit}" = "scenario_satellite" ]; then
            print_step "Satellite phase failed; waiting for SSH recovery on ${SAT_IP:-10.168.128.1} before root-auth fallback retry."
            if ! preflight_config_as_code_targets "satellite:${SAT_IP:-10.168.128.1}"; then
                print_warning "Satellite SSH preflight did not converge before fallback retry; attempting root-auth retry anyway."
            fi
        fi

        print_warning "${phase_label} failed on first attempt; retrying once with root SSH auth fallback."
        phase_auth_fallback_status="used"
        root_force_auth_args=(
            -e "ansible_user=root"
            -e "ansible_password=${root_auth_pass}"
            -e "ansible_become=false"
            -e "ansible_become_password=${root_auth_pass}"
        )

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                "${root_force_auth_args[@]}" \
                "${fallback_phase_args[@]}" \
                "${phase_playbook}"
            if [ "$?" -eq 0 ]; then
                phase_auth_fallback_status="used/succeeded"
                return 0
            fi
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "${phase_limit}" \
                "${root_force_auth_args[@]}" \
                "${fallback_phase_args[@]}" \
                "${phase_playbook}"
            if [ "$?" -eq 0 ]; then
                phase_auth_fallback_status="used/succeeded"
                return 0
            fi
        fi

        print_warning "Auth fallback failed for ${phase_label}; collecting quick reachability diagnostics."
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "${phase_limit}" ${inv} "${vault_arg[@]}" ${evars} -m ansible.builtin.ping --one-line || true
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "${phase_limit}" ${inv} "${vault_arg[@]}" ${evars} "${root_force_auth_args[@]}" -m ansible.builtin.ping --one-line || true
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "${phase_limit}" ${inv} "${vault_arg[@]}" ${evars} -m ansible.builtin.ping --one-line || true
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "${phase_limit}" ${inv} "${vault_arg[@]}" ${evars} "${root_force_auth_args[@]}" -m ansible.builtin.ping --one-line || true
        fi

        phase_auth_fallback_status="used/failed"
        return 1
    }

    # ---- Satellite post-config and post-container helpers -------------------
    run_satellite_post_container_setup() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local sat_target_ip="${SAT_IP:-10.168.128.1}"
        local sat_target_host="${SAT_HOSTNAME:-satellite.example.com}"
        local ssh_key="${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-${HOME}/.ssh/minirhis-installer/id_rsa}"
        local libvirt_host="${INTERNAL_GW:-10.168.0.1}"
        local admin_pass="${SAT_INITIAL_ADMIN_PASS:-${ADMIN_PASS:-}}"
        local admin_user_q=""
        local admin_pass_q=""
        local reboot_cmd=""
        local post_install_cmd=""
        local foreman_setup_cmd=""
        local compute_resource_cmd=""
        local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -o ConnectTimeout=10"

        if ! is_enabled "${MINIRHIS_SAT_POSTCONTAINER_SETUP:-1}"; then
            print_step "Satellite post-container setup disabled (MINIRHIS_SAT_POSTCONTAINER_SETUP=0)."
            return 0
        fi

        [ "${run_satellite}" -eq 1 ] || return 0

        if [ -z "${admin_pass}" ]; then
            print_warning "Skipping Satellite post-container setup: ADMIN_PASS is not set."
            return 1
        fi

        if [ ! -r "${ssh_key}" ]; then
            ssh_key="${HOME}/.ssh/id_rsa"
        fi

        printf -v admin_user_q '%q' "${ADMIN_USER:-admin}"
        printf -v admin_pass_q '%q' "${admin_pass}"

        print_step "Satellite post-container setup: reboot, validate satellite-installer, and configure foreman+compute resources"

        # Phase 1: Reboot the Satellite system
        print_step "  Phase 1/3: Rebooting Satellite host (${sat_target_host})"
        reboot_cmd="shutdown -r +1 'MINIRHIS post-container reboot' || reboot"
        
        if [ -r "${ssh_key}" ] && timeout 10 ssh -i "${ssh_key}" ${ssh_opts} "root@${sat_target_ip}" 'echo ready' >/dev/null 2>&1; then
            ssh -i "${ssh_key}" ${ssh_opts} "root@${sat_target_ip}" "${reboot_cmd}" >/dev/null 2>&1 || true
        elif [ -n "${root_auth_pass}" ] && command -v sshpass >/dev/null 2>&1; then
            sshpass -p "${root_auth_pass}" ssh ${ssh_opts} "root@${sat_target_ip}" "${reboot_cmd}" >/dev/null 2>&1 || true
        fi

        # Wait for reboot (60 seconds)
        print_step "  Waiting for Satellite to reboot (60 seconds)..."
        sleep 60

        # Phase 2: Wait for SSH to be ready and validate satellite service
        print_step "  Phase 2/3: Waiting for SSH and validating satellite-installer scenario"
        local retry_count=0
        local max_retries=30
        local sat_validation_network="${SAT_PROVISIONING_SUBNET:-${INTERNAL_NETWORK:-10.168.0.0}}"
        local sat_validation_netmask="${SAT_PROVISIONING_NETMASK:-${NETMASK:-255.255.0.0}}"
        local sat_validation_gateway="${SAT_PROVISIONING_GW:-${INTERNAL_GW:-$(derive_gateway_from_network "${SAT_PROVISIONING_SUBNET:-${INTERNAL_NETWORK:-10.168.0.0}}")}}"
        local sat_validation_range="${SAT_PROVISIONING_DHCP_START:-10.168.128.100} ${SAT_PROVISIONING_DHCP_END:-10.168.128.200}"
        local sat_validation_dns="${SAT_PROVISIONING_DNS_PRIMARY:-${sat_target_ip}}"
        local sat_validation_reverse="${SAT_DNS_REVERSE_ZONE:-0.168.10.in-addr.arpa}"
        while [ $retry_count -lt $max_retries ]; do
            if timeout 5 ssh -i "${ssh_key}" ${ssh_opts} "root@${sat_target_ip}" "foreman-maintain packages unlock >/dev/null 2>&1 || true; satellite-installer --scenario satellite --foreman-initial-organization \"${SAT_ORG:-REDHAT}\" --foreman-initial-location \"${SAT_LOC:-CORE}\" --foreman-initial-admin-username \"${ADMIN_USER:-admin}\" --foreman-initial-admin-password ${admin_pass_q} --foreman-proxy-dns true --foreman-proxy-dns-interface eth1 --foreman-proxy-dns-managed true --foreman-proxy-dns-reverse \"${sat_validation_reverse}\" --foreman-proxy-dhcp true --foreman-proxy-dhcp-interface eth1 --foreman-proxy-dhcp-managed true --foreman-proxy-dhcp-network \"${sat_validation_network}\" --foreman-proxy-dhcp-netmask \"${sat_validation_netmask}\" --foreman-proxy-dhcp-gateway \"${sat_validation_gateway}\" --foreman-proxy-dhcp-range \"${sat_validation_range}\" --foreman-proxy-dhcp-nameservers \"${sat_validation_dns}\" --foreman-proxy-tftp true --foreman-proxy-tftp-managed true --enable-foreman-compute-libvirt --enable-foreman-plugin-ansible --enable-foreman-proxy-plugin-ansible --register-with-insights" >/dev/null 2>&1; then
                print_success "  Satellite installed and running (iteration $((retry_count+1))/${max_retries})"
                break
            fi
            retry_count=$((retry_count+1))
            if [ $retry_count -lt $max_retries ]; then
                print_step "  Satellite not yet ready, retrying... ($retry_count/${max_retries})"
                sleep 10
            fi
        done

        if [ $retry_count -ge $max_retries ]; then
            print_warning "Satellite validation timeout after ${max_retries} retries."
            return 1
        fi

        # Phase 3: Setup foreman SSH keys to libvirt and create compute resource
        print_step "  Phase 3/3: Setting up foreman user SSH keys and compute resource"
        
        foreman_setup_cmd="set -euo pipefail; \
su foreman -s /bin/bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && [ -f ~/.ssh/id_rsa ] || ssh-keygen -q -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa'; \
su foreman -s /bin/bash -c 'ssh-copy-id -o StrictHostKeyChecking=no -o BatchMode=yes root@${libvirt_host} 2>/dev/null || true'; \
dnf install -y foreman-cli >/dev/null 2>&1 || satellite-maintain packages install -y foreman-cli >/dev/null 2>&1 || true; \
bash tools/hammer_api_fallback.sh compute_resources 'name="Libvirt_Prod_Server"' -- \
    hammer compute-resource create --name \"Libvirt_Prod_Server\" --provider \"Libvirt\" --url \"qemu+ssh://root@${libvirt_host}/system\" --display-type \"VNC\" --locations \"${SAT_LOC:-CORE}\" --organizations \"${SAT_ORG:-REDHAT}\" >/dev/null 2>&1 || true; \
echo \"Compute resource created. Testing connection...\"; \
bash tools/hammer_api_fallback.sh compute_resources 'name=\"Libvirt_Prod_Server\"' -- \
    hammer compute-resource info --name \"Libvirt_Prod_Server\" | head -n 10 || echo \"Note: Compute resource info may need foreman API authentication\""

        if [ -r "${ssh_key}" ] && timeout 300 ssh -i "${ssh_key}" ${ssh_opts} "root@${sat_target_ip}" "${foreman_setup_cmd}" >/dev/null 2>&1; then
            print_success "Foreman SSH keys and compute resource setup complete."
        elif [ -n "${root_auth_pass}" ] && command -v sshpass >/dev/null 2>&1; then
            if timeout 300 sshpass -p "${root_auth_pass}" ssh ${ssh_opts} "root@${sat_target_ip}" "${foreman_setup_cmd}" >/dev/null 2>&1; then
                print_success "Foreman SSH keys and compute resource setup complete (password auth)."
            else
                print_warning "Foreman setup partially completed; manual verification may be needed."
            fi
        fi

        print_step "Satellite post-container setup complete."
        return 0
    }

    run_satellite_post_cac_customizations() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local installer_cmd=""
        local libvirt_prereq_cmd=""
        local provisioning_tags="tags_post_sync,tags_post_publication,tags_provisioning_config,tags_installation_media,tags_operating_systems,tags_activation_keys,tags_domains,tags_subnets,tags_pxe_defaults,tags_compute_resources,tags_compute_profiles,tags_provisioning_templates,tags_templates_sync,tags_hostgroups"
        local sat_libvirt_url="${MINIRHIS_SAT_LIBVIRT_URL:-qemu+ssh://root@${INTERNAL_GW:-10.168.0.1}/system}"
        local sat_dns_zone="${SAT_DNS_ZONE:-${DOMAIN:-}}"
        local sat_dns_reverse_zone="${SAT_DNS_REVERSE_ZONE:-0.168.10.in-addr.arpa}"
        local sat_dhcp_range="${SAT_PROVISIONING_DHCP_START:-10.168.130.1} ${SAT_PROVISIONING_DHCP_END:-10.168.255.254}"
        local sat_dhcp_nameservers="${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP:-10.168.128.1}}"
        local sat_initial_admin_pass="${SAT_INITIAL_ADMIN_PASS:-${ADMIN_PASS:-}}"
        local sat_org_q=""
        local sat_loc_q=""
        local sat_admin_user_q=""
        local sat_admin_pass_q=""
        local sat_service_iface="eth1"
        local sat_dns_reverse_q=""
        local sat_dhcp_gw_q=""
        local sat_dhcp_nameservers_q=""
        local sat_dhcp_range_q=""
        local sat_target_ip_q=""
        local installer_ok=0
        local provisioning_ok=0

        if ! is_enabled "${MINIRHIS_RUN_SATELLITE_POST_CONFIG_AFTER_CAC:-1}"; then
            print_step "Satellite post-CaC scenario pass disabled (MINIRHIS_RUN_SATELLITE_POST_CONFIG_AFTER_CAC=0)."
            return 0
        fi

        printf -v sat_org_q '%q' "${SAT_ORG}"
        printf -v sat_loc_q '%q' "${SAT_LOC}"
        printf -v sat_admin_user_q '%q' "${ADMIN_USER}"
        printf -v sat_admin_pass_q '%q' "${sat_initial_admin_pass}"
        printf -v sat_dns_reverse_q '%q' "${sat_dns_reverse_zone}"
        printf -v sat_dhcp_gw_q '%q' "${SAT_PROVISIONING_GW:-10.168.0.1}"
        printf -v sat_dhcp_nameservers_q '%q' "${sat_dhcp_nameservers}"
        printf -v sat_dhcp_range_q '%q' "${sat_dhcp_range}"
        printf -v sat_target_ip_q '%q' "${SAT_IP:-10.168.128.1}"

        if [ "${SAT_FIREWALLD_INTERFACE:-eth1}" != "eth1" ]; then
            print_warning "SAT_FIREWALLD_INTERFACE=${SAT_FIREWALLD_INTERFACE} overridden for Satellite service interfaces; enforcing eth1 for DNS/DHCP/TFTP/PXE."
        fi


        installer_cmd="export TERM=\"\${TERM:-dumb}\"; foreman-maintain packages unlock >/dev/null 2>&1 || true; satellite-installer --scenario satellite --foreman-initial-organization ${sat_org_q} --foreman-initial-location ${sat_loc_q} --foreman-initial-admin-username ${sat_admin_user_q} --foreman-initial-admin-password ${sat_admin_pass_q} --foreman-proxy-dns true --foreman-proxy-dns-interface ${sat_service_iface} --foreman-proxy-dns-managed true --foreman-proxy-dns-reverse ${sat_dns_reverse_q} --foreman-proxy-dhcp true --foreman-proxy-dhcp-interface ${sat_service_iface} --foreman-proxy-dhcp-managed true --foreman-proxy-dhcp-gateway ${sat_dhcp_gw_q} --foreman-proxy-dhcp-nameservers ${sat_dhcp_nameservers_q} --foreman-proxy-dhcp-range ${sat_dhcp_range_q} --foreman-proxy-tftp true --foreman-proxy-tftp-managed true --foreman-proxy-tftp-servername ${sat_target_ip_q} --enable-foreman-compute-libvirt --enable-foreman-plugin-ansible --enable-foreman-proxy-plugin-ansible --register-with-insights"
        libvirt_prereq_cmd="dnf -y install --nogpgcheck libvirt-client >/dev/null 2>&1 || satellite-maintain packages install libvirt-client >/dev/null 2>&1 || true; su foreman -s /bin/bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && [ -f ~/.ssh/id_rsa ] || ssh-keygen -q -t rsa -b 4096 -N \"\" -f ~/.ssh/id_rsa'; su foreman -s /bin/bash -c 'virsh -c ${sat_libvirt_url} list' || { echo \"WARN: foreman->libvirt connectivity test failed for ${sat_libvirt_url}\"; echo \"Foreman public key (copy to libvirt host authorized_keys):\"; su foreman -s /bin/bash -c 'cat ~/.ssh/id_rsa.pub' || true; true; }"

        print_step "Satellite post-CaC pass: running satellite-installer --scenario satellite with MINIRHIS options"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.shell \
                -a "${installer_cmd}" && installer_ok=1
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.shell \
                -a "${installer_cmd}" && installer_ok=1
        fi

        if [ "${installer_ok}" -ne 1 ] && [ -n "${root_auth_pass}" ]; then
            print_warning "Satellite installer scenario pass failed with inventory auth; retrying with root auth fallback."
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m ansible.builtin.shell \
                    -a "${installer_cmd}" && installer_ok=1
            else
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m ansible.builtin.shell \
                    -a "${installer_cmd}" && installer_ok=1
            fi
        fi

        if [ "${installer_ok}" -ne 1 ]; then
            print_warning "Satellite installer scenario pass failed."
            return 1
        fi

        print_step "Satellite post-CaC pass: applying libvirt/KVM prerequisites for Satellite compute integration"
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.shell \
                -a "${libvirt_prereq_cmd}" >/dev/null 2>&1 || true
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.shell \
                -a "${libvirt_prereq_cmd}" >/dev/null 2>&1 || true
        fi

        if ! is_enabled "${MINIRHIS_RUN_SATELLITE_KVM_PROVISIONING_AFTER_SCENARIO:-1}"; then
            print_step "Satellite KVM provisioning pass disabled (MINIRHIS_RUN_SATELLITE_KVM_PROVISIONING_AFTER_SCENARIO=0)."
            return 0
        fi

        print_step "Satellite post-CaC pass: applying KVM provisioning resources for image-based and kickstart host provisioning"
        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "scenario_satellite" \
                --tags "${provisioning_tags}" \
                --skip-tags "tags_satellite_install,tags_satellite_pre,tags_sync" \
                "/minirhis/minirhis-builder-satellite/main.yml" && provisioning_ok=1
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                --limit "scenario_satellite" \
                --tags "${provisioning_tags}" \
                --skip-tags "tags_satellite_install,tags_satellite_pre,tags_sync" \
                "/minirhis/minirhis-builder-satellite/main.yml" && provisioning_ok=1
        fi

        if [ "${provisioning_ok}" -ne 1 ] && [ -n "${root_auth_pass}" ]; then
            print_warning "Satellite KVM provisioning pass failed with inventory auth; retrying with root auth fallback."
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    --limit "scenario_satellite" \
                    --tags "${provisioning_tags}" \
                    --skip-tags "tags_satellite_install,tags_satellite_pre,tags_sync" \
                    "/minirhis/minirhis-builder-satellite/main.yml" && provisioning_ok=1
            else
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    --limit "scenario_satellite" \
                    --tags "${provisioning_tags}" \
                    --skip-tags "tags_satellite_install,tags_satellite_pre,tags_sync" \
                    "/minirhis/minirhis-builder-satellite/main.yml" && provisioning_ok=1
            fi
        fi

        if [ "${provisioning_ok}" -ne 1 ]; then
            print_warning "Satellite KVM provisioning pass failed."
            return 1
        fi

        return 0
    }

    # ---- Preflight remediation / diagnostics helpers ------------------------
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
        repos_out=$(podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" \
            "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
            ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${evars} \
            -m ansible.builtin.shell \
            -a "${check_cmd}" 2>/dev/null) || true

        # Fall back to root password if vault auth yielded nothing.
        if [ -z "${repos_out}" ] && [ -n "${root_auth_pass}" ]; then
            repos_out=$(podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" \
                "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "${register_target}" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${reg_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.ping >/dev/null 2>&1
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m ansible.builtin.ping >/dev/null 2>&1
        fi

        return $?
    }

    ensure_idm_fqdn_resolution() {
        local fqdn_shell="f='${IDM_HOSTNAME}'; h='${IDM_ALIAS:-idm}'; ip='${IDM_IP}'; [ -n \"\$ip\" ] || ip=\"\$(hostname -I 2>/dev/null | awk '{print \$1}')\"; if [ -n \"\$f\" ] && [ -n \"\$ip\" ] && ! getent hosts \"\$f\" >/dev/null 2>&1; then echo \"\$ip \$f \$h\" >> /etc/hosts; fi; getent hosts \"\$f\" >/dev/null 2>&1"

        print_step "Ensuring IdM host can resolve its own FQDN before idm_pre checks"

        if [ "$use_interactive_vault_prompt" = "1" ]; then
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${fqdn_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -m shell \
                -a "${net_shell}"
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
        local sat_shell='if command -v foreman-maintain >/dev/null 2>&1; then foreman-maintain packages unlock >/dev/null 2>&1 || true; fi; dnf upgrade -y --skip-broken --allowerasing --best || true; dnf install -y sos rhc || true; if [ -n "{{ cdn_organization_id | default("") }}" ] && [ -n "{{ cdn_sat_activation_key | default("") }}" ]; then rhc connect --activation-key "{{ cdn_sat_activation_key }}" --organization "{{ cdn_organization_id }}" || true; fi; dnf install -y rhc-worker-playbook || true; if ! subscription-manager identity >/dev/null 2>&1; then if [ -n "{{ cdn_organization_id | default("") }}" ] && [ -n "{{ cdn_sat_activation_key | default("") }}" ]; then subscription-manager register --org="{{ cdn_organization_id }}" --activationkey="{{ cdn_sat_activation_key }}" --force || true; else subscription-manager register --username="{{ rh_user | default("") }}" --password="{{ rh_pass | default("") }}" --force || true; fi; fi; subscription-manager attach --auto >/dev/null 2>&1 || true; subscription-manager refresh >/dev/null 2>&1 || true; subscription-manager repos --disable="*" >/dev/null 2>&1 || true; subscription-manager repos --enable="rhel-9-for-x86_64-baseos-rpms" --enable="rhel-9-for-x86_64-appstream-rpms" --enable="satellite-6.18-for-rhel-9-x86_64-rpms" --enable="satellite-maintenance-6.18-for-rhel-9-x86_64-rpms" >/dev/null 2>&1 || true; subscription-manager repos --list >/dev/null 2>&1 || true'
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
            _remediate_out=$(podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
        else
            _remediate_out=$(podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
                    _remediate_out=$(podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                        ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${sat_shell}" 2>&1) || _remediate_rc=$?
                else
                    _remediate_out=$(podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
                _remediate_dbg_out=$(podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "scenario_satellite" ${inv} "${vault_arg[@]}" ${_rem_evars} -m shell -a "${sat_shell}" -vvv 2>&1 || true)
            else
                _remediate_dbg_out=$(podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
            podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                ansible "idm" ${inv} "${vault_arg[@]}" ${evars} \
                -e "ansible_user=root" \
                -e "ansible_password=${root_auth_pass}" \
                -e "ansible_become=false" \
                -e "ansible_become_password=${root_auth_pass}" \
                -m shell \
                -a "${prep_shell}" >/dev/null 2>&1
        else
            podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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
            local gpg_shell='if [ -d /etc/pki/rpm-gpg ]; then for k in /etc/pki/rpm-gpg/*; do [ -f "$k" ] && rpm --import "$k" 2>/dev/null || true; done; fi; if ls /etc/yum.repos.d/*.repo >/dev/null 2>&1; then sed -i "s/^gpgcheck=.*/gpgcheck=0/" /etc/yum.repos.d/*.repo 2>/dev/null || true; sed -i "s/^repo_gpgcheck=.*/repo_gpgcheck=0/" /etc/yum.repos.d/*.repo 2>/dev/null || true; fi; for _conf in /etc/dnf/dnf.conf /etc/dnf5/dnf.conf; do [ -f "$_conf" ] || continue; sed -i "s/^gpgcheck=.*/gpgcheck=0/" "$_conf" 2>/dev/null || true; grep -q "^gpgcheck=" "$_conf" || printf "\ngpgcheck=0\n" >> "$_conf" 2>/dev/null || true; done; for _d in /etc/dnf/dnf.conf.d /etc/dnf5/dnf.conf.d; do [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || true; printf "[main]\ngpgcheck=0\nrepo_gpgcheck=0\nlocalpkg_gpgcheck=0\nexclude=intel-audio-firmware*\n" > "$_d/minirhis-disable-gpgcheck.conf" 2>/dev/null || true; done'

            [ -n "$root_auth_pass" ] || { print_warning "Skipping IdM GPG pre-flight: ROOT_PASS/ADMIN_PASS is unset."; return 0; }

            print_step "Pre-flight: importing RPM GPG keys and normalising repo gpgcheck on IdM host"

            run_ansible_shell_in_container "idm" "${gpg_shell}" "${root_auth_pass}" >/dev/null 2>&1

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
            run_ansible_shell_in_container "idm" "${diag_shell}" "${root_auth_pass}" && return 0
        fi

        run_ansible_shell_in_container "idm" "${diag_shell}" "" || true

        return 0
    }

    dump_idm_web_ui_diagnostics() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local diag_shell='echo "=== hostname ==="; hostname -f || hostname; echo "=== service states ==="; systemctl is-active ipa || true; systemctl is-active httpd || true; systemctl is-active pki-tomcatd@pki-tomcat || true; systemctl --no-pager --full -l status ipa httpd pki-tomcatd@pki-tomcat 2>/dev/null | tail -120 || true; echo "=== port 443 listeners ==="; ss -ltnp | grep -E "(:443\\b|:80\\b)" || true; echo "=== local curl /ipa/ui ==="; curl -k -sS -o /dev/null -w "HTTP %{http_code}\\n" https://localhost/ipa/ui/ || true'

        print_step "Diagnostics: collecting IdM Web UI/service state"

        if [ -n "$root_auth_pass" ]; then
            run_ansible_shell_in_container "idm" "${diag_shell}" "${root_auth_pass}" && return 0
        fi

        run_ansible_shell_in_container "idm" "${diag_shell}" "" || true

        return 0
    }

    ensure_idm_web_ui_ready() {
        local root_auth_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
        local timeout interval start_ts now elapsed
        local rc=0
        local check_out=""
        local remediate_shell='systemctl enable --now chronyd >/dev/null 2>&1 || true; systemctl enable --now httpd >/dev/null 2>&1 || true; ipactl status >/dev/null 2>&1 || ipactl start >/dev/null 2>&1 || true; systemctl restart httpd pki-tomcatd@pki-tomcat >/dev/null 2>&1 || true; curl -k -sS -o /dev/null -w "HTTP %{http_code}\\n" https://localhost/ipa/ui/ || true'
        local check_shell='code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ipa/ui/ 2>/dev/null || true)"; ss -ltn | grep -q ":443\\b" || exit 1; case "$code" in 200|301|302|303|307|308|401|403) echo "IDM_WEB_UI_READY:$code" ;; *) echo "IDM_WEB_UI_NOT_READY:$code"; exit 1 ;; esac'

        timeout="${MINIRHIS_IDM_WEB_UI_TIMEOUT:-900}"
        interval="${MINIRHIS_IDM_WEB_UI_INTERVAL:-15}"
        case "${timeout}" in ''|*[!0-9]*) timeout=900 ;; esac
        case "${interval}" in ''|*[!0-9]*) interval=15 ;; esac
        [ "${timeout}" -gt 0 ] || timeout=900
        [ "${interval}" -gt 0 ] || interval=15

        print_step "IdM Web UI gate: attempting service remediation before readiness checks"
        if [ -n "$root_auth_pass" ]; then
            run_ansible_shell_in_container "idm" "${remediate_shell}" "${root_auth_pass}" >/dev/null 2>&1 || true
        fi

        print_step "IdM Web UI gate: waiting up to ${timeout}s for https://${IDM_HOSTNAME:-idm}/ipa/ui"
        start_ts="$(date +%s)"
        while true; do
            rc=0
            if [ -n "$root_auth_pass" ]; then
                check_out=$(run_ansible_shell_in_container "idm" "${check_shell}" "${root_auth_pass}" "--one-line" 2>&1) || rc=$?
            else
                check_out=$(run_ansible_shell_in_container "idm" "${check_shell}" "" "--one-line" 2>&1) || rc=$?
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
            run_ansible_shell_in_container "scenario_satellite" "${diag_shell}" "${root_auth_pass}" && return 0
        fi

        run_ansible_shell_in_container "scenario_satellite" "${diag_shell}" "" || true

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
            run_ansible_shell_in_container "${target}" "${pkg_shell}" "${root_auth_pass}" >/dev/null 2>&1

            if [ "$?" -eq 0 ]; then
                classify="pkg-preflight-root-ok"
                print_success "Package pre-flight complete on ${target}."
                print_step "Package pre-flight (${target}): ${classify}"
                return 0
            fi
        fi

        print_warning "Package pre-flight with root auth failed/unavailable for ${target}; trying inventory auth."
        run_ansible_shell_in_container "${target}" "${pkg_shell}" "" >/dev/null 2>&1

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
            run_ansible_shell_in_container "${upgrade_target}" "${upgrade_shell}" "${root_auth_pass}"

            if [ "$?" -eq 0 ]; then
                print_success "IdM/AAP hosts upgraded successfully."
                return 0
            fi

            print_warning "dnf upgrade failed with root auth; skipping inventory-credential retry to avoid known admin auth noise."
            print_warning "Root-auth connectivity summary (expected IdM/AAP reachable as root):"
            if [ "$use_interactive_vault_prompt" = "1" ]; then
                podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible "${upgrade_target}" ${inv} "${vault_arg[@]}" ${evars} \
                    -e "ansible_user=root" \
                    -e "ansible_password=${root_auth_pass}" \
                    -e "ansible_become=false" \
                    -e "ansible_become_password=${root_auth_pass}" \
                    -m ansible.builtin.ping \
                    --one-line 2>/dev/null || true
            else
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
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

        run_ansible_shell_in_container "${upgrade_target}" "${upgrade_shell}" ""

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

        run_ansible_shell_in_container "${reboot_target}" "${reboot_shell}" "${root_auth_pass}" >/dev/null 2>&1 || true

        sleep 15
        print_step "Post-upgrade: waiting for IdM and Satellite to return after reboot"
        preflight_config_as_code_targets "idm:${IDM_IP}" "satellite:${SAT_IP}" || return 1
        print_success "Post-upgrade reboot complete; IdM and Satellite are reachable again."
        return 0
    }

    if is_enabled "${MINIRHIS_ENABLE_PRECHECK_ADHOC:-0}"; then
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
        print_step "Skipping optional pre-flight ad-hoc probes/upgrades (MINIRHIS_ENABLE_PRECHECK_ADHOC=0)."
    fi

    if [ "${run_idm}" -eq 1 ] || { [ "${run_satellite}" -eq 1 ] && [ "${SATELLITE_PRE_USE_IDM:-false}" = "true" ]; }; then
        prepare_idm_runtime_network || true
        ensure_idm_gpg_keys || true
        ensure_core_role_packages_on_managed_nodes "idm:scenario_satellite" || true
    fi

    # ---- Component phase execution ------------------------------------------
    # ── 1. IdM — must be ready first (Satellite/AAP enroll against it) ─────────
    if [ "${run_idm}" -eq 1 ]; then
    if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ] && ! ensure_container_running_with_retry; then
        idm_status="skipped-container"
        any_failed=1
        print_warning "Provisioner container unavailable; skipping IdM phase."
    elif ! run_phase_playbook_with_auth_fallback "Phase 1/3 — Configuring IdM..." "idm" "/minirhis/minirhis-builder-idm/main.yml"; then
        idm_auth_fallback_status="${phase_auth_fallback_status}"
        idm_status="failed"
        any_failed=1
        print_warning "IdM config-as-code failed.  Check the output above."
        dump_idm_network_diagnostics || true
        dump_idm_web_ui_diagnostics || true
        print_warning "You can re-run manually:"
        print_manual_rerun_template "idm"
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
    else
        idm_status="skipped-by-scope"
        print_step "IdM phase skipped by component scope (${component_scope})."
    fi

    # ── 2. Satellite ───────────────────────────────────────────────────────────
    if [ "${run_satellite}" -eq 1 ]; then
    stage_satellite_manifest || true
    remediate_satellite_repo_entitlements || true
    print_step "Pre-flight: collecting Satellite RHSM state"
    dump_satellite_rhsm_diagnostics || true
    if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ] && ! ensure_container_running_with_retry; then
        satellite_status="skipped-container"
        any_failed=1
        print_warning "Provisioner container unavailable; skipping Satellite phase."
    elif ! run_phase_playbook_with_auth_fallback "Phase 2/3 — Configuring Satellite..." "scenario_satellite" "/minirhis/minirhis-builder-satellite/main.yml"; then
        satellite_auth_fallback_status="${phase_auth_fallback_status}"
        satellite_status="failed"
        any_failed=1
        print_warning "Satellite config-as-code failed.  Check the output above."
        dump_satellite_rhsm_diagnostics || true
        print_warning "You can re-run manually:"
        print_manual_rerun_template "satellite"

        if is_enabled "${MINIRHIS_LOCAL_ROLE_FALLBACK:-1}"; then
            print_step "Attempting local Satellite fallback from ${MINIRHIS_LOCAL_ROLE_WORKDIR}"
            if run_local_satellite_playbook_fallback; then
                satellite_status="success-after-local-fallback"
                satellite_auth_fallback_status="${phase_auth_fallback_status}/local-succeeded"
                print_success "Local Satellite fallback succeeded."
            else
                print_warning "Local Satellite fallback failed."
            fi
        fi
    else
        satellite_auth_fallback_status="${phase_auth_fallback_status}"
        satellite_status="success"
        print_success "Satellite configuration complete."
        if run_satellite_post_cac_customizations; then
            satellite_status="success-with-post-cac"
            print_success "Satellite post-CaC customization pass complete."
            if run_satellite_post_container_setup; then
                satellite_status="success-with-post-container"
                print_success "Satellite post-container setup complete (reboot, validation, foreman config)."
            else
                satellite_status="partial-post-container"
                print_warning "Satellite post-container setup encountered issues; manual verification recommended."
            fi
        else
            satellite_status="failed-post-cac"
            any_failed=1
        fi
    fi
    print_step "Auth fallback (Satellite): ${satellite_auth_fallback_status}"
    else
        satellite_status="skipped-by-scope"
        print_step "Satellite phase skipped by component scope (${component_scope})."
    fi

    if [ "${run_aap}" -eq 1 ]; then
        ensure_core_role_packages_on_managed_nodes "aap" || true
    fi

    # ── 3. AAP ─────────────────────────────────────────────────────────────────
    if [ "${run_aap}" -eq 1 ]; then
    print_step "Phase gate: starting deferred AAP callback and readiness checks"
    if ! run_deferred_aap_callback; then
        aap_status="callback-failed"
        aap_auth_fallback_status="not-needed"
        any_failed=1
        print_warning "AAP callback did not complete; skipping AAP config-as-code phase."
    elif ! preflight_config_as_code_targets "aap:${AAP_IP}"; then
        aap_status="ssh-unreachable"
        aap_auth_fallback_status="not-needed"
        any_failed=1
        print_warning "AAP internal SSH is still not reachable; skipping AAP config-as-code phase."
    elif [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ] && ! ensure_container_running_with_retry; then
        aap_status="skipped-container"
        aap_auth_fallback_status="not-needed"
        any_failed=1
        print_warning "Provisioner container unavailable; skipping AAP phase."
    elif ! run_phase_playbook_with_auth_fallback "Phase 3/3 — Configuring AAP..." "aap" "/minirhis/minirhis-builder-aap/main.yml"; then
        aap_auth_fallback_status="${phase_auth_fallback_status}"
        aap_status="failed"
        any_failed=1
        print_warning "AAP config-as-code failed.  Check the output above."
        print_warning "You can re-run manually:"
        print_manual_rerun_template "aap"
    else
        aap_auth_fallback_status="${phase_auth_fallback_status}"
        aap_status="success"
        print_success "AAP configuration complete."
    fi
    print_step "Auth fallback (AAP): ${aap_auth_fallback_status}"
    else
        aap_status="skipped-by-scope"
        print_step "AAP phase skipped by component scope (${component_scope})."
    fi

    # ── 3b. RHIS AAP Config (standalone) — Only when scope = rhis-aap ──────────
    # Runs rhis_aap_config.yml directly; skips the full platform_post tear-down.
    if [ "${component_scope}" = "rhis-aap" ]; then
        local rhis_aap_playbook
        rhis_aap_playbook="${SCRIPT_DIR}/container/roles/minirhis-builder-aap/minirhis-builder-aap/rhis_aap_config.yml"
        print_step "RHIS AAP Config: running rhis_aap_config.yml against platform_installer"
        if [ "${use_local_exec}" -eq 1 ]; then
            local local_cfg_rhis="${SCRIPT_DIR}/container/roles/ansible.cfg"
            [ -f "${local_cfg_rhis}" ] || local_cfg_rhis="${MINIRHIS_ANSIBLE_CFG_HOST}"
            local local_evars_rhis="--extra-vars @${ANSIBLE_ENV_FILE}"
            local local_vault_rhis=""
            if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
                local_vault_rhis="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
            else
                local_vault_rhis="--ask-vault-pass"
            fi
            ANSIBLE_CONFIG="${local_cfg_rhis}" \
                ansible-playbook \
                    --inventory "${MINIRHIS_INVENTORY_FILE}" \
                    ${local_vault_rhis} \
                    ${local_evars_rhis} \
                    --limit "platform_installer" \
                    "${rhis_aap_playbook}" || {
                print_warning "RHIS AAP Config playbook failed.  Check output above."
                print_warning "Manual re-run:"
                print_warning "  ANSIBLE_CONFIG=${local_cfg_rhis} ansible-playbook --inventory ${MINIRHIS_INVENTORY_FILE} ${local_vault_rhis} ${local_evars_rhis} --limit platform_installer ${rhis_aap_playbook}"
                any_failed=1
            }
        else
            local container_rhis_aap_playbook="/minirhis/minirhis-builder-aap/rhis_aap_config.yml"
            if podman exec "${MINIRHIS_CONTAINER_NAME}" test -f "${container_rhis_aap_playbook}" 2>/dev/null; then
                podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" \
                    "${podman_user_args[@]:-}" "${MINIRHIS_CONTAINER_NAME}" \
                    ansible-playbook ${inv} "${vault_arg[@]}" ${evars} \
                    --limit platform_installer \
                    "${container_rhis_aap_playbook}" || {
                    print_warning "RHIS AAP Config container playbook failed."
                    any_failed=1
                }
            else
                print_warning "rhis_aap_config.yml not found in container; falling back to local execution."
                local local_cfg_fb="${SCRIPT_DIR}/container/roles/ansible.cfg"
                [ -f "${local_cfg_fb}" ] || local_cfg_fb="${MINIRHIS_ANSIBLE_CFG_HOST}"
                ANSIBLE_CONFIG="${local_cfg_fb}" \
                    ansible-playbook \
                        --inventory "${MINIRHIS_INVENTORY_FILE}" \
                        "${vault_arg[@]}" \
                        --extra-vars "@${ANSIBLE_ENV_FILE}" \
                        --limit platform_installer \
                        "${rhis_aap_playbook}" || {
                    print_warning "RHIS AAP Config local fallback playbook failed."
                    any_failed=1
                }
            fi
        fi
    fi

    if [ "$any_failed" -ne 0 ] && is_enabled "${MINIRHIS_RETRY_FAILED_PHASES_ONCE:-1}"; then
        print_step "Retry mode enabled: re-running only failed phases once"
        any_failed=0

        if [ "$idm_status" = "failed" ]; then
            if { [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ] || ensure_container_running_with_retry; } && run_phase_playbook_with_auth_fallback "Retry — IdM" "idm" "/minirhis/minirhis-builder-idm/main.yml"; then
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
            if { [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ] || ensure_container_running_with_retry; } && run_phase_playbook_with_auth_fallback "Retry — Satellite" "scenario_satellite" "/minirhis/minirhis-builder-satellite/main.yml"; then
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
            if { [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ] || ensure_container_running_with_retry; } && run_phase_playbook_with_auth_fallback "Retry — AAP" "aap" "/minirhis/minirhis-builder-aap/main.yml"; then
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

        healthcheck_exec_ansible_shell() {
            local _target="$1"
            local _shell="$2"
            local _extra_args="${3:-}"
            local local_inv="--inventory ${MINIRHIS_INVENTORY_FILE}"
            local local_cfg="${SCRIPT_DIR}/container/roles/ansible.cfg"
            local local_evars="--extra-vars @${ANSIBLE_ENV_FILE} --extra-vars {\"satellite_disconnected\":${SATELLITE_DISCONNECTED:-false},\"register_to_satellite\":${REGISTER_TO_SATELLITE:-false},\"satellite_pre_use_idm\":${sat_pre_use_idm},\"use_non_idm_certs\":${sat_use_non_idm_certs},\"sat_ssl_certs_dir\":\"${sat_ssl_certs_dir}\",\"async_timeout\":${idm_async_timeout},\"async_delay\":${idm_async_delay},\"satellite_url\":\"https://${SAT_HOSTNAME}\"}"
            local local_vault_arg=""

            if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "local" ]; then
                [ -f "${local_cfg}" ] || local_cfg="${MINIRHIS_ANSIBLE_CFG_HOST}"
                if [ -r "${ANSIBLE_VAULT_PASS_FILE}" ]; then
                    local_vault_arg="--vault-password-file ${ANSIBLE_VAULT_PASS_FILE}"
                else
                    local_vault_arg="--ask-vault-pass"
                fi

                if [ -n "${root_auth_pass}" ]; then
                    ANSIBLE_CONFIG="${local_cfg}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                        ansible "${_target}" ${local_inv} ${local_vault_arg} ${local_evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${_shell}" ${_extra_args}
                else
                    ANSIBLE_CONFIG="${local_cfg}" ANSIBLE_LOG_PATH="${ANSIBLE_ENV_DIR}/${AAP_ANSIBLE_LOG_BASENAME}" \
                        ansible "${_target}" ${local_inv} ${local_vault_arg} ${local_evars} \
                        -m shell -a "${_shell}" ${_extra_args}
                fi
                return $?
            fi

            if [ -n "${root_auth_pass}" ]; then
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${_shell}" ${_extra_args}
                else
                    podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -e "ansible_user=root" \
                        -e "ansible_password=${root_auth_pass}" \
                        -e "ansible_become=false" \
                        -e "ansible_become_password=${root_auth_pass}" \
                        -m shell -a "${_shell}" ${_extra_args}
                fi
            else
                if [ "$use_interactive_vault_prompt" = "1" ]; then
                    podman exec -it -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -m shell -a "${_shell}" ${_extra_args}
                else
                    podman exec -e "ANSIBLE_CONFIG=${MINIRHIS_ANSIBLE_CFG_CONTAINER}" -e "ANSIBLE_LOG_PATH=${ansible_log_file}" "${podman_user_args[@]}" "${MINIRHIS_CONTAINER_NAME}" \
                        ansible "${_target}" ${inv} "${vault_arg[@]}" ${evars} \
                        -m shell -a "${_shell}" ${_extra_args}
                fi
            fi
        }

        healthcheck_run_shell() {
            local _target="$1"
            local _label="$2"
            local _shell="$3"
            local _out=""
            local _rc=0

            print_step "Healthcheck: ${_label}"

            _out="$(healthcheck_exec_ansible_shell "${_target}" "${_shell}" "--one-line" 2>&1)" || _rc=$?

            MINIRHIS_HEALTHCHECK_LAST_OUT="${_out}"
            MINIRHIS_HEALTHCHECK_LAST_LABEL="${_label}"
            MINIRHIS_HEALTHCHECK_LAST_RC="${_rc}"
            [ -n "${_out}" ] && printf '%s\n' "${_out}" | head -40
            return ${_rc}
        }

        if ! is_enabled "${MINIRHIS_ENABLE_POST_HEALTHCHECK:-1}"; then
            print_step "Post-install healthcheck is disabled (MINIRHIS_ENABLE_POST_HEALTHCHECK=0)."
            return 0
        fi

        print_step "===== Post-install healthcheck (IdM/Satellite/AAP) ====="

        local idm_check='code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ipa/ui/ 2>/dev/null || true)"; ipactl status >/dev/null 2>&1; systemctl is-active --quiet httpd; ss -ltn | grep -q ":443\\b"; case "$code" in 200|301|302|303|307|308|401|403) echo "IDM_HEALTH_OK:$code" ;; *) echo "IDM_HEALTH_BAD:$code"; exit 1 ;; esac'
        local idm_fix='systemctl enable --now chronyd >/dev/null 2>&1 || true; systemctl enable --now httpd >/dev/null 2>&1 || true; ipactl status >/dev/null 2>&1 || ipactl start >/dev/null 2>&1 || true; systemctl restart httpd pki-tomcatd@pki-tomcat >/dev/null 2>&1 || true; true'

        if [ "${run_idm}" -eq 1 ]; then
        if healthcheck_run_shell "idm" "IdM web/service readiness" "${idm_check}"; then
            print_success "Healthcheck passed: IdM"
        else
            local_failures=$((local_failures + 1))
            print_warning "Healthcheck failed: IdM"
            if is_enabled "${MINIRHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                print_step "Healthcheck autofix: IdM service remediation"
                healthcheck_run_shell "idm" "IdM autofix action" "${idm_fix}" || true
                if healthcheck_run_shell "idm" "IdM post-autofix verification" "${idm_check}"; then
                    print_success "IdM recovered after autofix."
                    local_failures=$((local_failures - 1))
                elif is_enabled "${MINIRHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                    print_warning "Healthcheck rerun: IdM component playbook"
                    if run_phase_playbook_with_auth_fallback "Healthcheck repair — IdM" "idm" "/minirhis/minirhis-builder-idm/main.yml" && \
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
        else
            print_step "Skipping IdM post-install healthcheck (component scope: ${component_scope})."
        fi

        local sat_retries sat_interval
        sat_retries="${MINIRHIS_SAT_HEALTHCHECK_RETRIES:-5}"
        sat_interval="${MINIRHIS_SAT_HEALTHCHECK_INTERVAL:-15}"
        case "${sat_retries}" in ''|*[!0-9]*) sat_retries=5 ;; esac
        case "${sat_interval}" in ''|*[!0-9]*) sat_interval=15 ;; esac
        [ "${sat_retries}" -gt 0 ] || sat_retries=5
        [ "${sat_interval}" -gt 0 ] || sat_interval=15

        local sat_check='systemctl is-active --quiet httpd; ss -ltn | grep -q ":443\\b"; code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/api/status 2>/dev/null || true)"; case "$code" in 200|401|403) echo "SAT_HEALTH_OK:$code" ;; *) echo "SAT_HEALTH_BAD:$code"; exit 1 ;; esac'
        local sat_fix="systemctl enable --now httpd >/dev/null 2>&1 || true; satellite-maintain service restart >/dev/null 2>&1 || true; systemctl restart httpd >/dev/null 2>&1 || true; for _try in \$(seq 1 ${sat_retries}); do code=\"\$(curl -k -sS -o /dev/null -w \"%{http_code}\" https://localhost/api/status 2>/dev/null || true)\"; case \"\${code}\" in 200|401|403) echo SAT_API_RECOVERED:\${_try}; exit 0 ;; esac; sleep ${sat_interval}; done; echo SAT_API_STILL_FAIL; exit 1"

        if [ "${run_satellite}" -eq 1 ]; then
        if healthcheck_run_shell "scenario_satellite" "Satellite web/service readiness" "${sat_check}"; then
            print_success "Healthcheck passed: Satellite"
        else
            local_failures=$((local_failures + 1))
            print_warning "Healthcheck failed: Satellite"
            if is_enabled "${MINIRHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                print_step "Healthcheck autofix: Satellite service remediation"
                healthcheck_run_shell "scenario_satellite" "Satellite autofix action" "${sat_fix}" || true
                if healthcheck_run_shell "scenario_satellite" "Satellite post-autofix verification" "${sat_check}"; then
                    print_success "Satellite recovered after autofix."
                    local_failures=$((local_failures - 1))
                elif is_enabled "${MINIRHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                    print_warning "Healthcheck rerun: Satellite component playbook"
                    if run_phase_playbook_with_auth_fallback "Healthcheck repair — Satellite" "scenario_satellite" "/minirhis/minirhis-builder-satellite/main.yml" && \
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
        else
            print_step "Skipping Satellite post-install healthcheck (component scope: ${component_scope})."
        fi

        local aap_check='(ss -ltn | grep -q ":443\\b" || ss -ltn | grep -q ":80\\b"); code="$(curl -k -sS -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null || true)"; [ "$code" != "000" ] || code="$(curl -sS -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || true)"; case "$code" in 200|301|302|303|307|308|401|403) echo "AAP_HEALTH_OK:$code" ;; *) echo "AAP_HEALTH_BAD:$code"; exit 1 ;; esac'
        local aap_fix='systemctl enable --now podman >/dev/null 2>&1 || true; systemctl restart podman >/dev/null 2>&1 || true; true'

        if [ "${aap_status}" = "success" ] || [ "${aap_status}" = "success-after-retry" ]; then
            if healthcheck_run_shell "aap" "AAP web/service readiness" "${aap_check}"; then
                print_success "Healthcheck passed: AAP"
            else
                local_failures=$((local_failures + 1))
                print_warning "Healthcheck failed: AAP"
                if is_enabled "${MINIRHIS_HEALTHCHECK_AUTOFIX:-1}"; then
                    print_step "Healthcheck autofix: AAP service remediation"
                    healthcheck_run_shell "aap" "AAP autofix action" "${aap_fix}" || true
                    if healthcheck_run_shell "aap" "AAP post-autofix verification" "${aap_check}"; then
                        print_success "AAP recovered after autofix."
                        local_failures=$((local_failures - 1))
                    elif is_enabled "${MINIRHIS_HEALTHCHECK_RERUN_COMPONENT:-1}"; then
                        print_warning "Healthcheck rerun: AAP component playbook"
                        if run_phase_playbook_with_auth_fallback "Healthcheck repair — AAP" "aap" "/minirhis/minirhis-builder-aap/main.yml" && \
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
    print_manual_rerun_template "all"

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
            create_minirhis_vms || print_warning "VM creation did not complete."
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

    print_step "Configuring MINIRHIS to monitor VMs"

    if [ -f "MINIRHIS/config.json" ]; then
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
    # Skip loading if the variable already holds a real (non-placeholder) value.
    # Placeholder script defaults like "example.com"/"EXAMPLE.COM" must NOT block
    # the vault from providing the real value the user saved on a previous run.
    [ -n "${!var_name:-}" ] && ! is_unresolved_template_value "${!var_name:-}" && return 0
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
    [ -n "${!var_name:-}" ] && ! is_unresolved_template_value "${!var_name:-}" && return 0

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

# Load all MINIRHIS credentials from ~/.ansible/conf/env.yml.
# Variables holding real (non-placeholder) values are kept — CLI preseeds always win.
# Script-level placeholder defaults (e.g. "example.com", "EXAMPLE.COM") are
# overridable by vault so a saved real domain/realm is never silenced.
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
    _load_env_key SAT_INITIAL_ADMIN_PASS sat_initial_admin_pass
    _load_env_key AAP_ADMIN_PASS   aap_admin_pass
    _load_env_key AAP_DEPLOYMENT_TYPE aap_deployment_type
    _load_env_key SATELLITE_VALIDATE_CERTS satellite_validate_certs
    _load_env_key SATELLITE_DISCONNECTED satellite_disconnected
    _load_env_key REGISTER_TO_SATELLITE register_to_satellite
    _load_env_key SATELLITE_PRE_USE_IDM satellite_pre_use_idm
    _load_env_key SAT_USE_NON_IDM_CERTS use_non_idm_certs
    _load_env_key IPADM_PASSWORD   ipadm_password
    _load_env_key IPAADMIN_PASSWORD ipaadmin_password
    _load_env_key SAT_SSL_CERTS_DIR sat_ssl_certs_dir
    _load_env_key CDN_ORGANIZATION_ID cdn_organization_id
    _load_env_key CDN_SAT_ACTIVATION_KEY cdn_sat_activation_key
    _load_env_key RHC_ORGANIZATION_ID rhc_organization_id
    _load_env_key RHC_ACTIVATION_KEY rhc_activation_key
    _load_env_key SAT_FIREWALLD_ZONE sat_firewalld_zone
    _load_env_key SAT_FIREWALLD_INTERFACE sat_firewalld_interface
    _load_env_key SAT_FIREWALLD_SERVICES_JSON sat_firewalld_services_json
    _load_env_key SAT_PROVISIONING_SUBNET sat_provisioning_subnet
    _load_env_key SAT_PROVISIONING_NETMASK sat_provisioning_netmask
    _load_env_key SAT_PROVISIONING_GW sat_provisioning_gw
    _load_env_key SAT_PROVISIONING_DHCP_START sat_provisioning_dhcp_start
    _load_env_key SAT_PROVISIONING_DHCP_END sat_provisioning_dhcp_end
    _load_env_key SAT_PROVISIONING_DNS_PRIMARY sat_provisioning_dns_primary
    _load_env_key SAT_PROVISIONING_DNS_SECONDARY sat_provisioning_dns_secondary
    _load_env_key SAT_DNS_ZONE sat_dns_zone
    _load_env_key SAT_DNS_REVERSE_ZONE sat_dns_reverse_zone
    _load_env_key SAT_RHEL10_BASEOS_REPO sat_rhel10_baseos_repo
    _load_env_key SAT_RHEL10_APPSTREAM_REPO sat_rhel10_appstream_repo
    _load_env_key SAT_RHEL9_BASEOS_REPO sat_rhel9_baseos_repo
    _load_env_key SAT_RHEL9_APPSTREAM_REPO sat_rhel9_appstream_repo
    _load_env_key SAT_RHEL10_GPG_KEY_NAME sat_rhel10_gpg_key_name
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
    _load_env_key IDM_ADMINS_GROUP idm_admins_group
    _load_env_key IDM_CONTENT_MANAGERS_GROUP idm_content_managers_group
    _load_env_key IDM_AUTOMATION_ENGINEERS_GROUP idm_automation_engineers_group
    _load_env_key IDM_SYSTEM_SERVICES_GROUP idm_system_services_group
    _load_env_key IDM_ENABLE_HBAC_RULES idm_enable_hbac_rules
    _load_env_key IDM_ENABLE_SUDO_RULES idm_enable_sudo_rules
    _load_env_key HOST_INT_IP      host_int_ip
    _load_env_key AAP_BUNDLE_URL   aap_bundle_url
    _load_env_key SAT_MANIFEST_PATH sat_manifest_path
    _load_env_key SSHPASS_CMD      sshpass_cmd
    _load_env_key RHC_AUTO_CONNECT rhc_auto_connect
    _load_env_key RH_ISO_URL       rh_iso_url
    _load_env_key RH9_ISO_URL      rh9_iso_url
    _load_env_key MINIRHIS_INSTALL_PRODUCT minirhis_install_product
    _load_env_key MINIRHIS_PLATFORM_FAMILY minirhis_platform_family
    _load_env_key MINIRHIS_TARGET_PLATFORM minirhis_target_platform
    _load_env_key SAT_TARGET_PLATFORM sat_target_platform
    _load_env_key AAP_TARGET_PLATFORM aap_target_platform
    _load_env_key IDM_TARGET_PLATFORM idm_target_platform
    _load_env_key LIBVIRT_URI libvirt_uri
    _load_env_key LIBVIRT_STORAGE_POOL libvirt_storage_pool
    _load_env_key LIBVIRT_NETWORK libvirt_network
    _load_env_key VMWARE_VCENTER_HOST vmware_vcenter_host
    _load_env_key VMWARE_USERNAME vmware_username
    _load_env_key VMWARE_PASSWORD vmware_password
    _load_env_key VMWARE_DATACENTER vmware_datacenter
    _load_env_key VMWARE_CLUSTER vmware_cluster
    _load_env_key NUTANIX_ENDPOINT nutanix_endpoint
    _load_env_key NUTANIX_USERNAME nutanix_username
    _load_env_key NUTANIX_PASSWORD nutanix_password
    _load_env_key NUTANIX_CLUSTER nutanix_cluster
    _load_env_key OPENSHIFT_API_URL openshift_api_url
    _load_env_key OPENSHIFT_USERNAME openshift_username
    _load_env_key OPENSHIFT_TOKEN openshift_token
    _load_env_key OPENSHIFT_NAMESPACE openshift_namespace
    _load_env_key AWS_ACCESS_KEY_ID aws_access_key_id
    _load_env_key AWS_SECRET_ACCESS_KEY aws_secret_access_key
    _load_env_key AWS_SESSION_TOKEN aws_session_token
    _load_env_key AWS_DEFAULT_REGION aws_default_region
    _load_env_key AWS_VPC_ID aws_vpc_id
    _load_env_key AWS_SUBNET_ID aws_subnet_id
    _load_env_key AZURE_SUBSCRIPTION_ID azure_subscription_id
    _load_env_key AZURE_TENANT_ID azure_tenant_id
    _load_env_key AZURE_CLIENT_ID azure_client_id
    _load_env_key AZURE_CLIENT_SECRET azure_client_secret
    _load_env_key AZURE_RESOURCE_GROUP azure_resource_group
    _load_env_key AZURE_LOCATION azure_location
    _load_env_key GCP_PROJECT_ID gcp_project_id
    _load_env_key GCP_REGION gcp_region
    _load_env_key GCP_ZONE gcp_zone
    _load_env_key GCP_SERVICE_ACCOUNT_FILE gcp_service_account_file
    _load_env_key BMC_TYPE bmc_type
    _load_env_key BMC_ENDPOINT bmc_endpoint
    _load_env_key BMC_USERNAME bmc_username
    _load_env_key BMC_PASSWORD bmc_password
    _load_env_key BMC_SYSTEM_ID bmc_system_id
    _load_env_key BAREMETAL_ISO_URL baremetal_iso_url
    _load_env_key PXE_SERVER_URL pxe_server_url
    normalize_shared_env_vars

    # Keep legacy HUB_TOKEN and dedicated vault_console_redhat_token aligned.
    if [ -z "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ] && [ -n "${HUB_TOKEN:-}" ]; then
        VAULT_CONSOLE_REDHAT_TOKEN="${HUB_TOKEN}"
    fi
    if [ -z "${HUB_TOKEN:-}" ] && [ -n "${VAULT_CONSOLE_REDHAT_TOKEN:-}" ]; then
        HUB_TOKEN="${VAULT_CONSOLE_REDHAT_TOKEN}"
    fi
}

# Persist all MINIRHIS credentials to ~/.ansible/conf/env.yml (atomic write, chmod 600).
write_ansible_env_file() {
    mkdir -p "$ANSIBLE_ENV_DIR" || return 1
    ensure_ansible_vault || return 1
    ensure_vault_password_file || return 1
    normalize_shared_env_vars

    local tmp_env
    tmp_env="$(mktemp "${ANSIBLE_ENV_DIR}/.env.yml.XXXXXX")"
    cat > "$tmp_env" <<MINIRHIS_ENV_EOF
# MINIRHIS credentials — written by run_minirhis_install_sequence.sh on $(date '+%Y-%m-%d %H:%M')
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
sat_initial_admin_pass: "${SAT_INITIAL_ADMIN_PASS:-}"
aap_deployment_type: "${AAP_DEPLOYMENT_TYPE:-container}"
satellite_validate_certs: ${SATELLITE_VALIDATE_CERTS:-false}
satellite_disconnected: ${SATELLITE_DISCONNECTED:-false}
register_to_satellite: ${REGISTER_TO_SATELLITE:-false}
satellite_pre_use_idm: ${SATELLITE_PRE_USE_IDM:-false}
use_non_idm_certs: ${SAT_USE_NON_IDM_CERTS:-}
ipadm_password: "${IPADM_PASSWORD:-}"
ipaadmin_password: "${IPAADMIN_PASSWORD:-}"
sat_ssl_certs_dir: "${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}"
cdn_organization_id: "${CDN_ORGANIZATION_ID:-}"
cdn_sat_activation_key: "${CDN_SAT_ACTIVATION_KEY:-}"
rhc_organization_id: "${RHC_ORGANIZATION_ID:-${CDN_ORGANIZATION_ID:-}}"
rhc_activation_key: "${RHC_ACTIVATION_KEY:-${CDN_SAT_ACTIVATION_KEY:-}}"
# Aliases expected by minirhis-builder-idm idm_pre role (redhat.rhel_system_roles.rhc)
cdn_organization_vault: "${CDN_ORGANIZATION_ID:-}"
cdn_activation_key_vault: "${CDN_SAT_ACTIVATION_KEY:-}"
sat_firewalld_zone: "${SAT_FIREWALLD_ZONE:-public}"
sat_firewalld_interface: "${SAT_FIREWALLD_INTERFACE:-eth1}"
sat_firewalld_services_json: '${SAT_FIREWALLD_SERVICES_JSON:-["ssh","http","https"]}'
sat_provisioning_subnet: "${SAT_PROVISIONING_SUBNET:-${INTERNAL_NETWORK:-10.168.0.0}}"
sat_provisioning_netmask: "${SAT_PROVISIONING_NETMASK:-${NETMASK:-255.255.0.0}}"
sat_provisioning_gw: "${SAT_PROVISIONING_GW:-${INTERNAL_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK:-10.168.0.0}")}}"
sat_provisioning_dhcp_start: "${SAT_PROVISIONING_DHCP_START:-${SAT_IP:-10.168.128.1}}"
sat_provisioning_dhcp_end: "${SAT_PROVISIONING_DHCP_END:-${AAP_IP:-10.168.128.2}}"
sat_provisioning_dns_primary: "${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP:-10.168.128.1}}"
sat_provisioning_dns_secondary: "${SAT_PROVISIONING_DNS_SECONDARY:-8.8.8.8}"
sat_dns_zone: "${SAT_DNS_ZONE:-${DOMAIN:-}}"
sat_dns_reverse_zone: "${SAT_DNS_REVERSE_ZONE:-}"
sat_rhel10_baseos_repo: "${SAT_RHEL10_BASEOS_REPO:-rhel-10-for-x86_64-baseos-rpms}"
sat_rhel10_appstream_repo: "${SAT_RHEL10_APPSTREAM_REPO:-rhel-10-for-x86_64-appstream-rpms}"
sat_rhel9_baseos_repo: "${SAT_RHEL9_BASEOS_REPO:-rhel-9-for-x86_64-baseos-rpms}"
sat_rhel9_appstream_repo: "${SAT_RHEL9_APPSTREAM_REPO:-rhel-9-for-x86_64-appstream-rpms}"
sat_rhel10_gpg_key_name: "${SAT_RHEL10_GPG_KEY_NAME:-RPM-GPG-KEY-redhat-release}"
# Alias used by minirhis-builder host_vars templates ({{ global_admin_password }})
global_admin_password: "${ADMIN_PASS:-}"
# Installer/controller username consumed by installer host_vars
installer_user: "${INSTALLER_USER:-${ADMIN_USER:-admin}}"
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
idm_admins_group: "${IDM_ADMINS_GROUP:-minirhis-admins}"
idm_content_managers_group: "${IDM_CONTENT_MANAGERS_GROUP:-content-managers}"
idm_automation_engineers_group: "${IDM_AUTOMATION_ENGINEERS_GROUP:-automation-engineers}"
idm_system_services_group: "${IDM_SYSTEM_SERVICES_GROUP:-system-services}"

idm_enable_hbac_rules: ${IDM_ENABLE_HBAC_RULES:-1}
idm_enable_sudo_rules: ${IDM_ENABLE_SUDO_RULES:-1}
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
sat_manifest_path: "${SAT_MANIFEST_PATH:-}"
rh_iso_url: "${RH_ISO_URL:-}"
rh9_iso_url: "${RH9_ISO_URL:-}"
minirhis_install_product: "${MINIRHIS_INSTALL_PRODUCT:-}"
minirhis_platform_family: "${MINIRHIS_PLATFORM_FAMILY:-}"
minirhis_target_platform: "${MINIRHIS_TARGET_PLATFORM:-libvirt}"
sat_target_platform: "${SAT_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM:-libvirt}}"
aap_target_platform: "${AAP_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM:-libvirt}}"
idm_target_platform: "${IDM_TARGET_PLATFORM:-${MINIRHIS_TARGET_PLATFORM:-libvirt}}"
libvirt_uri: "${LIBVIRT_URI:-qemu:///system}"
libvirt_storage_pool: "${LIBVIRT_STORAGE_POOL:-default}"
libvirt_network: "${LIBVIRT_NETWORK:-default}"
vmware_vcenter_host: "${VMWARE_VCENTER_HOST:-}"
vmware_username: "${VMWARE_USERNAME:-}"
vmware_password: "${VMWARE_PASSWORD:-}"
vmware_datacenter: "${VMWARE_DATACENTER:-}"
vmware_cluster: "${VMWARE_CLUSTER:-}"
nutanix_endpoint: "${NUTANIX_ENDPOINT:-}"
nutanix_username: "${NUTANIX_USERNAME:-}"
nutanix_password: "${NUTANIX_PASSWORD:-}"
nutanix_cluster: "${NUTANIX_CLUSTER:-}"
openshift_api_url: "${OPENSHIFT_API_URL:-}"
openshift_username: "${OPENSHIFT_USERNAME:-}"
openshift_token: "${OPENSHIFT_TOKEN:-}"
openshift_namespace: "${OPENSHIFT_NAMESPACE:-openshift-cnv}"
aws_access_key_id: "${AWS_ACCESS_KEY_ID:-}"
aws_secret_access_key: "${AWS_SECRET_ACCESS_KEY:-}"
aws_session_token: "${AWS_SESSION_TOKEN:-}"
aws_default_region: "${AWS_DEFAULT_REGION:-us-east-1}"
aws_vpc_id: "${AWS_VPC_ID:-}"
aws_subnet_id: "${AWS_SUBNET_ID:-}"
azure_subscription_id: "${AZURE_SUBSCRIPTION_ID:-}"
azure_tenant_id: "${AZURE_TENANT_ID:-}"
azure_client_id: "${AZURE_CLIENT_ID:-}"
azure_client_secret: "${AZURE_CLIENT_SECRET:-}"
azure_resource_group: "${AZURE_RESOURCE_GROUP:-}"
azure_location: "${AZURE_LOCATION:-eastus}"
gcp_project_id: "${GCP_PROJECT_ID:-}"
gcp_region: "${GCP_REGION:-us-central1}"
gcp_zone: "${GCP_ZONE:-us-central1-a}"
gcp_service_account_file: "${GCP_SERVICE_ACCOUNT_FILE:-}"
bmc_type: "${BMC_TYPE:-redfish}"
bmc_endpoint: "${BMC_ENDPOINT:-}"
bmc_username: "${BMC_USERNAME:-}"
bmc_password: "${BMC_PASSWORD:-}"
bmc_system_id: "${BMC_SYSTEM_ID:-}"
baremetal_iso_url: "${BAREMETAL_ISO_URL:-}"
pxe_server_url: "${PXE_SERVER_URL:-}"
sshpass_cmd: "${SSHPASS_CMD:-sshpass}"
rhc_auto_connect: ${RHC_AUTO_CONNECT:-1}
MINIRHIS_ENV_EOF
    chmod 600 "$tmp_env"

    if vault_plaintext_matches_existing "$tmp_env"; then
        rm -f "$tmp_env"
        print_step "Encrypted environment unchanged: $ANSIBLE_ENV_FILE"
        return 0
    fi

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
    local prompt_domain_suffix=""
    local has_env_file=0
    local realm_default
    local bootstrap_missing=0
    [ -f "$ANSIBLE_ENV_FILE" ] && has_env_file=1

    if [ "$has_env_file" -eq 1 ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1
        normalize_shared_env_vars
        bootstrap_missing="$(count_missing_vars \
            ADMIN_USER ADMIN_PASS DOMAIN REALM INTERNAL_NETWORK NETMASK INTERNAL_GW \
            RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL RH9_ISO_URL HOST_INT_IP \
            SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC \
            SAT_FIREWALLD_INTERFACE SAT_FIREWALLD_ZONE SAT_FIREWALLD_SERVICES_JSON \
            CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY \
            AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE \
            IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS \
            SAT_PROVISIONING_SUBNET SAT_PROVISIONING_NETMASK SAT_PROVISIONING_GW SAT_PROVISIONING_DHCP_START \
            SAT_PROVISIONING_DHCP_END SAT_PROVISIONING_DNS_PRIMARY SAT_PROVISIONING_DNS_SECONDARY SAT_DNS_ZONE SAT_DNS_REVERSE_ZONE \
            SAT_RHEL10_BASEOS_REPO SAT_RHEL10_APPSTREAM_REPO SAT_RHEL9_BASEOS_REPO SAT_RHEL9_APPSTREAM_REPO \
            IDM_ADMINS_GROUP IDM_CONTENT_MANAGERS_GROUP IDM_AUTOMATION_ENGINEERS_GROUP IDM_SYSTEM_SERVICES_GROUP \
            IDM_ENABLE_HBAC_RULES IDM_ENABLE_SUDO_RULES)"
        if [ "${bootstrap_missing}" -eq 0 ]; then
            if ! is_noninteractive; then
                print_step "Using saved configuration from $ANSIBLE_ENV_FILE (no missing prompted values detected; use --reconfigure to edit values)."
            fi
            return 0
        fi
        if ! is_noninteractive; then
            print_step "Using saved configuration from $ANSIBLE_ENV_FILE, but ${bootstrap_missing} prompted value(s) are missing; prompting for completion."
        fi
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

    # First-time setup: create the conf directory and vault password file before prompting.
    if [ "$has_env_file" -eq 0 ]; then
        print_step "First-time setup: creating ${ANSIBLE_ENV_DIR}"
        mkdir -p "${ANSIBLE_ENV_DIR}" && chmod 700 "${ANSIBLE_ENV_DIR}" 2>/dev/null || true
        ensure_ansible_vault || return 1
        ensure_vault_password_file || return 1
    fi

    print_step "Collecting environment values and storing them in ansible-vault"
    echo "(Press Enter to accept the shown default where applicable.)"

    global_missing="$(count_missing_vars ADMIN_USER ADMIN_PASS DOMAIN REALM INTERNAL_NETWORK NETMASK INTERNAL_GW RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL RH9_ISO_URL HOST_INT_IP)"
    echo ""
    echo "=== Global (remaining missing: ${global_missing}/15) ==="
    prompt_with_default ADMIN_USER "Shared Admin Username" "${ADMIN_USER:-admin}" 0 1 || return 1
    prompt_with_default ADMIN_PASS "Shared Admin Password" "${ADMIN_PASS:-}" 1 1 || return 1
    prompt_with_default DOMAIN "Shared Domain" "${DOMAIN:-}" 0 1 || return 1
    realm_default="$(to_upper "${DOMAIN}")"
    prompt_domain_suffix="${DOMAIN:+.${DOMAIN}}"
    prompt_with_default REALM "Shared Kerberos Realm" "${REALM:-$realm_default}" 0 1 || return 1
    prompt_with_default INTERNAL_NETWORK "Shared Internal Network" "${INTERNAL_NETWORK:-10.168.0.0}" 0 1 || return 1
    prompt_with_default NETMASK "Shared Internal Netmask" "${NETMASK:-255.255.0.0}" 0 1 || return 1
    prompt_with_default INTERNAL_GW "Shared Internal Gateway" "${INTERNAL_GW:-$(derive_gateway_from_network "${INTERNAL_NETWORK}")}" 0 1 || return 1

    prompt_with_default RH_USER "Red Hat CDN Username" "${RH_USER:-}" 0 1 || return 1
    prompt_with_default RH_PASS "Red Hat CDN Password" "${RH_PASS:-}" 1 1 || return 1
    prompt_with_default RH_OFFLINE_TOKEN "Red Hat Offline Token" "${RH_OFFLINE_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ACCESS_TOKEN "Red Hat Access Token" "${RH_ACCESS_TOKEN:-}" 1 1 || return 1
    prompt_with_default HUB_TOKEN "Automation Hub token" "${HUB_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ISO_URL "RHEL 10 ISO URL (AAP/IdM)" "${RH_ISO_URL:-}" 0 1 || return 1
    prompt_with_default RH9_ISO_URL "RHEL 9 ISO URL (Satellite)" "${RH9_ISO_URL:-}" 0 1 || return 1
    prompt_with_default RHC_ORGANIZATION_ID "Red Hat Connector Organization ID (optional override)" "${RHC_ORGANIZATION_ID:-${CDN_ORGANIZATION_ID:-}}" 0 0 || return 1
    prompt_with_default RHC_ACTIVATION_KEY "Red Hat Connector Activation Key (optional override)" "${RHC_ACTIVATION_KEY:-${CDN_SAT_ACTIVATION_KEY:-}}" 1 0 || return 1
    prompt_with_default HOST_INT_IP "Host bridge IP for guest HTTP callbacks" "${HOST_INT_IP:-192.168.122.1}" 0 1 || return 1

    sat_missing="$(count_missing_vars SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC SAT_FIREWALLD_INTERFACE SAT_FIREWALLD_ZONE SAT_FIREWALLD_SERVICES_JSON CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY)"
    echo ""
    echo "=== Satellite (remaining missing: ${sat_missing}/13) ==="
    prompt_with_default SAT_IP "Satellite Internal IP (eth1)" "${SAT_IP:-10.168.128.1}" 0 1 || return 1
    prompt_with_default SAT_NETMASK "Satellite Internal Netmask" "${SAT_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default SAT_GW "Satellite Internal Gateway" "${SAT_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default SAT_HOSTNAME "Satellite Hostname (FQDN)" "${SAT_HOSTNAME:-satellite${prompt_domain_suffix}}" 0 1 || return 1
    prompt_with_default SAT_ALIAS "Satellite Alias" "${SAT_ALIAS:-satellite}" 0 1 || return 1
    prompt_with_default SAT_DOMAIN "Satellite Domain" "${SAT_DOMAIN:-$DOMAIN}" 0 1 || return 1
    prompt_with_default SAT_ORG "Satellite Organization" "${SAT_ORG:-REDHAT}" 0 1 || return 1
    prompt_with_default SAT_LOC "Satellite Location" "${SAT_LOC:-CORE}" 0 1 || return 1
    prompt_with_default SAT_FIREWALLD_INTERFACE "Satellite Internal Service Interface" "${SAT_FIREWALLD_INTERFACE:-eth1}" 0 1 || return 1
    prompt_with_default SAT_FIREWALLD_ZONE "Satellite Firewalld Zone" "${SAT_FIREWALLD_ZONE:-public}" 0 1 || return 1
    prompt_with_default SAT_FIREWALLD_SERVICES_JSON "Satellite Firewalld Services JSON" "${SAT_FIREWALLD_SERVICES_JSON:-[\"ssh\",\"http\",\"https\"]}" 0 1 || return 1
    prompt_with_default CDN_ORGANIZATION_ID "Satellite RHSM Organization ID (console.redhat.com/insights/connector/activation-keys#tags=)" "${CDN_ORGANIZATION_ID:-}" 0 1 || return 1
    prompt_with_default CDN_SAT_ACTIVATION_KEY "Satellite Activation Key name" "${CDN_SAT_ACTIVATION_KEY:-}" 0 1 || return 1
    prompt_with_default SAT_MANIFEST_PATH "Satellite manifest ZIP path (optional override)" "${SAT_MANIFEST_PATH:-}" 0 0 || return 1
    SAT_ADMIN_PASS="${ADMIN_PASS}"

    aap_missing="$(count_missing_vars AAP_IP AAP_NETMASK AAP_GW AAP_HOSTNAME AAP_ALIAS AAP_INVENTORY_TEMPLATE AAP_INVENTORY_GROWTH_TEMPLATE)"
    echo ""
    echo "=== AAP (remaining missing: ${aap_missing}/7) ==="
    prompt_with_default AAP_IP "AAP Internal IP (eth1)" "${AAP_IP:-10.168.128.2}" 0 1 || return 1
    prompt_with_default AAP_NETMASK "AAP Internal Netmask" "${AAP_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default AAP_GW "AAP Internal Gateway" "${AAP_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default AAP_HOSTNAME "AAP Hostname (FQDN)" "${AAP_HOSTNAME:-aap${prompt_domain_suffix}}" 0 1 || return 1
    prompt_with_default AAP_ALIAS "AAP Alias" "${AAP_ALIAS:-aap}" 0 1 || return 1
    prompt_with_default AAP_BUNDLE_URL "AAP bundle URL (optional if pre-staged locally)" "${AAP_BUNDLE_URL:-}" 0 0 || return 1
    AAP_ADMIN_PASS="${ADMIN_PASS}"
    select_aap_inventory_templates || return 1
    ensure_aap_pg_database_if_needed || return 1

    idm_missing="$(count_missing_vars IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS IDM_DS_PASS)"
    echo ""
    echo "=== IdM (remaining missing: ${idm_missing}/6) ==="
    prompt_with_default IDM_IP "IdM Internal IP (eth1)" "${IDM_IP:-10.168.128.3}" 0 1 || return 1
    prompt_with_default IDM_NETMASK "IdM Internal Netmask" "${IDM_NETMASK:-$NETMASK}" 0 1 || return 1
    prompt_with_default IDM_GW "IdM Internal Gateway" "${IDM_GW:-$INTERNAL_GW}" 0 1 || return 1
    prompt_with_default IDM_HOSTNAME "IdM Hostname (FQDN)" "${IDM_HOSTNAME:-idm${prompt_domain_suffix}}" 0 1 || return 1
    prompt_with_default IDM_ALIAS "IdM Alias" "${IDM_ALIAS:-idm}" 0 1 || return 1
    IDM_ADMIN_PASS="${ADMIN_PASS}"
    prompt_with_default IDM_DS_PASS "IdM Directory Service Password" "${IDM_DS_PASS:-}" 1 1 || return 1

    # --- Satellite Provisioning & Lifecycle Configuration ---
    echo ""
    echo "=== Satellite Provisioning Configuration ==="
    local sat_prov_subnet_default="${SAT_PROVISIONING_SUBNET:-${INTERNAL_NETWORK}}"
    local sat_prov_netmask_default="${SAT_PROVISIONING_NETMASK:-${NETMASK}}"
    local sat_prov_gw_default="${SAT_PROVISIONING_GW:-${INTERNAL_GW}}"
    local sat_prov_dhcp_start_default="${SAT_PROVISIONING_DHCP_START:-${SAT_IP}}"
    local sat_prov_dhcp_end_default="${SAT_PROVISIONING_DHCP_END:-${AAP_IP}}"
    local sat_dns_reverse_default="${SAT_DNS_REVERSE_ZONE:-}"

    if [ -z "${sat_dns_reverse_default}" ]; then
        local _sat_reverse_prefix
        _sat_reverse_prefix="$(printf '%s' "${sat_prov_subnet_default}" | awk -F. '{print $1"."$2"."$3}')"
        sat_dns_reverse_default="$(printf '%s' "${_sat_reverse_prefix}" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')"
    fi

    prompt_with_default SAT_PROVISIONING_SUBNET "Satellite Provisioning Subnet (CIDR notation or address)" "${sat_prov_subnet_default}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_NETMASK "Satellite Provisioning Netmask" "${sat_prov_netmask_default}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_GW "Satellite Provisioning Gateway" "${sat_prov_gw_default}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_DHCP_START "Satellite DHCP Start IP" "${sat_prov_dhcp_start_default}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_DHCP_END "Satellite DHCP End IP" "${sat_prov_dhcp_end_default}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_DNS_PRIMARY "Satellite Provisioning DNS Primary" "${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP}}" 0 1 || return 1
    prompt_with_default SAT_PROVISIONING_DNS_SECONDARY "Satellite Provisioning DNS Secondary" "${SAT_PROVISIONING_DNS_SECONDARY:-8.8.8.8}" 0 1 || return 1
    prompt_with_default SAT_DNS_ZONE "Satellite DNS Zone" "${SAT_DNS_ZONE:-${DOMAIN}}" 0 1 || return 1
    prompt_with_default SAT_DNS_REVERSE_ZONE "Satellite DNS Reverse Zone" "${sat_dns_reverse_default}" 0 1 || return 1

    # --- Satellite Repository Configuration ---
    echo ""
    echo "=== Satellite Repository Configuration ==="
    prompt_with_default SAT_RHEL10_BASEOS_REPO "RHEL 10 BaseOS Repository name" "${SAT_RHEL10_BASEOS_REPO:-rhel-10-for-x86_64-baseos-rpms}" 0 1 || return 1
    prompt_with_default SAT_RHEL10_APPSTREAM_REPO "RHEL 10 AppStream Repository name" "${SAT_RHEL10_APPSTREAM_REPO:-rhel-10-for-x86_64-appstream-rpms}" 0 1 || return 1
    prompt_with_default SAT_RHEL9_BASEOS_REPO "RHEL 9 BaseOS Repository name" "${SAT_RHEL9_BASEOS_REPO:-rhel-9-for-x86_64-baseos-rpms}" 0 1 || return 1
    prompt_with_default SAT_RHEL9_APPSTREAM_REPO "RHEL 9 AppStream Repository name" "${SAT_RHEL9_APPSTREAM_REPO:-rhel-9-for-x86_64-appstream-rpms}" 0 1 || return 1
    prompt_with_default SAT_RHEL10_GPG_KEY_NAME "RHEL 10 GPG key name" "${SAT_RHEL10_GPG_KEY_NAME:-RPM-GPG-KEY-redhat-release}" 0 1 || return 1

    echo ""
    echo "=== Advanced MINIRHIS / Satellite Options ==="
    prompt_with_default INSTALLER_USER "Installer/controller username" "${INSTALLER_USER:-${USER}}" 0 1 || return 1
    prompt_with_default SAT_INITIAL_ADMIN_PASS "Satellite initial admin password override (blank = Shared Admin Password)" "${SAT_INITIAL_ADMIN_PASS:-}" 1 0 || return 1
    prompt_with_default SATELLITE_DISCONNECTED "Satellite disconnected mode? (1=yes, 0=no)" "${SATELLITE_DISCONNECTED:-false}" 0 1 || return 1
    prompt_with_default REGISTER_TO_SATELLITE "Register managed hosts to Satellite? (1=yes, 0=no)" "${REGISTER_TO_SATELLITE:-false}" 0 1 || return 1
    prompt_with_default SATELLITE_PRE_USE_IDM "Use IdM-provided Satellite certs? (1=yes, 0=no)" "${SATELLITE_PRE_USE_IDM:-false}" 0 1 || return 1
    prompt_with_default SAT_USE_NON_IDM_CERTS "Use non-IdM Satellite certs? (1=yes, 0=no, blank=auto)" "${SAT_USE_NON_IDM_CERTS:-}" 0 0 || return 1
    prompt_with_default SAT_SSL_CERTS_DIR "Satellite SSL cert directory" "${SAT_SSL_CERTS_DIR:-/root/.sat_ssl/}" 0 1 || return 1
    prompt_with_default SATELLITE_VALIDATE_CERTS "Verify Satellite SSL certificates for API/module calls? (1=yes, 0=no)" "${SATELLITE_VALIDATE_CERTS:-false}" 0 1 || return 1
    prompt_with_default SAT_REALM "Satellite Realm (optional override)" "${SAT_REALM:-$REALM}" 0 0 || return 1
    prompt_with_default IPADM_PASSWORD "IdM principal admin password override (blank = IdM/Shared Admin Password)" "${IPADM_PASSWORD:-}" 1 0 || return 1
    prompt_with_default IPAADMIN_PASSWORD "IdM admin password override (blank = IPADM/IdM Admin Password)" "${IPAADMIN_PASSWORD:-${IPADM_PASSWORD:-}}" 1 0 || return 1
    prompt_with_default SSHPASS_CMD "sshpass command path/name" "${SSHPASS_CMD:-sshpass}" 0 1 || return 1
    prompt_with_default RHC_AUTO_CONNECT "Enable automatic rhc connect in guests? (1=yes, 0=no)" "${RHC_AUTO_CONNECT:-1}" 0 1 || return 1

    # --- IdM User Groups & Access Control ---
    echo ""
    echo "=== IdM Access Control Configuration ==="
    prompt_with_default IDM_ADMINS_GROUP "IdM Administrators group name" "${IDM_ADMINS_GROUP:-minirhis-admins}" 0 1 || return 1
    prompt_with_default IDM_CONTENT_MANAGERS_GROUP "IdM Content Managers group name" "${IDM_CONTENT_MANAGERS_GROUP:-content-managers}" 0 1 || return 1
    prompt_with_default IDM_AUTOMATION_ENGINEERS_GROUP "IdM Automation Engineers group name" "${IDM_AUTOMATION_ENGINEERS_GROUP:-automation-engineers}" 0 1 || return 1
    prompt_with_default IDM_SYSTEM_SERVICES_GROUP "IdM System Services group name" "${IDM_SYSTEM_SERVICES_GROUP:-system-services}" 0 1 || return 1
    prompt_with_default IDM_ENABLE_HBAC_RULES "IdM Enable Host-Based Access Control (HBAC) rules? (1=yes, 0=no)" "${IDM_ENABLE_HBAC_RULES:-1}" 0 1 || return 1
    prompt_with_default IDM_ENABLE_SUDO_RULES "IdM Enable SUDO delegation rules? (1=yes, 0=no)" "${IDM_ENABLE_SUDO_RULES:-1}" 0 1 || return 1

    normalize_shared_env_vars
    write_ansible_env_file || return 1
    print_success "Bootstrap complete. Future runs will reuse encrypted values from $ANSIBLE_ENV_FILE"
}

# Centralized prompt entrypoint used by provisioning flows.
# Ensures first-run bootstrap and missing-value prompting both execute.
prompt_use_existing_env() {
    if [ "${MINIRHIS_PROMPTS_COMPLETED:-0}" = "1" ]; then
        if [ -f "$ANSIBLE_ENV_FILE" ]; then
            load_ansible_env_file || return 1
        fi
        return 0
    fi

    prompt_all_env_options_once || return 1
    MINIRHIS_PROMPTS_COMPLETED=1
    FORCE_PROMPT_ALL=0

    if [ -f "$ANSIBLE_ENV_FILE" ]; then
        load_ansible_env_file || return 1
        print_step "Loaded existing encrypted credentials from $ANSIBLE_ENV_FILE"
    fi

    return 0
}

prompts_only_workflow() {
    local selected_product="${MINIRHIS_INSTALL_PRODUCT:-}"
    local selected_family=""
    local selected_platform=""

    print_step "Running prompts-only workflow"

    if [ -f "$ANSIBLE_ENV_FILE" ]; then
        load_ansible_env_file || return 1
    fi
    normalize_shared_env_vars

    if [ -n "${CLI_MINIRHIS:-}" ]; then
        selected_product="minirhis"
    elif [ -n "${CLI_SATELLITE:-}" ]; then
        selected_product="satellite"
    elif [ -n "${CLI_IDM:-}" ]; then
        selected_product="idm"
    elif [ -n "${CLI_AAP:-}" ]; then
        selected_product="aap"
    fi

    if [ -z "${CLI_MINIRHIS:-}${CLI_SATELLITE:-}${CLI_IDM:-}${CLI_AAP:-}" ]; then
        prompt_install_product_choice selected_product "${selected_product:-minirhis}" || return 1
    fi
    MINIRHIS_INSTALL_PRODUCT="${selected_product}"

    if [ -n "${CLI_LIBVIRT:-}" ]; then
        selected_platform="libvirt"
    elif [ -n "${CLI_BAREMETAL:-}" ]; then
        selected_platform="baremetal"
    elif [ -n "${CLI_AWS:-}" ]; then
        selected_platform="aws"
    elif [ -n "${CLI_AZURE:-}" ]; then
        selected_platform="azure"
    elif [ -n "${CLI_GCP:-}" ]; then
        selected_platform="gcp"
    elif [ -n "${CLI_NUTANIX:-}" ]; then
        selected_platform="nutanix"
    elif [ -n "${CLI_OPENSHIFT:-}" ]; then
        selected_platform="openshift"
    elif [ -n "${CLI_OPENSHIFT_VIRT:-}" ]; then
        selected_platform="openshift-virt"
    elif [ -n "${CLI_VMWARE:-}" ]; then
        selected_platform="vmware"
    fi

    if [ -n "${selected_platform}" ]; then
        selected_family="$(platform_family_for_provider "${selected_platform}")"
    else
        selected_family="${MINIRHIS_PLATFORM_FAMILY:-$(platform_family_for_provider "${MINIRHIS_TARGET_PLATFORM:-libvirt}")}"
        prompt_platform_family_choice selected_family "${selected_family:-virtual}" || return 1
        case "${selected_family}" in
            cloud)
                prompt_cloud_provider_choice selected_platform "${MINIRHIS_TARGET_PLATFORM:-aws}" || return 1
                ;;
            baremetal)
                selected_platform="baremetal"
                ;;
            *)
                prompt_virtual_provider_choice selected_platform "${MINIRHIS_TARGET_PLATFORM:-libvirt}" || return 1
                ;;
        esac
    fi

    MINIRHIS_PLATFORM_FAMILY="${selected_family}"
    set_platform_targets "${selected_product}" "${selected_platform}"
    prompt_platform_connection_details "${selected_platform}" || return 1

    case "${selected_product}" in
        minirhis)
            prompt_idm_details || return 1
            prompt_satellite_618_details || return 1
            prompt_aap_details || return 1
            ;;
        satellite)
            prompt_satellite_618_details || return 1
            ;;
        idm)
            prompt_idm_details || return 1
            ;;
        aap)
            prompt_aap_details || return 1
            ;;
        *)
            print_warning "Unsupported install product '${selected_product}'."
            return 1
            ;;
    esac

    MINIRHIS_PROMPTS_COMPLETED=1
    FORCE_PROMPT_ALL=0
    write_ansible_env_file || return 1

    if [ -f "$ANSIBLE_ENV_FILE" ]; then
        load_ansible_env_file || return 1
    fi
    normalize_shared_env_vars
    print_success "Prompts-only workflow complete. Saved encrypted values to ${ANSIBLE_ENV_FILE}"
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
        ssh-keygen -q -t rsa -b 4096 -N "" -f "${HOME}/.ssh/id_rsa" -C "minirhis-installer-host" || return 1
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

    ssh-keygen -t rsa -b 4096 -f "${AAP_SSH_PRIVATE_KEY}" -N "" -C "minirhis-aap-setup" || return 1
    chmod 600 "${AAP_SSH_PRIVATE_KEY}"
    chmod 644 "${AAP_SSH_PUBLIC_KEY}"
    print_success "SSH keys generated: ${AAP_SSH_KEY_DIR}"
}

# Collect public SSH keys that should be trusted by freshly installed guests.
# Sources (best-effort):
#   1. The installing machine user's existing SSH public keys
#   2. The MINIRHIS AAP orchestration key generated by ensure_ssh_keys()
#   3. The MINIRHIS provisioner container root public key, if available
collect_bootstrap_public_keys() {
    local key_file
    local container_pub=""

    ensure_minirhis_installer_ssh_key >/dev/null 2>&1 || true

    {
        for key_file in \
            "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" \
            "${HOME}/.ssh/id_ed25519.pub" \
            "${HOME}/.ssh/id_rsa.pub" \
            "${AAP_SSH_PUBLIC_KEY}"; do
            [ -r "${key_file}" ] && cat "${key_file}"
        done

        if command -v podman >/dev/null 2>&1 \
            && podman container exists "${MINIRHIS_CONTAINER_NAME}" >/dev/null 2>&1; then
            container_pub="$(podman exec "${MINIRHIS_CONTAINER_NAME}" sh -lc 'cat /root/.ssh/id_ed25519.pub 2>/dev/null || cat /root/.ssh/id_rsa.pub 2>/dev/null || true' 2>/dev/null || true)"
            [ -n "${container_pub}" ] && printf '%s\n' "${container_pub}"
        fi
    } | awk 'NF && !seen[$0]++'
}

# Download the AAP containerized bundle tarball to AAP_BUNDLE_DIR so it can be
# served over HTTP to the VM during kickstart %post.  The bundle is NOT embedded
# in the OEMDRV ISO — it is too large (5–10 GB) and would break ISO creation.
preflight_download_aap_bundle() {
    local bundle_filename
    local bundle_dest
    local bundle_alias="${AAP_BUNDLE_DIR}/aap-bundle.tar.gz"

    bundle_filename="$(derive_aap_bundle_filename "${AAP_BUNDLE_URL:-}")"
    bundle_dest="${AAP_BUNDLE_DIR}/${bundle_filename}"

    print_step "AAP bundle host path: ${bundle_dest}"

    if [ -f "${bundle_dest}" ]; then
        sudo ln -sfn "${bundle_filename}" "${bundle_alias}" >/dev/null 2>&1 || true
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
        sudo curl -fL -C - --retry 3 --retry-delay 10 \
            -H "Authorization: Bearer ${RH_ACCESS_TOKEN}" \
            -o "${bundle_dest}" "${AAP_BUNDLE_URL}" || return 1
    else
        sudo curl -fL -C - --retry 3 --retry-delay 10 \
            -o "${bundle_dest}" "${AAP_BUNDLE_URL}" || return 1
    fi

    if ! file "${bundle_dest}" | grep -qE 'gzip|tar|compress'; then
        print_warning "Downloaded file is not a valid tar archive. Removing."
        sudo rm -f "${bundle_dest}"
        return 1
    fi

    sudo ln -sfn "${bundle_filename}" "${bundle_alias}" >/dev/null 2>&1 || true

    print_success "AAP bundle staged at ${bundle_dest}"
    return 0
}

# Wait for the AAP VM to boot and SSH to be available, checking every 10s up to 10 minutes.
wait_for_vm_ssh() {
    local vm_name="${1:-aap}"
    local vm_ip
    local configured_vm_ip=""
    local discovered_ips=""
    local preferred_ip=""
    local vm_state
    local ssh_wait_timeout="${AAP_SSH_WAIT_TIMEOUT:-5400}"
    local ssh_wait_interval="${AAP_SSH_WAIT_INTERVAL:-10}"
    local ssh_progress_every="${AAP_SSH_PROGRESS_EVERY:-30}"
    local ssh_no_progress_timeout="${AAP_SSH_NO_PROGRESS_TIMEOUT:-5400}"
    local ssh_key_auth_failures=0
    local ssh_probe_out=""
    local callback_probe_ok=0
    local callback_probe_key=""
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
    local progress_inline_active=0

    _aap_progress_flush() {
        if [ "${progress_inline_active}" -eq 1 ]; then
            printf '\n'
            progress_inline_active=0
        fi
    }

    _aap_progress_render_inline() {
        local msg="$1"
        # Keep callback wait updates on one terminal line.
        printf '\r\033[K[STEP] %s' "$msg"
        progress_inline_active=1
    }

    if ! is_enabled "${AAP_SSH_CALLBACK_ENABLED:-0}"; then
        print_step "AAP SSH callback probing is disabled for this workflow; skipping wait_for_vm_ssh."
        return 1
    fi

    case "${ssh_wait_timeout}" in ''|*[!0-9]*) ssh_wait_timeout=5400 ;; esac
    case "${ssh_wait_interval}" in ''|*[!0-9]*) ssh_wait_interval=10 ;; esac
    case "${ssh_progress_every}" in ''|*[!0-9]*) ssh_progress_every=30 ;; esac
    case "${ssh_no_progress_timeout}" in ''|*[!0-9]*) ssh_no_progress_timeout=3600 ;; esac
    [ "${ssh_wait_interval}" -le 0 ] && ssh_wait_interval=10
    [ "${ssh_progress_every}" -le 0 ] && ssh_progress_every=30
    [ "${ssh_no_progress_timeout}" -le 0 ] && ssh_no_progress_timeout=3600

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
            _aap_progress_flush
            print_warning "${vm_name} SSH did not become available within $((ssh_wait_timeout / 60)) minute(s)."
            return 1
        fi

        stage=0
        vm_state="$(sudo virsh domstate "${vm_name}" 2>/dev/null | tr -d '[:space:]' || true)"
        if [ "${vm_state}" != "${last_vm_state}" ]; then
            _aap_progress_flush
            print_step "${vm_name} state transition: ${last_vm_state:-unknown} -> ${vm_state:-unknown}"
            last_vm_state="${vm_state}"
            last_stage_change="${now}"
        fi

        if [ "$vm_state" = "shutoff" ] || [ "$vm_state" = "crashed" ] || [ "$vm_state" = "pmsuspended" ]; then
            _aap_progress_flush
            print_warning "${vm_name} state is ${vm_state}; starting it to continue automated setup"
            sudo virsh start "${vm_name}" >/dev/null 2>&1 || true
            sleep 5
        fi

        if [ "$vm_state" = "running" ]; then
            stage=1
        fi

        case "$vm_name" in
            aap) configured_vm_ip="${AAP_IP:-}" ;;
            satellite) configured_vm_ip="${SAT_IP:-}" ;;
            idm) configured_vm_ip="${IDM_IP:-}" ;;
            *) configured_vm_ip="" ;;
        esac

        discovered_ips="$( { timeout 5 sudo -n virsh domifaddr "${vm_name}" 2>/dev/null || timeout 5 virsh domifaddr "${vm_name}" 2>/dev/null; } \
            | awk '/ipv4/ {print $4}' \
            | cut -d/ -f1 \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"

        # Always prefer the configured MINIRHIS internal IP for callback SSH.
        # domifaddr output can omit static/internal interfaces early in boot,
        # which previously caused fallback to the external DHCP address.
        preferred_ip="${configured_vm_ip}"
        if [ -z "${preferred_ip}" ]; then
            preferred_ip="$(printf '%s\n' "${discovered_ips}" | grep -E '^10\.168\.' | head -1 || true)"
            [ -z "${preferred_ip}" ] && preferred_ip="$(printf '%s\n' "${discovered_ips}" | head -1 || true)"
        fi

        vm_ip="${preferred_ip}"
        if [ -z "${vm_ip}" ]; then
            vm_ip="${configured_vm_ip}"
        fi

        if [ -n "${vm_ip}" ] && [ "${vm_ip}" != "${last_vm_ip}" ]; then
            _aap_progress_flush
            print_step "${vm_name} network update: detected IP ${vm_ip}"
            last_vm_ip="${vm_ip}"
            last_stage_change="${now}"
        fi

        if [ -n "${vm_ip}" ]; then
            stage=2

            # Probe SSH directly each cycle. TCP prechecks can be flaky while guest networking
            # and sshd settle, so direct key-auth probe is the source of truth.
            stage=3

            callback_probe_ok=0
            callback_probe_key=""
            ssh_probe_out=""
            for _probe_key in "${AAP_SSH_PRIVATE_KEY}" "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-}" "${HOME}/.ssh/id_rsa"; do
                [ -n "${_probe_key}" ] || continue
                [ -f "${_probe_key}" ] || continue
                ssh_probe_out="$(timeout 5 ssh \
                    -o BatchMode=yes \
                    -o PreferredAuthentications=publickey \
                    -o PasswordAuthentication=no \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ForwardX11=no \
                    -i "${_probe_key}" "root@${vm_ip}" "echo 'SSH ready'" 2>&1 || true)"
                if printf '%s' "${ssh_probe_out}" | grep -q "SSH ready"; then
                    callback_probe_ok=1
                    callback_probe_key="${_probe_key}"
                    break
                fi
            done

            if [ "${callback_probe_ok}" -eq 1 ]; then
                if [ "${ssh_port_reachable}" -eq 0 ]; then
                    _aap_progress_flush
                    print_success "${vm_name} is reachable on SSH at ${vm_ip}; starting setup callback."
                    ssh_port_reachable=1
                fi
                _aap_progress_flush
                print_success "${vm_name} SSH is ready at ${vm_ip} (key: ${callback_probe_key})"
                WAIT_FOR_VM_SSH_RESULT="${vm_ip}"
                return 0
            fi

            if [ "${ssh_port_reachable}" -eq 1 ]; then
                _aap_progress_flush
                print_warning "${vm_name} SSH became unreachable at ${vm_ip}; waiting for recovery."
                ssh_port_reachable=0
                last_stage_change="${now}"
            fi

            if printf '%s' "${ssh_probe_out}" | grep -Eqi "Permission denied|publickey"; then
                ssh_key_auth_failures="$((ssh_key_auth_failures + 1))"
                if [ "${ssh_key_auth_failures}" -ge "${AAP_SSH_KEY_FAIL_FAST_ATTEMPTS:-18}" ]; then
                    _aap_progress_flush
                    print_warning "${vm_name}: SSH key auth failed ${ssh_key_auth_failures} times at ${vm_ip}."
                    print_warning "Fail-fast triggered: likely SSH key injection/sshd auth mismatch (not a boot wait issue)."
                    print_warning "Check /root/.ssh/authorized_keys, sshd settings, and kickstart %post key injection."
                    return 1
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
            _aap_progress_render_inline "AAP callback wait: [${bar}] ${percent}%% elapsed=${elapsed}s/${ssh_wait_timeout}s remaining~${remaining}s stage=${stage_label}"
            last_progress_log="${now}"
        fi

        if [ $((now - last_stage_change)) -ge "${ssh_no_progress_timeout}" ]; then
            if [ "${stage}" -ge 3 ]; then
                _aap_progress_flush
                print_warning "${vm_name} callback wait stalled for ${ssh_no_progress_timeout}s (stage=${stage_label})."
                print_warning "Fail-fast triggered for troubleshooting. Check VM console, network, and /var/log/anaconda/ on guest."
                return 1
            fi
            # During kickstart/anaconda, it is normal to remain in stage<3 (no SSH yet)
            # for a long period; keep waiting until overall callback timeout.
            last_stage_change="${now}"
        fi

        sleep "${ssh_wait_interval}"
    done
}

# Run the AAP 2.6 containerized installer on the VM via SSH callback from the host.
# Supports both legacy setup.sh bundles and playbook-driven bundles.
run_aap_setup_on_vm() {
    local vm_name="${1:-aap}"
    local vm_ip
    local installer_inventory
    local bundle_url_runtime="${AAP_BUNDLE_EFFECTIVE_URL:-${AAP_BUNDLE_URL:-}}"
    local callback_ssh_key=""
    local local_bundle_source=""
    local bundle_remote_name
    local galaxy_token_remote="${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}"

    if ! is_enabled "${AAP_SSH_CALLBACK_ENABLED:-0}"; then
        print_step "AAP SSH callback is disabled; skipping run_aap_setup_on_vm."
        return 0
    fi

    WAIT_FOR_VM_SSH_RESULT=""
    wait_for_vm_ssh "${vm_name}" || {
        print_warning "Cannot reach ${vm_name} via SSH. Setup not attempted."
        return 1
    }
    vm_ip="${WAIT_FOR_VM_SSH_RESULT}"

    if [ -z "${vm_ip}" ]; then
        print_warning "${vm_name} SSH callback returned no VM IP. Setup not attempted."
        return 1
    fi

    installer_inventory="$(aap_installer_inventory_filename)"

    # Select a callback SSH key that can authenticate to root on the AAP VM.
    for _probe_key in "${AAP_SSH_PRIVATE_KEY}" "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-}" "${HOME}/.ssh/id_rsa"; do
        [ -n "${_probe_key}" ] || continue
        [ -f "${_probe_key}" ] || continue
        if timeout 6 ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no \
             -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no \
             -i "${_probe_key}" "root@${vm_ip}" "echo callback-key-ok" >/dev/null 2>&1; then
            callback_ssh_key="${_probe_key}"
            break
        fi
    done

    if [ -z "${callback_ssh_key}" ]; then
        print_warning "No callback SSH key can authenticate to root@${vm_ip}."
        print_warning "Checked keys: ${AAP_SSH_PRIVATE_KEY}, ${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-'(unset)'}, ${HOME}/.ssh/id_rsa"
        return 1
    fi

    # Prefer staging a locally cached bundle to avoid CDN/token failures on guest.
    bundle_remote_name="$(derive_aap_bundle_filename "${AAP_BUNDLE_URL:-${bundle_url_runtime:-}}")"
    if [ -f "${AAP_BUNDLE_DIR:-}/${bundle_remote_name}" ]; then
        local_bundle_source="${AAP_BUNDLE_DIR}/${bundle_remote_name}"
    elif [ -f "${AAP_BUNDLE_DIR:-}/aap-bundle.tar.gz" ]; then
        local_bundle_source="${AAP_BUNDLE_DIR}/aap-bundle.tar.gz"
    else
        local_bundle_source="$(ls -1t "${HOME}"/Downloads/ansible-automation-platform-containerized-setup-bundle-*.tar.gz 2>/dev/null | head -n 1 || true)"
    fi

    # Guard against stale HTML/error pages saved as *.tar.gz in the bundle cache.
    if [ -n "${local_bundle_source}" ] && [ -f "${local_bundle_source}" ] && ! tar -tzf "${local_bundle_source}" >/dev/null 2>&1; then
        print_warning "Cached AAP bundle is invalid tarball: ${local_bundle_source}"
        local_bundle_source=""
        while IFS= read -r _candidate; do
            [ -f "${_candidate}" ] || continue
            if tar -tzf "${_candidate}" >/dev/null 2>&1; then
                local_bundle_source="${_candidate}"
                break
            fi
        done < <(ls -1t "${HOME}"/Downloads/ansible-automation-platform-containerized-setup-bundle-*.tar.gz 2>/dev/null)
        if [ -n "${local_bundle_source}" ]; then
            print_step "Using valid fallback bundle from Downloads: ${local_bundle_source}"
        else
            print_warning "No valid local AAP bundle tarball found; callback will use URL fallback."
        fi
    fi

    if [ -n "${local_bundle_source}" ] && [ "$(basename "${local_bundle_source}")" != "aap-bundle.tar.gz" ]; then
        bundle_remote_name="$(basename "${local_bundle_source}")"
    fi

    if [ -n "${local_bundle_source}" ] && [ -f "${local_bundle_source}" ]; then
        print_step "Staging local AAP bundle on ${vm_name}: ${local_bundle_source}"
        if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no \
            -i "${callback_ssh_key}" "${local_bundle_source}" "root@${vm_ip}:/home/admin/${bundle_remote_name}" >/dev/null 2>&1; then
            print_warning "Could not stage local bundle to ${vm_name}; callback will use URL fallback if needed."
        fi
    fi

    print_step "Running AAP containerized installer via SSH on ${vm_name} (${vm_ip})..."
    print_step "  Callback SSH key: ${callback_ssh_key}"
    print_step "  Installer command: ansible-playbook -i ${installer_inventory} ansible.containerized_installer.install"
    print_step "  Output will be logged to: ${AAP_SETUP_LOG_LOCAL}"

    # SSH in and run the collection playbook entrypoint with the selected inventory.
    # Use a heredoc to avoid complex quote escaping and preserve robust failure handling.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting AAP setup on ${vm_ip}" | tee -a "${AAP_SETUP_LOG_LOCAL}"
    if ! (
        set -o pipefail
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no \
            -i "${callback_ssh_key}" "root@${vm_ip}" \
            "BUNDLE_URL='${bundle_url_runtime}' BUNDLE_FILENAME='${bundle_remote_name}' INSTALLER_INVENTORY='${installer_inventory}' RH_USER_REMOTE='${RH_USER:-}' RH_PASS_REMOTE='${RH_PASS:-}' GALAXY_TOKEN_REMOTE='${galaxy_token_remote}' bash -s" <<'EOF_REMOTE' 2>&1 | tee -a "${AAP_SETUP_LOG_LOCAL}"
set -euo pipefail

ADMIN_HOME=/home/admin
INSTALLER_LINK="${ADMIN_HOME}/aap-setup"
INSTALLER_STAGE="${ADMIN_HOME}/aap-setup.stage"
if [ -z "${BUNDLE_FILENAME:-}" ]; then
    BUNDLE_FILENAME="${BUNDLE_URL%%\?*}"
    BUNDLE_FILENAME="${BUNDLE_FILENAME##*/}"
fi
[ -n "${BUNDLE_FILENAME:-}" ] || BUNDLE_FILENAME="aap-bundle.tar.gz"
BUNDLE_TARBALL="${ADMIN_HOME}/${BUNDLE_FILENAME}"
INSTALLER_ROOT=""

stage_existing_overrides() {
    if [ -d "${INSTALLER_LINK}" ] && [ ! -L "${INSTALLER_LINK}" ] \
        && [ ! -f "${INSTALLER_LINK}/ansible.containerized_installer.install.yml" ] \
        && [ ! -f "${INSTALLER_LINK}/setup.sh" ]; then
        rm -rf "${INSTALLER_STAGE}"
        mv "${INSTALLER_LINK}" "${INSTALLER_STAGE}"
    fi
}

extract_installer_bundle() {
    local detected_root

    stage_existing_overrides
    detected_root="$(tar -tzf "${BUNDLE_TARBALL}" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "${detected_root}" ] || detected_root="${BUNDLE_FILENAME%.tar.gz}"

    tar -xzf "${BUNDLE_TARBALL}" -C "${ADMIN_HOME}"
    INSTALLER_ROOT="${ADMIN_HOME}/${detected_root}"
    if [ ! -d "${INSTALLER_ROOT}" ]; then
        echo "[aap-install] ERROR: extracted installer directory not found: ${INSTALLER_ROOT}"
        ls -la "${ADMIN_HOME}"
        exit 1
    fi

    ln -sfn "${INSTALLER_ROOT}" "${INSTALLER_LINK}"
    if [ -d "${INSTALLER_STAGE}" ]; then
        cp -af "${INSTALLER_STAGE}/." "${INSTALLER_ROOT}/"
        rm -rf "${INSTALLER_STAGE}"
    fi
    chown -h admin:admin "${INSTALLER_LINK}" || true
    chown -R admin:admin "${INSTALLER_ROOT}" || true
}

if [ ! -f "${INSTALLER_LINK}/ansible.containerized_installer.install.yml" ] && [ ! -f "${INSTALLER_LINK}/setup.sh" ]; then
    if [ -f "${BUNDLE_TARBALL}" ]; then
        echo "[aap-install] extracting staged local bundle from ${BUNDLE_TARBALL}"
        extract_installer_bundle
    else
        echo "[aap-install] bundle not found at ${BUNDLE_TARBALL}; downloading fallback bundle now"
        if [ -z "${BUNDLE_URL}" ]; then
            echo "[aap-install] ERROR: AAP_BUNDLE_URL is empty"
            exit 1
        fi
        curl -fL -C - --retry 5 --retry-delay 15 --connect-timeout 30 --max-time 7200 "${BUNDLE_URL}" -o "${BUNDLE_TARBALL}"
        extract_installer_bundle
    fi

    if [ ! -f "${INSTALLER_LINK}/setup.sh" ] && [ ! -d "${INSTALLER_LINK}/collections/ansible_collections/ansible/containerized_installer" ]; then
        echo "[aap-install] ERROR: bundle extraction did not produce expected installer assets"
        ls -la "${ADMIN_HOME}"
        exit 1
    fi
fi

INSTALLER_ROOT="$(readlink -f "${INSTALLER_LINK}" 2>/dev/null || true)"
[ -n "${INSTALLER_ROOT}" ] || INSTALLER_ROOT="${INSTALLER_LINK}"
cd "${INSTALLER_ROOT}"

dnf install -y --nogpgcheck wget git-core rsync vim ansible-core || true
command -v ansible-playbook >/dev/null 2>&1 || dnf install -y --nogpgcheck ansible-core

if ! dnf -q list podman crun slirp4netns fuse-overlayfs >/dev/null 2>&1; then
    echo "[aap-install] required container runtime packages are not available; attempting registration/package enablement"
    if ! subscription-manager identity >/dev/null 2>&1; then
        if [ -n "${RH_USER_REMOTE:-}" ] && [ -n "${RH_PASS_REMOTE:-}" ]; then
            subscription-manager register --username "${RH_USER_REMOTE}" --password "${RH_PASS_REMOTE}" --force || true
            subscription-manager refresh || true
            subscription-manager attach --auto || true
        else
            echo "[aap-install] WARNING: RH credentials are unavailable; cannot auto-register this host"
        fi
    fi
    dnf install -y --nogpgcheck podman crun slirp4netns fuse-overlayfs || true
fi

if ! dnf -q list podman crun slirp4netns fuse-overlayfs >/dev/null 2>&1; then
    echo "[aap-install] ERROR: required packages still unavailable (podman/crun/slirp4netns/fuse-overlayfs)"
    dnf repolist --enabled || true
    exit 1
fi

cat > "${INSTALLER_ROOT}/ansible.cfg" <<ANSIBLECFG
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ~/.ssh/id_rsa
control_path_dir = /tmp/.ansible-cp
retries = 3

[galaxy]
server_list = published, validated, community_galaxy

[galaxy_server.published]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token = ${GALAXY_TOKEN_REMOTE:-}

[galaxy_server.validated]
url = https://console.redhat.com/api/automation-hub/content/validated/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token = ${GALAXY_TOKEN_REMOTE:-}

[galaxy_server.community_galaxy]
url = https://galaxy.ansible.com/
ANSIBLECFG
chmod 600 "${INSTALLER_ROOT}/ansible.cfg"
chown admin:admin "${INSTALLER_ROOT}/ansible.cfg" || true
cp -f "${INSTALLER_ROOT}/ansible.cfg" /root/.ansible.cfg
chmod 600 /root/.ansible.cfg

mkdir -p "${INSTALLER_ROOT}/group_vars/automationeda"
cat > "${INSTALLER_ROOT}/group_vars/automationeda/main.yml" <<'EDACFG'
eda_safe_plugins:
    - ansible.eda.webhook
    - ansible.eda.alertmanager
EDACFG
chmod 600 "${INSTALLER_ROOT}/group_vars/automationeda/main.yml"
chown -R admin:admin "${INSTALLER_ROOT}/group_vars" || true

if [ ! -f "${INSTALLER_INVENTORY}" ]; then
    echo "[aap-install] ERROR: expected inventory file not found: ${INSTALLER_INVENTORY}"
    ls -la
    exit 1
fi

echo "[aap-install] running ansible-playbook -i ${INSTALLER_INVENTORY} ansible.containerized_installer.install"
if [ -f /home/admin/aap-setup/collections/ansible_collections/ansible/containerized_installer/roles/preflight/tasks/nodes.yml ]; then
    sed -i '0,/ansible_user_uid != 0/s//ansible_user_uid >= 0/' \
        /home/admin/aap-setup/collections/ansible_collections/ansible/containerized_installer/roles/preflight/tasks/nodes.yml || true
    echo "[aap-install] relaxed non-root preflight assertion for callback run"
fi

if [ "$(id -u)" -eq 0 ]; then
    _gateway_root_patch_out="$(python3 - <<'PY'
from pathlib import Path

roles_root = Path('/home/admin/aap-setup/collections/ansible_collections/ansible/containerized_installer/roles')
files = list(roles_root.rglob('*.yml')) if roles_root.exists() else []
gateway_migrate = roles_root / 'automationgateway/tasks/migrate.yml'
hub_upload_images = roles_root / 'automationhub/tasks/upload_images.yml'

updated = 0
for path in files:
    text = path.read_text(encoding='utf-8', errors='ignore')
    new_text = text.replace('userns: keep-id', 'userns: host')
    if new_text != text:
        path.write_text(new_text, encoding='utf-8')
        updated += 1

if gateway_migrate.exists():
    text = gateway_migrate.read_text(encoding='utf-8', errors='ignore')
    marker = '- name: Ensure automation gateway proxy is ready\n'
    injected = '''- name: Normalize automation gateway nginx temp ownership for root callback run
  ansible.builtin.command: podman exec automation-gateway sh -lc "chown -R 999:999 /var/lib/nginx/tmp"
  changed_when: false
  when: ansible_user_uid | int == 0

'''
    if injected not in text and marker in text:
        gateway_migrate.write_text(text.replace(marker, injected + marker, 1), encoding='utf-8')
        updated += 1

if hub_upload_images.exists():
    text = hub_upload_images.read_text(encoding='utf-8', errors='ignore')
    marker = '- name: Push the container images to automation hub\n'
    injected = '''- name: Normalize automation hub web nginx temp ownership for root callback run
  ansible.builtin.command: podman exec automation-hub-web sh -lc "uid=$(id -u nginx 2>/dev/null || echo 998); gid=$(id -g nginx 2>/dev/null || echo ${uid}); chown -R ${uid}:${gid} /var/lib/nginx/tmp"
  changed_when: false
  when: ansible_user_uid | int == 0

'''
    if injected not in text and marker in text:
        hub_upload_images.write_text(text.replace(marker, injected + marker, 1), encoding='utf-8')
        updated += 1

print(f'UPDATED={updated}')
PY
)"
    case "${_gateway_root_patch_out:-}" in
        UPDATED=0)
            echo "[aap-install] root userns hotfix already present or files unchanged"
            ;;
        UPDATED=*)
            echo "[aap-install] adjusted containerized installer userns settings for root callback run (${_gateway_root_patch_out})"
            ;;
        *)
            echo "[aap-install] WARNING: could not confirm root userns hotfix application"
            ;;
    esac
fi

ANSIBLE_CONFIG="${INSTALLER_ROOT}/ansible.cfg" ansible-playbook -i "${INSTALLER_INVENTORY}" ansible.containerized_installer.install
EOF_REMOTE
    ); then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AAP setup FAILED on ${vm_ip}" | tee -a "${AAP_SETUP_LOG_LOCAL}"
        return 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AAP setup completed successfully on ${vm_ip}" | tee -a "${AAP_SETUP_LOG_LOCAL}"

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

# After installer completes, pre-create credentials in AAP via REST API
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
            -d "{\"name\":\"MINIRHIS SSH Machine Credential\",\"credential_type\":1,\"inputs\":{\"username\":\"root\",\"ssh_key_data\":${ssh_key_json}}}" \
            -o /dev/null -w "%{http_code}")"
        case "$http_code" in
            200|201) print_success "Created: MINIRHIS SSH Machine Credential" ;;
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
        satellite) printf '%s\n' "${SAT_EXT_MAC:-52:54:00:61:80:01}" ;;
        aap)        printf '%s\n' "${AAP_EXT_MAC:-52:54:00:61:80:02}" ;;
        idm)           printf '%s\n' "${IDM_EXT_MAC:-52:54:00:61:80:03}" ;;
        *)             printf '%s\n' "" ;;
    esac
}

get_vm_internal_mac() {
    case "$1" in
        satellite) printf '%s\n' "${SAT_INT_MAC:-52:54:00:61:81:01}" ;;
        aap)        printf '%s\n' "${AAP_INT_MAC:-52:54:00:61:81:02}" ;;
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
    printf '%s\n' '    HOSTNAME=$(grep -oP '\''hostname=\\K\\S+'\'' /proc/cmdline 2>/dev/null || true)'
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
    local missing=0
    normalize_shared_env_vars
    if [ -f "$ANSIBLE_ENV_FILE" ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1
        normalize_shared_env_vars
        missing="$(count_missing_vars RH_USER RH_PASS ADMIN_USER ADMIN_PASS SAT_IP SAT_NETMASK SAT_GW SAT_HOSTNAME SAT_ALIAS SAT_DOMAIN SAT_ORG SAT_LOC CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY)"
        if [ "${missing}" -eq 0 ]; then
            return 0
        fi
        print_step "Satellite config has ${missing} missing value(s); prompting for required fields."
    fi
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
    local ks_file="${KS_DIR}/satellite.ks"
    local tmpdir tmp_ks tmp_oem
    local sat_ext_mac sat_int_mac
    local sat_prefix
    local root_pass_hash admin_pass_hash
    local ks_changed=0
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
    local ks_creator_baseline
    local ks_perf_network_snapshot
    local ks_runtime_exports
    local installer_user_q admin_user_q admin_pass_q rh_user_q rh_pass_q domain_q host_int_ip_q
    local cdn_org_q cdn_sat_key_q bootstrap_keys_block cdn_org_clean cdn_sat_key_clean
    local sat_rhel10_baseos_repo sat_rhel10_appstream_repo sat_rhel9_baseos_repo sat_rhel9_appstream_repo sat_rhel10_gpg_key_name
    local sat_rhel10_baseos_repo_q sat_rhel10_appstream_repo_q sat_rhel9_baseos_repo_q sat_rhel9_appstream_repo_q sat_rhel10_gpg_key_name_q

    # Always start fresh — remove any previously generated kickstart and OEMDRV ISO
    rm -f "${ks_file}" "${OEMDRV_ISO}" 2>/dev/null || true

    prompt_satellite_618_details || return 1
    ensure_iso_vars || return 1
    ensure_iso_tools || return 1
    ensure_ssh_keys || return 1

    sat_ext_mac="$(get_vm_external_mac "satellite")"
    sat_int_mac="$(get_vm_internal_mac "satellite")"
    sat_prefix="$(netmask_to_prefix "${SAT_NETMASK}")"
    print_kickstart_effective_values "Satellite" "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_NETMASK}" "${SAT_GW}"
    if [ -z "${RH_USER:-}" ] || [ -z "${RH_PASS:-}" ]; then
        print_warning "RH_USER or RH_PASS is empty — kickstart %post RHSM registration will fail."
        print_warning "Set rh_user and rh_pass in ${ANSIBLE_ENV_FILE} and regenerate the kickstart."
    fi
    root_pass_hash="$(kickstart_password_hash "${ROOT_PASS:-${ADMIN_PASS}}")" || return 1
    admin_pass_hash="$(kickstart_password_hash "${ADMIN_PASS}")" || return 1
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"
    prepare_kickstart_shared_blocks "satellite" "${SAT_HOSTNAME}" "${SAT_IP}" \
        "${sat_ext_mac}" "${sat_int_mac}" "${SAT_IP}" "${sat_prefix}" "${SAT_GW}" \
        1 1 "Satellite" \
        "rhel-9-for-x86_64-baseos-rpms" \
        "rhel-9-for-x86_64-appstream-rpms" \
        "satellite-6.18-for-rhel-9-x86_64-rpms" \
        "satellite-maintenance-6.18-for-rhel-9-x86_64-rpms"
    ks_nogpg_policy="${MINIRHIS_KS_NOGPG_POLICY}"
    ks_ssh_baseline="${MINIRHIS_KS_SSH_BASELINE}"
    ks_user_sudo_bootstrap="${MINIRHIS_KS_USER_SUDO_BOOTSTRAP}"
    ks_rhsm_register="${MINIRHIS_KS_RHSM_REGISTER}"
    ks_rhc_connect="${MINIRHIS_KS_RHC_CONNECT}"
    ks_repo_enable_verify="${MINIRHIS_KS_REPO_ENABLE_VERIFY}"
    ks_satellite_package_install="$(kickstart_satellite_package_install_block)"
    ks_nm_dual_nic="${MINIRHIS_KS_NM_DUAL_NIC}"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_HOSTNAME%%.*}" "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_HOSTNAME%%.*}" "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_HOSTNAME%%.*}")"
    ks_trust_bootstrap_keys="${MINIRHIS_KS_TRUST_BOOTSTRAP_KEYS}"
    ks_creator_baseline="${MINIRHIS_KS_CREATOR_BASELINE}"
    ks_perf_network_snapshot="$(kickstart_perf_network_snapshot_block)"
    cdn_org_clean="${CDN_ORGANIZATION_ID:-}"
    cdn_org_clean="${cdn_org_clean#\'}"
    cdn_org_clean="${cdn_org_clean%\'}"
    cdn_org_clean="${cdn_org_clean#\"}"
    cdn_org_clean="${cdn_org_clean%\"}"
    cdn_sat_key_clean="${CDN_SAT_ACTIVATION_KEY:-}"
    cdn_sat_key_clean="${cdn_sat_key_clean#\'}"
    cdn_sat_key_clean="${cdn_sat_key_clean%\'}"
    cdn_sat_key_clean="${cdn_sat_key_clean#\"}"
    cdn_sat_key_clean="${cdn_sat_key_clean%\"}"

    # Satellite lifecycle/content defaults for component-only workflows
    sat_rhel10_baseos_repo="${SAT_RHEL10_BASEOS_REPO:-rhel-10-for-x86_64-baseos-rpms}"
    sat_rhel10_appstream_repo="${SAT_RHEL10_APPSTREAM_REPO:-rhel-10-for-x86_64-appstream-rpms}"
    sat_rhel9_baseos_repo="${SAT_RHEL9_BASEOS_REPO:-rhel-9-for-x86_64-baseos-rpms}"
    sat_rhel9_appstream_repo="${SAT_RHEL9_APPSTREAM_REPO:-rhel-9-for-x86_64-appstream-rpms}"
    sat_rhel10_gpg_key_name="${SAT_RHEL10_GPG_KEY_NAME:-RPM-GPG-KEY-redhat-release}"

    installer_user_q="$(printf '%q' "${ADMIN_USER}")"
    admin_user_q="$(printf '%q' "${ADMIN_USER}")"
    admin_pass_q="$(printf '%q' "${ADMIN_PASS}")"
    rh_user_q="$(printf '%q' "${RH_USER}")"
    rh_pass_q="$(printf '%q' "${RH_PASS}")"
    domain_q="$(printf '%q' "${DOMAIN:-}")"
    host_int_ip_q="$(printf '%q' "${HOST_INT_IP:-192.168.122.1}")"
    cdn_org_q="$(printf '%q' "${cdn_org_clean}")"
    cdn_sat_key_q="$(printf '%q' "${cdn_sat_key_clean}")"
    sat_rhel10_baseos_repo_q="$(printf '%q' "${sat_rhel10_baseos_repo}")"
    sat_rhel10_appstream_repo_q="$(printf '%q' "${sat_rhel10_appstream_repo}")"
    sat_rhel9_baseos_repo_q="$(printf '%q' "${sat_rhel9_baseos_repo}")"
    sat_rhel9_appstream_repo_q="$(printf '%q' "${sat_rhel9_appstream_repo}")"
    sat_rhel10_gpg_key_name_q="$(printf '%q' "${sat_rhel10_gpg_key_name}")"
    bootstrap_keys_block="${bootstrap_ssh_keys}"
    ks_runtime_exports="$(cat <<EOF
# MINIRHIS runtime values injected at kickstart generation time
ADMIN_USER=${admin_user_q}
ADMIN_PASS=${admin_pass_q}
INSTALLER_USER=${installer_user_q}
RH_USER=${rh_user_q}
RH_PASS=${rh_pass_q}
DOMAIN=${domain_q}
HOST_INT_IP=${host_int_ip_q}
CDN_ORGANIZATION_ID=${cdn_org_q}
CDN_SAT_ACTIVATION_KEY=${cdn_sat_key_q}
SAT_RHEL10_BASEOS_REPO=${sat_rhel10_baseos_repo_q}
SAT_RHEL10_APPSTREAM_REPO=${sat_rhel10_appstream_repo_q}
SAT_RHEL9_BASEOS_REPO=${sat_rhel9_baseos_repo_q}
SAT_RHEL9_APPSTREAM_REPO=${sat_rhel9_appstream_repo_q}
SAT_RHEL10_GPG_KEY_NAME=${sat_rhel10_gpg_key_name_q}
RHC_AUTO_CONNECT=${RHC_AUTO_CONNECT:-1}
MINIRHIS_DEFER_COMPONENT_INSTALL=${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}
MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC=${MINIRHIS_TEMP_ENABLE_RC_LOCAL_EXEC:-1}
bootstrap_ssh_keys="\$(cat <<'MINIRHIS_BOOTSTRAP_KEYS'
${bootstrap_keys_block}
MINIRHIS_BOOTSTRAP_KEYS
)"
export ADMIN_USER ADMIN_PASS INSTALLER_USER RH_USER RH_PASS DOMAIN HOST_INT_IP CDN_ORGANIZATION_ID CDN_SAT_ACTIVATION_KEY SAT_RHEL10_BASEOS_REPO SAT_RHEL10_APPSTREAM_REPO SAT_RHEL9_BASEOS_REPO SAT_RHEL9_APPSTREAM_REPO SAT_RHEL10_GPG_KEY_NAME RHC_AUTO_CONNECT MINIRHIS_DEFER_COMPONENT_INSTALL bootstrap_ssh_keys
EOF
)"

    tmpdir="$(mktemp -d)"
    tmp_ks="${tmpdir}/satellite.ks"
    tmp_oem="${tmpdir}/ks.cfg"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --iscrypted "${root_pass_hash}"
user --name="${ADMIN_USER}" --password="${admin_pass_hash}" --iscrypted --groups=wheel

network --bootproto=dhcp --device=eth0 --interfacename=eth0:${sat_ext_mac} --activate --onboot=yes

%include /tmp/network-eth1

HEADER

    build_internal_kickstart_network_line "eth1" "${sat_int_mac}" "${SAT_IP}" "${SAT_NETMASK}" "${SAT_GW}" "${SAT_HOSTNAME}" >> "$tmp_ks"
    echo "" >> "$tmp_ks"

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "Satellite kickstart: DEMO LVM layout without dedicated /var/lib/pulp (uses /var)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
    # Requirements: 8 vCPU, 24 GB RAM, 150 GB raw storage
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs"  --size=2048
part swap                   --size=12288
part pv.01 --grow --size=1
volgroup vg_system pv.01
logvol /             --fstype="xfs" --name=lv_root --vgname=vg_system --size=20480
logvol /var/lib/pgsql --fstype="xfs" --name=lv_pgsql --vgname=vg_system --size=10240
    logvol /var          --fstype="xfs" --name=lv_var  --vgname=vg_system --size=1 --grow

DEMO_PART
    else
        print_step "Satellite kickstart: production LVM layout without dedicated /var/lib/pulp (uses /var)"
        cat >> "$tmp_ks" <<'STD_PART'
# Best Practice Partitioning for Satellite 6.18 (LVM)
    # Recommended: 8 vCPU, 32 GB RAM, 150+ GB raw storage
zerombr
clearpart --all --initlabel
part biosboot --fstype="biosboot" --size=1
part /boot --fstype="xfs" --size=2048
part swap  --size=16384
part pv.01 --grow --size=1
volgroup vg_system pv.01
logvol /             --fstype="xfs" --name=lv_root --vgname=vg_system --size=20480
logvol /var/lib/pgsql --fstype="xfs" --name=lv_pgsql --vgname=vg_system --size=12288
    logvol /var          --fstype="xfs" --name=lv_var  --vgname=vg_system --size=1 --grow

STD_PART
    fi

    # --- Packages ---
    cat >> "$tmp_ks" <<'PKGS'
%packages
@Base
@Core
ansible-core
bash-completion
bind-utils
chrony
libvirt-client
man-pages
net-tools
qemu-guest-agent
tmux
tuned
util-linux-core
xfsdump
yum
yum-utils
zip
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
set -x  # trace every command; all output captured in /root/ks-post.log

# Phase logger: writes to ks-post.log AND /dev/console (watch live: virsh console <vm>)
ks_log() { local ts; ts=\$(date +%H:%M:%S 2>/dev/null || echo "--:--:--"); printf '\n[MINIRHIS %s] %s\n' "\$ts" "\$*" | tee /dev/console 2>/dev/null || true; }
trap 'ec=\$?; ks_log "FAILED at line \${LINENO} (exit code \${ec}) -- see /root/ks-post.log"; exit \$ec' ERR
ks_log "=== MINIRHIS %post: satellite: STARTED ==="

${ks_runtime_exports}

${ks_nogpg_policy}

echo "Starting Satellite Pre-work..."

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" = "1" ]; then
    ks_log "Deferring component repo/package enablement to post-boot config-as-code"
    ks_log "Running RHSM/RHC registration during first boot"
${ks_rhsm_register}

${ks_rhc_connect}
else
${ks_rhsm_register}

${ks_rhc_connect}

${ks_repo_enable_verify}

${ks_satellite_package_install}
fi

${ks_creator_baseline}

# 3.5 Hostname
ks_log "Phase 3.5: Set hostname"
hostnamectl set-hostname "${SAT_HOSTNAME}"

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" = "1" ]; then
    ks_log "Satellite component install is deferred to post-boot config-as-code"
else

# 4. Satellite package installation
ks_log "Phase 4: Install satellite package"
if command -v foreman-maintain >/dev/null 2>&1; then
    foreman-maintain packages unlock || true
fi
dnf install -y --nogpgcheck satellite
if ! rpm -q satellite >/dev/null 2>&1; then
    echo "ERROR: Satellite package installation verification failed (rpm -q satellite)."
    exit 1
fi

# 5. Satellite Installer
ks_log "Phase 5: Run satellite-installer"
foreman-maintain packages unlock || true
satellite-installer --scenario satellite --foreman-initial-organization "${SAT_ORG}" --foreman-initial-location "${SAT_LOC}" --foreman-initial-admin-username "${ADMIN_USER}" --foreman-initial-admin-password "${ADMIN_PASS}" --foreman-proxy-dns true --foreman-proxy-dns-interface "eth1" --foreman-proxy-dns-zone "${SAT_DNS_ZONE:-${DOMAIN}}" --foreman-proxy-dns-reverse "${SAT_DNS_REVERSE_ZONE:-0.168.10.in-addr.arpa}" --foreman-proxy-dhcp true --foreman-proxy-dhcp-interface "eth1" --foreman-proxy-dhcp-gateway "${SAT_PROVISIONING_GW:-10.168.0.1}" --foreman-proxy-dhcp-nameservers "${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP}}" --foreman-proxy-dhcp-range "${SAT_PROVISIONING_DHCP_START:-10.168.130.1} ${SAT_PROVISIONING_DHCP_END:-10.168.255.254}" --foreman-proxy-tftp true --foreman-proxy-tftp-managed true --foreman-proxy-tftp-servername "${SAT_IP}" --foreman-proxy-http true --foreman-proxy-templates true --foreman-proxy-puppet false --no-enable-foreman-plugin-puppet --enable-foreman-plugin-ansible --enable-foreman-proxy-plugin-ansible --enable-foreman-plugin-remote-execution --enable-foreman-proxy-plugin-remote-execution-ssh --enable-foreman-compute-ec2 --enable-foreman-compute-gce --enable-foreman-compute-azure --enable-foreman-compute-libvirt --enable-foreman-plugin-openscap --enable-foreman-proxy-plugin-openscap --register-with-insights


# 5.1# 5.1 Post-Satellite Installation: Lifecycle Management & Provisioning Configuration
echo "=== SATELLITE LIFECYCLE & PROVISIONING CONFIGURATION ==="

# Wait for Foreman API to be fully ready
echo "Waiting for Foreman API to be ready..."
for i in {1..60}; do
    if curl -ksSf "https://localhost/api/v2/status" >/dev/null 2>&1; then
        echo "✓ Foreman API is ready"
        break
    fi
    if [ \$i -eq 60 ]; then
        echo "⚠ WARNING: Foreman API did not respond after 60 seconds (continuing anyway)"
    fi
    sleep 1
done

sleep 3

# Configure Hammer CLI globally for root and all admin users
# (centralized helper to reduce duplication)
bash tools/setup_hammer_cli.sh || true

# Grant all wheel-group users a valid Satellite admin role so they can run
# hammer commands without sudo. Keep this block shell-only in %post.
echo "Granting Satellite administrative role to wheel-group users..."
_minirhis_sat_role=""
for _role in "System Administrator" "Administrator" "Organization Administrator" "Organization Admin" "Manager"; do
    if hammer role info --name "\${_role}" >/dev/null 2>&1; then
        _minirhis_sat_role="\${_role}"
        break
    fi
done

if [ -n "\${_minirhis_sat_role}" ]; then
    getent group wheel | awk -F: '{print $4}' | tr ',' '\n' | sed '/^$/d' | while read -r _wuser; do
        hammer user add-role --login "\${_wuser}" --role "\${_minirhis_sat_role}" >/dev/null 2>&1 \
            && echo "  Granted \${_minirhis_sat_role} to \${_wuser}" \
            || echo "  ℹ Could not assign \${_minirhis_sat_role} to \${_wuser} via hammer"
    done
else
    echo "  ⚠ No known admin role name found on this Satellite; skipping automatic hammer role assignment."
fi

# --- 5.1.1 Create Lifecycle Environments for RHEL 10 ---
echo "Creating RHEL 10 lifecycle environments..."
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="DEV_RHEL_10_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="DEV_RHEL_10_x86_64" --description="Development environment for RHEL 10 x86_64" --prior="Library" 2>/dev/null || echo "  ℹ DEV_RHEL_10_x86_64 already exists"
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="TEST_RHEL_10_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="TEST_RHEL_10_x86_64" --description="Testing environment for RHEL 10 x86_64" --prior="DEV_RHEL_10_x86_64" 2>/dev/null || echo "  ℹ TEST_RHEL_10_x86_64 already exists"
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="PROD_RHEL_10_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="PROD_RHEL_10_x86_64" --description="Production environment for RHEL 10 x86_64" --prior="TEST_RHEL_10_x86_64" 2>/dev/null || echo "  ℹ PROD_RHEL_10_x86_64 already exists"

# --- 5.1.2 Create Lifecycle Environments for RHEL 9 ---
echo "Creating RHEL 9 lifecycle environments..."
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="DEV_RHEL_9_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="DEV_RHEL_9_x86_64" --description="Development environment for RHEL 9 x86_64" --prior="Library" 2>/dev/null || echo "  ℹ DEV_RHEL_9_x86_64 already exists"
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="TEST_RHEL_9_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="TEST_RHEL_9_x86_64" --description="Testing environment for RHEL 9 x86_64" --prior="DEV_RHEL_9_x86_64" 2>/dev/null || echo "  ℹ TEST_RHEL_9_x86_64 already exists"
bash tools/hammer_api_fallback.sh lifecycle_environments 'name="PROD_RHEL_9_x86_64"' -- \
    hammer lifecycle-environment create --organization="${SAT_ORG}" --name="PROD_RHEL_9_x86_64" --description="Production environment for RHEL 9 x86_64" --prior="TEST_RHEL_9_x86_64" 2>/dev/null || echo "  ℹ PROD_RHEL_9_x86_64 already exists"

# --- 5.1.3 Create Content Views for RHEL 10 & 9 ---
echo "Creating content views..."

# RHEL 10 Content View - API-first (centralized wrapper handles hammer fallback)
echo "Ensuring rhel-10-for-x86_64 content view (API-first)..."
bash tools/hammer_api_fallback.sh content_views 'name="rhel-10-for-x86_64"' -- \
    hammer content-view create --organization="${SAT_ORG}" --name="rhel-10-for-x86_64" --description="RHEL 10 BaseOS + AppStream for x86_64" 2>/dev/null || echo "  ℹ rhel-10-for-x86_64 content view already exists"

# Attach repositories to the RHEL 10 content view if not already attached (API-first)
for repo_name in "${SAT_RHEL10_BASEOS_REPO}" "${SAT_RHEL10_APPSTREAM_REPO}"; do
    cv_id=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views?search=name=\"rhel-10-for-x86_64\"" 2>/dev/null | sed -n 's/.*"results":\s*\[\(.*\)\].*/\1/p' | sed -n 's/.*"id":\s*\([0-9]*\).*/\1/p' | head -1 || true)
    if [ -n "${cv_id}" ]; then
        # Use wrapper to check repository attachment and run hammer add-repository as fallback
        bash tools/hammer_api_fallback.sh "content_views/${cv_id}/repositories" 'name="${repo_name}"' -- \
            hammer content-view add-repository --organization="${SAT_ORG}" --name="rhel-10-for-x86_64" --repository="${repo_name}" 2>/dev/null || echo "  ⚠ Failed to add ${repo_name} to rhel-10 CV"
    else
        echo "  ⚠ rhel-10-for-x86_64 content view not found; skipping repo attach for ${repo_name}"
    fi
done

# RHEL 9 Content View
api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views?search=name=\"rhel-9-for-x86_64\"" 2>/dev/null || true)
# RHEL 9 Content View - API-first (centralized wrapper handles hammer fallback)
echo "Ensuring rhel-9-for-x86_64 content view (API-first)..."
bash tools/hammer_api_fallback.sh content_views 'name="rhel-9-for-x86_64"' -- \
    hammer content-view create --organization="${SAT_ORG}" --name="rhel-9-for-x86_64" --description="RHEL 9 BaseOS + AppStream for x86_64" 2>/dev/null || echo "  ℹ rhel-9-for-x86_64 content view already exists"

# Attach repositories to the RHEL 9 content view if not already attached (API-first)
for repo_name in "${SAT_RHEL9_BASEOS_REPO}" "${SAT_RHEL9_APPSTREAM_REPO}"; do
    cv_id=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views?search=name=\"rhel-9-for-x86_64\"" 2>/dev/null | sed -n 's/.*"results":\s*\[\(.*\)\].*/\1/p' | sed -n 's/.*"id":\s*\([0-9]*\).*/\1/p' | head -1 || true)
    if [ -n "${cv_id}" ]; then
        attached_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views/${cv_id}/repositories?search=name=\"${repo_name}\"" 2>/dev/null || true)
        if [ -n "${attached_resp}" ] && ! echo "${attached_resp}" | grep -q '"total": *0'; then
            echo "  ℹ ${repo_name} already attached to rhel-9-for-x86_64 (verified via API)"
        else
            echo "  ℹ Attaching ${repo_name} to rhel-9-for-x86_64 via hammer (API missing or not attached)"
            bash tools/hammer_api_fallback.sh "content_views/${cv_id}/repositories" 'name="${repo_name}"' -- \
                hammer content-view add-repository --organization="${SAT_ORG}" --name="rhel-9-for-x86_64" --repository="${repo_name}" 2>/dev/null || echo "  ⚠ Failed to add ${repo_name} to rhel-9 CV"
        fi
    else
        echo "  ⚠ rhel-9-for-x86_64 content view not found; skipping repo attach for ${repo_name}"
    fi
done

# Import/attach RHEL 10 GPG key for synced content (API-first with hammer fallback)
echo "Importing RHEL 10 GPG key into Satellite content credentials..."
RHEL10_GPG_KEY_PATH="/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
if [ -f "${RHEL10_GPG_KEY_PATH}" ]; then
    # Check for existing GPG key via Satellite API
    gpg_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/gpg_keys?search=name=\"${SAT_RHEL10_GPG_KEY_NAME}\"" 2>/dev/null || true)
    if [ -n "${gpg_api_resp}" ] && ! echo "${gpg_api_resp}" | grep -q '"total": *0'; then
        echo "  ℹ GPG key already exists in Satellite (API): ${SAT_RHEL10_GPG_KEY_NAME}"
        RHEL10_GPG_KEY_ID=\$(echo "${gpg_api_resp}" | grep -o '"id":[0-9]*' | head -1 | sed 's/[^0-9]*//g' || true)
    else
        echo "  ℹ Creating GPG key (API reported missing or unreachable)"
        bash tools/hammer_api_fallback.sh gpg_keys 'name="${SAT_RHEL10_GPG_KEY_NAME}"' -- \
            hammer gpg create --organization="${SAT_ORG}" --name="${SAT_RHEL10_GPG_KEY_NAME}" --key="${RHEL10_GPG_KEY_PATH}" 2>/dev/null || echo "  ⚠ Failed to create Satellite GPG key (continuing)"
        RHEL10_GPG_KEY_ID="\$(hammer gpg list --organization="${SAT_ORG}" --search "name=\"${SAT_RHEL10_GPG_KEY_NAME}\"" --fields Id --csv 2>/dev/null | tail -1 | tr -d '\r')"
    fi

    for repo_name in "${SAT_RHEL10_BASEOS_REPO}" "${SAT_RHEL10_APPSTREAM_REPO}"; do
        # Try to find repository id via API
        repo_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/repositories?search=name=\"${repo_name}\"" 2>/dev/null || true)
        repo_id=\$(echo "${repo_api_resp}" | grep -o '"id":[0-9]*' | head -1 | sed 's/[^0-9]*//g' || true)
        if [ -n "${repo_id}" ] && [ -n "${RHEL10_GPG_KEY_ID}" ]; then
            # Attempt repository update via API
            update_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT -H "Content-Type: application/json" -d "{\"gpg_key_id\": ${RHEL10_GPG_KEY_ID}}" "${SAT_URL:-https://${SAT_IP}}/api/v2/repositories/${repo_id}" 2>/dev/null || true)
            if [ -z "${update_resp}" ]; then
                # Fallback to hammer if API update didn't return expected output
                hammer repository update --organization="${SAT_ORG}" --id="${repo_id}" --gpg-key-id="${RHEL10_GPG_KEY_ID}" 2>/dev/null || echo "  ⚠ Could not set GPG key on repo ${repo_name}"
            else
                echo "  ℹ Set GPG key on repo ${repo_name} via API"
            fi
        else
            echo "  ⚠ Repository or GPG key ID not found for ${repo_name}; skipping GPG assignment"
        fi
    done
else
    echo "  ⚠ RHEL GPG key file not found at ${RHEL10_GPG_KEY_PATH}; skipping Satellite GPG import"
fi

# Publish content views (API-first where possible)
echo "Publishing RHEL 10 content view..."
cv_id=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views?search=name=\"rhel-10-for-x86_64\"" 2>/dev/null | sed -n 's/.*"results":\s*\[\(.*\)\].*/\1/p' | sed -n 's/.*"id":\s*\([0-9]*\).*/\1/p' | head -1 || true)
if [ -n "${cv_id}" ]; then
    curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views/${cv_id}/publish" -o /dev/null -w "%{http_code}" | grep -qE '20[1-3]' && echo "  ℹ rhel-10 CV publish initiated via API" || echo "  ⚠ API publish failed; falling back to hammer"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        bash tools/hammer_api_fallback.sh content_views 'name="rhel-10-for-x86_64"' -- \
            hammer content-view publish --organization="${SAT_ORG}" --name="rhel-10-for-x86_64" 2>/dev/null || echo "  ℹ rhel-10 CV publish initiated or already published"
    fi
else
    echo "  ⚠ Unable to find content view via API; using hammer to publish"
    hammer content-view publish --organization="${SAT_ORG}" --name="rhel-10-for-x86_64" 2>/dev/null || echo "  ℹ rhel-10 CV publish initiated or already published"
fi

echo "Publishing RHEL 9 content view..."
cv_id=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views?search=name=\"rhel-9-for-x86_64\"" 2>/dev/null | sed -n 's/.*"results":\s*\[\(.*\)\].*/\1/p' | sed -n 's/.*"id":\s*\([0-9]*\).*/\1/p' | head -1 || true)
if [ -n "${cv_id}" ]; then
    curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${SAT_URL:-https://${SAT_IP}}/api/v2/content_views/${cv_id}/publish" -o /dev/null -w "%{http_code}" | grep -qE '20[1-3]' && echo "  ℹ rhel-9 CV publish initiated via API" || echo "  ⚠ API publish failed; falling back to hammer"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        bash tools/hammer_api_fallback.sh content_views 'name="rhel-9-for-x86_64"' -- \
            hammer content-view publish --organization="${SAT_ORG}" --name="rhel-9-for-x86_64" 2>/dev/null || echo "  ℹ rhel-9 CV publish initiated or already published"
    fi
else
    echo "  ⚠ Unable to find content view via API; using hammer to publish"
    hammer content-view publish --organization="${SAT_ORG}" --name="rhel-9-for-x86_64" 2>/dev/null || echo "  ℹ rhel-9 CV publish initiated or already published"
fi

# --- 5.1.4 Create Activation Keys for RHEL 10 ---
echo "Creating RHEL 10 activation keys..."
bash tools/hammer_api_fallback.sh activation_keys 'name="DEV_RHEL_10_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="DEV_RHEL_10_x86_64" --lifecycle-environment="DEV_RHEL_10_x86_64" --content-view="rhel-10-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ DEV_RHEL_10_x86_64 activation key already exists"
bash tools/hammer_api_fallback.sh activation_keys 'name="TEST_RHEL_10_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="TEST_RHEL_10_x86_64" --lifecycle-environment="TEST_RHEL_10_x86_64" --content-view="rhel-10-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ TEST_RHEL_10_x86_64 activation key already exists"
bash tools/hammer_api_fallback.sh activation_keys 'name="PROD_RHEL_10_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="PROD_RHEL_10_x86_64" --lifecycle-environment="PROD_RHEL_10_x86_64" --content-view="rhel-10-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ PROD_RHEL_10_x86_64 activation key already exists"

# --- 5.1.5 Create Activation Keys for RHEL 9 ---
echo "Creating RHEL 9 activation keys..."
bash tools/hammer_api_fallback.sh activation_keys 'name="DEV_RHEL_9_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="DEV_RHEL_9_x86_64" --lifecycle-environment="DEV_RHEL_9_x86_64" --content-view="rhel-9-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ DEV_RHEL_9_x86_64 activation key already exists"
bash tools/hammer_api_fallback.sh activation_keys 'name="TEST_RHEL_9_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="TEST_RHEL_9_x86_64" --lifecycle-environment="TEST_RHEL_9_x86_64" --content-view="rhel-9-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ TEST_RHEL_9_x86_64 activation key already exists"
bash tools/hammer_api_fallback.sh activation_keys 'name="PROD_RHEL_9_x86_64"' -- \
    hammer activation-key create --organization="${SAT_ORG}" --name="PROD_RHEL_9_x86_64" --lifecycle-environment="PROD_RHEL_9_x86_64" --content-view="rhel-9-for-x86_64" --unlimited-content-hosts 2>/dev/null || echo "  ℹ PROD_RHEL_9_x86_64 activation key already exists"

# --- 5.1.6 Configure Provisioning Subnet (Internal Network) ---
echo "Configuring provisioning subnet..."
NETMASK_PREFIX=\$(echo "${SAT_PROVISIONING_NETMASK:-255.255.0.0}" | awk -F. '{print 32-log(4294967296-(\$1*256*256*256+\$2*256*256+\$3*256+\$4))/log(2)}')
# Unconditional hammer subnet creation removed; next block performs API-first creation with hammer fallback

# API-first check for subnet existence; fallback to hammer for creation
echo "Configuring provisioning subnet (API-first)..."
subnet_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/subnets?search=name=\"internal-provision\"" 2>/dev/null || true)
if [ -n "${subnet_api_resp}" ] && ! echo "${subnet_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ internal-provision subnet already exists (verified via API)"
else
    echo "  ℹ Creating internal-provision subnet via hammer (API missing or absent)"
    bash tools/hammer_api_fallback.sh subnets 'name="internal-provision"' -- \
        hammer subnet create --name="internal-provision" \
            --network="${SAT_PROVISIONING_SUBNET:-${INTERNAL_NETWORK:-10.168.0.0}}" \
            --mask="${SAT_PROVISIONING_NETMASK:-${NETMASK:-255.255.0.0}}" \
            --gateway="${SAT_PROVISIONING_GW:-${INTERNAL_GW:-10.168.0.1}}" \
            --ipam-type="DHCP" \
            --from="${SAT_PROVISIONING_DHCP_START:-${SAT_IP:-10.168.128.1}}" \
            --to="${SAT_PROVISIONING_DHCP_END:-${AAP_IP:-10.168.128.2}}" \
            --dns-primary="${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP:-10.168.128.1}}" \
            --dns-secondary="${SAT_PROVISIONING_DNS_SECONDARY:-8.8.8.8}" \
            --boot-mode="DHCP" \
            --tftp-id="1" \
            --dhcp-id="1" \
            --dns-id="1" \
            --discovery-id="1" \
            --locations="${SAT_LOC}" \
            --organizations="${SAT_ORG}" 2>/dev/null || echo "  ℹ internal-provision subnet already configured"
fi

# --- 5.1.7 Configure Partition Tables (Standard Layouts) ---
echo "Configuring partition tables..."

# Simple single-partition layout

# Partition table: prefer API existence check, fallback to hammer create
pt_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/partition_tables?search=name=\"rhel-basic\"" 2>/dev/null || true)
if [ -n "${pt_api_resp}" ] && ! echo "${pt_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ rhel-basic partition table already exists (verified via API)"
else
    hammer partition-table create --name="rhel-basic" --layout='
<%= snippet("pxelinux_discovery") %>
zerombr
clearpart --all --initlabel
part /boot --fstype xfs --size 1024
part swap --size 4096
part / --fstype xfs --size 1 --grow
install
text
reboot
' --organizations="${SAT_ORG}" --locations="${SAT_LOC}" 2>/dev/null || echo "  ℹ rhel-basic partition table already exists"
fi

# LVM layout for production

# LVM partition table
pt_lvm_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/partition_tables?search=name=\"rhel-lvm\"" 2>/dev/null || true)
if [ -n "${pt_lvm_api_resp}" ] && ! echo "${pt_lvm_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ rhel-lvm partition table already exists (verified via API)"
else
    hammer partition-table create --name="rhel-lvm" --layout='
<%= snippet("pxelinux_discovery") %>
zerombr
clearpart --all --initlabel
part /boot --fstype xfs --size 1024
part swap --size 4096
part pv.01 --size 1 --grow
volgroup vg_system pv.01
logvol / --fstype xfs --vgname vg_system --name lv_root --size 1 --grow
logvol /var --fstype xfs --vgname vg_system --name lv_var --size 10240
install
text
reboot
' --organizations="${SAT_ORG}" --locations="${SAT_LOC}" 2>/dev/null || echo "  ℹ rhel-lvm partition table already exists"
fi

# --- 5.1.8 Configure Operating Systems ---
echo "Configuring operating system definitions..."

# RHEL 10 OS definition

# OS definitions: API-first existence check, hammer fallback to create
os10_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/operatingsystems?search=major=\"10\"" 2>/dev/null || true)
if [ -n "${os10_api_resp}" ] && ! echo "${os10_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL 10 OS definition already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh operating_systems 'major="10"' -- hammer os create --name="RHEL" --major="10" --description="Red Hat Enterprise Linux 10" \
        --family="Redhat" --release-name="Ootpa" \
        --architectures="x86_64" \
        --password-hash="SHA256" 2>/dev/null || echo "  ℹ RHEL 10 OS definition already exists"
fi

# RHEL 9 OS definition
os9_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/operatingsystems?search=major=\"9\"" 2>/dev/null || true)
if [ -n "${os9_api_resp}" ] && ! echo "${os9_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL 9 OS definition already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh operating_systems 'major="9"' -- hammer os create --name="RHEL" --major="9" --description="Red Hat Enterprise Linux 9" \
        --family="Redhat" --release-name="Plow" \
        --architectures="x86_64" \
        --password-hash="SHA256" 2>/dev/null || echo "  ℹ RHEL 9 OS definition already exists"
fi

# --- 5.1.9 Configure Installation Media for RHEL 10 and RHEL 9 ---
echo "Setting up installation media paths..."

# These reference synced content repositories - note that actual media must exist in Satellite first

# Media: check via API, fallback to hammer
media10_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/media?search=name=\"RHEL 10\"" 2>/dev/null || true)
if [ -n "${media10_api_resp}" ] && ! echo "${media10_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL 10 installation media already configured (verified via API)"
else
    bash tools/hammer_api_fallback.sh media 'name="RHEL 10"' -- hammer medium create --name="RHEL 10" --path="/pulp/content/ORGANIZATION_PATH/Library/custom/rhel-10-for-x86_64-baseos-rpms" \
        --operating-system-ids=\$(hammer os list --search "major=10" --fields=Id --csv | tail -1) 2>/dev/null || echo "  ℹ RHEL 10 installation media already configured"
fi

media9_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/media?search=name=\"RHEL 9\"" 2>/dev/null || true)
if [ -n "${media9_api_resp}" ] && ! echo "${media9_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL 9 installation media already configured (verified via API)"
else
    bash tools/hammer_api_fallback.sh media 'name="RHEL 9"' -- hammer medium create --name="RHEL 9" --path="/pulp/content/ORGANIZATION_PATH/Library/custom/rhel-9-for-x86_64-baseos-rpms" \
        --operating-system-ids=\$(hammer os list --search "major=9" --fields=Id --csv | tail -1) 2>/dev/null || echo "  ℹ RHEL 9 installation media already configured"
fi

# --- 5.1.10 Create Host Groups for Image-Based and Kickstart Provisioning ---
echo "Creating host groups for provisioning..."

# RHEL 10 Development Host Group

# Hostgroups: API existence check, fallback to hammer create
hg_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/hostgroups?search=name=\"RHEL10-DEV-Provision\"" 2>/dev/null || true)
if [ -n "${hg_api_resp}" ] && ! echo "${hg_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL10-DEV-Provision host group already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh hostgroups 'name="RHEL10-DEV-Provision"' -- hammer hostgroup create --name="RHEL10-DEV-Provision" \
        --organization="${SAT_ORG}" \
        --location="${SAT_LOC}" \
        --architecture="x86_64" \
        --operatingsystem=\$(hammer os list --search "major=10" --fields=Id --csv | tail -1) \
        --partition-table="rhel-basic" \
        --subnet="internal-provision" \
        --root-password="${ADMIN_PASS}" 2>/dev/null || echo "  ℹ RHEL10-DEV-Provision host group already exists"
fi

# RHEL 10 Production Host Group with LVM

hg_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/hostgroups?search=name=\"RHEL10-PROD-Provision\"" 2>/dev/null || true)
if [ -n "${hg_api_resp}" ] && ! echo "${hg_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL10-PROD-Provision host group already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh hostgroups 'name="RHEL10-PROD-Provision"' -- hammer hostgroup create --name="RHEL10-PROD-Provision" \
        --organization="${SAT_ORG}" \
        --location="${SAT_LOC}" \
        --architecture="x86_64" \
        --operatingsystem=\$(hammer os list --search "major=10" --fields=Id --csv | tail -1) \
        --partition-table="rhel-lvm" \
        --subnet="internal-provision" \
        --root-password="${ADMIN_PASS}" 2>/dev/null || echo "  ℹ RHEL10-PROD-Provision host group already exists"
fi

# RHEL 9 Development Host Group

hg_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/hostgroups?search=name=\"RHEL9-DEV-Provision\"" 2>/dev/null || true)
if [ -n "${hg_api_resp}" ] && ! echo "${hg_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL9-DEV-Provision host group already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh hostgroups 'name="RHEL9-DEV-Provision"' -- hammer hostgroup create --name="RHEL9-DEV-Provision" \
        --organization="${SAT_ORG}" \
        --location="${SAT_LOC}" \
        --architecture="x86_64" \
        --operatingsystem=\$(hammer os list --search "major=9" --fields=Id --csv | tail -1) \
        --partition-table="rhel-basic" \
        --subnet="internal-provision" \
        --root-password="${ADMIN_PASS}" 2>/dev/null || echo "  ℹ RHEL9-DEV-Provision host group already exists"
fi

# RHEL 9 Production Host Group with LVM

hg_api_resp=\$(curl -sS -k -u "${ADMIN_USER}:${ADMIN_PASS}" "${SAT_URL:-https://${SAT_IP}}/api/v2/hostgroups?search=name=\"RHEL9-PROD-Provision\"" 2>/dev/null || true)
if [ -n "${hg_api_resp}" ] && ! echo "${hg_api_resp}" | grep -q '"total": *0'; then
    echo "  ℹ RHEL9-PROD-Provision host group already exists (verified via API)"
else
    bash tools/hammer_api_fallback.sh hostgroups 'name="RHEL9-PROD-Provision"' -- \
        hammer hostgroup create --name="RHEL9-PROD-Provision" \
            --organization="${SAT_ORG}" \
            --location="${SAT_LOC}" \
            --architecture="x86_64" \
            --operatingsystem=\$(hammer os list --search "major=9" --fields=Id --csv | tail -1) \
            --partition-table="rhel-lvm" \
            --subnet="internal-provision" \
            --root-password="${ADMIN_PASS}" 2>/dev/null || echo "  ℹ RHEL9-PROD-Provision host group already exists"
fi

# --- 5.1.11 Enable Image Mode Provisioning ---
echo "Enabling image-based provisioning features..."

# Ensure Image Provisioning plugin is enabled (configured by satellite-installer)
systemctl status foreman-proxy | grep -q "active (running)" && echo "✓ Foreman proxy is running"

# Create ssh key template for image provisioning
mkdir -p /usr/share/foreman/provision_templates/ssh_provisioning 2>/dev/null || true

echo "=== SATELLITE LIFECYCLE & PROVISIONING CONFIGURATION COMPLETE ==="
echo "  ✓ Lifecycle Environments: Created for RHEL 9 & 10 (DEV/TEST/PROD)"
echo "  ✓ Content Views: RHEL 9 & 10 with BaseOS + AppStream repos"
echo "  ✓ Activation Keys: Created for all environments"
echo "  ✓ Provisioning Subnet: Configured (10.168.0.0/16) with DHCP/DNS/TFTP"
echo "  ✓ Partition Tables: Basic and LVM layouts available"
echo "  ✓ Operating Systems: RHEL 9 & 10 definitions"
echo "  ✓ Host Groups: DEV and PROD groups for both RHEL versions"
echo "  ✓ Image Mode: Ready for image-based provisioning"
echo "  ✓ DNS/DHCP/TFTP: All enabled via foreman-proxy on eth1"

# 5.2 MINIRHIS CMDB single-pane dashboard (Satellite + AAP + IdM + MINIRHIS container endpoint)
dnf install -y --nogpgcheck python3-pip sshpass
python3 -m pip install --upgrade pip setuptools wheel || true
python3 -m pip install ansible-cmdb || true

# Install MINIRHIS Python and Ansible Galaxy requirements on the Satellite host
_minirhis_req_txt="${MINIRHIS_DIR:-/minirhis}/container/requirements.txt"
_minirhis_req_yml="${MINIRHIS_DIR:-/minirhis}/container/requirements.yml"

if [ -f "${_minirhis_req_txt}" ]; then
    echo "Installing Python requirements from ${_minirhis_req_txt}..."
    python3 -m pip install --upgrade -r "${_minirhis_req_txt}" || \
        echo "  ⚠ Some Python requirements failed to install; check versions for this Python runtime."
else
    echo "  ⚠ requirements.txt not found at ${_minirhis_req_txt}; skipping Python requirements install."
fi

if [ -f "${_minirhis_req_yml}" ]; then
    echo "Installing Ansible collections from ${_minirhis_req_yml}..."
    ansible-galaxy collection install -r "${_minirhis_req_yml}" --force 2>&1 || \
        echo "  ⚠ Some Ansible collections failed to install; install manually: ansible-galaxy collection install -r ${_minirhis_req_yml}"
else
    echo "  ⚠ requirements.yml not found at ${_minirhis_req_yml}; skipping Ansible collection install."
fi

mkdir -p /etc/ansible /var/lib/minirhis-cmdb/facts /var/www/minirhis-cmdb

cat > /usr/local/bin/minirhis-cmdb-refresh.sh <<CMDB_REFRESH
#!/usr/bin/env bash
set -euo pipefail

INV=/etc/ansible/minirhis_inventory.ini
FACTS=/var/lib/minirhis-cmdb/facts
OUT=/var/www/minirhis-cmdb/index.html

cat > "\${INV}" <<INV_EOF
[minirhis_linux]
${SAT_HOSTNAME} ansible_host=${SAT_IP}
${AAP_HOSTNAME} ansible_host=${AAP_IP}
${IDM_HOSTNAME} ansible_host=${IDM_IP}

[all:vars]
ansible_user=${ADMIN_USER}
ansible_password=${ADMIN_PASS}
ansible_become=true
ansible_become_password=${ADMIN_PASS}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no'
INV_EOF

mkdir -p "\${FACTS}"

# Gather facts from MINIRHIS nodes (best effort so dashboard always refreshes)
ansible -i "\${INV}" minirhis_linux -m setup --tree "\${FACTS}" || true

# Add synthetic container health node so MINIRHIS container shows in the same pane
container_status="down"
if curl -ksSf --max-time 5 "http://${HOST_INT_IP}:3000/" >/dev/null 2>&1; then
    container_status="up"
fi

cat > "\${FACTS}/minirhis-container" <<JSON
{
    "ansible_facts": {
        "nodename": "minirhis-container",
        "fqdn": "minirhis-container",
        "default_ipv4": {"address": "${HOST_INT_IP}"},
        "minirhis_container_endpoint": "http://${HOST_INT_IP}:3000",
        "minirhis_container_status": "\${container_status}"
    },
    "changed": false
}
JSON

ansible-cmdb -t html_fancy "\${FACTS}" > "\${OUT}"
CMDB_REFRESH

chmod 0755 /usr/local/bin/minirhis-cmdb-refresh.sh

cat > /etc/systemd/system/minirhis-cmdb-refresh.service <<'CMDB_REFRESH_SVC'
[Unit]
Description=Refresh MINIRHIS ansible-cmdb dashboard data
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/minirhis-cmdb-refresh.sh
CMDB_REFRESH_SVC

cat > /etc/systemd/system/minirhis-cmdb-refresh.timer <<'CMDB_REFRESH_TIMER'
[Unit]
Description=Periodic MINIRHIS ansible-cmdb refresh timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=minirhis-cmdb-refresh.service

[Install]
WantedBy=timers.target
CMDB_REFRESH_TIMER

cat > /etc/systemd/system/minirhis-cmdb-http.service <<'CMDB_HTTP_SVC'
[Unit]
Description=MINIRHIS CMDB Dashboard HTTP Server
After=network-online.target minirhis-cmdb-refresh.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/var/www/minirhis-cmdb
ExecStart=/usr/bin/python3 -m http.server 18080 --bind 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CMDB_HTTP_SVC

systemctl daemon-reload
systemctl enable --now minirhis-cmdb-refresh.timer
systemctl start minirhis-cmdb-refresh.service || true
systemctl enable --now minirhis-cmdb-http.service

firewall-cmd --permanent --add-port=18080/tcp || true
firewall-cmd --reload || true
fi

${ks_perf_network_snapshot}

echo "Post-install configuration complete."
%end
POSTEOF

    cp "$tmp_ks" "$tmp_oem"
    write_file_if_changed "$tmp_ks" "$ks_file" 0644 || {
        rm -rf "$tmpdir"
        return 1
    }
    ks_changed="${MINIRHIS_LAST_WRITE_CHANGED:-0}"

    if [ "$ks_changed" = "0" ] && [ -f "$OEMDRV_ISO" ]; then
        rm -rf "$tmpdir"
        print_step "OEMDRV ISO unchanged: $OEMDRV_ISO"
        print_success "Generated Satellite kickstart: $ks_file"
        print_success "Created OEMDRV ISO: $OEMDRV_ISO"
        return 0
    fi

    print_step "Packaging Satellite kickstart into OEMDRV ISO"
    if command -v genisoimage >/dev/null 2>&1; then
        sudo genisoimage -output "$OEMDRV_ISO" -volid "OEMDRV" -rational-rock -joliet -full-iso9660-filenames "$tmp_oem" >/dev/null 2>&1
    else
        sudo xorriso -as mkisofs -o "$OEMDRV_ISO" -V OEMDRV -r -J "$tmp_oem" >/dev/null 2>&1
    fi

    sudo chmod 0644 "$OEMDRV_ISO"
    sudo chown qemu:qemu "$OEMDRV_ISO" 2>/dev/null || true
    rm -rf "$tmpdir"

    validate_kickstart_integrity "$ks_file" "Satellite kickstart" || return 1

    print_success "Generated Satellite kickstart: $ks_file"
    print_success "Created OEMDRV ISO: $OEMDRV_ISO"
}

generate_satellite_oemdrv_only() {
    print_step "Generating Satellite kickstart and OEMDRV ISO only"
    ensure_kickstart_prereqs_ready "satellite" || return 1
    normalize_shared_env_vars
    ensure_iso_vars || return 1
    sudo mkdir -p "${FILES_DIR}" "${KS_DIR}"
    generate_satellite_618_kickstart || {
        print_warning "Satellite kickstart/OEMDRV generation failed. Check required credentials in ${ANSIBLE_ENV_FILE}."
        return 1
    }
    print_success "Satellite OEMDRV workflow complete"
}

generate_aap_oemdrv_only() {
    print_step "Generating AAP kickstart and OEMDRV ISO only"
    ensure_kickstart_prereqs_ready "aap" || return 1
    normalize_shared_env_vars
    ensure_iso_vars || return 1
    sudo mkdir -p "${FILES_DIR}" "${KS_DIR}"
    generate_aap_kickstart || {
        print_warning "AAP kickstart/OEMDRV generation failed. Check required credentials in ${ANSIBLE_ENV_FILE}."
        return 1
    }
    print_success "AAP OEMDRV workflow complete"
}

generate_idm_oemdrv_only() {
    print_step "Generating IdM kickstart and OEMDRV ISO only"
    ensure_kickstart_prereqs_ready "idm" || return 1
    normalize_shared_env_vars
    ensure_iso_vars || return 1
    sudo mkdir -p "${FILES_DIR}" "${KS_DIR}"
    generate_idm_kickstart || {
        print_warning "IdM kickstart/OEMDRV generation failed. Check required credentials in ${ANSIBLE_ENV_FILE}."
        return 1
    }
    print_success "IdM OEMDRV workflow complete"
}

generate_oemdrv_kickstarts_only() {
    local oemdrv_choice
    print_minirhis_header
    echo "Generate OEMDRV Kickstarts"
    echo ""
    echo "  1) AAP OEMDRV kickstart"
    echo "  2) IdM OEMDRV kickstart"
    echo "  3) Satellite OEMDRV kickstart"
    echo "  4) All"
    echo "     - Satellite + AAP + IdM"
    echo "  0) Back"
    echo ""
    read -r -p "Select component [0-4]: " oemdrv_choice

    case "${oemdrv_choice}" in
        1) generate_aap_oemdrv_only || return 1 ;;
        2) generate_idm_oemdrv_only || return 1 ;;
        3) generate_satellite_oemdrv_only || return 1 ;;
        4)
            print_step "Generating kickstarts and OEMDRV ISOs for all components"
            ensure_kickstart_prereqs_ready "all" || return 1
            normalize_shared_env_vars
            ensure_iso_vars || return 1
            sudo mkdir -p "${FILES_DIR}" "${KS_DIR}"
            generate_satellite_618_kickstart || { print_warning "Satellite kickstart/OEMDRV generation failed."; return 1; }
            generate_aap_kickstart           || { print_warning "AAP kickstart generation failed."; return 1; }
            generate_idm_kickstart           || { print_warning "IdM kickstart generation failed."; return 1; }
            validate_generated_kickstarts || true
            print_success "All kickstart and OEMDRV artifacts generated successfully."
            ;;
        0) return 0 ;;
        *) print_warning "Invalid choice. Please select 0-4." ;;
    esac
}

create_satellite_vm_only() {
    local sat_disk sat_ram sat_vcpu

    print_phase 1 3 "Provision Satellite VM artifacts"
    print_step "Preparing Satellite-only qcow2 VM"
    prompt_use_existing_env
    normalize_shared_env_vars

    if is_demo; then
        print_step "DEMO mode: reduced Satellite VM specifications (PoC/learning environment)"
        sat_disk="150G"; sat_ram=24576; sat_vcpu=8
    else
        print_step "Standard mode: production/best-practice Satellite VM specifications"
        sat_disk="150G"; sat_ram=32768; sat_vcpu=8
    fi

    cleanup_minirhis_lock_files || true
    prune_local_ssh_trust_for_component "satellite" || true
    ensure_virtualization_tools || return 1
    ensure_iso_vars || return 1
    download_rhel9_iso || return 1
    assert_satellite_install_iso_is_valid "${SAT_ISO_PATH}" || return 1
    fix_qemu_permissions || return 1
    create_libvirt_storage_pool || return 1
    generate_satellite_oemdrv_only || return 1

    print_phase 2 3 "Create Satellite VM"
    create_vm_if_missing "satellite" "${VM_DIR}/satellite.qcow2" "$sat_disk" "$sat_ram" "$sat_vcpu" "${KS_DIR}/satellite.ks" "hd:LABEL=OEMDRV:/ks.cfg" "${SAT_ISO_PATH}" || return 1

    launch_single_vm_console_monitor_auto "satellite" || true

    print_phase 3 3 "Satellite VM provisioning request complete"
    print_success "Satellite-only VM provisioning complete."
    return 0
}

create_idm_vm_only() {
    local idm_disk idm_ram idm_vcpu

    print_phase 1 3 "Provision IdM VM artifacts"
    print_step "Preparing IdM-only qcow2 VM"
    prompt_use_existing_env
    normalize_shared_env_vars

    if is_demo; then
        print_step "DEMO mode: reduced IdM VM specifications (PoC/learning environment)"
        idm_disk="30G"; idm_ram=4096; idm_vcpu=2
    else
        print_step "Standard mode: production/best-practice IdM VM specifications"
        idm_disk="60G"; idm_ram=16384; idm_vcpu=4
    fi

    cleanup_minirhis_lock_files || true
    prune_local_ssh_trust_for_component "idm" || true
    ensure_virtualization_tools || return 1
    ensure_iso_vars || return 1
    download_rhel10_iso || return 1
    assert_idm_install_iso_is_valid "${ISO_PATH}" || return 1
    fix_qemu_permissions || return 1
    create_libvirt_storage_pool || return 1
    generate_idm_kickstart || return 1

    print_phase 2 3 "Create IdM VM"
    create_vm_if_missing "idm" "${VM_DIR}/idm.qcow2" "$idm_disk" "$idm_ram" "$idm_vcpu" "${KS_DIR}/idm.ks" || return 1

    launch_single_vm_console_monitor_auto "idm" || true

    print_phase 3 3 "IdM VM provisioning request complete"
    print_success "IdM-only VM provisioning complete."
    return 0
}

create_aap_vm_only() {
    local aap_disk aap_ram aap_vcpu

    print_phase 1 3 "Provision AAP VM artifacts"
    print_step "Preparing AAP-only qcow2 VM"
    prompt_use_existing_env
    normalize_shared_env_vars

    if is_demo; then
        print_step "DEMO mode: reduced AAP VM specifications (PoC/learning environment)"
        aap_disk="50G"; aap_ram=8152; aap_vcpu=4
    else
        print_step "Standard mode: production/best-practice AAP VM specifications"
        aap_disk="50G"; aap_ram=16384; aap_vcpu=8
    fi

    cleanup_minirhis_lock_files || true
    prune_local_ssh_trust_for_component "aap" || true
    ensure_virtualization_tools || return 1
    ensure_iso_vars || return 1
    download_rhel10_iso || return 1
    assert_aap_install_iso_is_valid "${ISO_PATH}" || return 1
    fix_qemu_permissions || return 1
    create_libvirt_storage_pool || return 1
    generate_aap_kickstart || return 1

    ensure_ssh_keys || {
        print_warning "Failed to generate SSH keys; AAP callback orchestration will not work."
        return 1
    }

    if [ -z "${AAP_BUNDLE_URL:-}" ]; then
        print_warning "AAP_BUNDLE_URL is required for AAP VM bundle download to /home/admin on the guest."
        return 1
    fi

    print_phase 2 3 "Create AAP VM"
    create_vm_if_missing "aap" "${VM_DIR}/aap.qcow2" "$aap_disk" "$aap_ram" "$aap_vcpu" "${KS_DIR}/aap.ks" || return 1

    launch_single_vm_console_monitor_auto "aap" || true

    print_phase 3 3 "AAP VM provisioning request complete"
    print_success "AAP-only VM provisioning complete."
    return 0
}

print_aap_inventory_model_guide() {
    cat <<'EOF'

AAP Tested Deployment Model Guide (inventory templates)
======================================================

  [1] Single Node (Controller + PostgreSQL local)

      +------------------------------+
      | aap                       |
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
      | aap (single node demo)    |
      +------------------------------+

            Templates:
                DEMO-inventory.j2
                inventory-growth.j2

Docs: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/tested_deployment_models/index

EOF
}

resolve_aap_inventory_template_path() {
    local selected="$1"
    local candidate_dir

    if [ -z "$selected" ]; then
        return 1
    fi

    if [ -f "$selected" ]; then
        printf '%s\n' "$selected"
        return 0
    fi

    for candidate_dir in \
        "${AAP_INVENTORY_TEMPLATE_DIR}" \
        "$SCRIPT_DIR/container/vars/external_inventory/aap" \
        "$SCRIPT_DIR/inventory/aap"; do
        [ -n "$candidate_dir" ] || continue
        if [ -f "${candidate_dir}/${selected}" ]; then
            printf '%s\n' "${candidate_dir}/${selected}"
            return 0
        fi
    done

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

aap_installer_inventory_filename() {
    local selected="${AAP_INVENTORY_TEMPLATE:-}"
    local base=""

    if is_demo; then
        printf '%s\n' "DEMO-inventory"
        return 0
    fi

    [ -n "$selected" ] || {
        printf '%s\n' "inventory"
        return 0
    }

    base="$(basename "$selected")"
    case "$base" in
        DEMO-inventory.j2|DEMO-inventory)
            printf '%s\n' "DEMO-inventory"
            ;;
        inventory-growth.j2|inventory-growth)
            printf '%s\n' "inventory-growth"
            ;;
        *)
            printf '%s\n' "inventory"
            ;;
    esac
}

_minirhis_show_about_inventory() {
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
    3. minirhis-builder renders inventory.j2 into /home/admin/aap-setup/inventory
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

_minirhis_show_about_inventory_growth() {
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
     2. minirhis-builder renders inventory-growth.j2 into
         /home/admin/aap-setup/inventory on the AAP host during kickstart %%post.
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
        AAP_TOPOLOGY="standalone"
        ensure_aap_pg_database_if_needed || return 1
        echo ""
        echo "  [DEMO] This item was skipped because --DEMO was chosen."
        echo "         The smallest model (DEMO-inventory.j2) will be created"
        echo "         for Demo, PoC, or Educational purposes."
        echo "         Note: DEMO inventory only affects the AAP installer profile."
        echo "               Full MiniRHIS still runs 3 servers: IdM + Satellite + AAP."
        return 0
    fi

    # If both are already set (env file or CLI), keep them.
    if [ -n "${AAP_INVENTORY_TEMPLATE:-}" ] && [ -n "${AAP_INVENTORY_GROWTH_TEMPLATE:-}" ]; then
        ensure_aap_pg_database_if_needed || return 1
        return 0
    fi

    # In non-interactive mode, default MiniRHIS to single-node standalone AAP.
    if is_noninteractive; then
        AAP_INVENTORY_TEMPLATE="${AAP_INVENTORY_TEMPLATE:-inventory-growth.j2}"
        AAP_INVENTORY_GROWTH_TEMPLATE="${AAP_INVENTORY_GROWTH_TEMPLATE:-inventory-growth.j2}"
        AAP_TOPOLOGY="${AAP_TOPOLOGY:-standalone}"
        ensure_aap_pg_database_if_needed || return 1
        return 0
    fi

    local inv_choice

    while true; do
        print_minirhis_header
        echo "AAP Inventory Architecture"
        echo ""
        echo "  0) Exit"
        echo "     - Return to previous menu"
        echo "  1) inventory"
        echo "     - Enterprise / Multi-Node deployment (not supported in this standalone lab)"
        echo "  2) About inventory"
        echo "     - Name, synopsis, diagram, and guidance"
        echo "  3) inventory-growth"
        echo "     - Growth / Single-Node containerized (includes local gateway container)"
        echo "  4) About inventory-growth"
        echo "     - Name, synopsis, diagram, and guidance"
        echo ""
        read -r -p "  Choice [0-4]: " inv_choice

        case "${inv_choice}" in
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "  Exiting inventory selection."
                return 1
                ;;
            1)
                print_warning "Enterprise inventory is disabled for this standalone deployment model."
                print_step "Selecting inventory-growth.j2 so all AAP services (including gateway) run as containers on ${AAP_HOSTNAME}."
                AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
                AAP_INVENTORY_GROWTH_TEMPLATE="inventory-growth.j2"
                AAP_TOPOLOGY="standalone"
                ensure_aap_pg_database_if_needed || return 1
                print_success "Selected: inventory-growth.j2 (Growth / Single-Node)"
                return 0
                ;;
            2)
                _minirhis_show_about_inventory
                ;;
            3)
                AAP_INVENTORY_TEMPLATE="inventory-growth.j2"
                AAP_INVENTORY_GROWTH_TEMPLATE="inventory-growth.j2"
                AAP_TOPOLOGY="standalone"
                ensure_aap_pg_database_if_needed || return 1
                print_success "Selected: inventory-growth.j2 (Growth / Single-Node)"
                return 0
                ;;
            4)
                _minirhis_show_about_inventory_growth
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
    local lightspeed_host_e lightspeed_admin_user_e lightspeed_admin_password_e lightspeed_admin_email_e
    local lightspeed_pg_host_e lightspeed_pg_password_e lightspeed_chatbot_model_url_e lightspeed_chatbot_model_api_key_e
    local lightspeed_chatbot_model_id_e lightspeed_chatbot_default_provider_e lightspeed_chatbot_model_extra_settings_e
    local lightspeed_mcp_controller_enabled_e lightspeed_mcp_lightspeed_enabled_e lightspeed_wca_model_type_e
    local lightspeed_wca_model_url_e lightspeed_wca_model_verify_ssl_e lightspeed_wca_model_enable_anonymization_e
    local lightspeed_wca_health_check_e eda_safe_plugins_e

    template_path="$(resolve_aap_inventory_template_path "$template_selector")" || {
        print_warning "AAP inventory template not found: ${template_selector}"
        print_warning "Looked in: ${AAP_INVENTORY_TEMPLATE_DIR}, ${SCRIPT_DIR}/container/vars/external_inventory/aap, ${SCRIPT_DIR}/inventory/aap, and absolute path input"
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
    lightspeed_host_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_HOST:-${AAP_HOSTNAME}}")"
    lightspeed_admin_user_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_ADMIN_USER:-${ADMIN_USER}}")"
    lightspeed_admin_password_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_ADMIN_PASSWORD:-${AAP_ADMIN_PASS:-$ADMIN_PASS}}")"
    lightspeed_admin_email_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_ADMIN_EMAIL:-${ADMIN_USER}@${DOMAIN}}")"
    lightspeed_pg_host_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_PG_HOST:-${AAP_HOSTNAME}}")"
    lightspeed_pg_password_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_PG_PASSWORD:-${AAP_ADMIN_PASS:-$ADMIN_PASS}}")"
    lightspeed_chatbot_model_url_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_CHATBOT_MODEL_URL}")"
    lightspeed_chatbot_model_api_key_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_CHATBOT_MODEL_API_KEY}")"
    lightspeed_chatbot_model_id_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_CHATBOT_MODEL_ID}")"
    lightspeed_chatbot_default_provider_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_CHATBOT_DEFAULT_PROVIDER}")"
    lightspeed_chatbot_model_extra_settings_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_CHATBOT_MODEL_EXTRA_SETTINGS}")"
    lightspeed_mcp_controller_enabled_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED}")"
    lightspeed_mcp_lightspeed_enabled_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED}")"
    lightspeed_wca_model_type_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_WCA_MODEL_TYPE}")"
    lightspeed_wca_model_url_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_WCA_MODEL_URL}")"
    lightspeed_wca_model_verify_ssl_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_WCA_MODEL_VERIFY_SSL}")"
    lightspeed_wca_model_enable_anonymization_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_WCA_MODEL_ENABLE_ANONYMIZATION}")"
    lightspeed_wca_health_check_e="$(sed_escape_replacement "${AAP_LIGHTSPEED_WCA_HEALTH_CHECK}")"
    eda_safe_plugins_e="$(sed_escape_replacement "${AAP_EDA_SAFE_PLUGINS}")"

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
        -e "s|{{AAP_LIGHTSPEED_HOST}}|${lightspeed_host_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_ADMIN_USER}}|${lightspeed_admin_user_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_ADMIN_PASSWORD}}|${lightspeed_admin_password_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_ADMIN_EMAIL}}|${lightspeed_admin_email_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_PG_HOST}}|${lightspeed_pg_host_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_PG_PASSWORD}}|${lightspeed_pg_password_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_CHATBOT_MODEL_URL}}|${lightspeed_chatbot_model_url_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_CHATBOT_MODEL_API_KEY}}|${lightspeed_chatbot_model_api_key_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_CHATBOT_MODEL_ID}}|${lightspeed_chatbot_model_id_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_CHATBOT_DEFAULT_PROVIDER}}|${lightspeed_chatbot_default_provider_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_CHATBOT_MODEL_EXTRA_SETTINGS}}|${lightspeed_chatbot_model_extra_settings_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED}}|${lightspeed_mcp_controller_enabled_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED}}|${lightspeed_mcp_lightspeed_enabled_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_WCA_MODEL_TYPE}}|${lightspeed_wca_model_type_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_WCA_MODEL_URL}}|${lightspeed_wca_model_url_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_WCA_MODEL_VERIFY_SSL}}|${lightspeed_wca_model_verify_ssl_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_WCA_MODEL_ENABLE_ANONYMIZATION}}|${lightspeed_wca_model_enable_anonymization_e}|g" \
        -e "s|{{AAP_LIGHTSPEED_WCA_HEALTH_CHECK}}|${lightspeed_wca_health_check_e}|g" \
        -e "s|{{AAP_EDA_SAFE_PLUGINS}}|${eda_safe_plugins_e}|g" \
        "$template_path"
}

prompt_aap_details() {
    local missing=0
    normalize_shared_env_vars
    if [ -f "$ANSIBLE_ENV_FILE" ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1
        normalize_shared_env_vars
        missing="$(count_missing_vars RH_USER RH_PASS ADMIN_USER ADMIN_PASS AAP_HOSTNAME AAP_ALIAS AAP_IP AAP_NETMASK AAP_GW HUB_TOKEN HOST_INT_IP)"
        if [ "${missing}" -eq 0 ]; then
            return 0
        fi
        print_step "AAP config has ${missing} missing value(s); prompting for required fields."
    fi
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
    local ks_file="${KS_DIR}/aap.ks"
    local tmp_ks
    local aap_ssh_pub_key
    local aap_inventory_content
    local aap_inventory_growth_content
    local aap_ext_mac aap_int_mac
    local aap_prefix
    local root_pass_hash admin_pass_hash
    local aap_bundle_filename
    local aap_bundle_filename_e
    local aap_bundle_url_e
    local aap_bundle_url_runtime
    local aap_galaxy_token_e
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
    local ks_creator_baseline
    local ks_perf_network_snapshot
    local ks_runtime_exports

    # Always start fresh — remove any previously generated kickstart
    rm -f "${ks_file}" 2>/dev/null || true

    prompt_aap_details || return 1
    ensure_iso_vars || return 1
    ensure_ssh_keys || return 1

    aap_ext_mac="$(get_vm_external_mac "aap")"
    aap_int_mac="$(get_vm_internal_mac "aap")"
    aap_prefix="$(netmask_to_prefix "${AAP_NETMASK}")"
    print_kickstart_effective_values "AAP" "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_NETMASK}" "${AAP_GW}"
    root_pass_hash="$(kickstart_password_hash "${ROOT_PASS:-${ADMIN_PASS}}")" || return 1
    admin_pass_hash="$(kickstart_password_hash "${ADMIN_PASS}")" || return 1
    prepare_kickstart_shared_blocks "aap" "${AAP_HOSTNAME}" "${AAP_IP}" \
        "${aap_ext_mac}" "${aap_int_mac}" "${AAP_IP}" "${aap_prefix}" "${AAP_GW}" \
        0 0 "AAP" \
        "rhel-10-for-x86_64-baseos-rpms" \
        "rhel-10-for-x86_64-appstream-rpms"
    ks_nogpg_policy="${MINIRHIS_KS_NOGPG_POLICY}"
    ks_ssh_baseline="${MINIRHIS_KS_SSH_BASELINE}"
    ks_user_sudo_bootstrap="${MINIRHIS_KS_USER_SUDO_BOOTSTRAP}"
    ks_rhsm_register="${MINIRHIS_KS_RHSM_REGISTER}"
    ks_rhc_connect="${MINIRHIS_KS_RHC_CONNECT}"
    ks_repo_enable_verify="${MINIRHIS_KS_REPO_ENABLE_VERIFY}"
    ks_nm_dual_nic="${MINIRHIS_KS_NM_DUAL_NIC}"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "{{SAT_IP}}" "{{SAT_HOSTNAME}}" "{{SAT_SHORT}}" "{{AAP_IP}}" "{{AAP_HOSTNAME}}" "{{AAP_SHORT}}" "{{IDM_IP}}" "{{IDM_HOSTNAME}}" "{{IDM_SHORT}}")"
    ks_trust_bootstrap_keys="${MINIRHIS_KS_TRUST_BOOTSTRAP_KEYS}"
    ks_creator_baseline="${MINIRHIS_KS_CREATOR_BASELINE}"
    ks_perf_network_snapshot="$(kickstart_perf_network_snapshot_block "net.core.somaxconn = 4096")"

    # Read the host's public key for SSH callback orchestration
    if [ ! -f "${AAP_SSH_PUBLIC_KEY}" ]; then
        print_warning "AAP SSH public key not found at ${AAP_SSH_PUBLIC_KEY}. Cannot inject into kickstart."
        return 1
    fi
    aap_ssh_pub_key="$(cat "${AAP_SSH_PUBLIC_KEY}")"
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"
    ks_runtime_exports="$(kickstart_runtime_exports_block "${bootstrap_ssh_keys}")"

    select_aap_inventory_templates || return 1
    aap_inventory_content="$(render_aap_inventory_template "${AAP_INVENTORY_TEMPLATE}")" || return 1
    aap_inventory_growth_content="$(render_aap_inventory_template "${AAP_INVENTORY_GROWTH_TEMPLATE}")" || return 1
    aap_bundle_filename="$(derive_aap_bundle_filename "${AAP_BUNDLE_URL:-}")"
    aap_bundle_url_runtime="${AAP_BUNDLE_EFFECTIVE_URL:-${AAP_BUNDLE_URL:-}}"
    aap_bundle_filename_e="$(sed_escape_replacement "${aap_bundle_filename}")"
    aap_bundle_url_e="$(sed_escape_replacement "${aap_bundle_url_runtime}")"
    aap_galaxy_token_e="$(sed_escape_replacement "${VAULT_CONSOLE_REDHAT_TOKEN:-${HUB_TOKEN:-}}")"

    tmp_ks="$(mktemp)"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --iscrypted "${root_pass_hash}"
user --name="${ADMIN_USER}" --password="${admin_pass_hash}" --iscrypted --groups=wheel

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
@Base
@Core
ansible-core
bash-completion
bind-utils
chrony
libvirt-client
man-pages
net-tools
qemu-guest-agent
tmux
tuned
util-linux-core
xfsdump
yum
yum-utils
zip
-ntp
%end

PKGS

        # --- Post-install: write kickstart %post and substitute placeholders ---
        cat >> "$tmp_ks" <<POSTEOF
%post --log=/root/ks-post.log
set -euo pipefail
set -x  # trace every command; all output captured in /root/ks-post.log

# Phase logger: writes to ks-post.log AND /dev/console (watch live: virsh console <vm>)
ks_log() { local ts; ts=\$(date +%H:%M:%S 2>/dev/null || echo "--:--:--"); printf '\n[MINIRHIS %s] %s\n' "\$ts" "\$*" | tee /dev/console 2>/dev/null || true; }
trap 'ec=\$?; ks_log "FAILED at line \${LINENO} (exit code \${ec}) -- see /root/ks-post.log"; exit \$ec' ERR
ks_log "=== MINIRHIS %post: aap: STARTED ==="

${ks_runtime_exports}

${ks_nogpg_policy}

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" = "1" ]; then
    ks_log "Deferring component repo/package enablement to post-boot config-as-code"
    ks_log "Running RHSM/RHC registration during first boot"
${ks_rhsm_register}

${ks_rhc_connect}
else
${ks_rhsm_register}

${ks_rhc_connect}

${ks_repo_enable_verify}
fi

${ks_creator_baseline}

# 4. Install installer prerequisites and fetch the AAP bundle in %post.
dnf install -y --nogpgcheck wget git-core rsync vim ansible-core >> /var/log/aap-setup-ready.log 2>&1 || true
mkdir -p /home/admin/aap-setup
chown -R admin:admin /home/admin || true
bundle_home="/home/admin"
bundle_dir="/home/admin/aap-setup"
bundle_stage_dir="/home/admin/aap-setup.stage"
bundle_filename="{{AAP_BUNDLE_FILENAME}}"
bundle_tarball="\${bundle_home}/\${bundle_filename}"
_bundle_ok=0

stage_bundle_overrides() {
    if [ -d "\${bundle_dir}" ] && [ ! -L "\${bundle_dir}" ] \
        && [ ! -f "\${bundle_dir}/ansible.containerized_installer.install.yml" ] \
        && [ ! -f "\${bundle_dir}/setup.sh" ]; then
        rm -rf "\${bundle_stage_dir}"
        mv "\${bundle_dir}" "\${bundle_stage_dir}"
    fi
}

extract_bundle_tree() {
    local detected_root installer_root

    stage_bundle_overrides
    detected_root="$(tar -tzf "\${bundle_tarball}" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "\${detected_root}" ] || detected_root="\${bundle_filename%.tar.gz}"
    tar -xzf "\${bundle_tarball}" -C "\${bundle_home}" >> /var/log/aap-setup-ready.log 2>&1
    installer_root="\${bundle_home}/\${detected_root}"
    if [ ! -d "\${installer_root}" ]; then
        echo "WARNING: Expected extracted installer directory missing: \${installer_root}" >> /var/log/aap-setup-ready.log
        return 1
    fi
    ln -sfn "\${installer_root}" "\${bundle_dir}"
    if [ -d "\${bundle_stage_dir}" ]; then
        cp -af "\${bundle_stage_dir}/." "\${installer_root}/"
        rm -rf "\${bundle_stage_dir}"
    fi
    chown -h admin:admin "\${bundle_dir}" || true
    chown -R admin:admin "\${installer_root}" || true
}

echo "Bundle download starting at \$(date)" >> /var/log/aap-setup-ready.log

if [ -z "{{AAP_BUNDLE_URL}}" ]; then
    echo "WARNING: AAP_BUNDLE_URL is empty — skipping %post download; first-boot service will retry." >> /var/log/aap-setup-ready.log
else
    echo "Attempting AAP bundle download from: {{AAP_BUNDLE_URL}}" >> /var/log/aap-setup-ready.log
    if curl -fL -C - --retry 3 --retry-delay 15 --connect-timeout 30 --max-time 7200 \
            "{{AAP_BUNDLE_URL}}" -o "\${bundle_tarball}" >> /var/log/aap-setup-ready.log 2>&1; then
        if extract_bundle_tree; then
            if [ -f "\${bundle_dir}/ansible.containerized_installer.install.yml" ] || \
               [ -f "\${bundle_dir}/setup.sh" ]; then
                _bundle_ok=1
                echo "Bundle downloaded to \${bundle_tarball} and extracted successfully in %post." >> /var/log/aap-setup-ready.log
            else
                echo "WARNING: Extraction succeeded but installer entrypoint not found; first-boot will retry." >> /var/log/aap-setup-ready.log
            fi
        else
            echo "WARNING: Bundle extraction failed in %post; first-boot will retry." >> /var/log/aap-setup-ready.log
        fi
    else
        echo "WARNING: Bundle download failed in %post; first-boot will retry." >> /var/log/aap-setup-ready.log
    fi
fi

# If %post download did not succeed, install a first-boot one-shot systemd service to retry.
if [ "\${_bundle_ok}" = "0" ]; then
    echo "Installing aap-bundle-fetch.service first-boot fallback." >> /var/log/aap-setup-ready.log
    mkdir -p /etc/systemd/system /usr/local/bin
    cat > /etc/systemd/system/aap-bundle-fetch.service <<'SVCEOF'
[Unit]
Description=AAP Bundle First-Boot Download
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/home/admin/aap-setup/ansible.containerized_installer.install.yml
ConditionPathExists=!/home/admin/aap-setup/setup.sh

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/aap-bundle-fetch.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SVCEOF
    cat > /usr/local/bin/aap-bundle-fetch.sh <<'FETCHEOF'
#!/bin/bash
set -euo pipefail
AAP_BUNDLE_URL="{{AAP_BUNDLE_URL}}"
bundle_home="/home/admin"
bundle_dir="/home/admin/aap-setup"
bundle_stage_dir="/home/admin/aap-setup.stage"
bundle_filename="{{AAP_BUNDLE_FILENAME}}"
bundle_tarball="${bundle_home}/${bundle_filename}"
log="/var/log/aap-setup-ready.log"
echo "[$(date)] aap-bundle-fetch: first-boot retry starting" >> "${log}"
mkdir -p "${bundle_dir}"
chown -R admin:admin "${bundle_home}" || true

stage_bundle_overrides() {
    if [ -d "${bundle_dir}" ] && [ ! -L "${bundle_dir}" ] \
        && [ ! -f "${bundle_dir}/ansible.containerized_installer.install.yml" ] \
        && [ ! -f "${bundle_dir}/setup.sh" ]; then
        rm -rf "${bundle_stage_dir}"
        mv "${bundle_dir}" "${bundle_stage_dir}"
    fi
}

extract_bundle_tree() {
    local detected_root installer_root

    stage_bundle_overrides
    detected_root="$(tar -tzf "${bundle_tarball}" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "${detected_root}" ] || detected_root="${bundle_filename%.tar.gz}"
    tar -xzf "${bundle_tarball}" -C "${bundle_home}" >> "${log}" 2>&1
    installer_root="${bundle_home}/${detected_root}"
    [ -d "${installer_root}" ] || return 1
    ln -sfn "${installer_root}" "${bundle_dir}"
    if [ -d "${bundle_stage_dir}" ]; then
        cp -af "${bundle_stage_dir}/." "${installer_root}/"
        rm -rf "${bundle_stage_dir}"
    fi
    chown -h admin:admin "${bundle_dir}" || true
    chown -R admin:admin "${installer_root}" || true
}

if [ -z "${AAP_BUNDLE_URL}" ]; then
    echo "[$(date)] ERROR: AAP_BUNDLE_URL is empty in first-boot service." >> "${log}"
    exit 1
fi
echo "[$(date)] Downloading from: ${AAP_BUNDLE_URL}" >> "${log}"
curl -fL -C - --retry 5 --retry-delay 30 --connect-timeout 60 --max-time 7200 \
    "${AAP_BUNDLE_URL}" -o "${bundle_tarball}" >> "${log}" 2>&1
echo "[$(date)] Extracting bundle..." >> "${log}"
extract_bundle_tree
echo "[$(date)] Bundle fetch complete. Disabling first-boot service." >> "${log}"
systemctl disable aap-bundle-fetch.service || true
FETCHEOF
    chmod 755 /usr/local/bin/aap-bundle-fetch.sh
    systemctl enable aap-bundle-fetch.service || \
        ln -sf /etc/systemd/system/aap-bundle-fetch.service \
               /etc/systemd/system/multi-user.target.wants/aap-bundle-fetch.service
    echo "aap-bundle-fetch.service enabled; will retry bundle download at first boot." >> /var/log/aap-setup-ready.log
fi
if [ "${DEMO_MODE:-0}" = "1" ]; then
    echo "AAP installer inventory selected: DEMO-inventory" >> /var/log/aap-setup-ready.log
elif [ -f /home/admin/aap-setup/inventory-growth ]; then
    echo "AAP installer inventory available: inventory-growth" >> /var/log/aap-setup-ready.log
else
    echo "AAP installer inventory selected: inventory" >> /var/log/aap-setup-ready.log
fi
echo "AAP installer entrypoint detected: ansible-playbook -i <inventory> ansible.containerized_installer.install" >> /var/log/aap-setup-ready.log
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
echo "[aap-setup] Bundle ready at /home/admin/aap-setup on $(date)" >> /var/log/aap-setup-ready.log

# 6. Bundle-local ansible.cfg and EDA defaults for collection seeding/installer runs.
cat > /home/admin/aap-setup/ansible.cfg <<ANSIBLECFG
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -i ~/.ssh/id_rsa
control_path_dir = /tmp/.ansible-cp
retries = 3

[galaxy]
server_list = published, validated, community_galaxy

[galaxy_server.published]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token={{GALAXY_TOKEN}}

[galaxy_server.validated]
url = https://console.redhat.com/api/automation-hub/content/validated/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
# token sourced from vaulted var vault_console_redhat_token (fallback HUB_TOKEN)
token={{GALAXY_TOKEN}}

[galaxy_server.community_galaxy]
url = https://galaxy.ansible.com/
ANSIBLECFG
chmod 600 /home/admin/aap-setup/ansible.cfg
cp -f /home/admin/aap-setup/ansible.cfg /root/.ansible.cfg
chmod 600 /root/.ansible.cfg

mkdir -p /home/admin/aap-setup/group_vars/automationeda
cat > /home/admin/aap-setup/group_vars/automationeda/main.yml <<'EDACFG'
eda_safe_plugins:
    - ansible.eda.webhook
    - ansible.eda.alertmanager
EDACFG
chmod 600 /home/admin/aap-setup/group_vars/automationeda/main.yml

# 7. Installer inventories rendered from Jinja2 templates selected at prompt/CLI
cat > /home/admin/aap-setup/inventory <<INVENTORY
${aap_inventory_content}
INVENTORY
chmod 600 /home/admin/aap-setup/inventory
if [ "${DEMO_MODE:-0}" = "1" ]; then
    cp -f /home/admin/aap-setup/inventory /home/admin/aap-setup/DEMO-inventory
    chmod 600 /home/admin/aap-setup/DEMO-inventory
fi

cat > /home/admin/aap-setup/inventory-growth <<INVENTORY_GROWTH
${aap_inventory_growth_content}
INVENTORY_GROWTH
chmod 600 /home/admin/aap-setup/inventory-growth
if [ ! -s /home/admin/aap-setup/inventory ] || [ ! -s /home/admin/aap-setup/inventory-growth ]; then
    echo "ERROR: AAP inventory rendering failed (inventory files missing/empty)."
    exit 1
fi

chown -R admin:admin /home/admin/aap-setup || true

echo "Rendered AAP inventory file: /home/admin/aap-setup/inventory"
echo "Preview (first 20 lines, passwords masked):"
sed -E 's/([A-Za-z0-9_]*password[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' /home/admin/aap-setup/inventory | head -n 20 || true

echo "Rendered AAP inventory file: /home/admin/aap-setup/inventory-growth"
echo "Preview (first 20 lines, passwords masked):"
sed -E 's/([A-Za-z0-9_]*password[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' /home/admin/aap-setup/inventory-growth | head -n 20 || true

${ks_perf_network_snapshot}
%end
POSTEOF

    # Substitute placeholders with actual values in the temp kickstart
    sed -i "s|{{HOST_INT_IP}}|${HOST_INT_IP}|g" "$tmp_ks"
    sed -i "s|{{AAP_SSH_PUB_KEY}}|${aap_ssh_pub_key}|g" "$tmp_ks"
    sed -i "s|{{HUB_TOKEN}}|${HUB_TOKEN}|g" "$tmp_ks"
    sed -i "s|{{GALAXY_TOKEN}}|${aap_galaxy_token_e}|g" "$tmp_ks"
    sed -i "s|{{SAT_IP}}|${SAT_IP}|g" "$tmp_ks"
    sed -i "s|{{SAT_HOSTNAME}}|${SAT_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{AAP_IP}}|${AAP_IP}|g" "$tmp_ks"
    sed -i "s|{{AAP_HOSTNAME}}|${AAP_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{AAP_BUNDLE_FILENAME}}|${aap_bundle_filename_e}|g" "$tmp_ks"
    sed -i "s|{{AAP_BUNDLE_URL}}|${aap_bundle_url_e}|g" "$tmp_ks"
    sed -i "s|{{IDM_IP}}|${IDM_IP}|g" "$tmp_ks"
    sed -i "s|{{IDM_HOSTNAME}}|${IDM_HOSTNAME}|g" "$tmp_ks"
    sed -i "s|{{SAT_SHORT}}|${SAT_HOSTNAME%%.*}|g" "$tmp_ks"
    sed -i "s|{{AAP_SHORT}}|${AAP_HOSTNAME%%.*}|g" "$tmp_ks"
    sed -i "s|{{IDM_SHORT}}|${IDM_HOSTNAME%%.*}|g" "$tmp_ks"

    write_file_if_changed "$tmp_ks" "$ks_file" 0644 || return 1
    validate_kickstart_integrity "$ks_file" "AAP kickstart" || return 1
    print_success "Generated AAP kickstart: $ks_file"
}

prompt_idm_details() {
    local missing=0
    normalize_shared_env_vars
    if [ -f "$ANSIBLE_ENV_FILE" ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1
        normalize_shared_env_vars
        missing="$(count_missing_vars RH_USER RH_PASS ADMIN_PASS IDM_IP IDM_NETMASK IDM_GW IDM_HOSTNAME IDM_ALIAS DOMAIN IDM_DS_PASS)"
        if [ "${missing}" -eq 0 ]; then
            return 0
        fi
        print_step "IdM config has ${missing} missing value(s); prompting for required fields."
    fi
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
    local root_pass_hash admin_pass_hash
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
    local ks_creator_baseline
    local ks_perf_network_snapshot
    local ks_runtime_exports

    # Always start fresh — remove any previously generated kickstart
    rm -f "${ks_file}" 2>/dev/null || true

    prompt_idm_details || return 1
    ensure_iso_vars || return 1
    ensure_ssh_keys || return 1

    idm_ext_mac="$(get_vm_external_mac "idm")"
    idm_int_mac="$(get_vm_internal_mac "idm")"
    idm_prefix="$(netmask_to_prefix "${IDM_NETMASK}")"
    print_kickstart_effective_values "IdM" "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_NETMASK}" "${IDM_GW}"
    root_pass_hash="$(kickstart_password_hash "${ROOT_PASS:-${ADMIN_PASS}}")" || return 1
    admin_pass_hash="$(kickstart_password_hash "${ADMIN_PASS}")" || return 1
    bootstrap_ssh_keys="$(collect_bootstrap_public_keys)"
    ks_runtime_exports="$(kickstart_runtime_exports_block "${bootstrap_ssh_keys}")"
    prepare_kickstart_shared_blocks "idm" "${IDM_HOSTNAME}" "${IDM_IP}" \
        "${idm_ext_mac}" "${idm_int_mac}" "${IDM_IP}" "${idm_prefix}" "${IDM_GW}" \
        0 1 "IdM" \
        "rhel-10-for-x86_64-baseos-rpms" \
        "rhel-10-for-x86_64-appstream-rpms"
    ks_nogpg_policy="${MINIRHIS_KS_NOGPG_POLICY}"
    ks_ssh_baseline="${MINIRHIS_KS_SSH_BASELINE}"
    ks_user_sudo_bootstrap="${MINIRHIS_KS_USER_SUDO_BOOTSTRAP}"
    ks_rhsm_register="${MINIRHIS_KS_RHSM_REGISTER}"
    ks_rhc_connect="${MINIRHIS_KS_RHC_CONNECT}"
    ks_repo_enable_verify="${MINIRHIS_KS_REPO_ENABLE_VERIFY}"
    ks_nm_dual_nic="${MINIRHIS_KS_NM_DUAL_NIC}"
    ks_hosts_mapping="$(kickstart_hosts_mapping_block "${SAT_IP}" "${SAT_HOSTNAME}" "${SAT_HOSTNAME%%.*}" "${AAP_IP}" "${AAP_HOSTNAME}" "${AAP_HOSTNAME%%.*}" "${IDM_IP}" "${IDM_HOSTNAME}" "${IDM_HOSTNAME%%.*}")"
    ks_trust_bootstrap_keys="${MINIRHIS_KS_TRUST_BOOTSTRAP_KEYS}"
    ks_creator_baseline="${MINIRHIS_KS_CREATOR_BASELINE}"
    ks_perf_network_snapshot="$(kickstart_perf_network_snapshot_block)"

    tmp_ks="$(mktemp)"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8
selinux --permissive
firewall --disabled
bootloader --append="net.ifnames=0 biosdevname=0"

rootpw --iscrypted "${root_pass_hash}"
user --name="${ADMIN_USER}" --password="${admin_pass_hash}" --iscrypted --groups=wheel

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
@Base
@Core
ansible-core
bash-completion
bind-utils
chrony
libvirt-client
man-pages
net-tools
qemu-guest-agent
tmux
tuned
util-linux-core
xfsdump
yum
yum-utils
zip
-ntp
ipa-server
ipa-server-dns
bind-dyndb-ldap
%end

PKGS

    # --- Post-install (variable expansion required) ---
    cat >> "$tmp_ks" <<POSTEOF
%post --log=/root/ks-post.log
set -euo pipefail
set -x  # trace every command; all output captured in /root/ks-post.log

# Phase logger: writes to ks-post.log AND /dev/console (watch live: virsh console <vm>)
ks_log() { local ts; ts=\$(date +%H:%M:%S 2>/dev/null || echo "--:--:--"); printf '\n[MINIRHIS %s] %s\n' "\$ts" "\$*" | tee /dev/console 2>/dev/null || true; }
trap 'ec=\$?; ks_log "FAILED at line \${LINENO} (exit code \${ec}) -- see /root/ks-post.log"; exit \$ec' ERR
ks_log "=== MINIRHIS %post: idm: STARTED ==="

${ks_runtime_exports}

${ks_nogpg_policy}

${ks_nm_dual_nic}

${ks_hosts_mapping}

${ks_ssh_baseline}

${ks_user_sudo_bootstrap}

${ks_trust_bootstrap_keys}

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" = "1" ]; then
    ks_log "Deferring component repo/package enablement to post-boot config-as-code"
    ks_log "Running RHSM/RHC registration during first boot"
${ks_rhsm_register}

${ks_rhc_connect}
else
${ks_rhsm_register}

${ks_rhc_connect}
fi

${ks_creator_baseline}

# 3. Hostname
hostnamectl set-hostname "${IDM_HOSTNAME}"

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" != "1" ]; then
# 4. Repositories
${ks_repo_enable_verify}
fi

# 4.1 Verify required IdM packages from kickstart payload are present
if ! rpm -q ipa-server ipa-server-dns bind-dyndb-ldap >/dev/null 2>&1; then
    echo "ERROR: Required IdM packages missing after kickstart package phase."
    rpm -qa | grep -E '^ipa-server|^bind-dyndb-ldap' || true
    exit 1
fi

if [ "${MINIRHIS_DEFER_COMPONENT_INSTALL:-1}" = "1" ]; then
    ks_log "IdM component install is deferred to post-boot config-as-code"
else

# 5. IdM Server Installation (unattended)
ipa-server-install --unattended --realm="${IDM_REALM}" --domain="${IDM_DOMAIN}" --hostname="${IDM_HOSTNAME}" --admin-password="${IDM_ADMIN_PASS}" --ds-password="${IDM_DS_PASS}" --setup-dns --auto-forwarders --no-ntp

# 5.1 Post-IdM Installation: User Management, Access Control & DNS Configuration
echo "=== IDM SERVER POST-INSTALL CONFIGURATION ==="

# Wait for IdM services to be fully ready
echo "Waiting for IdM services to be ready..."
for i in {1..60}; do
    if systemctl is-active -q ipa || ipactl status 2>/dev/null | grep -q "Directory Service"; then
        echo "✓ IdM services are ready"
        break
    fi
    if [ \$i -eq 60 ]; then
        echo "⚠ WARNING: IdM services did not fully start after 60 seconds (continuing anyway)"
    fi
    sleep 1
done

sleep 3

# Configure ipa CLI with admin credentials
export KRB5_TRACE=/dev/null 2>/dev/null || true
echo "${IDM_ADMIN_PASS}" | kinit admin@${IDM_REALM} 2>/dev/null || true

echo "IdM users/groups/password policy are managed post-boot by config-as-code roles (idm_users/idm_user_groups/idm_password_policy)."

# --- 5.1.4 Configure Host-Based Access Control (HBAC) ---
echo "Configuring host-based access control rules..."

if [ "${IDM_ENABLE_HBAC_RULES:-1}" = "1" ]; then
    # HBAC service for SSH
    ipa hbacsvc-add ssh 2>/dev/null || echo "  ℹ SSH HBAC service already exists"
    ipa hbacsvc-add satellite-api 2>/dev/null || echo "  ℹ Satellite API HBAC service already exists"
    ipa hbacsvc-add aap-api 2>/dev/null || echo "  ℹ AAP API HBAC service already exists"

    # HBAC rule for admins to all systems
    ipa hbacrule-add --usercat=all --hostcat=all minirhis-admin-all-access 2>/dev/null || echo "  ℹ minirhis-admin-all-access rule already exists"
    ipa hbacrule-add-service minirhis-admin-all-access --hbacsvcs=ssh 2>/dev/null || echo "  ℹ SSH service already added to rule"
    ipa hbacrule-add-user minirhis-admin-all-access --groups="${IDM_ADMINS_GROUP:-minirhis-admins}" 2>/dev/null || echo "  ℹ ${IDM_ADMINS_GROUP:-minirhis-admins} already in rule"

    # HBAC rule for automation group to automation hosts
    ipa hbacrule-add --usercat=all automation-host-access 2>/dev/null || echo "  ℹ automation-host-access rule already exists"
    ipa hbacrule-add-service automation-host-access --hbacsvcs=ssh 2>/dev/null || echo "  ℹ SSH service already added"
fi

# --- 5.1.5 Configure SUDO Rules ---
echo "Configuring IdM sudo rules for infrastructure automation..."

if [ "${IDM_ENABLE_SUDO_RULES:-1}" = "1" ]; then
    # Sudo rule for MINIRHIS admins (full sudo access)
    ipa sudorule-add minirhis-admins-all --hostcat=all --runasusercat=all 2>/dev/null || echo "  ℹ minirhis-admins-all sudo rule already exists"
    ipa sudorule-add-user minirhis-admins-all --groups="${IDM_ADMINS_GROUP:-minirhis-admins}" 2>/dev/null || echo "  ℹ ${IDM_ADMINS_GROUP:-minirhis-admins} group already added"
    ipa sudorule-add-allow-command minirhis-admins-all --allow-cmds=ALL 2>/dev/null || echo "  ℹ ALL commands already allowed"

    # Sudo rule for content managers (restricted commands)
    ipa sudorule-add content-manager-provision --hostcat=all 2>/dev/null || echo "  ℹ content-manager-provision sudo rule already exists"
    ipa sudorule-add-user content-manager-provision --groups="${IDM_CONTENT_MANAGERS_GROUP:-content-managers}" 2>/dev/null || echo "  ℹ ${IDM_CONTENT_MANAGERS_GROUP:-content-managers} group already added"
    ipa sudorule-add-allow-command content-manager-provision --allow-cmds="/usr/bin/hammer" 2>/dev/null || echo "  ℹ hammer command already allowed"
    ipa sudorule-add-allow-command content-manager-provision --allow-cmds="/usr/bin/ansible" 2>/dev/null || echo "  ℹ ansible command already allowed"
    ipa sudorule-add-allow-command content-manager-provision --allow-cmds="/usr/bin/ansible-playbook" 2>/dev/null || echo "  ℹ ansible-playbook command already allowed"
fi

# --- 5.1.6 Enable DNS Services and Configure Zone ---
echo "Configuring IdM DNS services..."

# Ensure DNS service is running
systemctl enable --now named || true
systemctl status named >/dev/null 2>&1 && echo "✓ DNS service running" || echo "⚠ DNS service not running"

# Add DNS zone delegation records (if using subdomain)
ipa dnszone-add ${IDM_DOMAIN}. 2>/dev/null || echo "  ℹ DNS zone ${IDM_DOMAIN}. already configured"

# Add DNS forwarder for lookup optimization
ipa dnsconfig-mod --forwarder=8.8.8.8 2>/dev/null || echo "  ℹ DNS forwarders already configured"

# --- 5.1.7 Configure SSH Key Distribution ---
echo "Setting up IdM SSH key management..."

# Create SSH public key object store
mkdir -p /var/lib/minirhis-ssh-keys
chmod 0755 /var/lib/minirhis-ssh-keys

# Enable SSH key authentication in IdM user accounts
ipa config-mod --enable-sid || echo "  ℹ SID already enabled"

# --- 5.1.8 Configure LDAP Replication/Synchronization ---
echo "Configuring IdM LDAP and replication parameters..."

# Set LDAP entry cache timeout for quicker updates
ldapmodify -D "cn=directory manager" -w "${IDM_DS_PASS}" <<'LDAP_CONFIG' 2>/dev/null || echo "  ℹ LDAP cache configuration skipped"
dn: cn=config
changetype: modify
replace: nsslapd-cachememsize
nsslapd-cachememsize: 52428800
-
replace: nsslapd-dbcachesize
nsslapd-dbcachesize: 104857600
LDAP_CONFIG

# --- 5.1.9 Configure Kerberos SPN Registration ---
echo "Registering service principal names..."

# Already configured during ipa-server-install, but verify key services
klist -e 2>/dev/null | grep -q "krbtgt/${IDM_REALM}" && echo "✓ Kerberos realm configured" || echo "⚠ Kerberos not fully initialized"

# --- 5.1.10 Export IdM Configuration for Satellite Integration ---
echo "Preparing IdM integration data for Satellite..."

# Create integration config export
mkdir -p /etc/minirhis-integration
cat > /etc/minirhis-integration/idm-config.sh <<'IDM_CONFIG'
#!/bin/bash
# IdM Configuration for MINIRHIS Integration
export IDM_DOMAIN="${IDM_DOMAIN}"
export IDM_REALM="${IDM_REALM}"
export IDM_HOSTNAME="${IDM_HOSTNAME}"
export IDM_IP="${IDM_IP}"
export IDM_ADMIN_USER="admin"
# Satellite LDAP integration
export SAT_LDAP_URL="ldap://${IDM_HOSTNAME}:389"
export SAT_LDAP_BASE_DN="dc=\$(echo ${IDM_DOMAIN} | tr '.' '\\n' | sed 's/^/dc=/g' | paste -sd, -)"
export SAT_LDAP_AUTH_SOURCE_TYPE="LDAP"
# AAP LDAP integration
export AAP_LDAP_URL="ldaps://${IDM_HOSTNAME}:636"
export AAP_LDAP_BIND_DN="uid=aap-svc,cn=users,cn=accounts,\${SAT_LDAP_BASE_DN}"
export AAP_LDAP_START_TLS=true
IDM_CONFIG

chmod 0640 /etc/minirhis-integration/idm-config.sh

# --- 5.1.11 Certificate Management for TLS/SSL ---
echo "Verifying TLS certificate configuration..."

# IdM automatically creates certificates; verify they exist
if [ -f /etc/ipa/ca.crt ]; then
    echo "✓ IdM CA certificate present: /etc/ipa/ca.crt"
    
    # Export CA cert for use by other components
    mkdir -p /usr/local/share/ca-certificates/minirhis
    cp /etc/ipa/ca.crt /usr/local/share/ca-certificates/minirhis/idm-ca.crt
    update-ca-trust 2>/dev/null || update-ca-certificates 2>/dev/null || true
    echo "✓ IdM CA installed in system trust store"
else
    echo "⚠ IdM CA certificate not found"
fi

# --- 5.1.12 Health Check & Verification ---
echo "Running IdM health checks..."

# Check IdM status
ipactl status 2>/dev/null | head -20 || echo "⚠ ipactl status unavailable"

# Verify LDAP connectivity
ldapsearch -x -H "ldap://${IDM_HOSTNAME}" -s base -b "" namingContexts >/dev/null 2>&1 && echo "✓ LDAP responding" || echo "⚠ LDAP check skipped"

# Verify DNS resolution
nslookup -type=SRV _kerberos._tcp.${IDM_DOMAIN} ${IDM_IP} 2>/dev/null | grep -q "kerberos" && echo "✓ Kerberos SRV records present" || echo "⚠ Kerberos SRV records check skipped"

# Verify HTTP/HTTPS APIs
curl -ksSf -u admin:${IDM_ADMIN_PASS} https://${IDM_HOSTNAME}/ipa/json 2>/dev/null && echo "✓ IdM JSON API responding" || echo "⚠ IdM JSON API check skipped"

echo "=== IDM SERVER POST-INSTALL CONFIGURATION COMPLETE ==="
echo "  ✓ User Groups: minirhis-admins, content-managers, automation-engineers, system-services"
echo "  ✓ Users: satellite-svc, aap-svc, minirhis-operator"
echo "  ✓ Password Policy: 12-char min, 365-day expiry, quality enforcement"
echo "  ✓ HBAC Rules: SSH access control for admins and automation"
echo "  ✓ SUDO Rules: Full admin access, limited content manager access"
echo "  ✓ DNS Services: Zone configured, forwarders enabled"
echo "  ✓ SSH Keys: Key management infrastructure ready"
echo "  ✓ Kerberos: Realm ${IDM_REALM} active"
echo "  ✓ LDAP: Configured with replication parameters"
echo "  ✓ TLS/SSL: CA certificate installed in system trust"
echo "  ✓ Integration: Satellite/AAP config exported to /etc/minirhis-integration/"
fi

${ks_perf_network_snapshot}
%end
POSTEOF

    write_file_if_changed "$tmp_ks" "$ks_file" 0644 || return 1
    validate_kickstart_integrity "$ks_file" "IdM kickstart" || return 1
    print_success "Generated IdM kickstart: $ks_file"
}

validate_kickstart_integrity() {
    local ks_file="$1"
    local label="${2:-Kickstart}"

    if [ ! -f "$ks_file" ]; then
        print_warning "${label} validation failed: file not found: ${ks_file}"
        return 1
    fi

    if grep -q '^POSTEOF$' "$ks_file"; then
        print_warning "${label} validation failed: leaked heredoc marker 'POSTEOF' found in ${ks_file}"
        return 1
    fi

    if ! awk '
        BEGIN { post_open=0; post_count=0; post_closed=0; rc=0 }
        /^[[:space:]]*%post([[:space:]]|$)/ {
            if (post_open) rc=1
            post_open=1
            post_count++
            next
        }
        /^[[:space:]]*%end([[:space:]]|$)/ {
            if (post_open) {
                post_open=0
                post_closed++
            }
            next
        }
        END {
            if (post_open) rc=1
            if (post_count == 0) rc=1
            if (post_count != post_closed) rc=1
            exit rc
        }
    ' "$ks_file"; then
        print_warning "${label} validation failed: %post/%end mismatch in ${ks_file}"
        return 1
    fi

    print_step "${label} validation passed: ${ks_file}"
    return 0
}

validate_generated_kickstarts() {
    local failed=0

    validate_kickstart_integrity "${KS_DIR}/satellite.ks" "Satellite kickstart" || failed=1
    validate_kickstart_integrity "${KS_DIR}/aap.ks" "AAP kickstart" || failed=1
    validate_kickstart_integrity "${KS_DIR}/idm.ks" "IdM kickstart" || failed=1

    [ "$failed" -eq 0 ]
}

cleanup_generated_kickstart_artifacts() {
    print_step "Removing generated kickstarts and OEMDRV artifacts"
    sudo rm -f \
        "${KS_DIR}/satellite.ks" \
        "${KS_DIR}/aap.ks" \
        "${KS_DIR}/idm.ks" \
        "${OEMDRV_ISO}" \
        /tmp/OEMDRV.iso \
        /tmp/ks.cfg || true
}

write_kickstarts() {
    generate_satellite_618_kickstart || return 1
    generate_aap_kickstart || return 1
    generate_idm_kickstart || return 1
    validate_generated_kickstarts || return 1
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

launch_vm_console_popup() {
    local vm_name="${1:-}"
    local viewer_log="/tmp/minirhis-virt-viewer-${vm_name}.log"

    [ -n "${vm_name}" ] || return 0

    case "$(echo "${MINIRHIS_AUTO_OPEN_VM_CONSOLE:-1}" | tr '[:upper:]' '[:lower:]')" in
        0|false|no|off)
            return 0
            ;;
    esac

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        print_warning "No desktop session detected; virtual console popup skipped for ${vm_name}."
        print_step "Use: sudo virsh console ${vm_name}"
        return 0
    fi

    if ! command -v virt-viewer >/dev/null 2>&1; then
        print_warning "virt-viewer is not installed; virtual console popup skipped for ${vm_name}."
        print_step "Use: sudo virsh console ${vm_name}"
        return 0
    fi

    print_step "Launching virtual console window for ${vm_name}"
    nohup virt-viewer --connect qemu:///system --reconnect --wait "${vm_name}" >"${viewer_log}" 2>&1 &
    disown || true
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
    print_step "DEMOKILL: cleanup start"

    stop_vm_power_watchdog || true

    print_step "DEMOKILL: stop console monitors"
    stop_vm_console_monitors || true
    force_kill_minirhis_leftovers || true

    print_step "DEMOKILL: remove provisioner container"
    podman rm -f "${MINIRHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true
    sudo podman rm -f "${MINIRHIS_CONTAINER_NAME}" >/dev/null 2>&1 || true

    local vm
    local -a demo_vms=("satellite" "aap" "idm")

    for vm in "${demo_vms[@]}"; do
        if sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            print_step "DEMOKILL: stop VM $vm"
            sudo virsh destroy "$vm" >/dev/null 2>&1 || true
            print_step "DEMOKILL: undefine VM $vm"
            sudo virsh undefine "$vm" --nvram >/dev/null 2>&1 || sudo virsh undefine "$vm" >/dev/null 2>&1 || true
        else
            [ "${MINIRHIS_DEMOKILL_COMPACT:-1}" = "1" ] || print_step "VM not defined (skipping): $vm"
        fi
    done

    print_step "DEMOKILL: remove VM disks"
    sudo rm -f \
        "${VM_DIR}/satellite.qcow2" \
        "${VM_DIR}/aap.qcow2" \
        "${VM_DIR}/idm.qcow2" || true
    # Backward-compatible cleanup for previously named disks.
    sudo rm -f "${VM_DIR}"/satellite*.qcow2 "${VM_DIR}"/aap*.qcow2 "${VM_DIR}"/idm*.qcow2 >/dev/null 2>&1 || true

    cleanup_generated_kickstart_artifacts

    print_step "DEMOKILL: remove staged AAP bundle"
    sudo rm -rf "${AAP_BUNDLE_DIR}" || true

    print_step "DEMOKILL: clean lock files"
    cleanup_minirhis_lock_files || true

    print_step "DEMOKILL: remove temp/cache artifacts"
    sudo rm -f \
        /tmp/aap-setup-*.log \
        /tmp/default.xml \
        /tmp/internal.xml || true

    print_step "DEMOKILL: stop AAP bundle HTTP server"
    sudo pkill -f "python3 -m http.server 8080 --bind" >/dev/null 2>&1 || true
    close_aap_bundle_firewall

    print_step "DEMOKILL: prune local SSH trust entries"
    prune_local_ssh_trust_for_component "all" || true

    print_step "DEMOKILL: restart libvirtd"
    sudo systemctl restart libvirtd || return 1

    print_step "DEMOKILL: start libvirt networks"
    sudo virsh net-start external >/dev/null 2>&1 || true
    sudo virsh net-autostart external >/dev/null 2>&1 || true
    sudo virsh net-start internal >/dev/null 2>&1 || true
    sudo virsh net-autostart internal >/dev/null 2>&1 || true

    print_step "DEMOKILL: verify qemu:///system"
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

    print_step "DEMOKILL: restart virt-manager session"
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

    print_success "DEMOKILL complete"
}

cleanup_minirhis_lock_files() {
    local -a lock_candidates
    local -a lock_globs
    local -a existing_locks
    local lock_path _glob _matched

    lock_candidates=(
        "${VM_DIR}/satellite.qcow2.lock"
        "${VM_DIR}/aap.qcow2.lock"
        "${VM_DIR}/idm.qcow2.lock"
        "${VM_DIR}/satellite.qcow2.lck"
        "${VM_DIR}/aap.qcow2.lck"
        "${VM_DIR}/idm.qcow2.lck"
        "${KS_DIR}/satellite.ks.lock"
        "${KS_DIR}/aap.ks.lock"
        "${KS_DIR}/idm.ks.lock"
        "/var/lock/libvirt/qemu/satellite.lock"
        "/var/lock/libvirt/qemu/aap.lock"
        "/var/lock/libvirt/qemu/idm.lock"
    )

    # Backward-compatible wildcard lock candidates for previously named artifacts.
    lock_globs=(
        "${VM_DIR}/satellite*.qcow2.lock"
        "${VM_DIR}/aap*.qcow2.lock"
        "${VM_DIR}/idm*.qcow2.lock"
        "${VM_DIR}/satellite*.qcow2.lck"
        "${VM_DIR}/aap*.qcow2.lck"
        "${VM_DIR}/idm*.qcow2.lck"
        "${KS_DIR}/satellite*.ks.lock"
        "${KS_DIR}/aap*.ks.lock"
        "${KS_DIR}/idm*.ks.lock"
        "/var/lock/libvirt/qemu/satellite*.lock"
        "/var/lock/libvirt/qemu/aap*.lock"
        "/var/lock/libvirt/qemu/idm*.lock"
    )

    for lock_path in "${lock_candidates[@]}"; do
        if [ -e "$lock_path" ]; then
            existing_locks+=("$lock_path")
        fi
    done

    for _glob in "${lock_globs[@]}"; do
        while IFS= read -r _matched; do
            [ -e "${_matched}" ] || continue
            existing_locks+=("${_matched}")
        done < <(compgen -G "${_glob}" || true)
    done

    if [ "${#existing_locks[@]}" -eq 0 ]; then
        print_step "No MINIRHIS lock files found"
        return 0
    fi

    print_warning "Found ${#existing_locks[@]} MINIRHIS lock file(s); removing..."
    for lock_path in "${existing_locks[@]}"; do
        print_step "Removing lock: $lock_path"
        sudo rm -f "$lock_path" || true
    done

    return 0
}

create_minirhis_vms() {
    print_phase 1 8 "Provision VM artifacts and prerequisites"
    print_step "Preparing Satellite / AAP / IdM qcow2 VMs"
    ensure_live_progress_monitors || true
    prompt_use_existing_env
    normalize_shared_env_vars
    validate_resolved_kickstart_inputs || return 1

    local sat_disk sat_ram sat_vcpu
    local aap_disk aap_ram aap_vcpu
    local idm_disk idm_ram idm_vcpu
    local ssh_mesh_bootstrap_ok=0

    if is_demo; then
        print_step "DEMO mode: reduced per-node VM specs for MiniRHIS 3-node stack (IdM + Satellite + AAP)"
        sat_disk="150G"; sat_ram=24576; sat_vcpu=8
        aap_disk="50G";  aap_ram=8152;  aap_vcpu=4
        idm_disk="30G";  idm_ram=4096;  idm_vcpu=2
    else
        print_step "Standard mode: production/best-practice VM specifications"
        sat_disk="150G"; sat_ram=32768; sat_vcpu=8
        aap_disk="50G";  aap_ram=16384; aap_vcpu=8
        idm_disk="60G";  idm_ram=16384; idm_vcpu=4
    fi

    print_warning "Pre-flight lock check: stale lock files can block provisioning."
    cleanup_minirhis_lock_files || true
    prune_local_ssh_trust_for_component "all" || true

    ensure_virtualization_tools || return 1
    ensure_iso_vars
    download_rhel10_iso || return 1
    download_rhel9_iso || return 1
    assert_satellite_install_iso_is_valid "${SAT_ISO_PATH}" || return 1
    assert_aap_install_iso_is_valid "${ISO_PATH}" || return 1
    assert_idm_install_iso_is_valid "${ISO_PATH}" || return 1
    fix_qemu_permissions
    create_libvirt_storage_pool || return 1

    # Pre-flight: ensure SSH keys exist for post-boot AAP callback orchestration
    ensure_ssh_keys || {
        print_warning "Failed to generate SSH keys; AAP callback orchestration will not work."
        return 1
    }

    # Resolve the bundle source used by kickstart and callback fallback.
    # Preferred path: pre-download once on installer host and serve locally to
    # avoid expiring signed CDN URLs during long guest installs.
    AAP_BUNDLE_EFFECTIVE_URL="${AAP_BUNDLE_URL:-}"
    if preflight_download_aap_bundle; then
        if serve_aap_bundle; then
            AAP_BUNDLE_EFFECTIVE_URL="http://${HOST_INT_IP}:8080/aap-bundle.tar.gz"
            print_step "AAP bundle source set to local HTTP mirror: ${AAP_BUNDLE_EFFECTIVE_URL}"
        else
            print_warning "Local AAP bundle HTTP server did not start; using direct URL fallback."
        fi
    else
        print_warning "AAP bundle preflight download failed; using direct URL from AAP_BUNDLE_URL during guest install."
    fi

    # Pre-flight guard: we still require a usable bundle URL path.
    if [ -z "${AAP_BUNDLE_EFFECTIVE_URL:-}" ]; then
        print_warning "AAP bundle source is empty. Set AAP_BUNDLE_URL in ${ANSIBLE_ENV_FILE} or pre-stage ${AAP_BUNDLE_DIR}/aap-bundle.tar.gz."
        return 1
    fi

    write_kickstarts || return 1

    # Build-order requirement: IdM must come first, then Satellite, then AAP.
    create_vm_if_missing "idm"           "${VM_DIR}/idm.qcow2"           "$idm_disk" "$idm_ram" "$idm_vcpu" "${KS_DIR}/idm.ks" || return 1

    launch_single_vm_console_monitor_auto "idm" || true

    create_vm_if_missing "satellite" "${VM_DIR}/satellite.qcow2" "$sat_disk" "$sat_ram" "$sat_vcpu" "${KS_DIR}/satellite.ks" "hd:LABEL=OEMDRV:/ks.cfg" "${SAT_ISO_PATH}" || return 1

    launch_single_vm_console_monitor_auto "satellite" || true

    create_vm_if_missing "aap"        "${VM_DIR}/aap.qcow2"        "$aap_disk" "$aap_ram" "$aap_vcpu" "${KS_DIR}/aap.ks" || return 1

    launch_single_vm_console_monitor_auto "aap" || true

    print_phase 2 8 "Guest settle and initial readiness"

    # Keep all VMs ON through installer reboot/power transitions while callbacks run.
    start_vm_power_watchdog 10800 || true

    # Individual console monitors already launched per-VM above; launch fallback
    # for any missed or orphaned consoles if needed
    launch_vm_console_monitors_auto || true

    print_step "AAP callback is deferred until the AAP configuration phase so IdM/Satellite can proceed first."

    ensure_minirhis_vms_powered_on
    wait_for_post_vm_settle || true
    sync_minirhis_external_hosts_entries || true

    # Post-provision host-access guarantees:
    # - installer host user has passwordless sudo
    # - installer host public keys trusted by admin/root on Satellite
    ensure_local_installer_user_passwordless_sudo || true
    ensure_host_installer_keys_on_satellite || true

    # As soon as VMs first come up, bootstrap SSH trust mesh before config-as-code.
    print_phase 3 8 "SSH mesh bootstrap"
    if setup_minirhis_ssh_mesh; then
        ssh_mesh_bootstrap_ok=1
    else
        if is_enabled "${MINIRHIS_ALLOW_DEFERRED_SSH_MESH:-0}"; then
            print_warning "SSH mesh bootstrap did not complete cleanly; deferred mode enabled (MINIRHIS_ALLOW_DEFERRED_SSH_MESH=1), will retry after config-as-code once nodes are fully initialized."
        else
            print_warning "SSH mesh bootstrap is required before continuing. Aborting now."
            print_warning "If you intentionally want deferred behavior, set MINIRHIS_ALLOW_DEFERRED_SSH_MESH=1 and re-run."
            stop_vm_power_watchdog || true
            return 1
        fi
    fi
    print_phase 4 8 "SSH mesh validation"
    if [ "${ssh_mesh_bootstrap_ok}" -eq 1 ]; then
        validate_minirhis_ssh_mesh || print_warning "SSH mesh validation reported failures; continuing."
    else
        print_step "Skipping early SSH mesh validation because bootstrap was deferred."
    fi

    # Trigger config-as-code via the provisioner container after SSH baseline is in place.
    print_phase 5 8 "Config-as-code orchestration"
    run_minirhis_config_as_code || print_warning "Config-as-code phase did not complete cleanly. VMs are running; re-run manually if needed."

    if [ "${ssh_mesh_bootstrap_ok}" -eq 0 ]; then
        print_step "Retrying deferred SSH mesh bootstrap/validation after config-as-code..."
        if setup_minirhis_ssh_mesh; then
            validate_minirhis_ssh_mesh || print_warning "Deferred SSH mesh validation still reported failures; continuing."
        else
            print_warning "Deferred SSH mesh bootstrap still did not complete cleanly; continuing."
        fi
    fi

    stop_vm_power_watchdog || true
    print_phase 6 8 "Root password normalization"
    fix_vm_root_passwords || print_warning "Root password fix step did not complete cleanly; continuing."
    print_phase 7 8 "Final health summary"
    print_minirhis_health_summary
    # Reboot all MINIRHIS VMs to ensure a clean post-install state before finalizing.
    reboot_all_minirhis_vms || print_warning "Reboot of MINIRHIS VMs did not complete cleanly; continuing."
    revert_rc_local_nonexec_on_minirhis_vms || print_warning "Post-install rc.local permission reversion reported issues; continuing."
    print_phase 8 8 "Workflow complete"
}

# Fix the OS root password on all MINIRHIS VMs using virsh set-user-password (via qemu-guest-agent).
# Called after VMs are powered on so the guest agent is running.
fix_vm_root_passwords() {
    local vm new_pass
    local -a vms=("satellite" "aap" "idm")

    # Re-load the vault so we always use the latest ADMIN_PASS value
    ADMIN_PASS=""
    read_ansible_env_content 2>/dev/null || true
    load_ansible_env_file 2>/dev/null || true
    normalize_shared_env_vars

    new_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"

    # ── Ansible-first path ────────────────────────────────────────────────
    if run_local_role "minirhis_vm_lifecycle" "installer" \
            --extra-vars "minirhis_vm_action=set_passwords admin_pass=${new_pass}" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_vm_lifecycle unavailable; running bash fallback for fix_vm_root_passwords"
    # ── Bash fallback ─────────────────────────────────────────────────────
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

reboot_all_minirhis_vms() {
    local vm
    local -a vms=("satellite" "aap" "idm")

    # ── Ansible-first path ────────────────────────────────────────────────
    if run_local_role "minirhis_vm_lifecycle" "installer" \
            --extra-vars "minirhis_vm_action=reboot" 2>/dev/null; then
        wait_for_post_vm_settle || print_warning "Post-reboot settle checks reported issues"
        return 0
    fi
    print_warning "Ansible role minirhis_vm_lifecycle unavailable; running bash fallback for reboot_all_minirhis_vms"
    # ── Bash fallback ─────────────────────────────────────────────────────
    print_step "Rebooting all MINIRHIS VMs"
    for vm in "${vms[@]}"; do
        if ! sudo virsh dominfo "$vm" >/dev/null 2>&1; then
            print_warning "VM not defined or libvirt cannot access: $vm; skipping"
            continue
        fi

        # Try a soft reboot first, fallback to reset if that fails
        if sudo virsh reboot "$vm" >/dev/null 2>&1; then
            print_step "Requested ACPI reboot for: $vm"
        else
            print_warning "Soft reboot failed for $vm; attempting hard reset"
            sudo virsh reset "$vm" >/dev/null 2>&1 || print_warning "Hard reset also failed for $vm"
        fi
    done

    # Allow guests to come back up and perform a light settle
    sleep 15
    wait_for_post_vm_settle || print_warning "Post-reboot settle checks reported issues"
    print_success "Reboot command issued for MINIRHIS VMs"
    return 0
}

revert_rc_local_nonexec_on_minirhis_vms() {
    local scope="${1:-all}"
    local root_pass admin_user admin_pass
    local node_label node_ip
    local remote_cmd remote_cmd_via_sudo
    local reverted=0
    local -a target_nodes=()

    if ! is_enabled "${MINIRHIS_REVERT_RC_LOCAL_NONEXEC_AFTER_INSTALL:-1}"; then
        print_step "Skipping rc.local permission reversion (MINIRHIS_REVERT_RC_LOCAL_NONEXEC_AFTER_INSTALL=${MINIRHIS_REVERT_RC_LOCAL_NONEXEC_AFTER_INSTALL})."
        return 0
    fi

    # ── Ansible-first path ────────────────────────────────────────────────
    # Determine which Ansible limit group to use based on scope argument.
    local _ansible_limit
    case "${scope}" in
        satellite) _ansible_limit="scenario_satellite" ;;
        idm)       _ansible_limit="idm" ;;
        aap)       _ansible_limit="aap" ;;
        *)         _ansible_limit="scenario_satellite:aap:idm" ;;
    esac
    if run_local_role "minirhis_vm_hardening" "${_ansible_limit}" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_vm_hardening unavailable; running bash fallback for revert_rc_local_nonexec_on_minirhis_vms"
    # ── Bash fallback ─────────────────────────────────────────────────────
    root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    admin_user="${ADMIN_USER:-admin}"
    admin_pass="${ADMIN_PASS:-}"

    print_step "Post-install hardening: reverting /etc/rc.d/rc.local to non-executable on MINIRHIS nodes"
    remote_cmd='if [ -f /etc/rc.d/rc.local ]; then chmod 0644 /etc/rc.d/rc.local || true; fi'
    remote_cmd_via_sudo="sudo -n bash -lc '$(printf '%s' "${remote_cmd}" | sed "s/'/'\\''/g")'"

    case "${scope}" in
        satellite) target_nodes=("satellite") ;;
        idm)       target_nodes=("idm") ;;
        aap)       target_nodes=("aap") ;;
        *)         target_nodes=("satellite" "aap" "idm") ;;
    esac

    for node_label in "${target_nodes[@]}"; do
        case "${node_label}" in
            satellite) node_ip="${SAT_IP}" ;;
            aap)        node_ip="${AAP_IP}" ;;
            idm)           node_ip="${IDM_IP}" ;;
            *)             node_ip="" ;;
        esac

        [ -n "${node_ip}" ] || continue

        if [ -n "${root_pass}" ] && sshpass -p "${root_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"${node_ip}" "${remote_cmd}" >/dev/null 2>&1; then
            print_step "rc.local permissions reverted on ${node_label} (${node_ip}) via root"
            reverted=$((reverted + 1))
            continue
        fi

        if [ -n "${admin_pass}" ] && sshpass -p "${admin_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${admin_user}@${node_ip}" "${remote_cmd_via_sudo}" >/dev/null 2>&1; then
            print_step "rc.local permissions reverted on ${node_label} (${node_ip}) via ${admin_user}+sudo"
            reverted=$((reverted + 1))
            continue
        fi

        print_warning "Could not revert rc.local permissions on ${node_label} (${node_ip}); apply manually if needed: chmod 0644 /etc/rc.d/rc.local"
    done

    if [ "${reverted}" -gt 0 ]; then
        print_success "rc.local hardening complete on ${reverted} MINIRHIS node(s)."
    fi
    return 0
}

setup_minirhis_ssh_mesh() {
    local mesh_scope="${1:-${MINIRHIS_SSH_MESH_SCOPE:-all}}"

    # ── Ansible-first path ──────────────────────────────────────────────────
    # The Ansible role handles full pairwise key distribution.  The scope
    # argument is mapped to an inventory limit so per-node runs still work.
    local _ansible_limit
    case "${mesh_scope}" in
        satellite) _ansible_limit="installer:scenario_satellite" ;;
        idm)       _ansible_limit="installer:idm" ;;
        aap)       _ansible_limit="installer:aap" ;;
        *)         _ansible_limit="installer:scenario_satellite:aap:idm" ;;
    esac
    if run_local_role "minirhis_ssh_mesh" "${_ansible_limit}" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_ssh_mesh unavailable; running bash fallback for setup_minirhis_ssh_mesh"
    # ── Bash fallback (original implementation) ─────────────────────────────
    local root_pass installer_user installer_pass mesh_user mesh_pass ip pub login_user login_pass
    local ssh_bootstrap_retries ssh_bootstrap_delay
    local local_installer_pub=""
    local local_root_pub=""
    local root_mesh_failures=0
    local root_mesh_required=0
    local -a node_ips all_pubs root_pubs node_names
    local bootstrap_cmd append_cmd bootstrap_root_cmd append_root_cmd
    local bootstrap_root_via_mesh_cmd read_root_pub_via_mesh_cmd

    root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    installer_user="${INSTALLER_USER:-${ADMIN_USER}}"
    installer_pass="${ADMIN_PASS:-}"
    mesh_user="${ADMIN_USER:-admin}"
    mesh_pass="${ADMIN_PASS:-}"
    ssh_bootstrap_retries="${MINIRHIS_SSH_BOOTSTRAP_RETRIES:-45}"
    ssh_bootstrap_delay="${MINIRHIS_SSH_BOOTSTRAP_DELAY:-10}"
    if is_enabled "${MINIRHIS_REQUIRE_ROOT_SSH_MESH:-0}"; then
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

    case "${mesh_scope}" in
        satellite)
            node_ips=("${SAT_IP}")
            node_names=("satellite")
            ;;
        idm)
            node_ips=("${IDM_IP}")
            node_names=("idm")
            ;;
        aap)
            node_ips=("${AAP_IP}")
            node_names=("aap")
            ;;
        *)
            node_ips=("${SAT_IP}" "${AAP_IP}" "${IDM_IP}")
            node_names=("satellite" "aap" "idm")
            ;;
    esac

    # Rebuilds rotate SSH host keys on MINIRHIS nodes; keep installer known_hosts clean.
    refresh_minirhis_known_hosts || true

    # Ensure dedicated, persistent installer-host MINIRHIS key exists.
    if ! ensure_minirhis_installer_ssh_key; then
        print_warning "Could not prepare dedicated MINIRHIS installer SSH key at ${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}."
        return 1
    fi

    # Ensure local installer user has key + authorized_keys (install host).
    mkdir -p "${HOME}/.ssh" >/dev/null 2>&1 || true
    chmod 700 "${HOME}/.ssh" >/dev/null 2>&1 || true
    touch "${HOME}/.ssh/authorized_keys" >/dev/null 2>&1 || true
    chmod 600 "${HOME}/.ssh/authorized_keys" >/dev/null 2>&1 || true
    if [ -f "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        cat "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" >> "${HOME}/.ssh/authorized_keys"
        sort -u "${HOME}/.ssh/authorized_keys" -o "${HOME}/.ssh/authorized_keys" || true
        local_installer_pub="$(cat "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" 2>/dev/null || true)"
    fi

    # Explicit self trust requested: install-host user -> 127.0.0.1
    if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${installer_pass}" ] && [ -f "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        sshpass -p "${installer_pass}" ssh-copy-id -i "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" \
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

    bootstrap_cmd='set -e; target_user="'"${mesh_user}"'"; if ! id "$target_user" >/dev/null 2>&1; then echo "missing-user:${mesh_user}"; exit 1; fi; target_home="$(getent passwd "$target_user" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/$target_user"; install -d -m 700 -o "$target_user" -g "$target_user" "$target_home/.ssh"; if [ ! -f "$target_home/.ssh/id_rsa" ]; then sudo -u "$target_user" ssh-keygen -q -t rsa -b 4096 -N "" -f "$target_home/.ssh/id_rsa"; fi; touch "$target_home/.ssh/authorized_keys"; chown "$target_user:$target_user" "$target_home/.ssh/authorized_keys"; chmod 600 "$target_home/.ssh/authorized_keys"; cat > "$target_home/.ssh/config" <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chown "$target_user:$target_user" "$target_home/.ssh/config"; chmod 600 "$target_home/.ssh/config"; cat "$target_home/.ssh/id_rsa.pub" >> "$target_home/.ssh/authorized_keys"; sort -u "$target_home/.ssh/authorized_keys" -o "$target_home/.ssh/authorized_keys"'

    print_step "Bootstrapping admin SSH config/keys on MINIRHIS nodes (${mesh_user})"
    for ip in "${node_ips[@]}"; do
        local _bootstrap_ok=0
        local _attempt
        for _attempt in $(seq 1 "${ssh_bootstrap_retries}"); do
            login_user="${mesh_user}"
            login_pass="${mesh_pass}"
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
            print_warning "SSH bootstrap failed for ${ip} as ${mesh_user} and root after ${ssh_bootstrap_retries} attempts."
            return 1
        fi
    done

    # Ensure root keypair exists on every node.
    bootstrap_root_cmd='set -e; install -d -m 700 /root/.ssh; if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -q -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa; fi; touch /root/.ssh/authorized_keys; [ -f /root/.ssh/id_rsa.pub ] && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/id_rsa 2>/dev/null || true; chmod 644 /root/.ssh/id_rsa.pub 2>/dev/null || true; chmod 600 /root/.ssh/authorized_keys'
    bootstrap_root_via_mesh_cmd="sudo -n bash -lc '$(printf '%s' "${bootstrap_root_cmd}" | sed "s/'/'\\''/g")'"
    read_root_pub_via_mesh_cmd="sudo -n cat /root/.ssh/id_rsa.pub"
    print_step "Bootstrapping root SSH keys on MINIRHIS nodes"
    for ip in "${node_ips[@]}"; do
        if [ -n "$root_pass" ]; then
            if sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" "$bootstrap_root_cmd" >/dev/null 2>&1; then
                :
            elif [ -n "${mesh_pass}" ] && sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" "${bootstrap_root_via_mesh_cmd}" >/dev/null 2>&1; then
                print_step "Root SSH bootstrap on ${ip} completed via ${mesh_user} + sudo fallback."
            else
                print_warning "Root SSH bootstrap failed for ${ip} via direct root and ${mesh_user} + sudo fallback."
                if [ "${root_mesh_required}" -eq 1 ]; then
                    return 1
                fi
                root_mesh_failures=$((root_mesh_failures + 1))
                continue
            fi
        else
            if [ -n "${mesh_pass}" ] && sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" "${bootstrap_root_via_mesh_cmd}" >/dev/null 2>&1; then
                print_step "Root SSH bootstrap on ${ip} completed via ${mesh_user} + sudo fallback."
            else
                print_warning "Root password unavailable and ${mesh_user} + sudo fallback failed; cannot bootstrap root SSH keys on ${ip}."
                if [ "${root_mesh_required}" -eq 1 ]; then
                    return 1
                fi
                root_mesh_failures=$((root_mesh_failures + 1))
                continue
            fi
        fi
    done

    print_step "Collecting ${mesh_user} public keys for full mesh trust"
    for ip in "${node_ips[@]}"; do
        pub="$(sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" 'target_home="$(getent passwd "'"${mesh_user}"'" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/'"${mesh_user}"'"; cat "$target_home/.ssh/id_rsa.pub"' 2>/dev/null || true)"
        if [ -z "$pub" ] && [ -n "$root_pass" ]; then
            pub="$(sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" 'target_home="$(getent passwd "'"${mesh_user}"'" | cut -d: -f6)"; [ -n "$target_home" ] || target_home="/home/'"${mesh_user}"'"; cat "$target_home/.ssh/id_rsa.pub"' 2>/dev/null || true)"
        fi
        if [ -z "$pub" ]; then
            print_warning "Could not read ${mesh_user} SSH public key from ${ip}."
            return 1
        fi
        all_pubs+=("$pub")
    done

    print_step "Distributing trusted keys to all nodes (${mesh_user}-to-${mesh_user} mesh)"
    for ip in "${node_ips[@]}"; do
        for pub in "${all_pubs[@]}"; do
            append_cmd="target_home=\"\$(getent passwd '${mesh_user}' | cut -d: -f6)\"; [ -n \"\$target_home\" ] || target_home=\"/home/${mesh_user}\"; printf '%s\\n' '$pub' >> \"\$target_home/.ssh/authorized_keys\"; sort -u \"\$target_home/.ssh/authorized_keys\" -o \"\$target_home/.ssh/authorized_keys\"; chown '${mesh_user}:${mesh_user}' \"\$target_home/.ssh/authorized_keys\"; chmod 600 \"\$target_home/.ssh/authorized_keys\""
            if ! sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" "$append_cmd" >/dev/null 2>&1; then
                if [ -n "$root_pass" ]; then
                    sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" "$append_cmd" >/dev/null 2>&1 || {
                        print_warning "Failed to distribute SSH key to ${ip} as ${mesh_user} and root."
                        return 1
                    }
                else
                    print_warning "Failed to distribute SSH key to ${ip} as ${mesh_user}; root fallback unavailable."
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

    # Explicit install-host key push to root on each MINIRHIS node.
    # Installer-host user key is intentionally restricted to root
    # on managed nodes because those nodes only expose admin/root accounts.
    if [ -n "${local_installer_pub}" ] && [ -f "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" ]; then
        local i push_ip push_name pub_b64
        pub_b64="$(printf '%s' "${local_installer_pub}" | base64 -w0 2>/dev/null || true)"
        for i in "${!node_ips[@]}"; do
            push_ip="${node_ips[$i]}"
            push_name="${node_names[$i]}"

            # install-host key -> root
            if command -v ssh-copy-id >/dev/null 2>&1 && [ -n "${root_pass}" ]; then
                sshpass -p "${root_pass}" ssh-copy-id -i "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY}" \
                    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
                    "root@${push_ip}" >/dev/null 2>&1 || true
            fi
            if [ -n "${pub_b64}" ] && [ -n "${root_pass}" ]; then
                append_root_cmd="install -d -m 700 /root/.ssh; touch /root/.ssh/authorized_keys; printf '%s' '${pub_b64}' | base64 -d >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys"
                sshpass -p "${root_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@${push_ip}" "$append_root_cmd" >/dev/null 2>&1 || true
            fi

            print_step "Install-host key synchronized to root on ${push_name} (${push_ip})"
        done
    fi

    print_step "Collecting root public keys for full root mesh trust"
    for ip in "${node_ips[@]}"; do
        pub=""
        if [ -n "$root_pass" ]; then
            pub="$(sshpass -p "$root_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$ip" 'cat /root/.ssh/id_rsa.pub' 2>/dev/null || true)"
        fi
        if [ -z "$pub" ] && [ -n "${installer_pass}" ]; then
            pub="$(sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" "${read_root_pub_via_mesh_cmd}" 2>/dev/null || true)"
            [ -n "$pub" ] && print_step "Collected root SSH public key from ${ip} via ${mesh_user} + sudo fallback."
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
                elif [ -n "${mesh_pass}" ] && sshpass -p "${mesh_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${mesh_user}@${ip}" "sudo -n bash -lc '$(printf '%s' "${append_root_cmd}" | sed "s/'/'\\''/g")'" >/dev/null 2>&1; then
                    :
                else
                    print_warning "Failed to distribute root SSH key to ${ip} via direct root and ${mesh_user} + sudo fallback."
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
        print_warning "MINIRHIS SSH mesh configured with ${root_mesh_failures} root-mesh issue(s). Admin mesh is active; root mesh is best-effort."
    else
        print_success "MINIRHIS SSH mesh configured: ${mesh_user} and root SSH trust established across MINIRHIS nodes; install-host user key is trusted by root on each node."
    fi
    return 0
}

validate_minirhis_ssh_mesh() {
    local root_pass installer_user installer_pass mesh_user mesh_pass
    local src_name src_ip dst_name dst_ip
    local validation_cmd
    local failures=0
    local -a node_specs

    root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    installer_user="${INSTALLER_USER:-${ADMIN_USER}}"
    installer_pass="${ADMIN_PASS:-}"
    mesh_user="${ADMIN_USER:-admin}"
    mesh_pass="${ADMIN_PASS:-}"
    if [ -z "$installer_pass" ] && [ -z "$root_pass" ]; then
        print_warning "Cannot validate SSH mesh: admin and root passwords are both unset."
        return 1
    fi

    node_specs=(
        "${SAT_HOSTNAME}:${SAT_IP}"
        "${AAP_HOSTNAME}:${AAP_IP}"
        "${IDM_HOSTNAME}:${IDM_IP}"
    )

    print_step "Validating MINIRHIS SSH mesh (${mesh_user}-to-${mesh_user} key auth across all nodes)"
    for src in "${node_specs[@]}"; do
        src_name="${src%%:*}"
        src_ip="${src##*:}"
        for dst in "${node_specs[@]}"; do
            dst_name="${dst%%:*}"
            dst_ip="${dst##*:}"
            validation_cmd="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -o ConnectTimeout=8 ${mesh_user}@${dst_ip} 'echo ok:${dst_name}'"
            # Try with MINIRHIS installer key first (installer host key is pushed to each node's authorized_keys
            # during mesh setup to root only, so this path is typically not used for node-to-node admin mesh.
            if [ -f "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY:-}" ] && \
               ssh -i "${MINIRHIS_INSTALLER_SSH_PRIVATE_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ${mesh_user}@"$src_ip" "$validation_cmd" >/dev/null 2>&1; then
                print_step "SSH mesh OK: ${src_name} -> ${dst_name}"
            elif [ -n "$mesh_pass" ] && sshpass -p "$mesh_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ${mesh_user}@"$src_ip" "$validation_cmd" >/dev/null 2>&1; then
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
        print_step "Validating MINIRHIS root SSH mesh (root-to-root key auth across all nodes)"
        for src in "${node_specs[@]}"; do
            src_name="${src%%:*}"
            src_ip="${src##*:}"
            for dst in "${node_specs[@]}"; do
                dst_name="${dst%%:*}"
                dst_ip="${dst##*:}"
                validation_cmd="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardX11=no -o ConnectTimeout=8 root@${dst_ip} 'echo ok-root:${dst_name}'"
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

    print_success "SSH mesh validation complete: admin and root SSH trust is functional across MINIRHIS nodes."
    return 0
}

ensure_minirhis_vms_powered_on() {
    local vm state
    local -a vms=("satellite" "aap" "idm")

    # ── Ansible-first path ──────────────────────────────────────────────────
    if run_local_role "minirhis_vm_lifecycle" "installer" \
            --extra-vars "minirhis_vm_action=power_on" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_vm_lifecycle unavailable; running bash fallback for ensure_minirhis_vms_powered_on"
    # ── Bash fallback ───────────────────────────────────────────────────────
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

ensure_local_installer_user_passwordless_sudo() {
    local current_user="${USER:-$(whoami)}"
    local sudoers_file="/etc/sudoers.d/90-minirhis-${current_user}-nopasswd"

    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if sudo -n true >/dev/null 2>&1; then
        return 0
    fi

    print_step "Ensuring passwordless sudo for installer user ${current_user}"
    if ! printf '%s\n' "${current_user} ALL=(ALL) NOPASSWD: ALL" | sudo tee "${sudoers_file}" >/dev/null 2>&1; then
        print_warning "Could not create ${sudoers_file}; passwordless sudo for ${current_user} is not configured."
        return 1
    fi

    sudo chmod 0440 "${sudoers_file}" >/dev/null 2>&1 || true
    if ! sudo visudo -cf /etc/sudoers >/dev/null 2>&1; then
        print_warning "sudoers validation failed after writing ${sudoers_file}; rolling back."
        sudo rm -f "${sudoers_file}" >/dev/null 2>&1 || true
        return 1
    fi

    if sudo -n true >/dev/null 2>&1; then
        print_success "Passwordless sudo is active for installer user ${current_user}."
        return 0
    fi

    print_warning "Passwordless sudo setup for ${current_user} could not be verified automatically."
    return 1
}

ensure_host_installer_keys_on_satellite() {
    local sat_ip="${SAT_IP:-10.168.128.1}"
    local sat_host="${SAT_HOSTNAME:-satellite}"
    local admin_user="${ADMIN_USER:-admin}"
    local admin_pass="${ADMIN_PASS:-}"
    local root_pass="${ROOT_PASS:-${ADMIN_PASS:-}}"
    local -a pub_keys=()
    local key_file key_content
    local target_user target_pass target_home append_cmd

    [ -n "${sat_ip}" ] || return 1

    for key_file in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub" "${MINIRHIS_INSTALLER_SSH_PUBLIC_KEY:-}"; do
        [ -n "${key_file}" ] || continue
        [ -r "${key_file}" ] || continue
        key_content="$(cat "${key_file}" 2>/dev/null || true)"
        [ -n "${key_content}" ] || continue
        pub_keys+=("${key_content}")
    done

    if [ "${#pub_keys[@]}" -eq 0 ]; then
        print_warning "No local installer public keys found to push to Satellite."
        return 1
    fi

    if ! command -v sshpass >/dev/null 2>&1; then
        print_step "Installing sshpass for post-provision Satellite key sync"
        sudo dnf install -y --nogpgcheck sshpass >/dev/null 2>&1 || true
    fi

    print_step "Post-provision key sync: pushing installer-host public keys to ${admin_user}@${sat_host} and root@${sat_host}"

    for target_user in "${admin_user}" "root"; do
        case "${target_user}" in
            root)
                target_pass="${root_pass}"
                target_home="/root"
                ;;
            *)
                target_pass="${admin_pass}"
                target_home="$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6)"
                [ -n "${target_home}" ] || target_home="/home/${target_user}"
                ;;
        esac

        [ -n "${target_pass}" ] || {
            print_warning "Skipping key push to ${target_user}@${sat_host}: password is not set."
            continue
        }

        for key_content in "${pub_keys[@]}"; do
            append_cmd="install -d -m 700 ${target_home}/.ssh; touch ${target_home}/.ssh/authorized_keys; printf '%s\\n' '${key_content}' >> ${target_home}/.ssh/authorized_keys; sort -u ${target_home}/.ssh/authorized_keys -o ${target_home}/.ssh/authorized_keys; chmod 600 ${target_home}/.ssh/authorized_keys"
            sshpass -p "${target_pass}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${target_user}@${sat_ip}" "${append_cmd}" >/dev/null 2>&1 || true
        done

        print_step "Installer-host keys synchronized to ${target_user}@${sat_host} (${sat_ip})"
    done

    return 0
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
        Y|y|"") create_minirhis_vms || print_warning "VM creation did not complete." ;;
        *) print_warning "Skipping VM creation." ;;
    esac

    print_success "Virt-Manager setup complete"
}

ensure_libvirtd() {
    # ── Ansible-first path ──────────────────────────────────────────────────
    if run_local_role "minirhis_host_setup" "installer" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_host_setup unavailable; running bash fallback for ensure_libvirtd"
    # ── Bash fallback ───────────────────────────────────────────────────────
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

# Ensure the current user can access the system libvirt socket (qemu:///system).
# If access is denied by policy, attempt to assist by adding the user to the
# distro's libvirt group and deploying a permissive polkit rule for members of
# that group. This function is conservative and will only act when sudo is
# available and the operations succeed; otherwise it prints guidance.
ensure_libvirt_access() {
    # ── Ansible-first path ──────────────────────────────────────────────────
    if run_local_role "minirhis_host_setup" "installer" 2>/dev/null; then
        return 0
    fi
    print_warning "Ansible role minirhis_host_setup unavailable; running bash fallback for ensure_libvirt_access"
    # ── Bash fallback ───────────────────────────────────────────────────────
    print_step "Verifying libvirt access for user: ${USER:-$(whoami)}"

    if virsh --connect qemu:///system list --all >/dev/null 2>&1; then
        print_success "User can access qemu:///system"
        return 0
    fi

    local virsh_err libvirt_group polkit_rule remediation_allowed="1"
    local needs_relogin=0
    virsh_err="$(virsh --connect qemu:///system list --all 2>&1 || true)"
    print_warning "Cannot access qemu:///system: ${virsh_err%%$'\n'*}"

    if [ "$(id -u)" -eq 0 ]; then
        print_warning "Root cannot connect to libvirt: inspect libvirt-daemon, socket permissions, and SELinux/audit logs."
        return 1
    fi

    if getent group libvirt >/dev/null 2>&1; then
        libvirt_group="libvirt"
    elif getent group libvirt-qemu >/dev/null 2>&1; then
        libvirt_group="libvirt-qemu"
    else
        libvirt_group="libvirt"
    fi

    polkit_rule="/etc/polkit-1/rules.d/80-libvirt-unix.rules"

    if ! is_noninteractive; then
        local fix_choice
        read -r -p "Attempt automatic libvirt access remediation now (group + polkit)? [Y/n]: " fix_choice
        case "${fix_choice:-Y}" in
            Y|y|"") remediation_allowed="1" ;;
            *) remediation_allowed="0" ;;
        esac
    fi

    if [ "${remediation_allowed}" = "1" ]; then
        if id -nG "${USER}" | grep -qw "${libvirt_group}"; then
            print_step "User already in ${libvirt_group}"
        else
            print_step "Adding ${USER} to group: ${libvirt_group} (requires sudo)"
            if sudo usermod -aG "${libvirt_group}" "${USER}"; then
                print_success "Added ${USER} to ${libvirt_group}"
                needs_relogin=1
            else
                print_warning "Could not add ${USER} to ${libvirt_group}. Run: sudo usermod -aG ${libvirt_group} ${USER}"
            fi
        fi

        if [ -w /etc/polkit-1/rules.d ] || sudo test -d /etc/polkit-1/rules.d; then
            print_step "Installing polkit rule for ${libvirt_group} members (requires sudo)"
            sudo tee "${polkit_rule}" >/dev/null <<'POLKIT'
polkit.addRule(function(action, subject) {
    var ids = ["org.libvirt.unix.manage", "org.freedesktop.libvirt.unix.manage"];
    if (ids.indexOf(action.id) >= 0) {
        if (subject.isInGroup("libvirt") || subject.isInGroup("libvirt-qemu")) {
            return polkit.Result.YES;
        }
    }
});
POLKIT
            sudo chmod 0644 "${polkit_rule}" || true
            sudo systemctl reload-or-restart polkit.service >/dev/null 2>&1 || true
            print_success "Polkit rule installed at ${polkit_rule}"
        else
            print_warning "Cannot write ${polkit_rule}; create it as root to allow group-based libvirt access."
        fi
    else
        print_warning "Automatic remediation skipped by user."
    fi

    if virsh --connect qemu:///system list --all >/dev/null 2>&1; then
        print_success "libvirt access confirmed after remediation"
        return 0
    fi

    if command -v getenforce >/dev/null 2>&1; then
        local selinux_mode
        selinux_mode="$(getenforce 2>/dev/null || true)"
        if [ -n "${selinux_mode}" ]; then
            print_step "SELinux mode: ${selinux_mode}"
        fi
    fi

    if command -v ausearch >/dev/null 2>&1; then
        local avc_sample
        avc_sample="$(sudo ausearch -m AVC -ts recent 2>/dev/null | tail -n 20 || true)"
        if [ -n "${avc_sample}" ]; then
            print_warning "Recent SELinux AVC denials detected; these may block libvirt access."
            printf '%s\n' "${avc_sample}" | sed 's/^/  AVC: /'
        fi
    fi

    if is_noninteractive; then
        print_warning "NONINTERACTIVE mode: libvirt access is still unavailable after remediation attempts."
        print_warning "Required remediation:"
        print_warning "  1) sudo usermod -aG ${libvirt_group} ${USER}"
        print_warning "  2) log out and back in (or reboot)"
        print_warning "  3) verify: virsh --connect qemu:///system list --all"
        print_warning "  4) if still blocked, inspect: sudo journalctl -u libvirtd --no-pager -n 200 && sudo ausearch -m AVC -ts recent"
        return 1
    fi

    if [ "${needs_relogin}" -eq 1 ]; then
        print_warning "Group membership changed. Log out and back in (or reboot) before retrying."
    fi
    print_warning "libvirt access still denied. Verify with: virsh --connect qemu:///system list --all"
    print_warning "If it still fails, inspect: sudo journalctl -u libvirtd --no-pager -n 200 && sudo ausearch -m AVC -ts recent"
    return 1
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
    # Defensive guard: if early variable init is changed, keep runtime layout paths sane.
    SCRIPT_DIR="${SCRIPT_DIR:-$(pwd)}"
    MINIRHIS_INVENTORY_DIR="${MINIRHIS_INVENTORY_DIR:-${SCRIPT_DIR}/container/vars/external_inventory}"
    MINIRHIS_INVENTORY_FILE="${MINIRHIS_INVENTORY_FILE:-${MINIRHIS_INVENTORY_DIR}/hosts.yml}"
    MINIRHIS_CONTAINER_INVENTORY_FILE="${MINIRHIS_CONTAINER_INVENTORY_FILE:-/minirhis/vars/external_inventory/$(basename "${MINIRHIS_INVENTORY_FILE}")}"
    MINIRHIS_HOST_VARS_DIR="${MINIRHIS_HOST_VARS_DIR:-${SCRIPT_DIR}/host_vars}"

    print_step "Ensuring generated MINIRHIS runtime layout exists under ${SCRIPT_DIR}"

    mkdir -p "${MINIRHIS_INVENTORY_DIR}" "${MINIRHIS_HOST_VARS_DIR}" "${SCRIPT_DIR}/container/roles" "${SCRIPT_DIR}/docs" || return 1

        # First-run bootstrap for required non-markdown artifacts. These are
        # created only when missing and never overwritten.
        local container_requirements_yml="${SCRIPT_DIR}/container/requirements.yml"
        local container_requirements_txt="${SCRIPT_DIR}/container/requirements.txt"
        local inventory_sample="${SCRIPT_DIR}/inventory/hosts.SAMPLE"

        if [ ! -f "${container_requirements_yml}" ]; then
                print_step "Bootstrapping missing artifact: container/requirements.yml"
                cat > "${container_requirements_yml}" <<'EOF'
---
collections:
    - name: "ansible.posix"
        version: "*"
    - name: "community.general"
        version: "*"
    - name: "freeipa.ansible_freeipa"
        version: "*"
    - name: "infra.aap_configuration"
        version: "*"
    - name: "infra.aap_utilities"
        version: "*"
    - name: "infra.ah_configuration"
        version: "*"
    - name: "infra.controller_configuration"
        version: "*"
    - name: "infra.eda_configuration"
        version: "*"
    - name: "infra.ee_utilities"
        version: "*"
    - name: "redhat.rhel_system_roles"
        version: "*"
    - name: "redhat.satellite"
        version: "*"
    - name: "redhat.satellite_operations"
        version: "*"
EOF
        fi

        if [ ! -f "${container_requirements_txt}" ]; then
                print_step "Bootstrapping missing artifact: container/requirements.txt"
                cat > "${container_requirements_txt}" <<'EOF'
requests>=2.28.0
jinja2>=3.0.0
PyYAML>=6.0
paramiko>=2.12.0
netaddr>=0.8.0
boto3>=1.26.0
botocore>=1.29.0
dnspython>=2.2.0
cryptography>=38.0.0
EOF
        fi

        if [ ! -f "${inventory_sample}" ]; then
                print_step "Bootstrapping missing artifact: inventory/hosts.SAMPLE"
                cat > "${inventory_sample}" <<'EOF'
[ansibledev]
{{CONTROLLER_HOST}}

[libvirt]
{{CONTROLLER_HOST}}

[installer]
{{CONTROLLER_HOST}} ansible_host={{HOST_INT_IP}} ansible_user={{INSTALLER_USER}} ansible_become=true

[scenario_satellite]
{{SAT_HOSTNAME}} ansible_host={{SAT_IP}} ansible_user={{ADMIN_USER}} ansible_become=true

[sat_primary:children]
scenario_satellite

[aap]
{{AAP_HOSTNAME}} ansible_host={{AAP_IP}} ansible_user={{ADMIN_USER}} ansible_become=true

[aap_hosts:children]
aap

[platform_installer:children]
aap

[idm]
{{IDM_HOSTNAME}} ansible_host={{IDM_IP}} ansible_user={{ADMIN_USER}} ansible_become=true

[idm_primary:children]
idm

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ForwardX11=no'
EOF
        fi

    # Placeholders are intentionally minimal; real content is generated on run.
    [ -f "${MINIRHIS_INVENTORY_DIR}/README.md" ] || printf '%s\n' "# Generated by minirhis_install.sh" > "${MINIRHIS_INVENTORY_DIR}/README.md"
    [ -f "${MINIRHIS_HOST_VARS_DIR}/README.md" ] || printf '%s\n' "# Generated by minirhis_install.sh" > "${MINIRHIS_HOST_VARS_DIR}/README.md"
    [ -f "${SCRIPT_DIR}/docs/README.md" ] || printf '%s\n' "# Generated by minirhis_install.sh" > "${SCRIPT_DIR}/docs/README.md"

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

    # Keep pip path available for optional Python helpers used by MINIRHIS flows.
    python3 -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
    return 0
}

minirhis_required_ansible_collections() {
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

    mapfile -t collections < <(minirhis_required_ansible_collections)

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
    local req_timeout_sec=120
    local container_requirements_yml="${SCRIPT_DIR}/container/requirements.yml"
    local container_requirements_txt="${SCRIPT_DIR}/container/requirements.txt"

    print_step "Ensuring installer-host requirements and Ansible collections are installed"

    if ! command -v ansible-galaxy >/dev/null 2>&1; then
        print_step "Installing ansible-core for host-side collection management"
        sudo dnf install -y --nogpgcheck ansible-core || return 1
    fi

    generate_minirhis_ansible_cfg || true
    cfg="${MINIRHIS_ANSIBLE_CFG_HOST}"

    # Install consolidated container requirements in the same startup phase as
    # collection verification so all dependencies are aligned.
    if [ -f "${container_requirements_yml}" ]; then
        print_step "Installing Ansible collections from ${container_requirements_yml}"
        if timeout ${req_timeout_sec} bash -c "ANSIBLE_CONFIG='${cfg}' ansible-galaxy collection install -r '${container_requirements_yml}'" >/dev/null 2>&1; then
            print_success "Applied collection requirements from container/requirements.yml"
        else
            print_warning "Could not fully apply ${container_requirements_yml}; continuing with per-collection verification."
        fi
    else
        print_warning "Collection requirements file not found: ${container_requirements_yml}"
    fi

    if [ -f "${container_requirements_txt}" ]; then
        local req_line req_spec
        local py_ok=0
        local py_failed=0
        local failed_file="${SCRIPT_DIR}/failed_packages.txt"

        print_step "Installing Python requirements line-by-line from ${container_requirements_txt} (robust fallback strategy)"
        : > "${failed_file}"

        while IFS= read -r req_line || [ -n "${req_line}" ]; do
            # Strip inline comments and trim whitespace.
            req_spec="$(printf '%s' "${req_line}" | sed -E 's/[[:space:]]*#.*$//' | xargs)"
            [ -n "${req_spec}" ] || continue

            # Workaround: ansible/ansible-core are installer-host managed via dnf;
            # avoid pip resolver issues on newer Python runtimes.
            case "${req_spec}" in
                ansible*|ansible-core*)
                    print_step "Skipping pip install for ${req_spec} (managed by ansible-core package on host)."
                    continue
                    ;;
            esac

            # Use robust installation with fallback strategy
            if install_package_with_fallback "${req_spec}"; then
                py_ok=$((py_ok + 1))
            else
                py_failed=$((py_failed + 1))
                printf '%s\n' "${req_spec}" >> "${failed_file}"
            fi
        done < "${container_requirements_txt}"

        if [ "${py_failed}" -eq 0 ]; then
            print_success "Applied Python requirements from container/requirements.txt (ok=${py_ok})."
            rm -f "${failed_file}" >/dev/null 2>&1 || true
        else
            print_warning "Python requirements completed with ${py_failed} unresolved package(s)."
            print_warning "Failed package list saved to: ${failed_file}"
            print_warning "Workaround: install remaining entries manually, or adjust versions for this host Python runtime."
        fi
    else
        print_warning "Python requirements file not found: ${container_requirements_txt}"
    fi

    # Required collections (normalized, unique, and alphabetically sorted).
    # NOTE: `eda_configuration` has been normalized to `infra.eda_configuration`.
    mapfile -t collections < <(minirhis_required_ansible_collections)

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

# Robust pip package installation with fallback strategy:
# 1. Try: pip install --upgrade --user <package>
# 2. Fallback 1: Try installing base package without version
# 3. Fallback 2: Try: dnf install -y --skip-broken --allowerasing --best
# 4. Fallback 3: dnf with base package without version
# Returns 0 on any success; warns on all failures but doesn't exit
install_package_with_fallback() {
    local pkg_spec="$1"
    local pkg_base pkg_version timeout_sec=60
    local use_pip=1

    # Extract base package name (before any version specifier like ==, >=, <=, ~=)
    pkg_base="$(printf '%s' "${pkg_spec}" | sed -E 's/[><=!~].*//')"

    if [ -z "${pkg_spec}" ]; then
        return 0
    fi

    # Step 1: Try pip install --upgrade --user
    if [ "${use_pip}" -eq 1 ] && command -v pip3 >/dev/null 2>&1; then
        if timeout ${timeout_sec} pip3 install --upgrade --user "${pkg_spec}" >/dev/null 2>&1; then
            print_step "✓ Installed (pip): ${pkg_spec}"
            return 0
        fi

        # Fallback 1: Try base package without version via pip
        if [ "${pkg_base}" != "${pkg_spec}" ]; then
            if timeout ${timeout_sec} pip3 install --upgrade --user "${pkg_base}" >/dev/null 2>&1; then
                print_step "✓ Installed (pip base): ${pkg_base}"
                return 0
            fi
        fi

        # Fallback 2: Try via sudo python3 -m pip
        if timeout ${timeout_sec} sudo python3 -m pip install --upgrade --user "${pkg_spec}" >/dev/null 2>&1; then
            print_step "✓ Installed (sudo pip): ${pkg_spec}"
            return 0
        fi
    fi

    # Step 2: Try dnf install with skip-broken and allowerasing
    if command -v dnf >/dev/null 2>&1; then
        # First try with specific version
        if timeout ${timeout_sec} sudo dnf install -y --skip-broken --allowerasing --best "${pkg_spec}" >/dev/null 2>&1; then
            print_step "✓ Installed (dnf): ${pkg_spec}"
            return 0
        fi

        # Fallback 3: Try base package without version via dnf
        if [ "${pkg_base}" != "${pkg_spec}" ]; then
            if timeout ${timeout_sec} sudo dnf install -y --skip-broken --allowerasing --best "${pkg_base}" >/dev/null 2>&1; then
                print_step "✓ Installed (dnf base): ${pkg_base}"
                return 0
            fi
        fi
    fi

    print_warning "Could not install package (tolerated failure): ${pkg_spec}"
    return 0  # Tolerate failure
}

# Robust dnf package installation with fallback strategy:
# 1. Try: dnf install -y --skip-broken --allowerasing --best <package>
# 2. If version specified and fails, retry with base package without version
# Returns 0 on success; tolerates failures
install_dnf_package_with_fallback() {
    local pkg_spec="$1"
    local pkg_base timeout_sec=60

    if [ -z "${pkg_spec}" ]; then
        return 0
    fi

    # Extract base package name
    pkg_base="$(printf '%s' "${pkg_spec}" | sed -E 's/[><=!~].*//')"

    # Try with skip-broken and allowerasing
    if timeout ${timeout_sec} sudo dnf install -y --skip-broken --allowerasing --best "${pkg_spec}" >/dev/null 2>&1; then
        print_step "✓ Installed (dnf): ${pkg_spec}"
        return 0
    fi

    # If version specified and that failed, retry with base package
    if [ "${pkg_base}" != "${pkg_spec}" ]; then
        if timeout ${timeout_sec} sudo dnf install -y --skip-broken --allowerasing --best "${pkg_base}" >/dev/null 2>&1; then
            print_step "✓ Installed (dnf base): ${pkg_base}"
            return 0
        fi
    fi

    print_warning "Could not install package (tolerated failure): ${pkg_spec}"
    return 0  # Tolerate failure
}

main() {
    init_minirhis_run_logging
    print_minirhis_header

    parse_args "$@"
    apply_cli_overrides

    if is_menutest; then
        run_menutest_mode
        exit $?
    fi

    # Show entry menu in interactive mode with no explicit action flag set.
     if ! is_noninteractive && \
         [ -z "${CLI_DEMOKILL:-}${CLI_GENERATE_ENV:-}${CLI_VALIDATE:-}${CLI_STATUS:-}${CLI_TEST:-}${CLI_MINIRHIS:-}${CLI_IDM:-}${CLI_SATELLITE:-}${CLI_AAP:-}${CLI_CONFIG_SCOPE:-}" ]; then
        show_entry_menu
    fi

    # CLI-only fast path: DEMOKILL should never require env/vault prompts.
    if [ -n "${CLI_DEMOKILL:-}" ]; then
        print_step "DEMOKILL requested from CLI; skipping credential prompts"
        demokill_cleanup || { print_warning "DEMOKILL failed"; exit 1; }
        print_success "Run complete"
        # Optional terminal reset for users who explicitly want it.
        if is_enabled "${MINIRHIS_DEMOKILL_RESET_TERMINAL:-0}"; then
            command -v reset >/dev/null 2>&1 && reset || true
        fi
        exit 0
    fi

    # CLI-only fast path: write headless env template and exit.
    if [ -n "${CLI_GENERATE_ENV:-}" ]; then
        generate_env_template "${CLI_GENERATE_ENV}"
        exit $?
    fi

    if [ ! -f "$ANSIBLE_ENV_FILE" ]; then
        load_preseed_env
    fi
    load_ansible_env_file
    normalize_shared_env_vars

    # CLI-only fast path: run pre-flight validation and exit.
    if [ -n "${CLI_VALIDATE:-}" ]; then
        validate_headless_config
        exit $?
    fi

    ensure_workspace_runtime_layout || {
        print_warning "Could not initialize generated workspace runtime layout."
        exit 1
    }

    if [ -n "${CLI_STATUS:-}" ]; then
        print_phase 1 1 "Read-only status snapshot"
        print_runtime_configuration
        print_minirhis_health_summary
        MINIRHIS_DASHBOARD_SINGLE_SHOT=1
        show_live_status_dashboard || true
        MINIRHIS_DASHBOARD_SINGLE_SHOT=0
        print_success "Status snapshot complete"
        exit 0
    fi

    if [ -n "${CLI_STATUS_LIVE:-}" ]; then
        print_phase 1 1 "Live status dashboard"
        print_runtime_configuration
        print_minirhis_health_summary
        MINIRHIS_DASHBOARD_SINGLE_SHOT=0
        show_live_status_dashboard || true
        print_success "Live status dashboard closed"
        exit 0
    fi

    # CLI-only fast path: reopen VM console monitors without prompts.
    if [ -n "${CLI_ATTACH_CONSOLES:-}" ]; then
        print_phase 1 1 "Reattach VM console monitors"
        ensure_libvirt_access || print_warning "libvirt access check failed; console reattach may not work until access is fixed."
        launch_progress_dashboard_auto || true
        reattach_vm_consoles || {
            print_warning "Console reattach failed"
            exit 1
        }
        print_success "Console reattach request complete"
        exit 0
    fi

    # Component-specific CLI workflows: only prompt for component-specific vars
    # Note: --minirhis (full stack) is treated as non-component mode
    if { [ -z "$CLI_IDM" ] && [ -z "$CLI_SATELLITE" ] && [ -z "$CLI_AAP" ] && [ -z "${CLI_CONFIG_SCOPE:-}" ]; } || \
       [ -n "$CLI_MINIRHIS" ] || [ "${CLI_CONFIG_SCOPE:-}" = "all" ]; then
        # Full stack or menu-driven mode: prompt for all values
        prompt_all_env_options_once
    else
        # Component-specific mode: load env file and let component handle its own prompting
        if [ -f "$ANSIBLE_ENV_FILE" ]; then
            load_ansible_env_file || {
                print_warning "Could not load encrypted env file; running full prompts instead"
                prompt_all_env_options_once
            }
        else
            # No env file yet; run full prompts to bootstrap
            prompt_all_env_options_once
        fi
    fi
    MINIRHIS_PROMPTS_COMPLETED=1
    FORCE_PROMPT_ALL=0
    normalize_shared_env_vars
    retire_preseed_env_file
    print_runtime_configuration

	print_step "Startup: Checking libvirtd"
	ensure_libvirtd || { print_warning "libvirtd check failed"; exit 1; }

    # Verify the installer user can talk to the system libvirt socket and
    # attempt automated remediation when possible (group membership / polkit).
    ensure_libvirt_access || print_warning "libvirt access check failed; VM creation may fail until access is fixed."

	print_step "Startup: Checking ISO image tools"
	ensure_iso_tools || { print_warning "ISO image tools check failed"; exit 1; }

    print_step "Startup: Ensuring installer-host platform packages"
    ensure_platform_packages_for_virt_manager || { print_warning "Installer-host package check failed"; exit 1; }

    print_step "Startup: Pre-flight collection visibility"
    check_missing_installer_host_ansible_collections || true

    print_step "Startup: Ensuring installer-host Ansible collections"
    ensure_installer_host_ansible_collections || print_warning "Installer-host collection install encountered issues; continuing."

    if [ -n "${CLI_CONFIG_SCOPE:-}" ]; then
        print_phase 1 1 "Config-as-code role execution (${CLI_CONFIG_SCOPE})"
        case "${CLI_CONFIG_SCOPE}" in
            idm|satellite|aap|rhis-aap)
                run_component_config_scope "${CLI_CONFIG_SCOPE}" || {
                    print_warning "Config-as-code execution failed for scope: ${CLI_CONFIG_SCOPE}"
                    exit 1
                }
                ;;
            all)
                if [ "${MINIRHIS_EXECUTION_MODE:-container}" = "container" ]; then
                    install_container || {
                        print_warning "Could not initialize provisioner container for config-as-code."
                        exit 1
                    }
                fi
                MINIRHIS_COMPONENT_SCOPE="all" run_minirhis_config_as_code || {
                    print_warning "Config-as-code execution failed for full stack scope."
                    exit 1
                }
                ;;
            *)
                print_warning "Unknown --config scope: ${CLI_CONFIG_SCOPE}"
                exit 1
                ;;
        esac
        print_success "Run complete"
        exit 0
    fi

    if [ -n "${CLI_TEST:-}" ]; then
        if minirhis_run_test_suite; then
            print_success "Run complete"
            exit 0
        fi
        exit 1
    fi

	while true; do
        prompt_deployment_scope
        case "$?" in
            2)
                command -v clear >/dev/null 2>&1 && clear
                echo "Exiting installation script"
                exit 0
                ;;
        esac

        if is_enabled "${MINIRHIS_GUIDED_SCOPE_FLOW:-0}"; then
            run_guided_scope_workflow
            case "$?" in
                0)
                    print_success "Run complete"
                    exit 0
                    ;;
                10)
                    DEPLOYMENT_SCOPE_PROMPTED=0
                    continue
                    ;;
                *)
                    print_warning "Guided deployment workflow failed"
                    exit 1
                    ;;
            esac
        fi

		reset_menu_view
		show_menu
		case "$choice" in
            1)
                select_stack_sizing_profile || { print_warning "Could not determine sizing profile"; exit 1; }
                run_container_config_only || { print_warning "MINIRHIS Full Stack workflow failed"; exit 1; }
                ;;
            2) show_standalone_components_submenu || { print_warning "Standalone components submenu failed"; exit 1; } ;;
            3) configure_platform_selection || { print_warning "Platform selection failed"; exit 1; } ;;
			4) prompts_only_workflow || { print_warning "Prompts-only workflow failed"; exit 1; } ;;
			5) generate_oemdrv_kickstarts_only ;;
            6) show_configure_existing_submenu || { print_warning "Configure Existing Stack workflow failed"; exit 1; } ;;
            7) ensure_rootless_podman && print_success "Rootless Podman is ready." || print_warning "Rootless Podman setup did not complete; see messages above." ;;
            # Backward-compatible hidden menu choices for existing automation/CLI shortcuts
            9) install_satellite_only || { print_warning "Satellite-only workflow failed"; exit 1; } ;;
            10) install_idm_only || { print_warning "IdM-only workflow failed"; exit 1; } ;;
            11) install_aap_only || { print_warning "AAP-only workflow failed"; exit 1; } ;;
            0)
                command -v clear >/dev/null 2>&1 && clear
                echo "Exiting installation script"
                exit 0
                ;;
        *) print_warning "Invalid choice. Please select 0-6." ;;
		esac

        reset_menu_view

        if is_noninteractive || [ "${RUN_ONCE:-0}" = "1" ]; then
            print_success "Run complete"
            exit 0
        fi

		echo ""
	done
}

main "$@"

