# mrhis-recovery

Ansible role to create a safe backup of a libvirt `qcow2` image, mount the backup, inject an SSH public key, and restore SELinux labels (best-effort).

Usage example (control host is the libvirt host where images are stored):

```
ansible-playbook playbooks/recover-vm.yml -e vm_name=aap
```

Role variables (defaults in `roles/mrhis-recovery/defaults/main.yml`):
- `vm_name` (required): short name of the VM whose image is at `/var/lib/libvirt/images/{{ vm_name }}.qcow2`.
- `recovery_backup_dir`: where the backup copy will be written.
- `mount_point`: temporary mountpoint used by `guestmount`.
- `installer_pubkey`: path to the public key to inject into the image's `/root/.ssh/authorized_keys`.

Notes & warnings:
- The role uses `qemu-img convert` to produce a backup copy. This is deliberate (full copy + safe) but can be slow for large images.
- `guestmount` requires `libguestfs`/`guestmount` on the host.
- This role is intended to run on the libvirt host (localhost) that hosts the VM images.

---

**Rules & Policies**

- This role follows the repository RULES: see `RULES.md` and `docs/assistant-adherence-rules.md` for the full policy.
- Always create a backup before writing to the original image and record the backup filename and timestamp in your run metadata.
- Prefer using `qemu-guest-agent`-driven in-guest operations when available; use this role only when offline image edits are required and documented.

## Headless Test & Vault

See the top-level README 'Headless Noninteractive Test (developer)' for the noninteractive test command and vault guidance.
