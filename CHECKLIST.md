# MRHIS Checklist

This checklist summarizes current progress and next steps for the MRHIS repository.

## Completed
- Restore `MRHIS.sh` to repository HEAD
- Refactor IdM kickstart generation into `generate_idm_kickstart_core` and update callsites

## In-progress
- Audit codebase for hard-coded secrets and sensitive data (see repo scan results)

## Pending
- Remove/relocate any hard-coded secrets to vaulted `~/.ansible/conf/env.yml`
- Run headless verification and capture logs (NONINTERACTIVE test)
- Analyze headless logs and fix runtime issues
- Vault `idm_ds_pass` and realm/domain into `~/.ansible/conf/env.yml` (requires secrets from operator)
- Update README files and documentation to reflect noninteractive flow and vault usage
- Consolidate duplicates and remove unnecessary artifacts before pushing to GitHub
- Add CI pre-commit + ansible-lint hooks to prevent secret commits
- Commit changes to a feature branch and open PR

## Todos
- [x] Fix always-true `LIVE_IP` condition in noninteractive validation path (`MRHIS.sh`), so MOTD splash hook runs only when `LIVE_IP` is actually set.
- [x] Reduce argument-splitting risk in post-install healthcheck Ansible calls by using arrays for inventory, vault args, extra-vars, and one-line option handling.
- [x] Reduce argument-splitting risk in sshpass first-touch bootstrap by switching SSH option handling to an array.
- [ ] Refactor remaining dynamic Ansible invocations that still use string-expanded composite args (for example `inv`/`evars` in container execution paths) into arrays.
- [ ] Security tightening items are deferred by operator preference to prioritize easiest installation path (keep existing permissive bootstrap approach unless it blocks installs).

## Notes
- The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default.
 - Do NOT commit `env.yml` or vault password files. Add any sensitive artifacts to `.gitignore`.

## Red Hat API & Downloads

- API access page: https://access.redhat.com/management/api
- Token exchange endpoint: https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
- Image download endpoint (template): https://api.access.redhat.com/management/v1/images/<image-id>/download

To exchange an offline token for an access token:

```bash
offline_token='YOUR_OFFLINE_TOKEN'
token=$(curl https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token \
		 -d grant_type=refresh_token \
		 -d client_id=rhsm-api \
		 -d refresh_token=$offline_token | jq -r .access_token)
```

## Tokens & Where to Obtain Them

- `RH_OFFLINE_TOKEN`: Red Hat Offline Token — obtain from https://access.redhat.com/ (Account -> Settings -> API Tokens / Subscriptions area).
- `RH_ACCESS_TOKEN`: Red Hat Access Token — can be generated via https://console.redhat.com/ or derived from an offline token (see example above).
- `HUB_TOKEN`: Automation Hub token — find or create this in Automation Hub / https://cloud.redhat.com/ under your Automation Hub account settings (Tokens/API access).
- `VAULT_CONSOLE_REDHAT_TOKEN`: Optional Red Hat Console/Vault token — see https://cloud.redhat.com/ for token generation.
- `GITTEA_ADMIN_TOKEN`: Personal access token for Gitea — generate in your Gitea instance under `Settings -> Applications` or `Settings -> Access Tokens` (e.g. https://<gittea_host>/user/settings/applications).

Ensure these token names match the variable names used by the installer prompts and the vaulted `~/.ansible/conf/env.yml` to avoid ambiguity.
