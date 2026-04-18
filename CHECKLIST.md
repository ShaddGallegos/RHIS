# CHECKLIST

This checklist lists required inputs and quick pointers for running the MiniRHIS workflows.

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

Runtime artifacts and debug helpers (collected 2026-04-17):

- Gateway logs: artifacts_user/gw-automation-gateway-aap.prod.spg.log
- Gateway proxy logs: artifacts_user/gw-automation-gateway-proxy-aap.prod.spg.log
- Controller logs archive: artifacts_user/controller-logs-aap.prod.spg.tar.gz
- Extracted AAP root CA: artifacts_user/aap-root-ca.pem

Where to put your inputs:

- Place saved `env.yml` / vault files in `host_vars/` or supply a custom `--env-file` to `MiniRHIS.sh`.
- Place any local ISO files in the path referenced by your env file.

Minimal verification before running:

1. `podman ps` shows provisioner container when running container workflows
2. `virsh net-list --all` shows your internal network active
3. `ansible --version` matches the `requirements.txt` recommendations (use a virtualenv if needed)

If something goes wrong, collect artifacts to `artifacts_user/` and open an issue or attach them to your support request.
