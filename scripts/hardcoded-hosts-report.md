Hardcoded hosts & IPs scan
===========================

This report lists occurrences of internal IPs and example FQDNs that should be reviewed and (where appropriate) replaced with vaulted variables (`~/.ansible/conf/env.yml`) or template variables.

Summary of notable findings (non-exhaustive):

- `MRHIS.sh` contains many defaults and fallbacks referencing `10.168.0.0/16` and `10.168.128.x` (these are often assigned as variable defaults; review them to ensure they come from `env.yml` at runtime).
- `playbooks/templates/mrhis-hosts.j2` still contains defaults with literal `10.168.128.x` and `*.prod.spg` hostnames — these are template defaults and should be parameterized from the vaulted env file.
- `README.md` contained multiple literal IPs (now partially replaced with `${VAR:-fallback}` placeholders) — verify the remaining examples.
- Sample artifacts and local templates (e.g., `local/vars/templates/ansible-cmdb-history-dashboard.sample.yml`) reference `*.prod.spg` names; these are sample files but should prefer variables or be clearly labeled as examples.

Selected locations (path:line — snippet):

MRHIS.sh
- line ~374: `INTERNAL_NETWORK="${INTERNAL_NETWORK:-10.168.0.0}"`
- line ~379: `SAT_IP="${SAT_IP:-10.168.128.1}"`
- line ~380: `AAP_IP="${AAP_IP:-10.168.128.2}"`
- line ~381: `IDM_IP="${IDM_IP:-10.168.128.3}"`
- line ~431: `SAT_PROVISIONING_DNS_PRIMARY="${SAT_PROVISIONING_DNS_PRIMARY:-${SAT_IP:-10.168.128.1}}"`
- line ~2158: network summary prints with `10.168.128.x` fallbacks

playbooks/templates/mrhis-hosts.j2
- lines 10-13: entries with `{{ SAT_IP | default('10.168.128.1') }} satellite.prod.spg satellite` and similar for `aap`, `idm`.

README.md
- multiple occurrences of `10.168.128.x` (now replaced in many places). See `README.md` for updated placeholders; verify the table and TLS examples.

local/vars/templates/ansible-cmdb-history-dashboard.sample.yml
- contains node names: `aap.prod.spg`, `satellite.prod.spg`, `idm.prod.spg`, `cmdb.internal.prod.spg`.

playbooks and scripts
- some playbooks and embedded templates contain literal `*.prod.spg` and example IPs (search for `prod.spg` and `10.168.` across the repo).

Recommendations
- Replace example FQDNs in templates and documentation with placeholders that point to vaulted variables: e.g., `${SAT_IP:-10.168.128.1}`, `${SAT_HOSTNAME:-satellite.<domain>}` or use Jinja2 variables (`{{ sat_ip }}`) in templates.
- Ensure `playbooks/templates/mrhis-hosts.j2` is rendered from vault-backed env values and remove any fallback literals where not appropriate.
- For sample files (in `local/vars/templates`), clearly label them as examples and avoid real-looking defaults where possible.

Next steps performed by the assistant in this run:
- Updated README examples to use environment-variable placeholders for a range of quick-check commands and the default node table.
- Added `build/etc/hosts.template` and `build/render_hosts.sh` to generate /etc/hosts fragments from `~/.ansible/conf/env.yml`.

Use the following command to re-run a full scan (copy/paste-friendly):

```bash
grep -R --line-number --binary-files=without-match -E "10\\.168\\.|\.prod\\.spg|example\\.com" . | sed -E 's|^\./||' | sort
```

If you want, I can now (A) automatically replace remaining safe occurrences in non-code files (docs, samples), (B) update Jinja2 templates to use vaulted variables, and (C) create a branch with these changes and a unit test checklist. Tell me which to proceed with next or confirm "go" and I'll apply the safe replacements now.
