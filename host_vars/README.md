# host_vars/

This directory is bind-mounted into the `rhis-provisioner` container at  
`/rhis/vars/host_vars/`.

## Setup

Copy each `*.SAMPLE` file to its actual name (removing `.SAMPLE`) and fill in  
real values before running any rhis-builder playbook:

```
host_vars/satellite.yml   — Satellite VM connection + org/location vars
host_vars/aap.yml         — AAP admin credentials
host_vars/idm.yml         — IdM realm/domain overrides
host_vars/installer.yml   — Controller/installer host SSH settings
```

## Secrets

Sensitive values (passwords, tokens) **must not** be stored in plain text.  
Reference them from your Ansible vault instead:

```yaml
ansible_password: "{{ global_admin_password | default('') }}"
```

Store the vault at `~/.ansible/conf/env.yml` (encrypted with `ansible-vault`).  
See `CHECKLIST.md` in the repo root for the full secret checklist.
