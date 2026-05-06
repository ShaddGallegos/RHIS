# MINIRHIS Checklist

This checklist summarizes current progress and next steps for the MINIRHIS repository.

## Completed
- Restore `MiniRHIS.sh` to repository HEAD
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

## Notes
- The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default.
- Do NOT commit `env.yml` or vault password files. Add any sensitive artifacts to `.gitignore`.
