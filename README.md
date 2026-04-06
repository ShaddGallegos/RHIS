# MiniRHIS - Red Hat Infrastructure Standard

## Synopsis

MINIRHIS stands for **Red Hat Infrastructure Standard**.

This repository is built around `MiniRHIS.sh` (MiniRHIS), an orchestration script for building and bootstrapping a Red Hat management lab on libvirt/KVM.

The current workflow focuses on:

- **Red Hat Satellite 6.18**
- **Red Hat Ansible Automation Platform 2.6**
- **Red Hat Identity Management (IdM / FreeIPA)**
- optional **MINIRHIS container** deployment

The script automates:

- encrypted configuration capture with `ansible-vault`
- RHEL ISO preparation
- kickstart generation for Satellite, AAP, and IdM
- unattended VM creation on libvirt/KVM
- RHSM registration and repo enablement during kickstart `%post`
- automatic `rhc connect` in guest `%post` (enabled by default)
- initial Day-0 bootstrap actions required to continue automated configuration

If you are starting fresh, review:

- [CHECKLIST.md](CHECKLIST.md) — what must be provided by the user and where to obtain it

---

## Table of contents

- [Quick start](#quick-start)
- [Main entry point](#main-entry-point)
- [Headless Operations](#headless-operations)
- [Headless Quick Reference](#headless-quick-reference)
- [Headless Troubleshooting](#headless-troubleshooting)
- [Recovery & Diagnostics](#recovery--diagnostics)
- [Configuration and secrets](#configuration-and-secrets)
- [Default lab layout](#default-lab-layout)
- [Kickstart generation](#kickstart-generation)
- [VM provisioning behavior](#vm-provisioning-behavior)
- [Virt-manager and libvirt setup](#virt-manager-and-libvirt-setup)
- [DEMOKILL behavior](#demokill-behavior)
- [MINIRHIS CMDB / HTML dashboard](#minirhis-cmdb--html-dashboard)
- [MINIRHIS Hardware Planning & Resource Management Guide (RHEL 10)](#minirhis-hardware-planning--resource-management-guide-rhel-10)
- [Directory Structure & Configuration Files](#directory-structure--configuration-files)
- [Important files](#important-files)
- [Recommended run sequence](#recommended-run-sequence)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

---

## Purpose of this repository

[⬆ Back to top](#table-of-contents)

This repository is intended for repeatable build-out of a Red Hat infrastructure management stack with:

- one **external** network for updates and remote access
- one **internal** network for provisioning, orchestration, and management
- consistent bootstrap of these core nodes:
  - `satellite`
  - `aap`
  - `idm`

This is primarily an **infrastructure provisioning and bootstrap repository**, not just a generic application project.

The machine where you execute `MiniRHIS.sh` is the **installer host**. Host-side prerequisites and collection management are resolved there.

---

## Installer host responsibilities

[⬆ Back to top](#table-of-contents)

`MiniRHIS.sh` is expected to ensure installer-host software requirements using `dnf`/`pip` (current platform profile focuses on libvirt + virt-manager workflows).

It also ensures host-side Ansible collections in this order:

1. Red Hat Automation Hub (`console.redhat.com`, published/validated)
2. Fallback to `galaxy.ansible.com` when not available there

This keeps the installer host self-sufficient for the MiniRHIS workflow.

---

## Quick start

[⬆ Back to top](#table-of-contents)

### What's new

- Container-first automation now supports a prescribed config order:
  - `IdM -> Satellite -> AAP`
- Menu option `2` (Container Deployment) now auto-runs config-as-code by default.
- New one-shot workflow:
  - `./MiniRHIS.sh --container-config-only`
- Retry behavior for transient failures:
  - Failed phases are retried once by default.
  - Disable with `MINIRHIS_RETRY_FAILED_PHASES_ONCE=0`.
- Auto-sequence after menu option `2` can be disabled with:
  - `MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0`

### Recommended first run

```bash
./MiniRHIS.sh --reconfigure
```

### Clean up a previous demo run

```bash
./MiniRHIS.sh --DEMOKILL
```

### Build the demo stack

```bash
./MiniRHIS.sh --DEMO
```

---

## Main entry point

[⬆ Back to top](#table-of-contents)

The main workflow is:

```bash
./MiniRHIS.sh
```

### Interactive menu options

- `1` Local Installation (npm)
- `2` Container Deployment (Podman) + auto config-as-code (`IdM -> Satellite -> AAP`)
- `3` Setup Virt-Manager Only
- `4` Full Setup (Local + Virt-Manager)
- `5` Full Setup (Container + Virt-Manager)
- `6` Generate Satellite OEMDRV Only
- `7` Container Config-Only (`IdM -> Satellite -> AAP`)
- `8` Live Status Dashboard
- `9` Install Satellite 6.18 Only
- `10` Install IdM 5.0 Only
- `11` Install AAP 2.6 Only
- `0` Exit

Environment toggles:

- `MINIRHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0` disables auto config-as-code after menu option `2`
- `MINIRHIS_RETRY_FAILED_PHASES_ONCE=0` disables automatic retry of failed config-as-code phases
- `RHC_AUTO_CONNECT=0` disables automatic `rhc connect` during guest kickstart `%post`
- `MINIRHIS_POST_VM_SETTLE_GRACE=650` default guest settle window before SSH preflight checks
- `MINIRHIS_INTERNAL_SSH_WARN_GRACE=<seconds>` delay before per-host warning logs (default `600`)
- `MINIRHIS_INTERNAL_SSH_LOG_EVERY=<seconds>` periodic preflight progress log cadence (default `60`)

### Command-line options

```text
--non-interactive        Run without prompts; required values must already be set
--menu-choice <0-11>     Preselect a visible menu option
--env-file <path>        Load preseed variables from a custom env file
--inventory <template>   Pin AAP inventory template; skips interactive submenu
--inventory-growth <tpl> Pin AAP inventory-growth template; skips interactive submenu
                         Interactive (no --non-interactive): a guided submenu with
                         About pages is presented when template values are unset.
                         --DEMO always forces DEMO-inventory.j2 and skips the submenu.
--container-config-only  One-shot: start container + run IdM -> Satellite -> AAP
--satellite              Run Satellite 6.18-only workflow (menu option 9)
--idm                    Run IdM 5.0-only workflow (menu option 10)
--aap                    Run AAP 2.6-only workflow (menu option 11)
--attach-consoles        Re-open VM console monitors for Satellite/AAP/IdM
  --status                 Read-only status snapshot (no provisioning changes)
--reconfigure            Prompt for all installer values and update env.yml
--test[=fast|full]       Run a curated non-interactive test sweep and print a summary
--DEMO            Use demo sizing/profile for VM specs
--DEMOKILL        CLI-only cleanup for demo VMs/files/temp artifacts/lock files/processes
--help                   Show usage
```

### AAP installer inventory selection

When running interactively without a pre-configured template, the script presents
a guided **inventory architecture submenu**:

```text
  0) Exit              -- Return to previous menu
  1) inventory         -- Enterprise / Multi-Node deployment
  2) About inventory   -- Name, synopsis, diagram & guidance
  3) inventory-growth  -- Growth / Single-Node containerized
  4) About inventory-growth
                       -- Name, synopsis, diagram & guidance
```

Choosing **2** or **4** shows a full About page (topology diagram, setup steps,
why Red Hat recommends that model) and then returns to the submenu.
`--DEMO` bypasses the submenu and auto-selects `DEMO-inventory.j2`.

To skip the submenu non-interactively, pass `--inventory` and `--inventory-growth`
or pre-set `AAP_INVENTORY_TEMPLATE` / `AAP_INVENTORY_GROWTH_TEMPLATE` in your env file.
See [inventory/README.md](inventory/README.md) for template details.

### Generated Ansible runtime files

MINIRHIS now generates a host-side Ansible config for provisioner runs and mounts it into the container automatically:

- `~/.ansible/conf/minirhis-ansible.cfg` — generated MINIRHIS Ansible runtime config
- `~/.ansible/conf/ansible-provisioner.log` — stable provisioner log file
- `~/.ansible/conf/facts-cache/` — Ansible fact cache

The provisioner container uses that generated config via `ANSIBLE_CONFIG` and writes logs/cache on the host through the existing vault bind mount.

### IdM 5.0 repository prerequisites

For IdM 5.0 installation/configuration paths, ensure the target system has access to these repositories:

```bash
subscription-manager repos --enable="rhel-10-for-x86_64-baseos-rpms" \
--enable="rhel-10-for-x86_64-appstream-rpms"
```

### Container one-shot examples

```bash
./MiniRHIS.sh --container-config-only
```

Run one-shot container workflow without retries:

```bash
MINIRHIS_RETRY_FAILED_PHASES_ONCE=0 ./MiniRHIS.sh --container-config-only
```

Re-open VM console monitors after boot:

```bash
./MiniRHIS.sh --attach-consoles
```

Read-only health/status snapshot (no provisioning changes):

```bash
./MiniRHIS.sh --status
```

Run a fast noninteractive validation sweep (recommended after `--DEMOKILL`):

```bash
./MiniRHIS.sh --test=fast --DEMO
```

Run the broader integration-style validation sweep:

```bash
./MiniRHIS.sh --test=full --DEMO
```

### Common examples

Generate only the Satellite kickstart and `OEMDRV.iso`:

```bash
./MiniRHIS.sh --menu-choice 6
```

Run fully unattended:

```bash
./MiniRHIS.sh --non-interactive --menu-choice 6
```

Use a custom bootstrap env file:

```bash
./MiniRHIS.sh --env-file /path/to/custom.env --menu-choice 3
```

Re-prompt for all saved values:

```bash
./MiniRHIS.sh --reconfigure
```

Destroy demo resources and clean leftovers:

```bash
./MiniRHIS.sh --DEMOKILL
```

---

## Headless Operations

[⬆ Back to top](#table-of-contents)

MINIRHIS can run on headless systems (no display/keyboard) using environment variables and command-line flags instead of interactive prompts.

### Quick Start: Headless Container + VMs Deployment

```bash
# Create an environment file with all required values
cat > /tmp/minirhis-headless.env << 'EOF'
# Core Credentials
RH_USER="your-rhn-username"
RH_PASS="your-rhn-password"
ADMIN_USER="rhisadmin"
ADMIN_PASS="secure-admin-password"

# IdM Configuration
IDM_IP="10.168.128.3"
IDM_NETMASK="255.255.255.0"
IDM_GW="10.168.128.1"
IDM_HOSTNAME="idm.example.com"
IDM_ALIAS="idm"
DOMAIN="example.com"
IDM_DS_PASS="secure-ds-password"

# Satellite Configuration
SAT_IP="10.168.128.1"
SAT_NETMASK="255.255.255.0"
SAT_GW="10.168.128.1"
SAT_HOSTNAME="satellite.example.com"
SAT_ORG="Default_Organization"
SAT_LOC="Default_Location"

# AAP Configuration
AAP_IP="10.168.128.2"
AAP_NETMASK="255.255.255.0"
AAP_GW="10.168.128.1"
AAP_HOSTNAME="aap.example.com"
AAP_ADMIN_USER="admin"
AAP_ADMIN_EMAIL="admin@example.com"
HUB_TOKEN="your-automation-hub-token"

# Network Configuration
HOST_EXT_IP="192.168.1.X"          # Your host's external IP
HOST_INT_IP="10.168.128.1"          # Your host's internal network IP
MGMT_NETWORK="10.168.128.0/24"

# Feature Flags (optional - defaults shown)
DEMO_MODE=0
MINIRHIS_ENABLE_POST_HEALTHCHECK=1
MINIRHIS_HEALTHCHECK_AUTOFIX=1
EOF

# Run headless installation (Container + VMs + Config-as-Code)
./MiniRHIS.sh \
  --non-interactive \
  --menu-choice 5 \
  --env-file /tmp/minirhis-headless.env
```

**Expected Flow:**

1. Loads env vars from file
2. Skips all interactive prompts
3. Deploys container (Podman)
4. Creates VM infrastructure (Virt-Manager)
5. Runs config-as-code phases (IdM → Satellite → AAP)
6. Exits with status code 0 on success

### Required Environment Variables

**Authentication (Required)**

```bash
RH_USER="<Red Hat CDN username>"
RH_PASS="<Red Hat CDN password>"
ADMIN_USER="<local admin user>"
ADMIN_PASS="<local admin password>"
```

**IdM Configuration (Required for Options 3-5)**

```bash
IDM_IP="10.168.128.3"              # Static IP on internal network
IDM_NETMASK="255.255.255.0"        # /24 = 255.255.255.0
IDM_GW="10.168.128.1"              # Gateway (usually your host)
IDM_HOSTNAME="idm.example.com"     # FQDN required
IDM_ALIAS="idm"                    # Short name
DOMAIN="example.com"               # Base domain
IDM_DS_PASS="secure-password"      # Directory Service password
```

**Satellite Configuration (Required for Options 3-5)**

```bash
SAT_IP="10.168.128.1"              # Static IP
SAT_NETMASK="255.255.255.0"        
SAT_GW="10.168.128.1"              
SAT_HOSTNAME="satellite.example.com"
SAT_ORG="Default_Organization"     # Satellite org name
SAT_LOC="Default_Location"         # Satellite location
```

**AAP Configuration (Required for Options 3-5)**

```bash
AAP_IP="10.168.128.2"              # Static IP
AAP_NETMASK="255.255.255.0"        
AAP_GW="10.168.128.1"              
AAP_HOSTNAME="aap.example.com"     # FQDN required
AAP_ADMIN_USER="admin"             
AAP_ADMIN_EMAIL="admin@example.com"
HUB_TOKEN="<your-hub-token>"       # Automation Hub token
```

**Network Configuration (Optional)**

```bash
HOST_EXT_IP="192.168.1.100"        # External NIC IP (default: auto-detect)
HOST_INT_IP="10.168.128.1"         # Internal NIC IP (default: 10.168.128.1)
MGMT_NETWORK="10.168.128.0/24"     # Internal network (default: auto-calc)
```

### Exit Codes

| Code | Meaning                               |
| ---- | ------------------------------------- |
| 0    | Success                               |
| 1    | General error (check logs)            |
| 2    | Invalid CLI flag                      |
| 3    | Missing required environment variable |
| 4    | Network/connectivity error            |
| 5    | Container/VM operation failed         |

### Expected Timeline

| Phase             | Duration       | What's Happening                  |
| ----------------- | -------------- | --------------------------------- |
| Container setup   | 2-5 min        | Download image, run provisioner   |
| VM creation       | 5-10 min       | Create 3 VMs, allocate storage    |
| IdM install       | 15-20 min      | IdM server install + web UI ready |
| Satellite install | 20-30 min      | Satellite installer runs          |
| AAP install       | 10-15 min      | AAP setup + callback              |
| **Total**         | **~60-90 min** | Complete deployment               |

---

## Headless Quick Reference

[⬆ Back to top](#table-of-contents)

### One-Command Deployment

```bash
# 1. Copy template
cp minirhis-headless.env.template /etc/minirhis/headless.env

# 2. Edit with your values
nano /etc/minirhis/headless.env

# 3. Run deployment
source /etc/minirhis/headless.env
./MiniRHIS.sh --non-interactive --menu-choice 5
```

### Environment Variables Cheat Sheet

| Variable       | Purpose              | Example                 | Required     |
| -------------- | -------------------- | ----------------------- | ------------ |
| `RH_USER`      | Red Hat CDN username | `rh_user@example.com`   | Menu 1,2,4,5 |
| `RH_PASS`      | Red Hat CDN password | `secure-pass`           | Menu 1,2,4,5 |
| `ADMIN_PASS`   | Local admin password | `P@ssw0rd123!`          | Menu 3,4,5,7 |
| `IDM_IP`       | IdM VM IP (internal) | `10.168.128.3`          | Menu 3,4,5,7 |
| `IDM_HOSTNAME` | IdM FQDN             | `idm.example.com`       | Menu 4,5,7   |
| `SAT_IP`       | Satellite VM IP      | `10.168.128.1`          | Menu 3,4,5,7 |
| `SAT_HOSTNAME` | Satellite FQDN       | `satellite.example.com` | Menu 4,5,7   |
| `AAP_IP`       | AAP VM IP            | `10.168.128.2`          | Menu 3,4,5,7 |
| `AAP_HOSTNAME` | AAP FQDN             | `aap.example.com`       | Menu 4,5,7   |
| `HUB_TOKEN`    | Automation Hub token | `eyJ...`                | Menu 4,5,7   |

---

## Headless Troubleshooting

[⬆ Back to top](#table-of-contents)

### Common Issues & Solutions

**Issue 1: "NONINTERACTIVE mode requires X to be set"**

```bash
# Check which variable is missing
env | grep -E "^(RH_|IDM_|SAT_|AAP_|ADMIN_|HUB_|DOMAIN|HOST_)"

# Export individually if needed
export RH_USER="username"
export RH_PASS="password"
export ADMIN_PASS="password"
```

**Issue 2: "Cannot reach aap via SSH"**

```bash
# Check VM status
virsh list --all | grep aap

# Test SSH manually
ssh -o ConnectTimeout=5 root@10.168.128.2 "hostname"

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
```

**Issue 3: Installation hangs with no output**

```bash
# Monitor real-time logs
tail -100f /var/log/minirhis/minirhis_install_*.log

# Check container execution
podman ps -a
podman logs -f minirhis-provisioner
```

**Issue 4: Container fails to start**

```bash
# Stop and remove old container
podman stop minirhis-provisioner 2>/dev/null || true
podman rm minirhis-provisioner 2>/dev/null || true

# Re-run installer
./MiniRHIS.sh --non-interactive --menu-choice 5
```

**Issue 5: "Failed to reach Satellite/IdM web UI"**

```bash
# Check service status
ssh root@10.168.128.1 "systemctl status satellite"
ssh root@10.168.128.1 "systemctl status httpd"

# Check if port is listening
ssh root@10.168.128.1 "ss -tlnp | grep :443"
```

### Cleanup

After deployment or if starting over:

```bash
# Stop all MINIRHIS services
podman stop minirhis-provisioner

# Remove all VMs  
for vm in satellite aap idm; do
  virsh destroy "$vm" 2>/dev/null || true
  virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
done

# Remove container
podman rm minirhis-provisioner

# Start fresh
./MiniRHIS.sh --non-interactive --menu-choice 5
```

---

## Recovery & Diagnostics

[⬆ Back to top](#table-of-contents)

### Situation: Config-as-Code Phases Failed

If IdM, Satellite, or AAP playbooks fail during deployment:

**Recovery Procedures**

**Option A: Retry Config-as-Code (Recommended - Simple)**

```bash
# Re-run the config-as-code phases
./MiniRHIS.sh --non-interactive --menu-choice 7
```

**Option B: Re-run Full MINIRHIS Installer**

```bash
# Backup any important logs/configs:
cp -r /var/log/minirhis /var/log/minirhis.backup.2026-03-24

# Stop the container:
podman rm -f minirhis-provisioner

# Re-run the installer:
cd ~/GIT/MINIRHIS
./MiniRHIS.sh
```

**Option C: Manual Phase Re-execution**

```bash
# Connect to provisioner container:
podman exec -it -e ANSIBLE_DEBUG=1 minirhis-provisioner /bin/bash

# Run IdM with verbose output:
cd /minirhis
ansible-playbook -vvv \
  --inventory /minirhis/vars/external_inventory/hosts \
  --vault-password-file /minirhis/vars/vault/.vaultpass.container \
  --extra-vars @/minirhis/vars/vault/env.yml \
  --limit scenario_idm \
  /minirhis/minirhis-builder-idm/main.yml 2>&1 | tee /tmp/idm-playbook.log
```

**Option D: Isolated Component Testing**

```bash
# Test IdM SSH connectivity and basic services:
ssh root@10.168.128.3 "ipactl status && systemctl status ipa httpd"

# Test Satellite SSH connectivity:
ssh root@10.168.128.1 "systemctl status httpd"

# Test AAP SSH connectivity:
ssh root@10.168.128.2 "whoami"
```

### Verification

After remediation, verify all phases pass:

```bash
# Check IdM
curl -k https://10.168.128.3/ipa/ui/ && echo "✓  IdM UI reached"

# Check Satellite
curl -k https://10.168.128.1/ && echo "✓  Satellite web reached"

# Check AAP (after setup completes)
curl -k https://10.168.128.2/ && echo "✓  AAP web reached"
```

---

## Directory Structure & Configuration Files

[⬆ Back to top](#table-of-contents)

### Top-Level Files

| File           | Purpose                                             |
| -------------- | --------------------------------------------------- |
| `MiniRHIS.sh`  | Primary orchestration script                        |
| `CHECKLIST.md` | Required user-provided inputs and where to get them |
| `README.md`    | This document - complete MINIRHIS documentation         |
| `LICENSE`      | License information                                 |

### Directory: `host_vars/`

This directory is bind-mounted into the `minirhis-provisioner` container at `/minirhis/vars/host_vars/`.

**Setup:** Copy each `*.SAMPLE` file to its actual name and fill in real values:

- `host_vars/satellite.yml` — Satellite VM connection + org/location vars
- `host_vars/aap.yml` — AAP admin credentials
- `host_vars/idm.yml` — IdM realm/domain overrides
- `host_vars/installer.yml` — Controller/installer host SSH settings

**Runtime Note:** `MiniRHIS.sh` regenerates `host_vars/*.yml` during config-as-code startup. Treat these files as generated runtime artifacts.

### Directory: `inventory/`

This directory is bind-mounted into the `minirhis-provisioner` container at `/minirhis/vars/external_inventory/`.

**Setup:**

1. Copy `hosts.SAMPLE` → `hosts` and fill in your actual hostnames and IPs.
2. The `hosts` file is referenced by all minirhis-builder playbooks.

**Group Names:**

| Group                | Purpose                        |
| -------------------- | ------------------------------ |
| `scenario_satellite` | Satellite VM                   |
| `aap`                | Ansible Automation Platform VM |
| `idm`                | Red Hat Identity Management VM |

**AAP Inventory Templates:**

Available deployment models:

1. **Enterprise / Multi-Node** (`inventory.j2`): All AAP components on separate VMs
2. **Growth / Single-Node** (`inventory-growth.j2`): All AAP components co-located on one VM
3. **DEMO** (`DEMO-inventory.j2`): Forced automatically with `--DEMO`

**CLI Overrides:**

```bash
# Force DEMO model
./MiniRHIS.sh --non-interactive --DEMO

# Pin specific topology
./MiniRHIS.sh --non-interactive \
   --inventory inventory.j2
```

---

## Configuration and secrets

[⬆ Back to top](#table-of-contents)

The script stores working configuration in:

- `~/.ansible/conf/env.yml` — encrypted with `ansible-vault`
- `~/.ansible/conf/.vaultpass.txt` — local vault password file

On first run, the script prompts for required values and writes encrypted configuration.
On later runs, it reloads saved values and only prompts for missing or unresolved entries unless `--reconfigure` is used.

`--env-file` remains supported for bootstrap/preseed use, but the vault-backed `env.yml` is the authoritative runtime source.

### Core user-supplied values

At minimum, be ready to provide:

- Red Hat CDN username and password
- Red Hat offline token
- Red Hat access token
- RHEL ISO URL
- AAP bundle URL
- Automation Hub token
- shared admin username/password
- shared domain and realm
- Satellite, AAP, and IdM IPs / hostnames
- Satellite organization and location
- IdM admin and DS passwords

For the detailed list, use:

- `CHECKLIST.md`

---

## Default lab layout

[⬆ Back to top](#table-of-contents)

By default, the script uses these internal addresses:

| Node      |     Default IP | Default Hostname Pattern |
| --------- | -------------: | ------------------------ |
| Satellite | `10.168.128.1` | `satellite.<domain>`     |
| AAP       | `10.168.128.2` | `aap.<domain>`           |
| IdM       | `10.168.128.3` | `idm.<domain>`           |

Shared defaults also include:

- `INTERNAL_NETWORK=10.168.0.0`
- `NETMASK=255.255.0.0`
- `INTERNAL_GW=10.168.0.1`

Connectivity defaults also include:

- `RHC_AUTO_CONNECT=1` (attempt `rhc connect` by default on Satellite, AAP, and IdM)

Role aliases (used for hostname-role matching and inventory convenience names):

- `SAT_ALIAS=satellite`
- `AAP_ALIAS=aap`
- `IDM_ALIAS=idm`

Adjust these during `--reconfigure` if your environment needs different values.

Satellite service/provisioning settings are also defaulted, prompted, and then
persisted in encrypted `~/.ansible/conf/env.yml` (for example:
`SAT_FIREWALLD_INTERFACE`, `SAT_FIREWALLD_ZONE`,
`SAT_FIREWALLD_SERVICES_JSON`, `SAT_PROVISIONING_*`, `SAT_DNS_ZONE`,
`SAT_DNS_REVERSE_ZONE`).

---

## Kickstart generation

[⬆ Back to top](#table-of-contents)

The script generates unattended kickstarts for:

- Satellite
- AAP
- IdM

### Satellite OEMDRV workflow

The Satellite build produces:

- `kickstarts/satellite.ks`
- `/var/lib/libvirt/images/OEMDRV.iso`

Satellite boots using:

- `inst.ks=hd:LABEL=OEMDRV:/ks.cfg`

### What the generated kickstarts include

All generated kickstarts include the automation required for Day-0 bootstrap, including:

- text-mode unattended installation
- BIOS/GPT-safe partitioning
- root/admin bootstrap accounts
- static provisioning-side internal network configuration
- local `/etc/hosts` seeding across Satellite, AAP, and IdM
- RHSM registration in `%post`
- purpose-specific repository enablement with validation

### Product-specific kickstart behavior

#### Satellite

- registers to RHSM during `%post`
- enables required Satellite 6.18 repositories
- runs `satellite-installer`
- prepares the system for management, provisioning, and follow-on automation

#### AAP

- registers to RHSM during `%post`
- enables AAP-specific repositories
- stages the AAP containerized setup bundle
- prepares SSH/bootstrap content used by the host callback workflow

#### IdM

- registers to RHSM during `%post`
- enables required base repositories
- runs unattended `ipa-server-install`

### RHSM and repository enablement

The script now enforces registration and repo configuration during kickstart `%post` by:

- retrying RHSM registration
- refreshing subscription data
- disabling all repositories first
- enabling only required repositories for the system’s role
- validating that those repositories are actually enabled before continuing

---

## VM provisioning behavior

[⬆ Back to top](#table-of-contents)

When you choose a libvirt build path, the script:

1. validates configuration
2. generates kickstarts
3. stages the AAP bundle on the host
4. creates these VMs:

- `idm`
- `satellite`
- `aap`

1. enables `virsh autostart` for each VM
2. checks that the three VMs are left in an ON/running state so automation can continue

After provisioning, config-as-code is executed in dependency order:

1. `IdM`
2. `Satellite`
3. `AAP`

The AAP callback/install step is deferred until the AAP phase so foundational
IdM/Satellite phases can proceed first.

### AAP callback progress + fail-fast behavior

While waiting for AAP SSH callback readiness, MINIRHIS now reports live progress with:

- VM state transitions (including power-state changes)
- detected IP changes
- SSH reachability transitions
- periodic progress heartbeat with percent + ETA-style remaining time

If callback state does not progress for a configured timeout window, MINIRHIS now
fails fast so troubleshooting can begin immediately instead of waiting silently.

Relevant environment controls:

- `AAP_SSH_WAIT_TIMEOUT` (default `5400`)
- `AAP_SSH_WAIT_INTERVAL` (default `10`)
- `AAP_SSH_PROGRESS_EVERY` (default `30`)
- `AAP_SSH_NO_PROGRESS_TIMEOUT` (default `900`)

If a phase fails, the script retries only failed phases once by default.

### Console monitoring during build

During provisioning, the script attempts to open console monitors automatically:

- if a desktop terminal is available, it opens separate terminal windows
- on headless systems, it falls back to a detached `tmux` session

This makes it easier to watch Anaconda and serial console output while the stack is installing.

---

## Virt-manager and libvirt setup

[⬆ Back to top](#table-of-contents)

The script can configure:

- `libvirtd`
- libvirt networks
- `virt-manager`
- libvirt storage pool handling
- XML editor preferences
- guest resize behavior

### Expected network model

- **external** — outbound connectivity, updates, remote access
- **internal** — provisioning, orchestration, and management traffic

This matches the intended MINIRHIS lab design.

---

## DEMOKILL behavior

[⬆ Back to top](#table-of-contents)

`--DEMOKILL` is intended for interrupted runs, rebuilds, and stale lab cleanup.

It currently cleans up:

- demo VMs
- qcow2 disks
- generated kickstarts
- `OEMDRV.iso`
- staged AAP bundle content
- known lock files
- MINIRHIS temp/cache artifacts
- stale MINIRHIS node SSH trust entries in the installer host's `~/.ssh/known_hosts`
- stale MINIRHIS node hostname/IP comment lines in the installer host's `~/.ssh/authorized_keys`
- auto-opened console monitor windows
- fallback `tmux` console sessions
- known leftover processes from current or previous MINIRHIS runs

It also:

- restarts `libvirtd`
- reconnects `qemu:///system`
- re-enables libvirt networks
- restarts `virt-manager` when a desktop session is available

Use this before retrying a build if a prior run failed or was interrupted.

---

## MINIRHIS CMDB / HTML dashboard

[⬆ Back to top](#table-of-contents)

The script includes bootstrap logic for a lightweight MINIRHIS CMDB-style dashboard on the Satellite node using:

- `ansible-cmdb`
- a simple Python HTTP server

The intent is to provide a single-pane view of the MINIRHIS nodes and related services.

### Live Status Dashboard (menu option `8`)

The interactive dashboard now includes:

- VM power state and discovered IPs
- current provisioning / installer activity
- provisioner container state and recent logs
- tail of `~/.ansible/conf/ansible-provisioner.log`
- tail of the temporary AAP bundle HTTP log
- AAP callback log presence
- Satellite CMDB URL / port status

### Read-only status mode (`--status`)

The script can provide a non-destructive snapshot without provisioning changes:

- runtime configuration summary
- VM state + internal SSH reachability summary
- one-shot dashboard snapshot

Use:

```bash
./MiniRHIS.sh --status
```

### Ports used by the workflow

- `3000/tcp` — MINIRHIS container/web application
- `8080/tcp` — temporary AAP bundle HTTP server during provisioning
- `18080/tcp` — MINIRHIS CMDB / HTML dashboard on the Satellite node

---

## MINIRHIS Hardware Planning & Resource Management Guide (RHEL 10)

[⬆ Back to top](#table-of-contents)

This document consolidates the resource requirements, platform comparisons, overcommit strategies, and health-check commands for a Red Hat Infrastructure Setup (MINIRHIS) consisting of **Satellite 6.18**, **Ansible Automation Platform (AAP) 2.6**, and **Identity Management (IdM)**.

---

## 1. Product Resource Requirements

[⬆ Back to top](#table-of-contents)

These specifications are tailored for **RHEL 10** environments. Satellite and AAP are resource-intensive due to their database and containerization (Podman) requirements.

| Product            | Role                 | Min vCPU | Min RAM   | Rec vCPU | Rec RAM    | Storage Notes                    |
| :----------------- | :------------------- | :------- | :-------- | :------- | :--------- | :------------------------------- |
| **Satellite 6.18** | Lifecycle & Repos    | 4        | 20 GB     | 8        | 32 GB+     | 500GB+ for `/var/lib/pulp`       |
| **AAP 2.6**        | Automation (Bundled) | 4        | 16 GB     | 8-16     | 32 GB      | 100GB+ for `/var/lib/containers` |
| **IdM**            | Identity & DNS       | 2        | 4 GB      | 4        | 8-16 GB    | 50GB for LDAP & Logs             |
| **TOTAL**          | **Full Stack**       | **10**   | **40 GB** | **20**   | **80 GB+** | **~700GB Total SSD/NVMe**        |

---

## 2. Platform Overhead Comparison

[⬆ Back to top](#table-of-contents)

The hypervisor choice dictates how much "tax" is taken from your physical hardware before the VMs even boot.

| Platform Type           | Examples                | CPU Overhead  | RAM Overhead    | Impact on MINIRHIS                        |
| :---------------------- | :---------------------- | :------------ | :-------------- | :------------------------------------ |
| **Type 1 (Bare Metal)** | ESXi, Nutanix, KVM      | Low (~2-5%)   | Fixed (~1-2GB)  | Most efficient for heavy stacks.      |
| **Type 2 (Hosted)**     | Workstation, VirtualBox | Medium (~15%) | High (Host OS)  | Not recommended for production.       |
| **Cloud (Off-Prem)**    | AWS, Azure, GCP         | Variable      | Included in SKU | Avoid "Burstable" CPUs for Satellite. |

---

## 3. Safe Overcommit Ratios

[⬆ Back to top](#table-of-contents)

Overcommitting allows you to run more virtual resources than you have physical hardware, provided you follow these "Golden Ratios."

- **vCPU Overcommit (3:1 to 5:1):** Generally safe. You can assign 3–5 vCPUs per physical core.
- **RAM Overcommit (1:1):** Highly dangerous for MINIRHIS. Satellite and AAP rely on PostgreSQL; if they are forced into swap, performance collapses.

### Sample Calculation: 64GB RAM / 12-Core (24 Thread) Host

| VM Name            | vCPU | RAM   | Note                               |
| :----------------- | :--- | :---- | :--------------------------------- |
| **Satellite 6.18** | 8    | 28 GB | Priority for RAM                   |
| **AAP 2.6**        | 8    | 24 GB | Needs RAM for Execution Envs       |
| **IdM Server**     | 4    | 6 GB  | Lightweight                        |
| **Host Buffer**    | -    | 6 GB  | Essential for Hypervisor stability |

---

## 4. Monitoring Host Health & Memory Pressure

[⬆ Back to top](#table-of-contents)

Use these commands to determine if your hardware can handle an additional VM or if it is currently "thrashing."

### A. Pressure Stall Information (PSI)

The most accurate health metric in RHEL 10. It measures how much time processes spend waiting for resources.

```bash
# Check for Memory Stalls
cat /proc/pressure/memory
```

- **avg10 > 10.00:** Your RAM is over-saturated. Do not add more VMs.

- **avg10 < 1.00:** Your system is healthy and has room to grow.

### B. Hypervisor Stats (virsh)

Run these on the KVM/Libvirt host to see actual physical memory footprint (`rss`).

```bash
# Get memory stats for all running domains
virsh domstats --memory

# Check for specific domain memory ballooning
virsh memstat <domain_name>
```

### C. Standard Linux Monitoring

| Tool       | Command      | Focus                                                                 |
| :--------- | :----------- | :-------------------------------------------------------------------- |
| **Free**   | `free -h`    | Look at the **available** column only.                                |
| **Vmstat** | `vmstat 1 5` | If **si** (swap in) or **so** (swap out) are > 0, you are out of RAM. |
| **Top**    | `top`        | Press `m` to sort by memory; check `avail Mem`.                       |

---

## 5. Performance Optimization: KSM

[⬆ Back to top](#table-of-contents)

For RHEL 10 hosts running multiple RHEL 10 guests, enable **Kernel Same-page Merging**. This de-duplicates identical memory pages (like the kernel code) across all VMs, often freeing up several gigabytes of RAM.

```bash
# Enable KSM and the tuning daemon
systemctl enable --now ksm ksmtuned

# Check how much memory KSM has saved (in pages)
cat /sys/kernel/mm/ksm/pages_shared
```

---

## Important files

[⬆ Back to top](#table-of-contents)

- `MiniRHIS.sh` — primary orchestration script
- `CHECKLIST.md` — required user-provided inputs and where to get them
- `README.md` — this document

For a minimal source tree model, treat these as the canonical non-hidden top-level artifacts:

- `CHECKLIST.md`
- `LICENSE`
- `README.md`
- `MiniRHIS.sh`

Other runtime directories/files (for example `inventory/`, `host_vars/`, generated placeholders) can be generated by the script if missing.

---

## Recommended run sequence

[⬆ Back to top](#table-of-contents)

```bash
# 1. Review what you need
cat CHECKLIST.md

# 2. Configure or update saved values
./MiniRHIS.sh --reconfigure

# 3. Clean old lab state if needed
./MiniRHIS.sh --DEMOKILL

# 4. Build the demo stack
./MiniRHIS.sh --DEMO

# 5. Optional: run a fast end-to-end wiring check
./MiniRHIS.sh --test=fast --DEMO
```

---

## Troubleshooting

[⬆ Back to top](#table-of-contents)

If provisioning behaves unexpectedly:

- verify `virsh list --all`
- verify libvirt networks are active
- watch the console monitor windows / tmux monitor
- inspect generated kickstarts in `/var/lib/libvirt/images/kickstarts/`
- inspect guest `%post` logs such as `/root/ks-post.log`
- use `--DEMOKILL` before retrying a clean rebuild

### Current pre-flight safeguards (built into script)

- Managed-node package pre-flight now ensures `rhel-system-roles` and `rhc-worker-playbook` are installed before phase playbooks.
  - `rhc-worker-playbook` install order: pinned version first, then latest if unavailable.
  - If install fails, script retries with `--nogpgcheck`.
- Satellite entitlement pre-flight now validates against **enabled** repos (`subscription-manager repos --list-enabled`) to avoid false negatives.
- Satellite RHSM remediation prints a one-line cause classification (for easier log scanning):
  - `remediation-ok`
  - `auth-failed`
  - `auth-failed-both`
  - `remediation-failed`

### Manual rerun command format

When running `ansible-playbook` manually, keep the JSON extra-vars argument quoted as one shell token.

Before any manual re-run, ensure the provisioner container exists and is running:

```bash
podman ps -a --format '{{.Names}} {{.Status}}' | grep -E '^minirhis-provisioner\b' || echo 'Container missing: run menu option 2 first'
podman start minirhis-provisioner >/dev/null 2>&1 || true
```

Example:

```bash
podman exec -it minirhis-provisioner ansible-playbook --inventory /minirhis/vars/external_inventory/hosts --vault-password-file /minirhis/vars/vault/.vaultpass.container --extra-vars @/minirhis/vars/vault/env.yml --extra-vars '{"satellite_disconnected":false,"register_to_satellite":false}' --limit idm /minirhis/minirhis-builder-idm/main.yml
```

If inventory/admin auth fails, use root-auth fallback explicitly:

```bash
podman exec -it -e ANSIBLE_CONFIG=/minirhis/vars/vault/minirhis-ansible.cfg minirhis-provisioner ansible-playbook --inventory /minirhis/vars/external_inventory/hosts --vault-password-file /minirhis/vars/vault/.vaultpass.container --extra-vars @/minirhis/vars/vault/env.yml --extra-vars '{"satellite_disconnected":false,"register_to_satellite":false}' -e ansible_user=root -e ansible_password='<ROOT_PASS>' -e ansible_become=false --limit idm /minirhis/minirhis-builder-idm/main.yml
```

If configuration values are wrong, rerun:

```bash
./MiniRHIS.sh --reconfigure
```

---

## Support

[⬆ Back to top](#table-of-contents)

For issues, improvements, or repo-specific workflow questions, open a repository issue or contact the maintainers.

**License**: MIT
