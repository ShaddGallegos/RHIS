# RHIS - Red Hat Infrastructure Standard

## Synopsis

RHIS stands for **Red Hat Infrastructure Standard**.

This repository is built around `run_rhis_install_sequence.sh`, an orchestration script for building and bootstrapping a Red Hat management lab on libvirt/KVM.

The current workflow focuses on:

- **Red Hat Satellite 6.18**
- **Red Hat Ansible Automation Platform 2.6**
- **Red Hat Identity Management (IdM / FreeIPA)**
- optional **RHIS container** deployment

The script automates:

- encrypted configuration capture with `ansible-vault`
- RHEL ISO preparation
- kickstart generation for Satellite, AAP, and IdM
- unattended VM creation on libvirt/KVM
- RHSM registration and repo enablement during kickstart `%post`
- initial Day-0 bootstrap actions required to continue automated configuration

If you are starting fresh, review:

- `CHECKLIST.md` — what must be provided by the user and where to obtain it

---

## Purpose of this repository

This repository is intended for repeatable build-out of a Red Hat infrastructure management stack with:

- one **external** network for updates and remote access
- one **internal** network for provisioning, orchestration, and management
- consistent bootstrap of these core nodes:
  - `satellite-618`
  - `aap-26`
  - `idm`

This is primarily an **infrastructure provisioning and bootstrap repository**, not just a generic application project.

---

## Quick start

### What's new

- Container-first automation now supports a prescribed config order:
  - `IdM -> Satellite -> AAP`
- Menu option `2` (Container Deployment) now auto-runs config-as-code by default.
- New one-shot workflow:
  - `./run_rhis_install_sequence.sh --container-config-only`
- Retry behavior for transient failures:
  - Failed phases are retried once by default.
  - Disable with `RHIS_RETRY_FAILED_PHASES_ONCE=0`.
- Auto-sequence after menu option `2` can be disabled with:
  - `RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0`

### Recommended first run

```bash
./run_rhis_install_sequence.sh --reconfigure
```

### Clean up a previous demo run

```bash
./run_rhis_install_sequence.sh --DEMOKILL
```

### Build the demo stack

```bash
./run_rhis_install_sequence.sh --DEMO
```

---

## Main entry point

The main workflow is:

```bash
./run_rhis_install_sequence.sh
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
- `0` Exit

Environment toggles:

- `RHIS_AUTO_CONFIG_ON_CONTAINER_ONLY=0` disables auto config-as-code after menu option `2`
- `RHIS_RETRY_FAILED_PHASES_ONCE=0` disables automatic retry of failed config-as-code phases

### Command-line options

```text
--non-interactive        Run without prompts; required values must already be set
--menu-choice <0-8>      Preselect a visible menu option
--env-file <path>        Load preseed variables from a custom env file
--inventory <template>   Pin AAP inventory template; skips interactive submenu
--inventory-growth <tpl> Pin AAP inventory-growth template; skips interactive submenu
                         Interactive (no --non-interactive): a guided submenu with
                         About pages is presented when template values are unset.
                         --DEMO always forces DEMO-inventory.j2 and skips the submenu.
--container-config-only  One-shot: start container + run IdM -> Satellite -> AAP
--attach-consoles        Re-open VM console monitors for Satellite/AAP/IdM
--reconfigure            Prompt for all installer values and update env.yml
--test[=fast|full]       Run a curated non-interactive test sweep and print a summary
--DEMO|--demo            Use demo sizing/profile for VM specs
--DEMOKILL|--demokill    CLI-only cleanup for demo VMs/files/temp artifacts/lock files/processes
--help                   Show usage
```

### AAP installer inventory selection

When running interactively without a pre-configured template, the script presents
a guided **inventory architecture submenu**:

```
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

RHIS now generates a host-side Ansible config for provisioner runs and mounts it into the container automatically:

- `~/.ansible/conf/rhis-ansible.cfg` — generated RHIS Ansible runtime config
- `~/.ansible/conf/ansible-provisioner.log` — stable provisioner log file
- `~/.ansible/conf/facts-cache/` — Ansible fact cache

The provisioner container uses that generated config via `ANSIBLE_CONFIG` and writes logs/cache on the host through the existing vault bind mount.

### Container one-shot examples

```bash
./run_rhis_install_sequence.sh --container-config-only
```

Run one-shot container workflow without retries:

```bash
RHIS_RETRY_FAILED_PHASES_ONCE=0 ./run_rhis_install_sequence.sh --container-config-only
```

Re-open VM console monitors after boot:

```bash
./run_rhis_install_sequence.sh --attach-consoles
```

Run a fast noninteractive validation sweep (recommended after `--DEMOKILL`):

```bash
./run_rhis_install_sequence.sh --test=fast --DEMO
```

Run the broader integration-style validation sweep:

```bash
./run_rhis_install_sequence.sh --test=full --DEMO
```

### Common examples

Generate only the Satellite kickstart and `OEMDRV.iso`:

```bash
./run_rhis_install_sequence.sh --menu-choice 6
```

Run fully unattended:

```bash
./run_rhis_install_sequence.sh --non-interactive --menu-choice 6
```

Use a custom bootstrap env file:

```bash
./run_rhis_install_sequence.sh --env-file /path/to/custom.env --menu-choice 3
```

Re-prompt for all saved values:

```bash
./run_rhis_install_sequence.sh --reconfigure
```

Destroy demo resources and clean leftovers:

```bash
./run_rhis_install_sequence.sh --DEMOKILL
```

---

## Configuration and secrets

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

By default, the script uses these internal addresses:

| Node | Default IP | Default Hostname Pattern |
|---|---:|---|
| Satellite | `10.168.128.1` | `satellite-618.<domain>` |
| AAP | `10.168.128.2` | `aap-26.<domain>` |
| IdM | `10.168.128.3` | `idm.<domain>` |

Shared defaults also include:

- `NETMASK=255.255.0.0`
- `INTERNAL_GW=0.0.0.0`

Adjust these during `--reconfigure` if your environment needs different values.

---

## Kickstart generation

The script generates unattended kickstarts for:

- Satellite
- AAP
- IdM

### Satellite OEMDRV workflow

The Satellite build produces:

- `kickstarts/satellite-618.ks`
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

When you choose a libvirt build path, the script:

1. validates configuration
2. generates kickstarts
3. stages the AAP bundle on the host
4. creates these VMs:
   - `satellite-618`
   - `aap-26`
   - `idm`
5. enables `virsh autostart` for each VM
6. checks that the three VMs are left in an ON/running state so automation can continue

After provisioning, config-as-code is executed in dependency order:

1. `IdM`
2. `Satellite`
3. `AAP`

If a phase fails, the script retries only failed phases once by default.

### Console monitoring during build

During provisioning, the script attempts to open console monitors automatically:

- if a desktop terminal is available, it opens separate terminal windows
- on headless systems, it falls back to a detached `tmux` session

This makes it easier to watch Anaconda and serial console output while the stack is installing.

---

## Virt-manager and libvirt setup

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

This matches the intended RHIS lab design.

---

## DEMOKILL behavior

`--DEMOKILL` is intended for interrupted runs, rebuilds, and stale lab cleanup.

It currently cleans up:

- demo VMs
- qcow2 disks
- generated kickstarts
- `OEMDRV.iso`
- staged AAP bundle content
- known lock files
- RHIS temp/cache artifacts
- auto-opened console monitor windows
- fallback `tmux` console sessions
- known leftover processes from current or previous RHIS runs

It also:

- restarts `libvirtd`
- reconnects `qemu:///system`
- re-enables libvirt networks
- restarts `virt-manager` when a desktop session is available

Use this before retrying a build if a prior run failed or was interrupted.

---

## RHIS CMDB / HTML dashboard

The script includes bootstrap logic for a lightweight RHIS CMDB-style dashboard on the Satellite node using:

- `ansible-cmdb`
- a simple Python HTTP server

The intent is to provide a single-pane view of the RHIS nodes and related services.

### Live Status Dashboard (menu option `8`)

The interactive dashboard now includes:

- VM power state and discovered IPs
- current provisioning / installer activity
- provisioner container state and recent logs
- tail of `~/.ansible/conf/ansible-provisioner.log`
- tail of the temporary AAP bundle HTTP log
- AAP callback log presence
- Satellite CMDB URL / port status

### Ports used by the workflow

- `3000/tcp` — RHIS container/web application
- `8080/tcp` — temporary AAP bundle HTTP server during provisioning
- `18080/tcp` — RHIS CMDB / HTML dashboard on the Satellite node

---

## Important files

- `run_rhis_install_sequence.sh` — primary orchestration script
- `CHECKLIST.md` — required user-provided inputs and where to get them
- `README.md` — this document

---

## Recommended run sequence

```bash
# 1. Review what you need
cat CHECKLIST.md

# 2. Configure or update saved values
./run_rhis_install_sequence.sh --reconfigure

# 3. Clean old lab state if needed
./run_rhis_install_sequence.sh --DEMOKILL

# 4. Build the demo stack
./run_rhis_install_sequence.sh --DEMO

# 5. Optional: run a fast end-to-end wiring check
./run_rhis_install_sequence.sh --test=fast --DEMO
```

---

## Troubleshooting

If provisioning behaves unexpectedly:

- verify `virsh list --all`
- verify libvirt networks are active
- watch the console monitor windows / tmux monitor
- inspect generated kickstarts in `/var/lib/libvirt/images/kickstarts/`
- inspect guest `%post` logs such as `/root/ks-post.log`
- use `--DEMOKILL` before retrying a clean rebuild

If configuration values are wrong, rerun:

```bash
./run_rhis_install_sequence.sh --reconfigure
```

---

## Support

For issues, improvements, or repo-specific workflow questions, open a repository issue or contact the maintainers.

**License**: MIT
