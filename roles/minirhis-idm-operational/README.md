IdM operational role
====================

This role consolidates post-install operational tasks for the IdM (FreeIPA) node.

Usage:

- Include the role in a play targeting the `idm` host group (10.168.128.3 in your inventory).
- Configure `minirhis_installer_pubkey` if you want the controller's installer public key installed on the IdM node.

Variables (defaults in `defaults/main.yml`):
- `ipa_backup_dir` - directory to store ipa backups
- `ipa_backup_script_path` - path to the backup script on the node
- `ipa_healthcheck_script_path` - path to the healthcheck script on the node
- `enable_cockpit` - enable `cockpit.socket` on the node
