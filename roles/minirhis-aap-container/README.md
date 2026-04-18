# minirhis-aap-container

Skeleton Ansible role to prepare a host for running AAP 2.6 controller in containers.

This role is intentionally small and safe: it ensures `podman` and `crun` are available, creates persistent volumes, pulls a placeholder image, and installs a simple `systemd` service stub to run the container.

Usage

```
ansible-playbook -i inventory/hosts playbooks/run-aap-container-setup.yml -e "aap_controller_image=registry.example.com/aap:2.6"
```

Notes
- Replace `aap_controller_image` with the official registry image path for AAP 2.6 during final conversion.
- This role is a scaffold and should be extended to map RPM-based AAP tasks (DB initialization, migrations, data directories) to containerized equivalents.
