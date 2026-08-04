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

1) Full-test / CI manual run

- Full end-to-end run (DEMOKILL then DEMO rhis):

  ```bash
  bash MiniRHIS.sh --DEMOKILL
  bash MiniRHIS.sh --DEMO --rhis
  ```

- The repository also includes an automated wrapper that runs the two commands, retries basic fixes, and writes logs to `./log`:
- The repository also includes an automated wrapper that runs the two commands, retries basic fixes, and writes logs to `../log` (parent folder):

  ```bash
  ./tools/run_rhis_full_test.sh
  ```

- Wrapper logs: `../log/rhis_YYYYmmdd-HHMMSS.log` and a symlink `../log/rhis_latest.log` points to the latest run.
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
    timestamped log file (each attempt is written to `../log/rhis_YYYYmmdd-HHMMSS.log`).
  - To opt out of strict warning handling, set `TOLERATE_WARNINGS=1` in the environment
    before running the wrapper.

1) Gitea opt-in and DEMOKILL preservation

- If you opt in to Gitea via the CLI flag `--gittea` the generator creates a marker at
  - `${SCRIPT_DIR}/local/gitea-present` and (best-effort) `/var/lib/minirhis/gitea-present`.
- `demokill_cleanup()` will preserve the internal libvirt network and other internal-only resources when that marker exists.

1) Troubleshooting hints

- If a test run fails, inspect the tail of the log:

  ```bash
  tail -n 500 ../log/rhis_latest.log
  ```

- Vault-related errors will show up as `Vault` or `ANSIBLE_VAULT` messages; ensure the vault password file exists and is protected (`chmod 600`).

1) Security

- Never store vault passwords in the repository.
- Prefer `ansible-vault view`/`edit` (no plaintext on disk) unless absolutely necessary.

If you'd like these rules added to another document or in a different format (contributing guide, README excerpt, etc.), tell me where to place them.
