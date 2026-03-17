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

# Best practice: use /var/lib/libvirt/images for all ISO/disk files
ISO_DIR="${ISO_DIR:-/var/lib/libvirt/images}"
ISO_NAME="${ISO_NAME:-rhel-10-everything-x86_64-dvd.iso}"
ISO_PATH="${ISO_PATH:-$ISO_DIR/$ISO_NAME}"
RH_TOKEN_URL="${RH_TOKEN_URL:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"
RH_OSINFO="${RH_OSINFO:-linux2024}"
VM_DIR="${VM_DIR:-/var/lib/libvirt/images}"
KS_DIR="${KS_DIR:-/var/lib/libvirt/images/kickstarts}"
OEMDRV_ISO="${OEMDRV_ISO:-$ISO_DIR/OEMDRV.iso}"
ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
ANSIBLE_ENV_FILE="${ANSIBLE_ENV_FILE:-$ANSIBLE_ENV_DIR/env.yml}"
ANSIBLE_VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-$ANSIBLE_ENV_DIR/.vaultpass.txt}"

REPO_URL="${REPO_URL:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESEED_ENV_FILE="${PRESEED_ENV_FILE:-$SCRIPT_DIR/.env}"
CLI_MENU_CHOICE=""
CLI_NONINTERACTIVE=""
RUN_ONCE="${RUN_ONCE:-0}"
DEMO_MODE="${DEMO_MODE:-0}"
CLI_DEMO=""
CLI_DEMOKILL=""
CLI_RECONFIGURE=""
MENU_CHOICE_CONSUMED=0

# Automation Hub + AAP bundle pre-flight HTTP-serve variables
HUB_TOKEN="${HUB_TOKEN:-}"
HOST_INT_IP="${HOST_INT_IP:-192.168.122.1}"
AAP_BUNDLE_URL="${AAP_BUNDLE_URL:-}"
AAP_BUNDLE_DIR="${AAP_BUNDLE_DIR:-${VM_DIR}/aap-bundle}"
AAP_HTTP_PID=""
AAP_ADMIN_PASS="${AAP_ADMIN_PASS:-}"

# Shared identity/network defaults (single source of truth)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-r3dh4t7!}"
DOMAIN="${DOMAIN:-example.com}"
REALM="${REALM:-}"
NETMASK="${NETMASK:-255.255.0.0}"
INTERNAL_GW="${INTERNAL_GW:-0.0.0.0}"

# Internal interface static defaults (eth1)
SAT_IP="${SAT_IP:-10.168.128.1}"
AAP_IP="${AAP_IP:-10.168.128.2}"
IDM_IP="${IDM_IP:-10.168.128.3}"
SAT_HOSTNAME="${SAT_HOSTNAME:-satellite-618.example.com}"
AAP_HOSTNAME="${AAP_HOSTNAME:-aap-26.example.com}"
IDM_HOSTNAME="${IDM_HOSTNAME:-idm.example.com}"

# Satellite defaults
SAT_ORG="${SAT_ORG:-REDHAT}"
SAT_LOC="${SAT_LOC:-CORE}"
IDM_DS_PASS="${IDM_DS_PASS:-r3dh4t7!}"

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

# Function to print colored output
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --non-interactive        Run without prompts; required values must be preseeded
  --menu-choice <0-6>      Preselect a visible menu option
  --env-file <path>        Load preseed variables from a custom env file
  --reconfigure            Prompt for all env values and update env.yml
  --demo                   Use minimal PoC/demo VM specs and kickstarts
  --demokill               Destroy demo VMs/files/temp locks and exit (CLI-only)
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

print_runtime_configuration() {
    print_step "Runtime configuration summary"
    echo "  PRESEED_ENV_FILE=${PRESEED_ENV_FILE}"
    echo "  NONINTERACTIVE=${NONINTERACTIVE:-0}"
    echo "  MENU_CHOICE=${MENU_CHOICE:-'(unset)'}"
    echo "  RH_ISO_URL=${RH_ISO_URL:-'(unset)'}"
    echo "  RH_OFFLINE_TOKEN=$(mask_secret "${RH_OFFLINE_TOKEN:-}")"
    echo "  RH_ACCESS_TOKEN=$(mask_secret "${RH_ACCESS_TOKEN:-}")"
    echo "  RH_PASS=$(mask_secret "${RH_PASS:-}")"
    echo "  SAT_HOSTNAME=${SAT_HOSTNAME:-'(unset)'}"
    echo "  SAT_ORG=${SAT_ORG:-'(unset)'}"
    echo "  SAT_LOC=${SAT_LOC:-'(unset)'}"
    echo "  DEMO_MODE=${DEMO_MODE:-0}"
    echo "  HUB_TOKEN=$(mask_secret "${HUB_TOKEN:-}")"
    echo "  HOST_INT_IP=${HOST_INT_IP:-'(unset)'}"
    echo "  AAP_BUNDLE_URL=${AAP_BUNDLE_URL:-'(unset)'}"
    echo "  AAP_SSH_KEY_DIR=${AAP_SSH_KEY_DIR:-'(unset)'}"
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
        MENU_CHOICE="8"
    fi

    if [ -n "$CLI_RECONFIGURE" ]; then
        FORCE_PROMPT_ALL=1
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

is_unresolved_template_value() {
    local value="${1:-}"
    case "$value" in
        *"{{"*|*"}}"*)
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

    DOMAIN="${DOMAIN:-${SAT_DOMAIN:-${AAP_DOMAIN:-${IDM_DOMAIN:-example.com}}}}"
    REALM="${REALM:-${IDM_REALM:-${SAT_REALM:-}}}"
    [ -n "${REALM:-}" ] || REALM="$(to_upper "$DOMAIN")"

    ADMIN_USER="${ADMIN_USER:-admin}"
    ADMIN_PASS="${ADMIN_PASS:-${AAP_ADMIN_PASS:-${IDM_ADMIN_PASS:-${SAT_ADMIN_PASS:-r3dh4t7!}}}}"

    NETMASK="${NETMASK:-${SAT_NETMASK:-${AAP_NETMASK:-${IDM_NETMASK:-255.255.0.0}}}}"
    INTERNAL_GW="${INTERNAL_GW:-${SAT_GW:-${AAP_GW:-${IDM_GW:-0.0.0.0}}}}"

    SAT_IP="${SAT_IP:-10.168.128.1}"
    AAP_IP="${AAP_IP:-10.168.128.2}"
    IDM_IP="${IDM_IP:-10.168.128.3}"

    SAT_ORG="${SAT_ORG:-REDHAT}"
    SAT_LOC="${SAT_LOC:-CORE}"

    SAT_DOMAIN="${SAT_DOMAIN:-$DOMAIN}"
    AAP_DOMAIN="${AAP_DOMAIN:-$DOMAIN}"
    IDM_DOMAIN="${IDM_DOMAIN:-$DOMAIN}"

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

    SAT_REALM="${SAT_REALM:-$REALM}"
    IDM_REALM="${IDM_REALM:-$REALM}"

    SAT_ADMIN_PASS="${SAT_ADMIN_PASS:-$ADMIN_PASS}"
    AAP_ADMIN_PASS="${AAP_ADMIN_PASS:-$ADMIN_PASS}"
    IDM_ADMIN_PASS="${IDM_ADMIN_PASS:-$ADMIN_PASS}"

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
    local lower_prompt prompt_label

    lower_prompt="$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')"
    prompt_label="$prompt_text"
    if [[ "$lower_prompt" != *"optional"* ]] && [[ "$lower_prompt" != *"required"* ]]; then
        prompt_label="${prompt_text} [Optional]"
    fi

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
    local prompt_with_meta lower_prompt

    lower_prompt="$(printf '%s' "$prompt_label" | tr '[:upper:]' '[:lower:]')"
    prompt_with_meta="$prompt_label"
    if [[ "$lower_prompt" != *"optional"* ]] && [[ "$lower_prompt" != *"required"* ]]; then
        if [ "$is_required" = "1" ]; then
            prompt_with_meta="${prompt_label} [Required]"
        else
            prompt_with_meta="${prompt_label} [Optional]"
        fi
    fi

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
        DOMAIN
        SAT_IP AAP_IP IDM_IP
        SAT_HOSTNAME AAP_HOSTNAME IDM_HOSTNAME
        RH_USER RH_PASS RH_ISO_URL
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
    echo "1) Local Installation (npm)"
    echo "2) Container Deployment (Podman)"
    echo "3) Setup Virt-Manager Only"
    echo "4) Full Setup (Local + Virt-Manager)"
    echo "5) Full Setup (Container + Virt-Manager)"
    echo "6) Generate Satellite OEMDRV Only"
    echo "0) Exit"
    echo ""
    read -r -p "Enter choice [0-6]: " choice
}

# Ensure Node.js is installed
ensure_node() {
    if command -v node >/dev/null 2>&1; then
        return 0
    fi

    print_warning "Node.js not found. Attempting installation..."
    sudo dnf install -y nodejs npm
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
        sudo dnf install -y firewalld
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
    print_step "Configuring libvirt networks (default->external, create internal)"

    if ! command -v virsh >/dev/null 2>&1; then
        print_warning "virsh not found; skipping libvirt network configuration."
        return 0
    fi

    # Rename default -> external (same settings)
    if sudo virsh net-info default >/dev/null 2>&1; then
        print_step "Stopping and renaming network: default -> external"
        sudo virsh net-destroy default >/dev/null 2>&1 || true

        sudo virsh net-dumpxml default | sudo tee /tmp/default.xml >/dev/null
        sudo sed -i 's#<name>default</name>#<name>external</name>#' /tmp/default.xml
        sudo sed -i '/<uuid>/d' /tmp/default.xml

        sudo virsh net-undefine default

        if ! sudo virsh net-info external >/dev/null 2>&1; then
            sudo virsh net-define /tmp/default.xml
        fi
        sudo virsh net-start external >/dev/null 2>&1 || true
        sudo virsh net-autostart external
    else
        print_warning "Network 'default' not found; skipping rename to 'external'."
        if sudo virsh net-info external >/dev/null 2>&1; then
            sudo virsh net-start external >/dev/null 2>&1 || true
            sudo virsh net-autostart external
        fi
    fi

    # Create internal static network 10.168.0.0/16 with no DHCP
    if ! sudo virsh net-info internal >/dev/null 2>&1; then
        print_step "Creating network: internal (10.168.0.0/16, static, no DHCP)"
        cat <<'EOF' | sudo tee /tmp/internal.xml >/dev/null
<network>
  <name>internal</name>
  <bridge name='virbr-internal' stp='on' delay='0'/>
  <dns enable='no'/>
  <ip address='10.168.0.1' netmask='255.255.0.0'/>
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
        exit 1
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
        print_warning "No package.json found in $SCRIPT_DIR."
        print_warning "This project appears to be container-based."
        read -r -p "Run container deployment now? [Y/n]: " use_container
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
        sudo dnf install -y podman shadow-utils slirp4netns fuse-overlayfs
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

install_container() {
    print_step "Starting Container Deployment"
    ensure_rootless_podman || exit 1
    configure_rhis_network_policy

    print_step "Pulling RHIS container image"
    podman pull quay.io/parmstro/rhis-provisioner-9-2.5:latest

    # Replace existing container if present
    podman rm -f rhis >/dev/null 2>&1 || true

    print_step "Running RHIS container (rootless)"
    podman run -d -p 3000:3000 \
        -e CONFIG_PATH=/etc/rhis/config.json \
        --name rhis \
        quay.io/parmstro/rhis-provisioner-9-2.5:latest

    print_success "Container deployment complete"
    echo "Access dashboard at http://localhost:3000"
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
    configure_libvirt_firewall_policy
    enable_virt_manager_xml_editor
    enable_virt_manager_resize_guest
    configure_libvirt_networks
    download_rhel10_iso || true

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
    sudo dnf install -y yum-utils
    sudo yum-builddep -y virt-install qemu-img libvirt-client libvirt virt-manager

    print_step "Installing virt-manager and dependencies"
    sudo dnf install virt-manager virt-viewer libvirt qemu-kvm -y

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
	sudo dnf install -y jq
	return $?
}

# ─── Credential store: ~/.ansible/conf/env.yml ────────────────────────────────
# Ensure ansible-vault exists.
ensure_ansible_vault() {
    if command -v ansible-vault >/dev/null 2>&1; then
        return 0
    fi

    print_warning "ansible-vault not found. Attempting to install ansible-core..."
    sudo dnf install -y ansible-core >/dev/null 2>&1 || {
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

# Load all RHIS credentials from ~/.ansible/conf/env.yml.
# Only populates variables currently unset — preseed / CLI values always win.
load_ansible_env_file() {
    [ -f "$ANSIBLE_ENV_FILE" ] || return 0
    read_ansible_env_content || return 1
    _load_env_key ADMIN_USER      admin_user
    _load_env_key ADMIN_PASS      admin_pass
    _load_env_key DOMAIN          domain
    _load_env_key REALM           realm
    _load_env_key NETMASK         netmask
    _load_env_key INTERNAL_GW     internal_gw
    _load_env_key RH_USER          rh_user
    _load_env_key RH_PASS          rh_pass
    _load_env_key RH_OFFLINE_TOKEN rh_offline_token
    _load_env_key RH_ACCESS_TOKEN  rh_access_token
    _load_env_key HUB_TOKEN        hub_token
    _load_env_key SAT_ADMIN_PASS   sat_admin_pass
    _load_env_key AAP_ADMIN_PASS   aap_admin_pass
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
    _load_env_key SAT_HOSTNAME     sat_hostname
    _load_env_key SAT_DOMAIN       sat_domain
    _load_env_key SAT_ORG          sat_org
    _load_env_key SAT_LOC          sat_loc
    _load_env_key AAP_HOSTNAME     aap_hostname
    _load_env_key AAP_DOMAIN       aap_domain
    _load_env_key IDM_HOSTNAME     idm_hostname
    _load_env_key IDM_DOMAIN       idm_domain
    _load_env_key IDM_REALM        idm_realm
    _load_env_key IDM_ADMIN_PASS   idm_admin_pass
    _load_env_key IDM_DS_PASS      idm_ds_pass
    _load_env_key HOST_INT_IP      host_int_ip
    _load_env_key AAP_BUNDLE_URL   aap_bundle_url
    _load_env_key RH_ISO_URL       rh_iso_url
    normalize_shared_env_vars
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
netmask: "${NETMASK:-}"
internal_gw: "${INTERNAL_GW:-}"
rh_user: "${RH_USER:-}"
rh_pass: "${RH_PASS:-}"
rh_offline_token: "${RH_OFFLINE_TOKEN:-}"
rh_access_token: "${RH_ACCESS_TOKEN:-}"
hub_token: "${HUB_TOKEN:-}"
aap_ip: "${AAP_IP:-}"
idm_ip: "${IDM_IP:-}"
aap_admin_pass: "${AAP_ADMIN_PASS:-}"
sat_ip: "${SAT_IP:-}"
sat_netmask: "${SAT_NETMASK:-}"
sat_gw: "${SAT_GW:-}"
sat_hostname: "${SAT_HOSTNAME:-}"
sat_domain: "${SAT_DOMAIN:-}"
sat_realm: "${SAT_REALM:-}"
sat_org: "${SAT_ORG:-}"
sat_loc: "${SAT_LOC:-}"
aap_hostname: "${AAP_HOSTNAME:-}"
aap_domain: "${AAP_DOMAIN:-}"
aap_netmask: "${AAP_NETMASK:-}"
aap_gw: "${AAP_GW:-}"
idm_hostname: "${IDM_HOSTNAME:-}"
idm_domain: "${IDM_DOMAIN:-}"
idm_realm: "${IDM_REALM:-}"
idm_admin_pass: "${IDM_ADMIN_PASS:-}"
idm_ds_pass: "${IDM_DS_PASS:-}"
idm_netmask: "${IDM_NETMASK:-}"
idm_gw: "${IDM_GW:-}"
host_int_ip: "${HOST_INT_IP:-}"
aap_bundle_url: "${AAP_BUNDLE_URL:-}"
rh_iso_url: "${RH_ISO_URL:-}"
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
    [ -f "$ANSIBLE_ENV_FILE" ] && has_env_file=1

    if [ "$has_env_file" -eq 1 ] && [ "${FORCE_PROMPT_ALL:-0}" != "1" ]; then
        load_ansible_env_file || return 1

        if is_noninteractive; then
            return 0
        fi

        global_missing="$(count_missing_vars ADMIN_USER ADMIN_PASS DOMAIN REALM NETMASK INTERNAL_GW RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL)"
        echo ""
        echo "=== Global (remaining missing: ${global_missing}/12) ==="
        if [ -z "${ADMIN_USER:-}" ]; then
            prompt_with_default ADMIN_USER "Shared Admin Username" "${ADMIN_USER:-admin}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${ADMIN_PASS:-}" ]; then
            prompt_with_default ADMIN_PASS "Shared Admin Password" "${ADMIN_PASS:-r3dh4t7!}" 1 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var DOMAIN; then
            prompt_with_default DOMAIN "Shared Domain" "${DOMAIN:-example.com}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${REALM:-}" ]; then
            prompt_with_default REALM "Shared Kerberos Realm (blank=DOMAIN uppercased)" "${REALM:-}" 0 0 || return 1
            env_changed=1
        fi
        if [ -z "${NETMASK:-}" ]; then
            prompt_with_default NETMASK "Shared Internal Netmask" "${NETMASK:-255.255.0.0}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${INTERNAL_GW:-}" ]; then
            prompt_with_default INTERNAL_GW "Shared Internal Gateway" "${INTERNAL_GW:-0.0.0.0}" 0 1 || return 1
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
            prompt_with_default RH_ACCESS_TOKEN "Red Hat Access Token (optional)" "${RH_ACCESS_TOKEN:-}" 1 0 || return 1
            env_changed=1
        fi
        if [ -z "${HUB_TOKEN:-}" ]; then
            prompt_with_default HUB_TOKEN "Automation Hub token" "${HUB_TOKEN:-}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${RH_ISO_URL:-}" ]; then
            prompt_with_default RH_ISO_URL "RHEL ISO URL" "${RH_ISO_URL:-}" 0 1 || return 1
            env_changed=1
        fi

        sat_missing="$(count_missing_vars SAT_IP SAT_HOSTNAME SAT_ORG SAT_LOC)"
        echo ""
        echo "=== Satellite (remaining missing: ${sat_missing}/4) ==="
        if [ -z "${SAT_IP:-}" ]; then
            prompt_with_default SAT_IP "Satellite Internal IP (eth1)" "${SAT_IP:-10.168.128.1}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var SAT_HOSTNAME; then
            prompt_with_default SAT_HOSTNAME "Satellite Hostname (FQDN)" "${SAT_HOSTNAME:-satellite-618.${DOMAIN}}" 0 1 || return 1
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

        aap_missing="$(count_missing_vars AAP_IP AAP_HOSTNAME AAP_BUNDLE_URL)"
        echo ""
        echo "=== AAP (remaining missing: ${aap_missing}/3) ==="
        if [ -z "${AAP_IP:-}" ]; then
            prompt_with_default AAP_IP "AAP Internal IP (eth1)" "${AAP_IP:-10.168.128.2}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var AAP_HOSTNAME; then
            prompt_with_default AAP_HOSTNAME "AAP Hostname (FQDN)" "${AAP_HOSTNAME:-aap-26.${DOMAIN}}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${AAP_BUNDLE_URL:-}" ]; then
            prompt_with_default AAP_BUNDLE_URL "AAP bundle URL" "${AAP_BUNDLE_URL:-}" 0 1 || return 1
            env_changed=1
        fi

        idm_missing="$(count_missing_vars IDM_IP IDM_HOSTNAME IDM_ADMIN_PASS IDM_DS_PASS)"
        echo ""
        echo "=== IdM (remaining missing: ${idm_missing}/4) ==="
        if [ -z "${IDM_IP:-}" ]; then
            prompt_with_default IDM_IP "IdM Internal IP (eth1)" "${IDM_IP:-10.168.128.3}" 0 1 || return 1
            env_changed=1
        fi
        if needs_prompt_var IDM_HOSTNAME; then
            prompt_with_default IDM_HOSTNAME "IdM Hostname (FQDN)" "${IDM_HOSTNAME:-idm.${DOMAIN}}" 0 1 || return 1
            env_changed=1
        fi
        if [ -z "${IDM_ADMIN_PASS:-}" ]; then
            prompt_with_default IDM_ADMIN_PASS "IdM Admin Password" "${IDM_ADMIN_PASS:-$ADMIN_PASS}" 1 1 || return 1
            env_changed=1
        fi
        if [ -z "${IDM_DS_PASS:-}" ]; then
            prompt_with_default IDM_DS_PASS "IdM Directory Service Password" "${IDM_DS_PASS:-r3dh4t7!}" 1 1 || return 1
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
    fi

    print_step "First run detected: collecting environment values and storing them in ansible-vault"
    echo "(Press Enter to accept the shown default where applicable.)"

    global_missing="$(count_missing_vars ADMIN_USER ADMIN_PASS DOMAIN REALM NETMASK INTERNAL_GW RH_USER RH_PASS RH_OFFLINE_TOKEN RH_ACCESS_TOKEN HUB_TOKEN RH_ISO_URL)"
    echo ""
    echo "=== Global (remaining missing: ${global_missing}/12) ==="
    prompt_with_default ADMIN_USER "Shared Admin Username" "${ADMIN_USER:-admin}" 0 1 || return 1
    prompt_with_default ADMIN_PASS "Shared Admin Password" "${ADMIN_PASS:-r3dh4t7!}" 1 1 || return 1
    prompt_with_default DOMAIN "Shared Domain" "${DOMAIN:-example.com}" 0 1 || return 1
    prompt_with_default REALM "Shared Kerberos Realm (blank=DOMAIN uppercased)" "${REALM:-}" 0 0 || return 1
    prompt_with_default NETMASK "Shared Internal Netmask" "${NETMASK:-255.255.0.0}" 0 1 || return 1
    prompt_with_default INTERNAL_GW "Shared Internal Gateway" "${INTERNAL_GW:-0.0.0.0}" 0 1 || return 1

    prompt_with_default RH_USER "Red Hat CDN Username" "${RH_USER:-}" 0 1 || return 1
    prompt_with_default RH_PASS "Red Hat CDN Password" "${RH_PASS:-}" 1 1 || return 1
    prompt_with_default RH_OFFLINE_TOKEN "Red Hat Offline Token" "${RH_OFFLINE_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ACCESS_TOKEN "Red Hat Access Token (optional)" "${RH_ACCESS_TOKEN:-}" 1 0 || return 1
    prompt_with_default HUB_TOKEN "Automation Hub token" "${HUB_TOKEN:-}" 1 1 || return 1
    prompt_with_default RH_ISO_URL "RHEL ISO URL" "${RH_ISO_URL:-}" 0 1 || return 1

    sat_missing="$(count_missing_vars SAT_IP SAT_HOSTNAME SAT_ORG SAT_LOC)"
    echo ""
    echo "=== Satellite (remaining missing: ${sat_missing}/4) ==="
    prompt_with_default SAT_IP "Satellite Internal IP (eth1)" "${SAT_IP:-10.168.128.1}" 0 1 || return 1
    prompt_with_default SAT_HOSTNAME "Satellite Hostname (FQDN)" "${SAT_HOSTNAME:-satellite-618.${DOMAIN}}" 0 1 || return 1
    prompt_with_default SAT_ORG "Satellite Organization" "${SAT_ORG:-REDHAT}" 0 1 || return 1
    prompt_with_default SAT_LOC "Satellite Location" "${SAT_LOC:-CORE}" 0 1 || return 1

    aap_missing="$(count_missing_vars AAP_IP AAP_HOSTNAME AAP_BUNDLE_URL)"
    echo ""
    echo "=== AAP (remaining missing: ${aap_missing}/3) ==="
    prompt_with_default AAP_IP "AAP Internal IP (eth1)" "${AAP_IP:-10.168.128.2}" 0 1 || return 1
    prompt_with_default AAP_HOSTNAME "AAP Hostname (FQDN)" "${AAP_HOSTNAME:-aap-26.${DOMAIN}}" 0 1 || return 1
    prompt_with_default AAP_BUNDLE_URL "AAP bundle URL" "${AAP_BUNDLE_URL:-}" 0 1 || return 1

    idm_missing="$(count_missing_vars IDM_IP IDM_HOSTNAME IDM_ADMIN_PASS IDM_DS_PASS)"
    echo ""
    echo "=== IdM (remaining missing: ${idm_missing}/4) ==="
    prompt_with_default IDM_IP "IdM Internal IP (eth1)" "${IDM_IP:-10.168.128.3}" 0 1 || return 1
    prompt_with_default IDM_HOSTNAME "IdM Hostname (FQDN)" "${IDM_HOSTNAME:-idm.${DOMAIN}}" 0 1 || return 1
    prompt_with_default IDM_ADMIN_PASS "IdM Admin Password" "${IDM_ADMIN_PASS:-$ADMIN_PASS}" 1 1 || return 1
    prompt_with_default IDM_DS_PASS "IdM Directory Service Password" "${IDM_DS_PASS:-r3dh4t7!}" 1 1 || return 1

    normalize_shared_env_vars
    write_ansible_env_file || return 1
    print_success "Bootstrap complete. Future runs will reuse encrypted values from $ANSIBLE_ENV_FILE"
}

# If env.yml already has credentials, offer to reuse them before prompting.
# Non-interactive mode always loads silently.
prompt_use_existing_env() {
    if [ ! -f "$ANSIBLE_ENV_FILE" ]; then
        return 0
    fi

    load_ansible_env_file || return 1
    print_step "Loaded existing encrypted credentials from $ANSIBLE_ENV_FILE"
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

# Ensure SSH key pair exists for AAP VM post-boot callback orchestration.
ensure_ssh_keys() {
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

# Download the AAP containerized bundle tarball to AAP_BUNDLE_DIR so it can be
# served over HTTP to the VM during kickstart %post.  The bundle is NOT embedded
# in the OEMDRV ISO — it is too large (5–10 GB) and would break ISO creation.
preflight_download_aap_bundle() {
    local bundle_dest="${AAP_BUNDLE_DIR}/aap-bundle.tar.gz"

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
    local ssh_attempts=0
    local ssh_max_attempts=540  # 540 × 10s = 90 minutes
    local elapsed_minutes=0

    print_step "Waiting for ${vm_name} to boot and SSH to become available (up to 90 min)..."
    print_step "  (Anaconda install + 3.5 GB bundle download typically takes 30-60 min)"

    while [ "${ssh_attempts}" -lt "${ssh_max_attempts}" ]; do
        # Get the VM's IP from virsh
        vm_ip="$(sudo virsh domifaddr "${vm_name}" --lease 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

        if [ -n "${vm_ip}" ]; then
            print_step "${vm_name} has IP ${vm_ip} — checking SSH..."
            # Try SSH with short timeout
            if timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -i "${AAP_SSH_PRIVATE_KEY}" "root@${vm_ip}" "echo 'SSH ready'" &>/dev/null; then
                print_success "${vm_name} SSH is ready at ${vm_ip}"
                echo "${vm_ip}"
                return 0
            fi
        fi

        ssh_attempts="$((ssh_attempts + 1))"
        printf "."
        if [ $((ssh_attempts % 6)) -eq 0 ]; then
            elapsed_minutes=$((ssh_attempts / 6))
            echo ""
            print_step "Still waiting for ${vm_name} SSH... elapsed ${elapsed_minutes} minute(s)"
            print_step "Tip: check VM state with: sudo virsh list --all"
        fi
        sleep 10
    done

        print_warning "${vm_name} SSH did not become available within 90 minutes."
    return 1
}

# Run the AAP 2.6 containerized installer on the VM via SSH callback from the host.
# Captures setup.sh output, validates exit code, and stops the HTTP server upon completion.
run_aap_setup_on_vm() {
    local vm_name="${1:-aap-26}"
    local vm_ip

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

    (cd "${AAP_BUNDLE_DIR}" && exec python3 -m http.server 8080 --bind "${HOST_INT_IP}") &
    AAP_HTTP_PID=$!
    print_success "AAP bundle HTTP server running (PID: ${AAP_HTTP_PID}) — serving ${AAP_BUNDLE_DIR}"
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
        sudo dnf install -y virt-install qemu-img libvirt-client || return 1

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
    set_or_prompt SAT_DOMAIN "Domain Name: " || return 1
    set_or_prompt SAT_ORG "Organization Name: " || return 1
    set_or_prompt SAT_LOC "Location Name: " || return 1
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_satellite_618_kickstart() {
    local ks_file="${KS_DIR}/satellite-618.ks"
    local tmpdir tmp_ks tmp_oem

    prompt_satellite_618_details || return 1
    ensure_iso_vars || return 1
    ensure_iso_tools || return 1

    tmpdir="$(mktemp -d)"
    tmp_ks="${tmpdir}/satellite-618.ks"
    tmp_oem="${tmpdir}/ks.cfg"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8

network --bootproto=dhcp --device=eth0 --activate --onboot=yes
network --bootproto=static --device=eth1 --ip=${SAT_IP} --netmask=${SAT_NETMASK} --gateway=${SAT_GW} --activate --onboot=yes --hostname=${SAT_HOSTNAME}

HEADER

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "Satellite kickstart: DEMO partition layout (/boot 2G + swap 18G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 8 vCPU, 24 GB RAM, 100 GB raw storage
zerombr
clearpart --all --initlabel
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
# 1. Registration
subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach

# 1.1 Local hosts mapping (temporary DNS-independent bootstrap)
cat > /etc/hosts <<EOF
127.0.0.1 localhost localhost.localdomain
${SAT_IP} ${SAT_HOSTNAME} ${SAT_HOSTNAME%%.*}
${AAP_IP} ${AAP_HOSTNAME} ${AAP_HOSTNAME%%.*}
${IDM_IP} ${IDM_HOSTNAME} ${IDM_HOSTNAME%%.*}
EOF

# 2. Repositories
subscription-manager repos --disable="*"
subscription-manager repos --enable="rhel-10-for-x86_64-baseos-rpms" --enable="rhel-10-for-x86_64-appstream-rpms" --enable="satellite-6.18-for-rhel-10-x86_64-rpms" --enable="satellite-maintenance-6.18-for-rhel-10-x86_64-rpms"

# 3. Installation
dnf install -y satellite

# 4. Satellite Installer
satellite-installer --scenario satellite --foreman-initial-organization "${SAT_ORG}" --foreman-initial-location "${SAT_LOC}" --foreman-initial-admin-username "${ADMIN_USER}" --foreman-initial-admin-password "${ADMIN_PASS}" --foreman-proxy-dns true --foreman-proxy-dns-interface eth1 --foreman-proxy-dhcp true --foreman-proxy-dhcp-interface eth1 --foreman-proxy-tftp true --foreman-proxy-tftp-managed true --enable-foreman-plugin-ansible --enable-foreman-proxy-plugin-ansible --enable-foreman-compute-ec2 --enable-foreman-compute-gce --enable-foreman-compute-azure --enable-foreman-compute-libvirt --enable-foreman-plugin-openscap --enable-foreman-proxy-plugin-openscap --register-with-insights true

# 5. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true
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

prompt_aap_details() {
    normalize_shared_env_vars
    set_or_prompt RH_USER     "Red Hat CDN Username: "  || return 1
    set_or_prompt RH_PASS     "Red Hat CDN Password: " 1 || return 1
    set_or_prompt ADMIN_USER  "Shared Admin Username: " || return 1
    set_or_prompt ADMIN_PASS  "Shared Admin Password: " 1 || return 1
    echo -e "\n--- AAP Identity ---"
    set_or_prompt AAP_HOSTNAME   "AAP Hostname (FQDN): "   || return 1
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
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_aap_kickstart() {
    local ks_file="${KS_DIR}/aap-26.ks"
    local tmp_ks
    local aap_ssh_pub_key

    prompt_aap_details || return 1
    ensure_iso_vars || return 1
    ensure_ssh_keys || return 1

    # Read the host's public key for SSH callback orchestration
    if [ ! -f "${AAP_SSH_PUBLIC_KEY}" ]; then
        print_warning "AAP SSH public key not found at ${AAP_SSH_PUBLIC_KEY}. Cannot inject into kickstart."
        return 1
    fi
    aap_ssh_pub_key="$(cat "${AAP_SSH_PUBLIC_KEY}")"

    tmp_ks="$(mktemp)"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8

network --bootproto=dhcp --device=eth0 --activate --onboot=yes
network --bootproto=static --device=eth1 --ip=${AAP_IP} --netmask=${AAP_NETMASK} --gateway=${AAP_GW} --activate --onboot=yes --hostname=${AAP_HOSTNAME}

HEADER

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "AAP kickstart: DEMO partition layout (/boot 2G + swap 10G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 4 vCPU, 8152 MB RAM, 50 GB raw storage
zerombr
clearpart --all --initlabel
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

    # --- Post-install: write literal kicsstart %post section, then make per-variable substitutions ---
    cat >> "$tmp_ks" <<'POSTEOF'
%post --log=/root/ks-post.log
# 1. Registration
subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach

# 1.1 Local hosts mapping (temporary DNS-independent bootstrap)
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost localhost.localdomain
{{SAT_IP}} {{SAT_HOSTNAME}} {{SAT_SHORT}}
{{AAP_IP}} {{AAP_HOSTNAME}} {{AAP_SHORT}}
{{IDM_IP}} {{IDM_HOSTNAME}} {{IDM_SHORT}}
HOSTS

# 2. Repositories
subscription-manager repos --disable="*"
subscription-manager repos --enable="rhel-10-for-x86_64-baseos-rpms" --enable="rhel-10-for-x86_64-appstream-rpms" --enable="ansible-automation-platform-2.6-for-rhel-10-x86_64-rpms"

# 3. Download the AAP bundle from the host HTTP server (started by run_rhis_install_sequence.sh)
mkdir -p /root/aap-setup
echo "Bundle download starting at $(date)" >> /var/log/aap-setup-ready.log
curl -fL --retry 5 --retry-delay 15 http://{{HOST_INT_IP}}:8080/aap-bundle.tar.gz -o /root/aap-bundle.tar.gz
tar -xzf /root/aap-bundle.tar.gz -C /root/aap-setup --strip-components=1
rm -f /root/aap-bundle.tar.gz
echo "Bundle extracted. Ready for SSH callback." >> /var/log/aap-setup-ready.log

# 4. SSH setup — enable root login and inject host public key for SSH callback
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
systemctl enable sshd

mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<SSH_KEYS
{{AAP_SSH_PUB_KEY}}
SSH_KEYS
chmod 600 /root/.ssh/authorized_keys

# Log setup readiness for debugging
echo "[aap-setup] Bundle ready at /root/aap-setup on $(date)" >> /var/log/aap-setup-ready.log

# 5. Automation Hub credentials so the containerized installer can pull collections
cat > /root/.ansible.cfg <<ANSIBLECFG
[defaults]
galaxy_server_list = automation_hub

[galaxy_server.automation_hub]
url=https://console.redhat.com/api/automation-hub/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token={{HUB_TOKEN}}
ANSIBLECFG
chmod 600 /root/.ansible.cfg

# 6. Minimal single-node inventory for the containerized installer
cat > /root/aap-setup/inventory <<INVENTORY
[automationcontroller]
${AAP_HOSTNAME} ansible_connection=local

[all:vars]
admin_password='${AAP_ADMIN_PASS}'
pg_host=''
pg_port=5432
pg_database='awx'
pg_username='awx'
pg_password='${AAP_ADMIN_PASS}'
registry_username='${RH_USER}'
registry_password='${RH_PASS}'
INVENTORY
chmod 600 /root/aap-setup/inventory

# 7. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
net.core.somaxconn = 4096
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true
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

    echo -e "\n--- IdM Network (eth1 — static) ---"
    set_or_prompt IDM_IP      "IdM Static IP for eth1: " || return 1
    set_or_prompt IDM_NETMASK "Subnet Mask: "            || return 1
    set_or_prompt IDM_GW      "Gateway: "                || return 1

    echo -e "\n--- IdM Identity ---"
    set_or_prompt IDM_HOSTNAME   "IdM Hostname (FQDN): "               || return 1
    set_or_prompt DOMAIN         "Shared Domain Name: "                || return 1
    set_or_prompt IDM_ADMIN_PASS "IPA Admin Password: "  1             || return 1
    set_or_prompt IDM_DS_PASS    "Directory Service Password: " 1      || return 1
    normalize_shared_env_vars
    write_ansible_env_file
}

generate_idm_kickstart() {
    local ks_file="${KS_DIR}/idm.ks"
    local tmp_ks

    prompt_idm_details || return 1
    ensure_iso_vars || return 1

    tmp_ks="$(mktemp)"

    # --- Common header ---
    cat > "$tmp_ks" <<HEADER
text
reboot
keyboard us
lang en_US.UTF-8

network --bootproto=dhcp --device=eth0 --activate --onboot=yes
HEADER

    # --- eth1 (always static for internal provisioning/management network) ---
    cat >> "$tmp_ks" <<NET
network --bootproto=static --device=eth1 --ip=${IDM_IP} --netmask=${IDM_NETMASK} --gateway=${IDM_GW} --activate --onboot=yes --hostname=${IDM_HOSTNAME}

NET

    # --- Partitioning (DEMO vs production best-practice) ---
    if is_demo; then
        print_step "IdM kickstart: DEMO partition layout (/boot 2G + swap 4G + / rest)"
        cat >> "$tmp_ks" <<'DEMO_PART'
# DEMO Partitioning — minimal footprint for PoC/learning environments
# Requirements: 2 vCPU, 4 GB RAM, 30 GB raw storage
zerombr
clearpart --all --initlabel
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
# 1. Registration
subscription-manager register --username="${RH_USER}" --password="${RH_PASS}" --auto-attach

# 2. Hostname
hostnamectl set-hostname "${IDM_HOSTNAME}"

# 2.1 Local hosts mapping (temporary DNS-independent bootstrap)
cat > /etc/hosts <<EOF
127.0.0.1 localhost localhost.localdomain
${SAT_IP} ${SAT_HOSTNAME} ${SAT_HOSTNAME%%.*}
${AAP_IP} ${AAP_HOSTNAME} ${AAP_HOSTNAME%%.*}
${IDM_IP} ${IDM_HOSTNAME} ${IDM_HOSTNAME%%.*}
EOF

# 3. Repositories
subscription-manager repos --disable="*"
subscription-manager repos --enable="rhel-10-for-x86_64-baseos-rpms" --enable="rhel-10-for-x86_64-appstream-rpms"

# 4. IdM Server Installation (unattended)
ipa-server-install --unattended --realm="${IDM_REALM}" --domain="${IDM_DOMAIN}" --hostname="${IDM_HOSTNAME}" --admin-password="${IDM_ADMIN_PASS}" --ds-password="${IDM_DS_PASS}" --setup-dns --auto-forwarders --no-ntp

# 5. Performance baseline for virtual guests
systemctl enable --now qemu-guest-agent || true
systemctl enable --now tuned || true
tuned-adm profile virtual-guest || true
cat > /etc/sysctl.d/99-rhis-performance.conf <<'EOF'
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-rhis-performance.conf || true
%end
POSTEOF

    sudo mkdir -p "$KS_DIR"
    sudo install -m 0644 "$tmp_ks" "$ks_file"
    rm -f "$tmp_ks"
    print_success "Generated IdM kickstart: $ks_file"
}

write_kickstarts() {
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
    local extra_args
    local -a virt_install_cmd

	[ -n "$vm_name" ] || { print_warning "vm_name required"; return 1; }
	[ -n "$disk_path" ] || disk_path="${VM_DIR}/${vm_name}.qcow2"
	[ -n "$ks_file" ] || ks_file="${KS_DIR}/${vm_name}.ks"

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

	if [ ! -f "${ISO_PATH:-}" ]; then
		print_warning "ISO not found at ${ISO_PATH:-}. Aborting VM create for ${vm_name}."
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
        --network "network=external,model=virtio"
        --network "network=internal,model=virtio"
        --graphics "vnc,listen=127.0.0.1"
        --video vga
        --location "${ISO_PATH}"
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

	print_success "VM creation requested: $vm_name"
}

demokill_cleanup() {
    print_step "DEMOKILL: destroying demo VMs and cleaning generated files"

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

    print_step "Removing demo qcow2 disks and kickstarts"
    sudo rm -f \
        "${VM_DIR}/satellite-618.qcow2" \
        "${VM_DIR}/aap-26.qcow2" \
        "${VM_DIR}/idm.qcow2" \
        "${KS_DIR}/satellite-618.ks" \
        "${KS_DIR}/aap-26.ks" \
        "${KS_DIR}/idm.ks" \
        "${OEMDRV_ISO}" || true

    print_step "Removing staged AAP bundle directory"
    sudo rm -rf "${AAP_BUNDLE_DIR}" || true

    print_step "Checking RHIS-related lock files"
    cleanup_rhis_lock_files || true

    print_step "Removing RHIS temporary/cache artifacts"
    sudo rm -f \
        /tmp/aap-setup-*.log \
        /tmp/default.xml \
        /tmp/internal.xml \
        /tmp/OEMDRV.iso \
        /tmp/ks.cfg || true

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
    print_step "Preparing Satellite / AAP / IdM qcow2 VMs"
    prompt_use_existing_env
    normalize_shared_env_vars
    validate_resolved_kickstart_inputs || return 1

    local sat_disk sat_ram sat_vcpu
    local aap_disk aap_ram aap_vcpu
    local idm_disk idm_ram idm_vcpu

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

    create_vm_if_missing "satellite-618" "${VM_DIR}/satellite-618.qcow2" "$sat_disk" "$sat_ram" "$sat_vcpu" "${KS_DIR}/satellite-618.ks" "hd:LABEL=OEMDRV:/ks.cfg"

    # Start the HTTP server before the AAP VM boots so the bundle is available
    # when anaconda runs %post.
    if [ -d "${AAP_BUNDLE_DIR}" ]; then
        serve_aap_bundle || print_warning "Could not start AAP bundle HTTP server; AAP %post bundle download will fail."
    fi

    create_vm_if_missing "aap-26"        "${VM_DIR}/aap-26.qcow2"        "$aap_disk" "$aap_ram" "$aap_vcpu" "${KS_DIR}/aap-26.ks"

    # Post-boot callback orchestration: wait for AAP VM to boot, then run setup.sh remotely via SSH
    if [ "${AAP_HTTP_PID}" -gt 0 ] 2>/dev/null; then
           # The VM runs anaconda, reboots, then %post downloads+extracts the 3.5 GB bundle.
           # wait_for_vm_ssh polls up to 90 min — no fixed pre-sleep needed.
           print_step "AAP VM is installing. SSH callback will begin as soon as the VM is reachable (up to 90 min)."
           print_step "  You can monitor progress: sudo virsh console aap-26   (Ctrl+] to detach)"
           if run_aap_setup_on_vm "aap-26"; then
            print_success "AAP setup orchestration complete via SSH callback."
            create_aap_credentials
        else
            print_warning "AAP setup failed or timed out. Check ${AAP_SETUP_LOG_LOCAL} for details."
        fi

        # Stop the HTTP server now that setup is done
        if kill "${AAP_HTTP_PID}" 2>/dev/null; then
            print_success "AAP bundle HTTP server stopped (PID ${AAP_HTTP_PID})."
        fi
        close_aap_bundle_firewall
    fi

    create_vm_if_missing "idm"           "${VM_DIR}/idm.qcow2"           "$idm_disk" "$idm_ram" "$idm_vcpu" "${KS_DIR}/idm.ks"
}

setup_virt_manager() {
    print_step "Setting up Virt-Manager"
    configure_libvirt_firewall_policy
    enable_virt_manager_xml_editor
    enable_virt_manager_resize_guest
    configure_libvirt_networks
    download_rhel10_iso || true

    read -r -p "Create Satellite/AAP VMs now? [Y/n]: " build_vms
    case "${build_vms:-Y}" in
        Y|y|"") create_rhis_vms || print_warning "VM creation did not complete." ;;
        *) print_warning "Skipping VM creation." ;;
    esac

    print_success "Virt-Manager setup complete"
}

ensure_libvirtd() {
	if ! command -v libvirtd >/dev/null 2>&1; then
		print_warning "libvirtd not found. Installing..."
		sudo dnf install -y libvirt libvirt-daemon
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
	sudo dnf install -y genisoimage xorriso

	command -v genisoimage >/dev/null 2>&1 || command -v xorriso >/dev/null 2>&1
}

main() {
    parse_args "$@"
    apply_cli_overrides

    # CLI-only fast path: DEMOKILL should never require env/vault prompts.
    if [ -n "${CLI_DEMOKILL:-}" ] || [ "${MENU_CHOICE:-}" = "8" ]; then
        print_step "DEMOKILL requested from CLI; skipping credential prompts"
        demokill_cleanup || { print_warning "DEMOKILL failed"; exit 1; }
        print_success "Run complete"
        exit 0
    fi

    if [ ! -f "$ANSIBLE_ENV_FILE" ]; then
        load_preseed_env
    fi
    load_ansible_env_file
    normalize_shared_env_vars
    prompt_all_env_options_once
    normalize_shared_env_vars
    retire_preseed_env_file
    print_runtime_configuration

	print_step "Startup: Checking libvirtd"
	ensure_libvirtd || { print_warning "libvirtd check failed"; exit 1; }

	print_step "Startup: Checking ISO image tools"
	ensure_iso_tools || { print_warning "ISO image tools check failed"; exit 1; }

	while true; do
		show_menu
		case "$choice" in
			1) install_local ;;
			2) install_container ;;
			3) setup_virt_manager ;;
			4) install_local; setup_virt_manager ;;
            5) install_container; setup_virt_manager ;;
            6) generate_satellite_oemdrv_only ;;
            0) print_success "Exiting installation script"; exit 0 ;;
            8) demokill_cleanup ;;
            *) print_warning "Invalid choice. Please select 0-6." ;;
		esac

        if is_noninteractive || [ "${RUN_ONCE:-0}" = "1" ]; then
            print_success "Run complete"
            exit 0
        fi

		read -r -p "Press Enter to continue..."
	done
}

main "$@"

