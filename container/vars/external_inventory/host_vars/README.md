# host_vars — Ansible Inventory-Relative Host Variables

These files are **auto-generated** by `MiniRHIS.sh` (`generate_rhis_host_vars()`)
and placed here so Ansible discovers them automatically when using the inventory
file at `container/vars/external_inventory/hosts.yml`.

Per Ansible convention, each file is named after the **host** it applies to:

| File                     | Host         |
| ------------------------ | ------------ |
| `satellite.prod.spg.yml` | Satellite VM |
| `aap.prod.spg.yml`       | AAP VM       |
| `idm.prod.spg.yml`       | IdM VM       |

## Source of truth

All values come from `~/.ansible/conf/env.yml` (ansible-vault encrypted).
Edit via `./MiniRHIS.sh --reconfigure` — do NOT edit these files directly.

## Security

Do **not** commit these files — they contain resolved IPs and credentials.
`.gitignore` excludes this directory (covered by `container/vars/external_inventory/`
gitignore patterns are not set — these are intentionally tracked as generated
artifacts when running standalone builder workflows).

> **Note:** Passwords are vault references (`{{ sat_admin_pass }}`), not plaintext.
