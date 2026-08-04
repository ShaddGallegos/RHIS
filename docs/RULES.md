RULES for MiniRHIS
==================

1) Canonical host FQDNs

- All generated node FQDNs MUST use the short hostname + the domain defined in the vaulted Ansible env file.
- Canonical format: <short-hostname>.<domain-from-env.yml>
  - Examples: `satellite.prod.spg`, `aap.prod.spg`, `idm.prod.spg`
- The code in `MiniRHIS.sh` now reads the domain from the vaulted `ANSIBLE_ENV_FILE` and derives hostnames as:
  - `SAT_HOSTNAME=${SAT_ALIAS}.${DOMAIN}`
  - `AAP_HOSTNAME=${AAP_ALIAS}.${DOMAIN}`
  - `IDM_HOSTNAME=${IDM_ALIAS}.${DOMAIN}`

1) Vaulted env file

- Location (project default): `$HOME/.ansible/conf/env.yml`
- Vault password file (project default): `$HOME/.ansible/conf/.vaultpass.txt`
 - Vault password file (search order): `$HOME/.ansible/conf/.vaultpass.text` (preferred), then `$HOME/.ansible/conf/.vaultpass.txt`.
 - MiniRHIS reads and uses the vaulted env file in-place at `$HOME/.ansible/conf/env.yml`. Do NOT move the file; ensure the decryptable vault password file is present in the same directory or set `ANSIBLE_VAULT_PASS_FILE` to the correct path before running `MiniRHIS.sh`.

- Reconfigure behavior: If you run `MiniRHIS.sh` with the `--reconfigure` flag, the installer will enter the interactive configuration prompt flow to (re)create or repair `$HOME/.ansible/conf/env.yml` even when `--non-interactive` is also set. Run `--reconfigure` from an interactive terminal or ensure required values and a working vault password file (`ANSIBLE_VAULT_PASS_FILE`) are available ahead of time.
- To safely view the file (no plaintext left on disk):

  ```bash
  ANSIBLE_VAULT_PASSWORD_FILE=$HOME/.ansible/conf/.vaultpass.txt \
    ansible-vault view $HOME/.ansible/conf/env.yml
  ```

- To edit in-place (re-encrypted on save):

  ```bash
  ANSIBLE_VAULT_PASSWORD_FILE=$HOME/.ansible/conf/.vaultpass.txt \
    ansible-vault edit $HOME/.ansible/conf/env.yml
  ```

- If you must dump plaintext briefly, redirect to a secure temp file and remove it after use:

  ```bash
  ANSIBLE_VAULT_PASSWORD_FILE=$HOME/.ansible/conf/.vaultpass.txt \
    ansible-vault view $HOME/.ansible/conf/env.yml > /tmp/env.yml.plain
  chmod 600 /tmp/env.yml.plain
  # inspect, then securely delete
  shred -u /tmp/env.yml.plain || rm -f /tmp/env.yml.plain
  ```

- Do NOT commit `env.yml` plaintext or any vault password files to git.

1) Registration policy

- All target systems (Satellite, AAP, IdM, and optional Gitea) MUST attempt to register
  with Red Hat Subscription Management (RHSM) and Red Hat Insights as early as possible
  during bootstrap or immediately after the first reboot (post-kickstart) — before
  performing system updates or product installation steps.
- Registration credentials (for example `rh_user`/`rh_pass` or `cdn_organization_id`/`cdn_sat_activation_key`)
  MUST be stored in the vaulted runtime configuration at `$HOME/.ansible/conf/env.yml` and
  never hard-coded in playbooks or scripts. The installer roles will load that file
  and perform a best-effort registration when network connectivity is available.

1) Full-test / CI manual run

- Full end-to-end run (DEMOKILL then DEMO rhis):

  ```bash
  bash MiniRHIS.sh --DEMOKILL
  bash MiniRHIS.sh --DEMO --rhis
  ```

 The repository includes an automated wrapper that runs the two commands, retries basic fixes, and writes logs to /var/log/minirhis:

  ```bash
  ./scripts/run_rhis_full_test.sh
 Wrapper logs: `/var/log/minirhis/rhis_YYYYmmdd-HHMMSS.log` and a symlink `/var/log/minirhis/rhis_latest.log` points to the latest run.
 The wrapper will attempt some non-invasive, best-effort fixes (vault
 placeholder creation, libvirtd restart, syntax checks, optional `./scripts/apply-fixes.sh`).
 - The wrapper will attempt some non-invasive, best-effort fixes (e.g., create a placeholder vault password file, restart libvirtd) when it can detect related errors in logs.

3.a) Strict monitoring mode (MCP / AI enabled)

- When an MCP server or AI monitoring is enabled for the install (for example via the
  `AAP_LIGHTSPEED_MCP_CONTROLLER_ENABLED`, `AAP_LIGHTSPEED_MCP_LIGHTSPEED_ENABLED`, or
  relevant `AAP_LIGHTSPEED_CHATBOT_*` environment variables), the wrapper enforces a
  strict policy:
  - Any `ERROR`, `CRITICAL`, `FATAL`, or `FAIL` pattern found in the live run log will
    immediately stop the running test.
  - If `TOLERATE_WARNINGS` is not set to `1`, `WARNING` patterns are treated as
    non-tolerated and will also stop the test when monitoring is active.
  - When stopped, the wrapper runs automated diagnostics and best-effort fixes (vault
    placeholder creation, libvirtd restart, syntax checks, optional `./scripts/apply-fixes.sh`).
  - After automated fixes complete, the wrapper will restart the full test into a new
    timestamped log file (each attempt is written to `/var/log/minirhis/rhis_YYYYmmdd-HHMMSS.log`).
  - To opt out of strict warning handling, set `TOLERATE_WARNINGS=1` in the environment
    before running the wrapper.

1) Gitea opt-in and DEMOKILL preservation

- If you opt in to Gitea via the CLI flag `--gittea` the generator creates a marker at
  - `${SCRIPT_DIR}/local/gitea-present` and (best-effort) `/var/lib/minirhis/gitea-present`.
- `demokill_cleanup()` will preserve the internal libvirt network and other internal-only resources when that marker exists.

1) Troubleshooting hints

- If a test run fails, inspect the tail of the log:

  ```bash
  tail -n 500 /var/log/minirhis/rhis_latest.log
  ```

- Vault-related errors will show up as `Vault` or `ANSIBLE_VAULT` messages; ensure the vault password file exists and is protected (`chmod 600`).

1) Security

- Never store vault passwords in the repository.
- Prefer `ansible-vault view`/`edit` (no plaintext on disk) unless absolutely necessary.

If you'd like these rules added to another document or in a different format (contributing guide, README excerpt, etc.), tell me where to place them.

Hostnames & IPs (defaults)
---------------------------

Note: the hostnames, IP addresses, and example ports listed below represent the default selections used by our prompting/system generator. They are NOT secrets or sensitive data. However, they MUST NOT be hard-coded into scripts, playbooks, roles, or other repository artifacts. Once a value is chosen (prompted or otherwise), store it in the vaulted per-user environment file at `$HOME/.ansible/conf/env.yml` and reference it from there.

- Default internal network (private, prompted default): `10.168.0.0/16` — assigned to `eth1` (the second ethernet device). Internal services and cluster traffic MUST use this network when available.
- Default external network (public-facing for RHIS registration/console access, prompted default): `192.168.0.0/24` — assigned to `eth0` (the first ethernet device). This network is typically provided by the selected install platform (default: `lbvirt`).

Examples of default host mappings used by the generator (place these values into `$HOME/.ansible/conf/env.yml` if you select them; do not hardcode in repo files):

- Satellite
  - FQDN: `satellite.prod.spg`
  - Internal IP (eth1): `10.168.128.1`
  - External example: `192.168.122.1` (libvirt example)
  - Web console: `https://satellite.prod.spg` or `https://10.168.128.1`
  - Cockpit: `https://satellite.prod.spg:9090`

- Satellite
- FQDN: `${SAT_HOSTNAME:-satellite.prod.spg}`
- Internal IP (eth1): `${SAT_IP:-10.168.128.1}`
- External example: `192.168.122.1` (libvirt example)
- Web console: `https://${SAT_HOSTNAME:-satellite.prod.spg}` or `${SAT_IP:-10.168.128.1}`
- Cockpit: `https://${SAT_HOSTNAME:-satellite.prod.spg}:9090`

- Automation Platform (AAP)
  - FQDN: `aap.prod.spg`
  - Internal IP (eth1): `10.168.128.2`
  - External examples: `https://aap.prod.spg` or `https://192.168.122.6`
  - Web console (UI): `https://aap.prod.spg` (alternate example `https://192.168.122.6:9090`)
  - Cockpit: `https://aap.prod.spg`

- Automation Platform (AAP)
- FQDN: `${AAP_HOSTNAME:-aap.prod.spg}`
- Internal IP (eth1): `${AAP_IP:-10.168.128.2}`
- External examples: `https://${AAP_HOSTNAME:-aap.prod.spg}` or `https://192.168.122.6`
- Web console (UI): `https://${AAP_HOSTNAME:-aap.prod.spg}` (alternate example `https://192.168.122.6:9090`)
- Cockpit: `https://${AAP_HOSTNAME:-aap.prod.spg}`

- Identity Management (IDM)
  - FQDN: `idm.prod.spg`
  - Internal IP (eth1): `10.168.128.3`
  - External example: `https://idm.prod.spg` or `https://192.168.122.7`
  - Cockpit: `https://idm.prod.spg:9090`

- Identity Management (IDM)
- FQDN: `${IDM_HOSTNAME:-idm.prod.spg}`
- Internal IP (eth1): `${IDM_IP:-10.168.128.3}`
- External example: `https://${IDM_HOSTNAME:-idm.prod.spg}` or `https://192.168.122.7`
- Cockpit: `https://${IDM_HOSTNAME:-idm.prod.spg}:9090`

- CMDB
  - FQDN: `cmdb.prod.spg`
  - Internal IP (eth1): `10.168.128.5`
  - Web UI: `https://cmdb.prod.spg:1776`

- CMDB
- FQDN: `${CMDB_HOSTNAME:-cmdb.prod.spg}`
- Internal IP (eth1): `${CMDB_IP:-10.168.128.5}`
- Web UI: `https://${CMDB_HOSTNAME:-cmdb.prod.spg}:1776`

- (Optional) Gitea
  - FQDN: `gittea.prod.spg`
  - Internal IP (eth1): `10.168.128.4`
  - Web console: `https://gittea.prod.spg` or `https://10.168.128.4`
  - Cockpit: `https://gittea.prod.spg:9090`

- (Optional) Gitea
- FQDN: `${GITTEA_HOSTNAME:-gittea.prod.spg}`
- Internal IP (eth1): `${GITTEA_IP:-10.168.128.4}`
- Web console: `https://${GITTEA_HOSTNAME:-gittea.prod.spg}` or `${GITTEA_IP:-10.168.128.4}`
- Cockpit: `https://${GITTEA_HOSTNAME:-gittea.prod.spg}:9090`

Guidelines
```
- Do NOT hardcode the example IPs/FQDNs into repository files.
- Prompt users for the networks and hostnames during environment generation.
- After selection, write chosen values into: $HOME/.ansible/conf/env.yml (vaulted).
- Use Ansible variable lookups or the vaulted `env.yml` in playbooks/roles to reference these values.
```

SSH keys & passwordless access
-------------------------------

The installer requires passwordless SSH between the installer host (the machine running the generator/playbooks, referred to as `$USER@installer`) and all RHIS nodes. Keys MUST be generated and shared as part of the install process; do NOT embed private keys in the repository.

- Key generation and distribution requirements:
  - Generate SSH keypairs for both the interactive installer user (`$USER@installer`) and for `root` on the installer node if your workflow expects `root`-initiated actions.
  - Create and distribute keys for the `admin` account on all RHIS systems: `admin@aap`, `admin@satellite`, `admin@idm`, and `admin@gittea` (if Gitea is installed).
  - Create and distribute keys for the `root` account on all RHIS systems: `root@aap`, `root@satellite`, `root@idm`, and `root@gittea` (if Gitea is installed).
  - The installer should create these keys during provisioning and place public keys into the target nodes' `~/.ssh/authorized_keys` for the matching accounts.

- Connectivity guarantees:
  - After install completes, `$USER@installer` and `root` MUST be able to SSH to every RHIS node WITHOUT a password (full mesh for `root` across all RHIS nodes and the installer host). This includes Gitea when enabled.
  - `admin` accounts should likewise be passwordless for `admin`-level operations where required by the automation.

- Security and system configuration:
  - Do NOT commit private keys to git. Private keys must remain on the installer host or be generated per-node during provisioning.
  - Adjust `firewalld`/the system firewall to allow SSH (typically port 22) between the installer and RHIS nodes on both `eth0` and `eth1` as appropriate for your network configuration.
  - Ensure SELinux policies permit SSH key-based authentication and any automation actions that rely on SSH; where custom policies are required, include them in the installer tasks and document them in `SECURITY.md`.

- Implementation notes for playbooks/scripts:
  - The provisioning role or script responsible for account creation should accept vaulted variables for key generation preferences and user lists, e.g., `rhis_ssh_users: ["admin","root"]` and `rhis_ssh_pubkeys: {}`.
  - Use `ansible.builtin.authorized_key` to safely deploy public keys into users' `~/.ssh/authorized_keys`.
  - Use vault-protected values or generated ephemeral keys — avoid plaintext secrets in logs or temporary files. If a private key must be temporarily stored, ensure secure permissions (`chmod 600`) and remove it immediately after use.

If you'd like, I can: (a) add an Ansible role scaffolding that generates and distributes these keys during install, or (b) add a simple script that creates the keypairs and prints vault-friendly snippets for inclusion in `$HOME/.ansible/conf/env.yml`. Which do you prefer?
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

10. FAILURE/HALT POLICY: On any install failure, warning, or unexpected problem the workflow MUST stop immediately. The operator (script/automation) must:
  - Halt the current automated phase and gather diagnostics (libvirt console capture, `qemu-guest-agent` logs, `journalctl`, and Ansible ad-hoc probes).
  - Attempt best-effort automated remediation by running the matching remediation playbook(s) (for example: `playbooks/remediate-rootless-podman.yml`, `playbooks/fix-guest-sudoers.yml`, role-based repairs).
  - Append any remaining required manual/unresolved actions to the persistent TODO list and reorder TODOs by precedence (highest priority first).
  - Only resume the paused phase when diagnostics show cleared ERROR/WARNING tokens and smoke checks pass; otherwise fail loudly and require operator review.
  - Never delete undone TODOs; only mark completed items as completed. The orchestrator must persist TODO state and surface it to operators.

11. CLI SWITCH MATRIX (ENFORCED):
  - `--fullstack` = `idm` + `satellite` + `aap` + `gittea` + `openstack` (mapped to OpenShift in current implementation).
  - `--minirhis` = `idm` + `satellite` + `aap`.
  - `--rhis` = `idm` + `satellite` + `aap`.
  - `--satellite` = `satellite`.
  - `--aap` = `aap`.
  - `--idm` = `idm`.
  - `--gittea` = `gittea`.
  - `--openstack` = `openstack` (implemented as `--openshift` alias until a dedicated OpenStack component exists).
  - Combined flags are additive. Example: `--rhis --gittea` = `idm` + `satellite` + `aap` + `gittea`.

12. DEMO PREFLIGHT POLICY (ENFORCED):
  - `--DEMO` is non-production mode.
  - Preflight validation failures and transient readiness failures are tolerated as warnings in DEMO mode so test/lab flows can continue.
  - In non-DEMO runs, preflight failures remain blocking.


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
| Satellite manifest import                                   | Implemented | `scripts/import_manifest.sh`                                                                  | API-first with hammer fallback                                                                   |
| Satellite hammer/API helper setup                           | Implemented | `scripts/setup_hammer_cli.sh`, `scripts/hammer_api_fallback.sh`                                 | Standardizes Hammer CLI config and API fallback pattern                                          |
| Satellite sync plan/lifecycle/content views/activation keys | Backlog     | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Satellite DNS/DHCP/TFTP and provisioning subnet/domain      | Backlog     | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Libvirt compute resources, hostgroup, naming conventions    | Backlog     | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Ansible remote execution enablement in Satellite            | Backlog     | (no canonical playbook yet)                                                                 | Required by rules; codify in Ansible role/playbook                                               |
| Node decommission cleanup (Satellite + libvirt + qcow2)     | Partial     | `roles/minirhis-recovery`, `playbooks/recover-vm.yml`, `playbooks/rollback-vm.yml`          | Recovery exists; explicit host decommission workflow should be codified                          |

Current remaining gaps are explicitly tracked as Backlog items in this checklist: sync plan/lifecycle/content views/activation keys, DNS/DHCP/TFTP provisioning domain, compute resources/hostgroup naming automation, and Satellite remote execution enablement. These gaps match what is not yet codified in playbooks/roles and should be prioritized into project issues for implementation.

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
