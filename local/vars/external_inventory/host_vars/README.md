# host_vars — Ansible Inventory-Relative Host Variables

These files are **auto-generated** by `MiniRHIS.sh` (`generate_minirhis_host_vars()`)
and placed here so Ansible discovers them automatically when using the inventory
at `local/vars/external_inventory/hosts.yml`.

Per Ansible convention, each file is named after the **host** it applies to —
the FQDN of the VM as set in `~/.ansible/conf/env.yml`.

## Generated filenames (examples)

| File                     | Host         |
| ------------------------ | ------------ |
| `satellite.<domain>.yml` | Satellite VM |
| `aap.<domain>.yml`       | AAP VM       |
| `idm.<domain>.yml`       | IdM VM       |

The `<domain>` part is the `DOMAIN` value you set during `./MiniRHIS.sh --reconfigure`.

## Source of truth

All values come from `~/.ansible/conf/env.yml` (ansible-vault encrypted).
Edit via `./MiniRHIS.sh --reconfigure` — do NOT edit these files directly.

## Security / git tracking

**Do NOT commit these files.**  They contain resolved IPs, FQDNs, and path
references specific to your deployment.

`.gitignore` excludes this directory with:

```gitignore
local/vars/external_inventory/host_vars/*.yml
!local/vars/external_inventory/host_vars/README.md
```

Passwords stored here are vault references (`{{ sat_admin_pass }}`), not plaintext.

---

**Rules & Policies**

- Do not commit generated host_vars. Refer to `RULES.md` and `docs/assistant-adherence-rules.md` for the policy on when and how to perform image or host edits.
