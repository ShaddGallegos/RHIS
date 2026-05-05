# RULES — Quick Reference

This file is the concise, top-level summary of the project rules. The full, authoritative rules document is `docs/assistant-adherence-rules.md`.

Quick rules (must follow):

1. RULE: Do not use container workflows unless an explicit flag is provided (for example `--container`, `--container-config-only`, or `--use-container`). The default operations run on the host.
2. Configuration-as-code first: codify all fixes, installer steps, and recovery procedures as Ansible roles/playbooks in this repo.
3. Snapshot before edits: always snapshot or copy any VM image (`qcow2`) before offline edits and record snapshot name + timestamp.
4. Prefer guest-agent: use `qemu-guest-agent` for in-guest operations instead of offline mounts when possible.
5. Secrets must be stored in Ansible Vault; do not commit plain credentials into the repository.
6. Idempotence: roles and playbooks must be idempotent and covered by smoke tests.
7. Use libvirt APIs for network changes; do not edit generated ephemeral files.
8. Record run metadata, logs and link to PR/issue for any deviation from these rules.
9. All Ansible modules used in playbooks and roles must use Fully Qualified Collection Names (FQCN), for example `ansible.builtin.package` or `ansible.posix.firewalld`. Enforce via `ansible-lint` and CI.

Execution goal (current MiniRHIS workflow)

- Installer node: perform all prework required to orchestrate installation.
- Target nodes to provision and prepare:
  - Satellite on RHEL 9
  - AAP on RHEL 10
  - IdM on RHEL 10
- Required sequence:
  - Load and validate vaulted runtime configuration before changes.
  - Enforce vaulted configuration hygiene before install (realm + IdM password fields) using `playbooks/add-realm-to-env.yml` and `playbooks/update-idm-passwords.yml` when required.
  - Validate installer host prerequisites and generated runtime layout.
  - Run installer prework (kickstart snippets and AAP bundle HTTP serving when needed).
  - Prepare target nodes with baseline bootstrap (packages, SELinux/firewalld policy, admin credential alignment).
  - Configure admin/root SSH access and key sharing where enabled.
  - Register nodes with RHSM (including attach/refresh) and import GPG keys.
  - Enable required repositories per node role.
  - Upgrade nodes and reboot as needed.
  - Stage required artifacts/dependencies in each node admin home directory.
  - Install products in full-stack order: IdM, then Satellite, then AAP.
  - Run IdM post-install operational playbook (`playbooks/idm-operational.yml`) for backups, healthchecks, log rotation, cockpit, and installer-key persistence.
  - Validate product readiness with HTTPS UI probes, service checks, and run logs.

Post-WebUI workflow (Satellite-first)

- Start post-install application configuration with Satellite.
- Import `manifest*.zip`.
- Add required repositories:
  - RHEL 9 x86_64 (BaseOS, Kickstart, Satellite Client, and product prerequisites)
  - RHEL 10 x86_64 (BaseOS, Kickstart, Satellite Client, and product prerequisites)
  - Repositories required for Satellite, IdM, and AAP containerized support
- Create weekly sync plan for all repositories.
- Create lifecycle environments:
  - RHEL 9 x86_64: DEV, TEST, PROD
  - RHEL 10 x86_64: DEV, TEST, PROD
- Create/promote content views and create activation keys per lifecycle path.
- Provisioning/compute setup:
  - Subnet on `10.168.0.0/16` with gateway and DNS `10.168.0.1`
  - Configure DNS, DHCP, TFTP, and set Libvirt as default install platform
  - Configure Foreman keys (skip if already present), Libvirt compute resources, and external/internal networks
- Host standards:
  - Host group `compute`
  - Naming `node1`, `node2`, `node3`, ... under `prod.spg`
  - `eth1` internal IP from Satellite DHCP on `10.168.0.0/16`
  - `eth0` external IP on `192.168.0.0/24` via Libvirt
- Operations:
  - Enable Ansible and import required roles
  - Enable Ansible remote execution
  - Configure Hammer CLI/API automation helpers for Satellite administration workflows
  - On node deletion, remove Satellite/Foreman host entry and delete matching Libvirt VM + qcow2 disk

Implementation Mapping Checklist (rules -> automation path)

| Workflow item                                               | Status      | Primary automation path                                                                     | Notes                                                                                            |
| ----------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Installer preflight and runtime layout                      | Implemented | `MiniRHIS.sh` (`main`, runtime/bootstrap helpers)                                           | Script-driven prechecks before playbook runs                                                     |
| Vault load and normalization                                | Implemented | `MiniRHIS.sh` (`load_ansible_env_file`, `normalize_shared_env_vars`)                        | Uses `~/.ansible/conf/env.yml`                                                                   |
| Vault schema maintenance (realm + IdM passwords)            | Implemented | `playbooks/add-realm-to-env.yml`, `playbooks/update-idm-passwords.yml`                      | Maintains required keys and password minimums in vaulted env                                     |
| Baseline node bootstrap                                     | Implemented | `playbooks/server-bootstrap.yml`, `roles/server_bootstrap`                                  | Packages, SELinux/firewalld policy, admin credential alignment                                   |
| SSH key distribution / mesh                                 | Implemented | `playbooks/share-ssh-keys.yml`, `roles/server_bootstrap` (`share_ssh_keys`)                 | Bidirectional key propagation for installer/nodes                                                |
| RHSM registration + attach/refresh                          | Implemented | `roles/minirhis-rhsm` (invoked by `playbooks/server-bootstrap.yml`)                         | Includes deferred marker and GPG import                                                          |
| Kickstart snippet generation                                | Implemented | `roles/minirhis-kickstart`, `playbooks/local-test-minirhis.yml`                             | Generates `%post` helper snippets                                                                |
| AAP bundle HTTP staging service                             | Implemented | `roles/minirhis-aap-serve`, `playbooks/local-test-minirhis.yml`                             | Serves bundle over `http.server`                                                                 |
| AAP container host preparation                              | Implemented | `playbooks/run-aap-container-setup.yml`, `roles/minirhis-aap-container`                     | Podman/runtime prereqs, bundle extraction, controller volume prep                                |
| Product install: IdM                                        | Implemented | `playbooks/idm-install.yml`                                                                 | Runs unattended `ipa-server-install`                                                             |
| IdM post-install operational hardening                      | Implemented | `playbooks/idm-operational.yml`, `roles/minirhis-idm-operational`                           | Backups, healthchecks, logrotate, cockpit socket, installer pubkey                               |
| Product install: Satellite                                  | Partial     | `playbooks/satellite-install.yml`                                                           | Current playbook performs readiness checks; full install workflow remains to be codified         |
| Product install: AAP                                        | Partial     | `playbooks/aap-install.yml`, `playbooks/run-aap-container-setup.yml`                        | Current playbooks focus on readiness/host prep; full app install workflow remains to be codified |
| Product post-install web/service checks                     | Implemented | `playbooks/idm-install.yml`, `playbooks/satellite-install.yml`, `playbooks/aap-install.yml` | Port/UI probes and service status checks                                                         |
| Satellite manifest import                                   | Implemented | `tools/import_manifest.sh`                                                                  | API-first with hammer fallback                                                                   |
| Satellite hammer/API helper setup                           | Implemented | `tools/setup_hammer_cli.sh`, `tools/hammer_api_fallback.sh`                                 | Standardizes Hammer CLI config and API fallback pattern                                          |
| Satellite sync plan/lifecycle/content views/activation keys | TODO        | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Satellite DNS/DHCP/TFTP and provisioning subnet/domain      | TODO        | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Libvirt compute resources, hostgroup, naming conventions    | TODO        | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Ansible remote execution enablement in Satellite            | TODO        | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Node decommission cleanup (Satellite + libvirt + qcow2)     | Partial     | `roles/minirhis-recovery`, `playbooks/recover-vm.yml`, `playbooks/rollback-vm.yml`          | Recovery exists; explicit host decommission workflow should be codified                          |

Current remaining gaps are explicitly marked TODO in this checklist: sync plan/lifecycle/content views/activation keys, DNS/DHCP/TFTP provisioning domain, compute resources/hostgroup naming automation, and Satellite remote execution enablement. These gaps match what is not yet codified in playbooks/roles.

See `docs/assistant-adherence-rules.md` for full details, examples, and enforcement guidance.

- **AAP Gateway port**: The `automation-gateway` container nginx listens on port **443** (HTTPS) by default. This is configurable via the `AAP_GATEWAY_HTTPS_PORT` environment variable. All health probes, UI links, and repair checks must use the configured port value.
- **AAP installer must always receive**: `-e bundle_dir=/home/admin/bundle -e validate_certs=false`. After installer completes, fix cert permissions (`chmod 0444`) on all files under `/home/admin/aap/gateway/etc/`, ensure directory traversal (`chmod o+rx /home/admin/aap/gateway/etc`), and restart gateway via `systemctl --user restart automation-gateway.service`.
- **Default credentials**: All system passwords default to `redhat` when not specified in vault or environment. These are managed in `~/.ansible/conf/env.yml` (vault-encrypted). Password prompts require confirmation (type twice) to prevent input errors.
- **Vault file management**: Always keep `~/.ansible/conf/env.yml` in sync. Use `playbooks/add-realm-to-env.yml` and `playbooks/update-idm-passwords.yml` for password maintenance. Validate vault contents before running installers.

- Role structure: every new Ansible role added to the repo must include a minimal layout: `defaults/main.yml`, `tasks/main.yml`, `meta/main.yml`, `README.md` and, where applicable, `handlers/main.yml`. The README must document purpose, variables, and usage examples.

Network topology (STATIC — do not change or "auto-detect")

- **Internal MINIRHIS network**: `10.168.0.0/16` — this is the **only** network used for node-to-node communication between installer host, Satellite, AAP, and IdM. It is **statically assigned** during kickstart/provisioning. Never derive this from host interfaces at runtime.
  - Installer host (kaso.prod.spg): `10.168.0.1/16` (bridge: `virbr-internal`)
  - Satellite: `10.168.128.1/16` (eth1)
  - AAP: `10.168.128.2/16` (eth1)
  - IdM: `10.168.128.3/16` (eth1)
- **External internet network**: `192.168.0.0/24` — use this network for RHIS node access to Red Hat CDN, registration, `console.redhat.com`, package updates, and any other internet-requiring traffic.
- **libvirt NAT network (virbr0)**: `192.168.122.0/24` remains a libvirt bootstrap/NAT network and is never a MINIRHIS east-west network.
- **Inter-node traffic rule (mandatory)**: all communication between RHIS nodes (installer, Satellite, AAP, IdM) must use `10.168.0.0/16`, including SSH, SCP, rsync, API calls, service-to-service communication, and installer orchestration traffic.
- **eth0** is the first ethernet device and the external/internet-facing interface (`192.168.0.0/24`).
- **eth1** is the second ethernet device.
- **eth1 `10.168.0.0/16`** is the bootstrap network and the internal MINIRHIS east-west network on all nodes.
- **Firewall policy (mandatory)**:
  - `eth0` (external) must remain firewalled with explicit allow rules only (default-deny posture).
  - `eth1` (internal) is trusted for MINIRHIS east-west traffic and allows RHIS service traffic (HTML/UI, SSH, Satellite DNS/DHCP/TFTP/PXE, and related internal APIs).
  - `sat_firewalld_interface` controls the Satellite firewalld ingress interface and defaults to `eth0`; Satellite service-plane endpoints still bind to `eth1`.
- RULE: The script must **never** auto-detect `HOST_INT_IP` or `INTERNAL_GW` from the running host's interfaces. All internal addresses must come from the vault (`~/.ansible/conf/env.yml`) or explicit CLI arguments. Any detected address outside `10.168.x.x` is invalid and must be rejected — not silently corrected at runtime.

Where stuff lives (important paths and files)

- **Vault password file**: `~/.ansible/conf/.vaultpass.txt` — used by both local and container runs. Do not delete this file; only regenerate it when it is missing or corrupted. The orchestrator expects this file at this exact path for automated reruns and remediation tasks. Also accepted at `~/.ansible/conf/.vaultpass.text` (both names resolve to the same file).
- **Vaulted env file**: `~/.ansible/conf/env.yml` — **the single source of truth for all secrets, passwords, tokens, and sensitive configuration**. This file contains: `admin_pass`, `rh_user`, `rh_pass`, `rh_offline_token`, `rh_access_token`, `hub_token`, `sat_admin_pass`, `aap_admin_pass`, `idm_admin_pass`, `idm_ds_pass`, `ipadm_password`, all IP/network/realm values, ISO URLs, and all other runtime variables. It is encrypted with Ansible Vault. Always decrypt with `ansible-vault view --vault-password-file ~/.ansible/conf/.vaultpass.txt ~/.ansible/conf/env.yml`. Never read, write, or edit this file in plaintext. Never commit it to the repo.
- **Password canonicalization rule**: `aap_admin_pass` is the canonical shared admin credential key. Compatibility aliases (`admin_pass`, `sat_admin_pass`, `sat_initial_admin_pass`, `idm_admin_pass`, `idm_ds_pass`, `ipadm_password`, `ipaadmin_password`, `global_admin_password`, `sat_compute_password`, `sat_image_password`) are retained but must resolve from `aap_admin_pass` unless explicitly overridden for a component-specific reason.
- **Runtime Ansible config**: `~/.ansible/conf/minirhis-ansible.runtime.cfg` — generated by `MiniRHIS.sh` and used for playbook runs.
- **VM images & staged artifacts**:
  - `/var/lib/libvirt/images/` — default VM disk location
  - `/var/lib/libvirt/images/aap-bundle/` — AAP bundle staging
  - `/var/lib/libvirt/images/files/` — expected staging for `manifest*.zip` files
- **Orchestrator script**: `MiniRHIS.sh` — primary entrypoint. Key functions to be aware of: `create_minirhis_vms`, `run_minirhis_config_as_code`, `generate_minirhis_ansible_cfg`, `generate_local_roles_ansible_cfg`, `run_local_role`, `ensure_minirhis_installer_ssh_key`, `set_or_prompt`, `prompt_with_default`, and `show_menu`.
- **Roles & playbooks**:
  - `local/roles/` — roles used by local execution mode
  - `roles/` — repository roles for local runs
  - `playbooks/` — top-level fallback playbooks (examples: `playbooks/idm-install.yml`, `playbooks/satellite-install.yml`)
- **Inventory**: `local/vars/external_inventory/hosts.yml` and `local/vars/external_inventory/host_vars/` — generated inventory used by the provisioner.
- **Provisioner container**: container name `minirhis-provisioner` (image: `quay.io/parmstro/minirhis-provisioner-9-2.5`) — used to run collection installs and long-running playbooks if container mode is selected.
- **Kickstarts and installer assets**: `kickstarts/`, `artifacts/`, and `artifacts_user/` — hold kickstarts, image build artifacts, and related installer files.
- **Installer SSH keys**: `~/.ssh/minirhis-installer/` — local control keys; public keys are deployed to `admin`/`root` on target VMs during bootstrap.

Metadata and change policy

- A machine-readable metadata file lives at the repo root: `RHIS_METADATA.yml`. It lists the primary features, functions, roles, and important file locations so automation and humans can quickly find and reason about what is configured.
- If a component is working, prefer documenting and improving it incrementally; do not remove or rewrite working artifacts unless the change improves safety, repeatability, or maintainability and is accompanied by tests or documented migration steps.

For more details and examples, see `docs/assistant-adherence-rules.md`.

## Requested Additions (user requests)

The following unique items were requested to be added to the project rules and automation roadmap.  These are recorded here so they can be codified into roles/playbooks and tracked.

- **Centralize AAP bundle config**: store AAP bundle download/extract settings in `~/.ansible/conf/env.yml` (vaulted) and make the role read it.
- **Persist IdM/Kerberos REALM**: ensure `REALM` and related IdM/Kerberos values are persisted in `~/.ansible/conf/env.yml` (vaulted) for non-interactive installs.
- **Kickstart %post snippets**: render and manage `%post` snippets via `minirhis-kickstart` / `MiniRHIS.sh` and keep them versioned in the repo.
- **Serve AAP bundle**: provide a systemd-managed HTTP service (role: `minirhis-aap-serve`) to stage and serve the AAP bundle during installs.
- **Auditable AI remediation**: create an `mcp-ai` user and a restricted runner (`/usr/local/bin/mcp-ai-runner`) with NOPASSWD limited to that runner; runner pulls containers with `podman` and records actions.
- **Local HAL CLI**: provide a `HAL` CLI (alias `hal`) to send queries to a local LLM bridge and persist transcripts for audit.
- **Dependency manifests**: add or maintain `requirements.yml`, `requirements.txt`, and `bindep.txt` for reproducible dependency installs and CI.
- **Configurable nginx redirect**: make `playbooks/nginx-redirect.yml` agnostic and configurable (reads canonical target from vaulted `env.yml` by default).
- **Satellite image provisioning automation**: document and automate image-mode provisioning (create hostgroups, protected params, import/assign provisioning templates) with an opt-in guard (`create_with_hammer`).
- **Use protected params for secrets**: prefer protected parameters (e.g., `ostree_registry_auth_b64`) and decode them in Kickstart `%pre`/`%post` instead of placing secrets in templates.

## Operational role usage (IdM)

- **Role**: `roles/minirhis-idm-operational` — consolidates post-install operational tasks (backups, healthchecks, cockpit, SELinux booleans).
- **Playbook**: `playbooks/idm-operational.yml` (target host group: `idm`, e.g. 10.168.128.3).
- **Run (dry-run)**:
  - `ANSIBLE_CONFIG=~/.ansible/conf/minirhis-ansible.runtime.cfg ansible-playbook -i local/vars/external_inventory/hosts.yml playbooks/idm-operational.yml --limit idm --check --diff --extra-vars @~/.ansible/conf/env.yml --vault-password-file ~/.ansible/conf/.vaultpass.txt -v`
- **Run (apply)**:
  - `ANSIBLE_CONFIG=~/.ansible/conf/minirhis-ansible.runtime.cfg ansible-playbook -i local/vars/external_inventory/hosts.yml playbooks/idm-operational.yml --limit idm --extra-vars @~/.ansible/conf/env.yml --vault-password-file ~/.ansible/conf/.vaultpass.txt -v`
- **Installer key**: to install the controller/installer public key on the IdM node, set `minirhis_installer_pubkey` in `~/.ansible/conf/env.yml` (vaulted) or pass via `--extra-vars 'minirhis_installer_pubkey="$(cat ~/.ssh/minirhis-installer/id_rsa.pub)"'` when running the playbook.
