# host_vars — Ansible Inventory-Relative Host Variables

The generated per-host YAML files were simplified so shared connection and role
defaults now live in `local/vars/external_inventory/group_vars/`. This directory
is kept only for compatibility with Ansible's inventory layout and for any
future per-host overrides that cannot be shared.

Per Ansible convention, each file is named after the **host** it applies to —
the FQDN of the VM as set in `~/.ansible/conf/env.yml`.

## Source of truth

All values come from `~/.ansible/conf/env.yml` (ansible-vault encrypted) and
the shared `group_vars/` inventory files. Edit via `./MiniRHIS.sh --reconfigure`
— do NOT edit generated inventory data directly.

## Security / git tracking

**Do NOT commit generated inventory data.** The repository now keeps the shared
defaults in `group_vars/` and only reserves this directory for local overrides.

`.gitignore` excludes this directory with:

```gitignore
local/vars/external_inventory/host_vars/*.yml
!local/vars/external_inventory/host_vars/README.md
```

---

**Rules & Policies**

- Do not commit generated host_vars. Refer to `RULES.md` and `docs/assistant-adherence-rules.md` for the policy on when and how to perform image or host edits.

## Headless Test & Vault

See the top-level README 'Headless Noninteractive Test (developer)' for the noninteractive test command and vault guidance.
