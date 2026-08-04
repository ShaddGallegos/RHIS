# CHECKLIST

This checklist lists required inputs and quick pointers for running the MRHIS workflows.

Required items (installer host):

- Red Hat CDN credentials (RH_USER / RH_PASS) with access to Satellite/AAP/IdM packages
- RHEL ISO image for the target guest installs (RHEL 10 recommended)
- Sufficient host resources (see README.md hardware guidance)
- Working libvirt/KVM environment and `virsh` access
- `podman` installed for container workflows
- `ansible` / `ansible-core` available on the installer host (pip or dnf)
- A dedicated internal network range for demo VMs (default: 10.168.128.0/24)

Optional (but recommended):

- `jq`, `openssl` and `curl` installed on installer host for debugging
- `podman-docker` if using Docker-compatibility wrappers

Note on artifacts, logs and secrets:

- Do NOT commit runtime artifacts, logs, or extracted certificates into the repository.
- Store runtime artifacts and collected logs in `artifacts_user/` (this path is ignored by git).
- Keep credential files out of source control. Use `ansible-vault` (e.g. `~/.ansible/conf/env.yml`) or pass a file with `--env-file` to `MRHIS.sh`.

Where to put your inputs:

- Place saved `env.yml` / vault files in `host_vars/` (vaulted) or supply a custom `--env-file` to `MRHIS.sh`.
- Place any local ISO files in the path referenced by your env file.

Minimal verification before running:

1. `podman ps` shows provisioner container when running container workflows
2. `virsh net-list --all` shows your internal network active
3. `ansible --version` matches the `requirements.txt` recommendations (use a virtualenv if needed)

MCP remediator quick checks:

- Ensure `mcp` system user exists and `/opt/mcp-rhel-manager` is present.
- To enable/start remediator services run: `/opt/mcp-rhel-manager/mcp-ai/enable_services.sh` (requires root).
- Check remediator health: `ss -ltnp | grep 1776` and `systemctl status mcp-bridge.service`.

If something goes wrong, collect artifacts to `artifacts_user/` and open an issue or attach them to your support request.
