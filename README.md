# RHIS - Resource Health Information System

## Synopsis

RHIS is a comprehensive monitoring and management platform for tracking, analyzing, and optimizing the health status of distributed resources with real-time insights into utilization, performance metrics, and system diagnostics.

This directory also includes `run_rhis_install_sequence.sh`, an orchestration script for:

- local RHIS installation
- container-based RHIS deployment
- `virt-manager` / libvirt setup
- Satellite 6.18 kickstart generation
- unattended `OEMDRV.iso` creation for Satellite VM builds

## Quick Start

**Local Installation:**
```bash
git clone <RHIS-repo-url> && cd RHIS
npm install && cp .env.example .env
npm start
```

**Container Deployment:**
```bash
podman pull quay.io/parmstro/rhis-provisioner-9-2.5:latest
podman run -d -p 3000:3000 -e CONFIG_PATH=/etc/rhis/config.json --name rhis quay.io/parmstro/rhis-provisioner-9-2.5:latest
```

Access dashboard at `http://localhost:3000`

## Installation Orchestration Script

Use `run_rhis_install_sequence.sh` when you want one entry point for RHIS setup, virtualization prep, and Satellite kickstart generation.

### Interactive usage

```bash
./run_rhis_install_sequence.sh
```

Menu options include:

- local RHIS install
- container RHIS deployment
- virt-manager setup
- combined install + virt-manager flows
- Satellite `OEMDRV.iso` generation only

### Command-line options

```text
--non-interactive        Run without prompts; required values must already be set
--menu-choice <0-6>      Preselect a visible menu option
--env-file <path>        Load preseed variables from a custom env file
--reconfigure            Prompt for all installer values and update env.yml
--demo                   Use demo sizing/profile for VM specs
--demokill               CLI-only cleanup for demo VMs/files/temp artifacts/lock files
--help                   Show usage
```

### Common examples

Generate only the Satellite kickstart and `OEMDRV.iso`:

```bash
./run_rhis_install_sequence.sh --menu-choice 6
```

Run fully unattended with a preseed file:

```bash
./run_rhis_install_sequence.sh --non-interactive --menu-choice 6
```

Re-prompt for all values and overwrite saved installer configuration:

```bash
./run_rhis_install_sequence.sh --reconfigure
```

Run demo cleanup directly from CLI (not shown in interactive menu):

```bash
./run_rhis_install_sequence.sh --demokill
```

Use a custom env file:

```bash
./run_rhis_install_sequence.sh --env-file /path/to/custom.env --menu-choice 3
```

## Installer Configuration and Secrets

Primary configuration/secrets are stored in:

- `~/.ansible/conf/env.yml` (encrypted with `ansible-vault`)
- vault password file: `~/.ansible/conf/.vaultpass.txt`

On first run, the installer prompts for required values and writes encrypted `env.yml`.
On subsequent runs, it loads from `env.yml` and only prompts for missing/unresolved values (or all values when `--reconfigure` is used).

`--env-file` remains available for bootstrap/preseed compatibility, but `env.yml` is the authoritative runtime source.

### Supported variables (env.yml schema)

#### Control

- `NONINTERACTIVE`
- `MENU_CHOICE`
- `PRESEED_ENV_FILE`

#### Shared identity/network

- `ADMIN_USER`
- `ADMIN_PASS`
- `DOMAIN`
- `REALM`
- `NETMASK`
- `INTERNAL_GW`

#### RHEL ISO and authentication

- `RH_AUTH_CHOICE`
- `RH_ISO_URL`
- `RH_OFFLINE_TOKEN`
- `RH_ACCESS_TOKEN`

#### Satellite 6.18 kickstart values

- `RH_USER`
- `RH_PASS`
- `SAT_IP`
- `SAT_HOSTNAME`
- `SAT_ORG`
- `SAT_LOC`

#### AAP/IdM kickstart values

- `AAP_IP`
- `AAP_HOSTNAME`
- `AAP_BUNDLE_URL`
- `IDM_IP`
- `IDM_HOSTNAME`
- `IDM_ADMIN_PASS`
- `IDM_DS_PASS`

#### Optional path overrides

- `ISO_DIR`
- `ISO_NAME`
- `ISO_PATH`
- `VM_DIR`
- `KS_DIR`
- `OEMDRV_ISO`

### Example bootstrap preseed file (`--env-file`)

```dotenv
NONINTERACTIVE=1
MENU_CHOICE=6
RH_AUTH_CHOICE=2
RH_ISO_URL="https://example.invalid/rhel-10.iso"
RH_OFFLINE_TOKEN="your-offline-token"
RH_USER="your-cdn-user"
RH_PASS="your-cdn-password"
ADMIN_USER="admin"
ADMIN_PASS="r3dh4t7!"
DOMAIN="example.com"
REALM="EXAMPLE.COM"
NETMASK="255.255.0.0"
INTERNAL_GW="0.0.0.0"
SAT_IP="10.168.128.1"
SAT_HOSTNAME="satellite-618.example.com"
SAT_ORG="REDHAT"
SAT_LOC="CORE"
AAP_IP="10.168.128.2"
AAP_HOSTNAME="aap-26.example.com"
IDM_IP="10.168.128.3"
IDM_HOSTNAME="idm.example.com"
AAP_BUNDLE_URL="https://example.invalid/aap-bundle.tar.gz"
HUB_TOKEN="your-hub-token"
```

## Satellite 6.18 OEMDRV Workflow

The script can generate:

- `kickstarts/satellite-618.ks`
- `/var/lib/libvirt/images/OEMDRV.iso`

The generated kickstart includes:

- Satellite registration
- repository enablement for RHEL 10 + Satellite 6.18
- `satellite-installer` bootstrap options
- static `eth1` network configuration
- LVM partitioning suitable for the Satellite VM flow in this repo

For VM creation, the script uses:

- `inst.ks=hd:LABEL=OEMDRV:/ks.cfg`

That allows the Satellite guest to consume the generated kickstart from the attached `OEMDRV` ISO during installation.

## Virt-Manager Setup

### Installation

```bash
# Install virt-manager and dependencies
sudo dnf install virt-manager virt-viewer libvirt qemu-kvm -y

# Enable libvirtd service
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Verify installation
virsh list --all
```

### Configure RHIS to Monitor VMs

1. Launch virt-manager: `virt-manager`
2. Create or connect to VMs you want to monitor
3. In RHIS config.json, add VM endpoints:
```json
{
  "resources": [
    {
      "name": "vm-server-1",
      "type": "libvirt",
      "endpoint": "qemu:///system",
      "collectInterval": 60
    }
  ]
}
```

4. Restart RHIS to begin monitoring VM health metrics

## Container Info

| Property | Value |
|----------|-------|
| **Image** | `quay.io/parmstro/rhis-provisioner-9-2.5:latest` |
| **Registry** | Quay.io |
| **Image ID** | ed7fc9343b15 |
| **Size** | 539 MB |
| **Updated** | 13 days ago |

## Examples

```javascript
// Monitor a resource
const rhis = require('rhis');
const monitor = new rhis.Monitor('my-server');
monitor.start();

// Get health status
const status = await monitor.getHealthStatus();
// { cpu: 45%, memory: 62%, disk: 78%, status: 'healthy' }

// Set alert
monitor.setAlert('cpu', { threshold: 80, action: 'notify' });
```

## How To

- **Add Resource**: Define in `config.json` → Create monitor instance → Configure thresholds → Start monitoring
- **Configure Alerts**: Dashboard Settings → Alerts → Create rules with conditions/actions → Test
- **Generate Reports**: Reports section → Select date range & resources → Choose type → Download/schedule

## Architecture

- **Collector**: Gathers metrics at configurable intervals
- **Analyzer**: Processes data and identifies anomalies
- **Dashboard**: Real-time and historical visualization

## Metrics & Configuration

**Collected Metrics**: CPU, Memory, Disk I/O, Network, Custom app-specific metrics

**Config (`config.json`)**: Resource endpoints, collection intervals, alert thresholds, dashboard settings, database connection

**Health Status**: Green (healthy) → Yellow (warning) → Red (critical) based on weighted algorithm

## API

| Method | Purpose |
|--------|---------|
| `start()` / `stop()` | Control monitoring |
| `getHealthStatus()` | Current status |
| `setAlert(metric, config)` | Configure alerts |
| `getMetrics(timeRange)` | Historical data |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Dashboard not loading | Check service status, verify port 3000 available, check browser console |
| No data appearing | Verify resource endpoints, check `logs/collector.log`, verify collection intervals |

## Contributing

1. Fork repository
2. Create feature branch
3. Submit PR with clear descriptions

## Support

For issues: Open a repository issue or contact maintainers

**License**: MIT
