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
 The wrapper will attempt some non-invasive, best-effort fixes (e.g., create a placeholder vault password file, restart libvirtd) when it can detect related errors in logs.
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

- Automation Platform (AAP)
  - FQDN: `aap.prod.spg`
  - Internal IP (eth1): `10.168.128.2`
  - External examples: `https://aap.prod.spg` or `https://192.168.122.6`
  - Web console (UI): `https://aap.prod.spg` (alternate example `https://192.168.122.6:9090`)
  - Cockpit: `https://aap.prod.spg`

- Identity Management (IDM)
  - FQDN: `idm.prod.spg`
  - Internal IP (eth1): `10.168.128.3`
  - External example: `https://idm.prod.spg` or `https://192.168.122.7`
  - Cockpit: `https://idm.prod.spg:9090`

- CMDB
  - FQDN: `cmdb.prod.spg`
  - Internal IP (eth1): `10.168.128.5`
  - Web UI: `https://cmdb.prod.spg:1776`

- (Optional) Gitea
  - FQDN: `gittea.prod.spg`
  - Internal IP (eth1): `10.168.128.4`
  - Web console: `https://gittea.prod.spg` or `https://10.168.128.4`
  - Cockpit: `https://gittea.prod.spg:9090`

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

