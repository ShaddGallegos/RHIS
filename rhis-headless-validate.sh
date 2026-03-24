#!/bin/bash
# rhis-headless-validate.sh
# 
# Validates RHIS headless environment configuration before deployment
# Usage: ./rhis-headless-validate.sh [--env-file /path/to/env] [--menu-choice N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${RHIS_ENV_FILE:-/etc/rhis/headless.env}"
MENU_CHOICE="${1:-5}"
DRY_RUN="${RHIS_DRY_RUN:-0}"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
WARN=0
FAIL=0

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RHIS Headless Environment Validation                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

header() {
    echo ""
    echo -e "${BLUE}━━ $1${NC}"
}

# Load environment file
header "Loading Environment File"

if [ ! -f "$ENV_FILE" ]; then
    check_fail "Environment file not found: $ENV_FILE"
    echo ""
    echo "Create one from template:"
    echo "  cp ${SCRIPT_DIR}/rhis-headless.env.template /etc/rhis/headless.env"
    exit 1
fi

check_pass "Environment file exists: $ENV_FILE"

# Source the file
if ! source "$ENV_FILE" 2>/dev/null; then
    check_fail "Failed to parse environment file (syntax error)"
    exit 1
fi

check_pass "Environment file is valid shell syntax"

# Determine menu choice
if [ -n "${1:-}" ]; then
    MENU_CHOICE="$1"
fi

echo ""
echo "Menu choice: $MENU_CHOICE"
echo ""

# Menu-specific required variables
case "$MENU_CHOICE" in
    1|2)
        REQUIRED_VARS=("RH_USER" "RH_PASS" "ADMIN_PASS")
        MODE="Local App / Container"
        ;;
    3)
        REQUIRED_VARS=("IDM_IP" "IDM_HOSTNAME" "IDM_GW" "IDM_NETMASK" "SAT_IP" "SAT_HOSTNAME" "AAP_IP" "AAP_HOSTNAME" "ADMIN_PASS")
        MODE="Virt-Manager Only"
        ;;
    4)
        REQUIRED_VARS=("RH_USER" "RH_PASS" "ADMIN_PASS" "IDM_IP" "IDM_HOSTNAME" "ADMIN_USER" "DOMAIN" "IDM_DS_PASS" "SAT_IP" "SAT_HOSTNAME" "SAT_ORG" "SAT_LOC" "AAP_IP" "AAP_HOSTNAME" "HUB_TOKEN" "ADMIN_PASS")
        MODE="Full Setup (Local + Virt-Manager)"
        ;;
    5)
        REQUIRED_VARS=("RH_USER" "RH_PASS" "ADMIN_PASS" "IDM_IP" "IDM_HOSTNAME" "ADMIN_USER" "DOMAIN" "IDM_DS_PASS" "SAT_IP" "SAT_HOSTNAME" "SAT_ORG" "SAT_LOC" "AAP_IP" "AAP_HOSTNAME" "HUB_TOKEN" "ADMIN_PASS")
        MODE="Full Setup (Container + Virt-Manager)"
        ;;
    7)
        REQUIRED_VARS=("RH_USER" "RH_PASS" "ADMIN_PASS" "IDM_IP" "DOMAIN" "IDM_DS_PASS" "SAT_IP" "AAP_IP" "HUB_TOKEN")
        MODE="Container Config-Only"
        ;;
    *)
        check_fail "Invalid menu choice: $MENU_CHOICE (must be 1-7)"
        exit 1
        ;;
esac

# Validate required variables
header "Validating Required Variables for $MODE"

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        check_fail "$var is required but not set"
    else
        # Mask passwords in output
        val="${!var}"
        if [[ "$var" == *"PASS"* ]] || [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"TOKEN"* ]]; then
            val="***REDACTED***"
        fi
        check_pass "$var is set ($val)"
    fi
done

# General checks
header "System Requirements"

# Check if running on Linux
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    check_pass "Running on Linux"
else
    check_fail "This script requires Linux (detected: $OSTYPE)"
fi

# Check if root or has sudo
if [ "$EUID" -eq 0 ]; then
    check_pass "Running as root"
elif sudo -n true 2>/dev/null; then
    check_pass "Running with passwordless sudo"
else
    check_warn "Not running as root and sudo requires password"
fi

# Check required commands
header "Required Commands"

REQUIRED_CMDS=("virsh" "podman" "ssh" "ssh-keygen" "jq" "curl")

for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        check_pass "$cmd is available"
    else
        check_fail "$cmd is not installed"
    fi
done

# Check SSH keys
header "SSH Configuration"

if [ -f "${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}" ]; then
    check_pass "SSH private key exists"
else
    check_warn "SSH private key not found at ${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
fi

if [ -f "${SSH_PUB_KEY_PATH:-$HOME/.ssh/id_rsa.pub}" ]; then
    check_pass "SSH public key exists"
else
    check_fail "SSH public key not found at ${SSH_PUB_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"
fi

# Network validation
header "Network Configuration"

# Check host IP is reachable
if ping -c 1 "${HOST_INT_IP}" >/dev/null 2>&1; then
    check_pass "Internal host IP is reachable: ${HOST_INT_IP}"
else
    check_warn "Cannot ping internal host IP: ${HOST_INT_IP}"
fi

# Check if IPs are in valid range (basic CIDR validation)
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

for ip_var in "IDM_IP" "SAT_IP" "AAP_IP" "HOST_INT_IP"; do
    ip="${!ip_var:-}"
    if [ -n "$ip" ]; then
        if validate_ip "$ip"; then
            check_pass "$ip_var is valid IP: $ip"
        else
            check_fail "$ip_var is not a valid IP address: $ip"
        fi
    fi
done

# Hostname validation
header "Hostname Configuration"

validate_fqdn() {
    local fqdn=$1
    if [[ $fqdn =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

for hostname_var in "IDM_HOSTNAME" "SAT_HOSTNAME" "AAP_HOSTNAME"; do
    hostname="${!hostname_var:-}"
    if [ -n "$hostname" ]; then
        if validate_fqdn "$hostname"; then
            check_pass "$hostname_var is valid FQDN: $hostname"
        else
            check_fail "$hostname_var is not a valid FQDN: $hostname"
        fi
    fi
done

# Storage space check
header "Storage Requirements"

REQUIRED_STORAGE_GB=300  # Rough estimate: 100 GB per VM

available_storage=$(df -B1 /var/lib/libvirt 2>/dev/null | awk 'NR==2 {print $4}' | awk '{print int($1/1024/1024/1024)}')

if [ -n "$available_storage" ]; then
    if [ "$available_storage" -gt "$REQUIRED_STORAGE_GB" ]; then
        check_pass "/var/lib/libvirt has sufficient storage: ${available_storage}GB (need ~${REQUIRED_STORAGE_GB}GB)"
    else
        check_fail "/var/lib/libvirt insufficient storage: ${available_storage}GB (need ~${REQUIRED_STORAGE_GB}GB)"
    fi
else
    check_warn "Could not determine storage availability"
fi

# Memory check
header "Memory Requirements"

total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_memory_gb=$((total_memory_kb / 1024 / 1024))
required_memory_gb=64  # Rough: 16 IdM + 32 Satellite + 16 AAP

if [ "$total_memory_gb" -gt "$required_memory_gb" ]; then
    check_pass "System memory adequate: ${total_memory_gb}GB (recommended $required_memory_gb GB+)"
else
    check_warn "System memory may be insufficient: ${total_memory_gb}GB (recommended ${required_memory_gb}GB+)"
fi

# Connectivity tests
header "Connectivity Tests"

# Test Red Hat CDN access
if curl -s --connect-timeout 5 "https://api.access.redhat.com/ping" -o /dev/null 2>&1; then
    check_pass "Red Hat CDN is reachable"
else
    check_fail "Cannot reach Red Hat CDN (needed for RH_PASS validation)"
fi

# Test DNS
if nslookup example.com >/dev/null 2>&1; then
    check_pass "DNS is functional"
else
    check_warn "DNS resolution may not be working properly"
fi

# Suggest next steps
header "Next Steps"

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "You can now run the RHIS installer:"
    echo ""
    echo "  source $ENV_FILE"
    echo "  ${SCRIPT_DIR}/rhis_install.sh --non-interactive --menu-choice $MENU_CHOICE"
    echo ""
    if [ "$WARN" -gt 0 ]; then
        echo -e "Note: There are $WARN warnings. Review above and address if necessary."
    fi
else
    echo ""
    echo -e "${RED}✗ Critical checks failed. Fix the above issues before proceeding.${NC}"
    echo ""
fi

# Summary
header "Summary"

echo ""
echo -e "Passed:   ${GREEN}$PASS${NC}"
echo -e "Warnings: ${YELLOW}$WARN${NC}"
echo -e "Failed:   ${RED}$FAIL${NC}"
echo ""

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN mode - no changes made"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
