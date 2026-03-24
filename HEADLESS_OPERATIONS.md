# RHIS Headless Operation Guide

## Overview

The RHIS installer can run on headless systems (no display/keyboard) using environment variables and command-line flags instead of interactive prompts.

---

## Quick Start: Headless Container + VMs Deployment

```bash
# Create an environment file with all required values
cat > /tmp/rhis-headless.env << 'EOF'
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
RHIS_ENABLE_POST_HEALTHCHECK=1
RHIS_HEALTHCHECK_AUTOFIX=1
EOF

# Run headless installation (Container + VMs + Config-as-Code)
./rhis_install.sh \
  --non-interactive \
  --menu-choice 5 \
  --env-file /tmp/rhis-headless.env
```

**Expected Flow:**
1. Loads env vars from file
2. Skips all interactive prompts
3. Deploys container (Podman)
4. Creates VM infrastructure (Virt-Manager)
5. Runs config-as-code phases (IdM → Satellite → AAP)
6. Exits with status code 0 on success

---

## Menu Options for Headless Mode

### Option 1: Local App Mode
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 1 \
  --env-file /tmp/rhis-headless.env
```
**Requirements:** Basic env vars (RH_USER, RH_PASS, ADMIN_PASS)  
**Output:** Provisioner container running locally

---

### Option 2: Container Only (No VMs)
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 2 \
  --env-file /tmp/rhis-headless.env
```
**Requirements:** Container env vars  
**Output:** Provisioner container ready for manual playbook execution  
**Note:** Use with `--container-config-only` to skip the prescribed sequence

---

### Option 3: Virt-Manager Only (No Container)
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 3 \
  --env-file /tmp/rhis-headless.env
```
**Requirements:** Network config (IDM_IP, SAT_IP, AAP_IP, etc.)  
**Output:** VMs created, no config applied

---

### Option 4: Full Setup (Local + Virt-Manager)
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 4 \
  --env-file /tmp/rhis-headless.env
```
**Requirements:** All env vars (container + network + credentials)  
**Output:** Container + VMs (no config-as-code)

---

### Option 5: Full Setup (Container + Virt-Manager) ⭐ **Recommended**
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 5 \
  --env-file /tmp/rhis-headless.env
```
**Requirements:** All env vars  
**Output:** Container + VMs + Config-as-Code (IdM → Satellite → AAP)  
**Timeline:** ~5-10 minutes for VMs + ~20-30 minutes for config-as-code

---

### Option 7: Container Config-Only (No VMs)
```bash
./rhis_install.sh \
  --non-interactive \
  --menu-choice 2 \
  --env-file /tmp/rhis-headless.env

# Later, run config-only after VMs are pre-provisioned:
./rhis_install.sh \
  --non-interactive \
  --menu-choice 7 \
  --env-file /tmp/rhis-headless.env
```
**Use Case:** Deploy to existing VMs

---

## Required Environment Variables

### Authentication (Required)
```bash
RH_USER="<Red Hat CDN username>"
RH_PASS="<Red Hat CDN password>"
ADMIN_USER="<local admin user>"
ADMIN_PASS="<local admin password>"
```

### IdM Configuration (Required for Options 3-5)
```bash
IDM_IP="10.168.128.3"              # Static IP on internal network
IDM_NETMASK="255.255.255.0"        # /24 = 255.255.255.0
IDM_GW="10.168.128.1"              # Gateway (usually your host)
IDM_HOSTNAME="idm.example.com"     # FQDN required
IDM_ALIAS="idm"                    # Short name
DOMAIN="example.com"               # Base domain
IDM_DS_PASS="secure-password"      # Directory Service password
```

### Satellite Configuration (Required for Options 3-5)
```bash
SAT_IP="10.168.128.1"              # Static IP
SAT_NETMASK="255.255.255.0"        
SAT_GW="10.168.128.1"              
SAT_HOSTNAME="satellite.example.com"
SAT_ORG="Default_Organization"     # Satellite org name
SAT_LOC="Default_Location"         # Satellite location
```

### AAP Configuration (Required for Options 3-5)
```bash
AAP_IP="10.168.128.2"              # Static IP
AAP_NETMASK="255.255.255.0"        
AAP_GW="10.168.128.1"              
AAP_HOSTNAME="aap.example.com"     # FQDN required
AAP_ADMIN_USER="admin"             
AAP_ADMIN_EMAIL="admin@example.com"
HUB_TOKEN="<your-hub-token>"       # Automation Hub token
```

### Network Configuration (Optional)
```bash
HOST_EXT_IP="192.168.1.100"        # External NIC IP (default: auto-detect)
HOST_INT_IP="10.168.128.1"         # Internal NIC IP (default: 10.168.128.1)
MGMT_NETWORK="10.168.128.0/24"     # Internal network (default: auto-calc)
```

### Feature Flags (Optional - Defaults Shown)
```bash
DEMO_MODE=0                        # 1=DEMO partitions (smaller); 0=production
RHIS_ENABLE_POST_HEALTHCHECK=1     # Run health checks post-install
RHIS_HEALTHCHECK_AUTOFIX=1         # Auto-fix failed services
RHIS_HEALTHCHECK_RERUN_COMPONENT=1 # Rerun playbooks if fix insufficient
RHIS_CONTAINER_NAME="rhis-provisioner"  # Container name
RUN_ONCE=1                         # Exit after first menu option execution
```

---

## Usage Patterns

### Pattern 1: Full Headless Deployment
```bash
export $(cat /tmp/rhis-headless.env | grep -v '^#')
./rhis_install.sh --non-interactive --menu-choice 5
```

### Pattern 2: Headless with Inline Environment
```bash
RH_USER="user" RH_PASS="pass" ADMIN_PASS="pass" \
IDM_IP="10.168.128.3" IDM_HOSTNAME="idm.example.com" \
... ./rhis_install.sh --non-interactive --menu-choice 5
```

### Pattern 3: Systemd Service (Background)
```bash
cat > /etc/systemd/system/rhis-installer.service << 'EOF'
[Unit]
Description=RHIS Container + VM Deployment
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/rhis/headless.env
ExecStart=/home/sgallego/GIT/RHIS/rhis_install.sh --non-interactive --menu-choice 5
StandardOutput=journal
StandardError=journal
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start rhis-installer.service
systemctl status rhis-installer.service
journalctl -u rhis-installer.service -f
```

### Pattern 4: Cron Job (Recurring Deployments)
```bash
cat >> /etc/cron.d/rhis-redeploy << 'EOF'
# Run RHIS deployment every Sunday at 2 AM
0 2 * * 0 root source /etc/rhis/headless.env && /home/sgallego/GIT/RHIS/rhis_install.sh --non-interactive --menu-choice 5 >> /var/log/rhis-cron.log 2>&1
EOF
```

### Pattern 5: CI/CD Pipeline
```yaml
# .gitlab-ci.yml or similar
deploy_rhis:
  stage: deploy
  script:
    - source $RHIS_ENV_FILE
    - /path/to/rhis_install.sh --non-interactive --menu-choice 5
  environment:
    name: rhis-staging
  only:
    - triggers
```

---

## Troubleshooting Headless Deployments

### Check Status
```bash
# View container logs
podman logs rhis-provisioner

# Check VM states
virsh list --all

# Monitor install progress
tail -f /var/log/rhis/rhis_install_*.log

# Watch live dashboard (with display available)
./rhis_install.sh --non-interactive --menu-choice 8
```

### Missing Environment Variables
```bash
# Validate env file before running
bash -c 'source /tmp/rhis-headless.env && env | grep -E "^(RH_|IDM_|SAT_|AAP_|ADMIN_|HUB_|HOST_)"'
```

### Network Configuration Issues
```bash
# Verify network access to key hosts
ping -c 3 10.168.128.1  # IdM gateway
ping -c 3 10.168.128.2  # AAP IP
ping -c 3 10.168.128.3  # IdM IP

# Check if network interfaces exist
ip addr show
nmcli connection show
```

### SSH Key Distribution Issues
```bash
# Verify SSH connectivity to VMs
ssh -o ConnectTimeout=5 root@10.168.128.1 "hostname"
ssh -o ConnectTimeout=5 root@10.168.128.2 "hostname"  
ssh -o ConnectTimeout=5 root@10.168.128.3 "hostname"
```

---

## Advanced: Custom Environment File

Create a versioned configuration file in your repo:

```bash
mkdir -p /etc/rhis
cat > /etc/rhis/headless.env << 'EOF'
# RHIS Headless Configuration
# Version: 1.0
# Last Updated: 2026-03-24

# === CREDENTIALS (keep secure) ===
RH_USER="${RH_USERNAME:-}"         # Set via secret management
RH_PASS="${RH_PASSWORD:-}"         
ADMIN_USER="rhisadmin"
ADMIN_PASS="${ADMIN_PASSWORD:-}"   

# === IdM ===
IDM_IP="10.168.128.3"
IDM_HOSTNAME="${DOMAIN_PREFIX:-idm}.${BASE_DOMAIN:-example.com}"
IDM_DS_PASS="${IDM_DS_PASSWORD:-}"

# === SATELLITE ===
SAT_IP="10.168.128.1"
SAT_HOSTNAME="${DOMAIN_PREFIX:-satellite}.${BASE_DOMAIN:-example.com}"

# === AAP ===
AAP_IP="10.168.128.2"
AAP_HOSTNAME="${DOMAIN_PREFIX:-aap}.${BASE_DOMAIN:-example.com}"
HUB_TOKEN="${AAP_HUB_TOKEN:-}"

# === NETWORK (auto-detected if empty) ===
HOST_INT_IP="${RHIS_INT_IP:-10.168.128.1}"
EOF

chmod 600 /etc/rhis/headless.env
source /etc/rhis/headless.env
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (check logs) |
| 2 | Invalid CLI flag |
| 3 | Missing required environment variable |
| 4 | Network/connectivity error |
| 5 | Container/VM operation failed |

---

## Monitoring Headless Deployment

```bash
# Watch installation logs in real-time
watch -n 5 "tail -20 /var/log/rhis/rhis_install_*.log | tail -40"

# Monitor system resources
watch -n 5 "free -h && echo '---' && df -h /var/lib/virt* && echo '---' && podman stats --no-stream"

# Check container and VM activity
while true; do
  clear
  echo "=== CONTAINER ==="
  podman ps | grep rhis
  echo ""
  echo "=== VMs ==="
  virsh list
  sleep 5
done
```

---

## Expected Timeline

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| Container setup | 2-5 min | Download image, run provisioner |
| VM creation | 5-10 min | Create 3 VMs, allocate storage |
| IdM install | 15-20 min | IdM server install + web UI ready |
| Satellite install | 20-30 min | Satellite installer runs |
| AAP install | 10-15 min | AAP setup + callback |
| **Total** | **~60-90 min** | Complete deployment |

---

## Best Practices

✅ **DO:**
- Use env files for production deployments
- Store passwords/tokens in secure vaults (Vault, Secrets Manager, etc.)
- Run from an automated system (Ansible, Terraform, CI/CD)
- Redirect output to logs for audit trails
- Validate env vars before running installer
- Use `--DEMO` flag for testing to save time

❌ **DON'T:**
- Hardcode credentials in scripts
- Mix interactive and non-interactive parameters
- Run multiple installers simultaneously on same host
- Interrupt the deployment once started
- Change network config during deployment

---

## Integration Examples

### Ansible Playbook
```yaml
---
- hosts: localhost
  become: yes
  vars:
    rhis_path: /home/sgallego/GIT/RHIS
  tasks:
    - name: Deploy RHIS headless
      shell: |
        export RH_USER="{{ rhn_user }}"
        export RH_PASS="{{ rhn_pass }}"
        {{ rhis_path }}/rhis_install.sh --non-interactive --menu-choice 5
      environment:
        IDM_HOSTNAME: "{{ domain_name }}"
        SAT_IP: "{{ sat_ip }}"
      register: deployment
      failed_when: deployment.rc not in [0]

    - name: Wait for services
      uri:
        url: "https://{{ domain_name }}/ipa/ui/"
        validate_certs: no
      retry: 60
      delay: 10
```

### Terraform
```hcl
resource "null_resource" "rhis_deployment" {
  provisioner "local-exec" {
    command = <<-EOT
      export RH_USER="${var.rh_username}"
      export RH_PASS="${var.rh_password}"
      ${local.rhis_script} --non-interactive --menu-choice 5
    EOT
    environment = {
      IDM_IP   = var.idm_ip
      SAT_IP   = var.sat_ip
      AAP_IP   = var.aap_ip
    }
  }
}
```

---

**Created:** 2026-03-24  
**Status:** Production Ready
