# Security and Sensitive Data Handling

This repository is configured to avoid storing any secrets, hostnames, SSH keys, or other sensitive data in the tracked sources.

Guidelines and automated helpers:

- All secrets (tokens, passwords, credentials, offline tokens) must live only in the untracked vaulted file: `~/.ansible/conf/env.yml`.
- Do not commit or store SSH private keys, PEM files, or any host facts under the repository. `.gitignore` already excludes common patterns (logs, keys, artifacts_user, host_vars, server_facts, server_diagnostics, local vault files).
- Before committing, run the scrub utility which moves detected sensitive runtime artifacts into a local temporary stash and creates placeholders:

```bash
./scripts/scrub_sensitive.sh
```

- The `scripts/aap_bundle_fetch.sh` script will persist refreshed `rh_offline_token` back into `~/.ansible/conf/env.yml` (using `ansible-vault`) when the vault password file is configured via `VAULT_PASS_FILE` and the vault file exists.

- Runtime logs should be written to system locations (`/var/log`) or the user's home under `~/.ansible/` as configured by local runtime variables.

- If you need to temporarily stage artifacts for the installer, prefer `/tmp` or an explicitly configured transient directory. Do not commit those files.

If you need additional automation (pre-commit hooks, CI checks to prevent accidental commits), tell me and I can add them (a lightweight pre-commit hook is recommended).