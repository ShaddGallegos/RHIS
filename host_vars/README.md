# host_vars — Per-Host Ansible Variables

These files are **auto-generated** by `MiniRHIS.sh` (`generate_minirhis_host_vars()`)
during initial setup or reconfiguration and placed here so Ansible discovers
them when using the top-level inventory.

## Git tracking

Only `*.SAMPLE` files are tracked in git — they contain commented-out examples
and serve as documentation for what each variable does.

Generated working copies (e.g., `aap.yml`, `satellite.yml`, `idm.yml`) are
excluded by `.gitignore` — they contain your lab-specific hostnames, IPs, and
vault references.

## Usage

1. Run `./MiniRHIS.sh --reconfigure` to (re)generate all host_vars files from
   your `~/.ansible/conf/env.yml`.
2. Review the SAMPLE files to understand available variables.
3. Do NOT commit the generated files — they contain deployment-specific secrets.

## File index

| File                      | Purpose                                      |
| ------------------------- | -------------------------------------------- |
| `aap.yml.SAMPLE`          | AAP Controller + Hub + Gateway variables     |
| `idm.yml.SAMPLE`          | Red Hat IdM / FreeIPA variables              |
| `satellite.yml.SAMPLE`    | Red Hat Satellite variables                  |
| `installer.yml.SAMPLE`    | Installer host (KVM controller) variables    |
