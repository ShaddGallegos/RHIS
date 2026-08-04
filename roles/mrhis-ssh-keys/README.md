Role: mrhis-ssh-keys
======================

Purpose
-------
Scaffold role to generate and distribute SSH public keys for RHIS accounts (`admin`, `root`, and optional `gittea`).

Usage
-----
- Generate installer keypair and a vault snippet using:

```bash
./scripts/generate_ssh_keys_and_vault_snippet.sh
# then edit/encrypt $HOME/.ansible/conf/env.yml and paste the snippet
```

- Run this role from the installer host against your inventory to distribute the public key to target accounts.

Notes
-----
- This role is a scaffold. It intentionally uses standard Ansible modules like `authorized_key`.
- Do NOT store private keys in the repository. Keep them local and vaulted if needed.
