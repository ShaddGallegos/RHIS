# RULES — Quick Reference

This file is the concise, top-level summary of the project rules. The full, authoritative rules document is `docs/assistant-adherence-rules.md`.

Quick rules (must follow):

1. RULE: Do not use container workflows unless an explicit flag is provided (for example `--container`, `--container-config-only`, or `--use-container`). The default operations run on the host.
2. Configuration-as-code first: codify all fixes, installer steps, and recovery procedures as Ansible roles/playbooks in this repo.
3. Snapshot before edits: always snapshot or copy any VM image (`qcow2`) before offline edits and record snapshot name + timestamp.
4. Prefer guest-agent: use `qemu-guest-agent` for in-guest operations instead of offline mounts when possible.
5. Secrets must be stored in Ansible Vault; do not commit plain credentials into the repository.
6. Idempotence: roles and playbooks must be idempotent and covered by smoke tests.
7. Use libvirt APIs for network changes; do not edit generated ephemeral files.
8. Record run metadata, logs and link to PR/issue for any deviation from these rules.

See `docs/assistant-adherence-rules.md` for full details, examples, and enforcement guidance.
 
- RULE: All Ansible PRs must pass CI linting and syntax checks (`ansible-lint`, `yamllint`, and `ansible-playbook --syntax-check`).
