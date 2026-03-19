# RHIS Script Run Checklist

Use this checklist before running `run_rhis_install_sequence.sh`.

You can provide most items in one of three ways:

- interactively when the script prompts
- in `~/.ansible/conf/env.yml` (encrypted with `ansible-vault`)
- in a bootstrap file passed with `--env-file /path/to/file`

---

## 1. Host machine prerequisites

### Required

- [ ] Linux host with `sudo` access
- [ ] Hardware virtualization available (`KVM`/`libvirt`)
- [ ] Enough CPU / RAM / disk for Satellite, AAP, and IdM VMs
- [ ] Internet access from host to Red Hat services
- [ ] Ability to install host packages as needed (`libvirt`, `virt-install`, `qemu-img`, `genisoimage`/`xorriso`, `tmux`, etc.)

### Notes

- The script installs some prerequisites automatically, but the host still needs working package repositories and sudo privileges.
- A GUI desktop session is helpful if you want the auto-opened console monitor windows. On headless systems the script falls back to `tmux`.

---

## 2. Vault / secret storage prerequisites

### Required

- [ ] An Ansible Vault password for `~/.ansible/conf/.vaultpass.txt`

### Where it comes from

- You create this locally the first time the script runs.
- It is **not** downloaded from a URL.

### Used for

- Encrypting `~/.ansible/conf/env.yml`

---

## 3. Red Hat account / entitlement inputs

### Required

- [ ] `RH_USER` — Red Hat CDN username
- [ ] `RH_PASS` — Red Hat CDN password
- [ ] `RH_OFFLINE_TOKEN` — Red Hat offline token
- [ ] `RH_ACCESS_TOKEN` — Red Hat access token

### Where to obtain them

- Red Hat Customer Portal / Hybrid Cloud Console:
  - https://access.redhat.com/
  - https://console.redhat.com/
- Offline token / API access context:
  - https://console.redhat.com/openshift/token
- Token endpoint used by the script:
  - `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`

### Notes

- The script can derive an access token from the offline token in some flows, but the current prompt flow expects both values to be available.
- These credentials are used for registration, repo enablement, ISO access, and bundle download.

---

## 4. Product download URLs / artifacts

### Required

- [ ] `RH_ISO_URL` — direct URL for the RHEL 10 installation ISO
- [ ] `AAP_BUNDLE_URL` — direct URL for the AAP 2.6 containerized setup bundle `.tar.gz`

### Where to obtain them

- Red Hat downloads portal:
  - https://access.redhat.com/downloads/

### Notes

- `RH_ISO_URL` should point to the RHEL 10 DVD / Everything ISO you want the VMs to install from.
- `AAP_BUNDLE_URL` should point to the **Ansible Automation Platform 2.6 containerized setup bundle**.
- These are usually authenticated CDN links copied from the downloads portal.

---

## 5. Automation Hub access

### Required

- [ ] `HUB_TOKEN` — Red Hat Automation Hub token

### Where to obtain it

- Red Hat Hybrid Cloud Console / Automation Hub:
  - https://console.redhat.com/

### Notes

- The AAP kickstart uses this so the containerized installer can access Automation Hub content.

---

## 6. Shared identity / naming inputs

### Required

- [ ] `ADMIN_USER` — shared admin username used across the lab
- [ ] `ADMIN_PASS` — shared admin password used across the lab
- [ ] `DOMAIN` — shared DNS domain (example: `prod.spg`)
- [ ] `REALM` — Kerberos realm (usually uppercase domain, example: `PROD.SPG`)

### Where these come from

- Chosen by you / your organization
- No download URL

### Notes

- These values are reused across Satellite, AAP, and IdM.
- The script now treats placeholders like `example.com` as unresolved and will prompt again.

---

## 7. Internal network plan

### Required by prompt flow or strong recommended customization

- [ ] `NETMASK` — shared internal subnet mask
- [ ] `INTERNAL_GW` — shared internal gateway
- [ ] `SAT_IP` — Satellite internal IP
- [ ] `AAP_IP` — AAP internal IP
- [ ] `IDM_IP` — IdM internal IP
- [ ] `SAT_HOSTNAME` — Satellite FQDN
- [ ] `AAP_HOSTNAME` — AAP FQDN
- [ ] `IDM_HOSTNAME` — IdM FQDN

### Default values currently assumed by the script

- `SAT_IP=10.168.128.1`
- `AAP_IP=10.168.128.2`
- `IDM_IP=10.168.128.3`
- `NETMASK=255.255.0.0`
- `INTERNAL_GW=0.0.0.0`

### Where these come from

- Chosen by you / your lab network design
- No download URL

### Notes

- The script expects:
  - `external` network = outside connectivity / updates / remote access
  - `internal` network = provisioning / orchestration / management
- Make sure your chosen IPs and names match your intended DNS and routing plan.

---

## 8. Satellite-specific values

### Required / prompted

- [ ] `SAT_ORG` — Satellite Organization
- [ ] `SAT_LOC` — Satellite Location

### Default values in script

- `SAT_ORG=REDHAT`
- `SAT_LOC=CORE`

### Where these come from

- Chosen by you / your Satellite design
- No download URL

---

## 9. IdM-specific values

### Required / prompted

- [ ] `IDM_ADMIN_PASS` — IdM admin password
- [ ] `IDM_DS_PASS` — IdM Directory Server password

### Default behavior

- `IDM_ADMIN_PASS` may inherit from the shared admin password if not customized
- `IDM_DS_PASS` has a script default, but you should set it explicitly for real use

### Where these come from

- Chosen by you / your organization
- No download URL

---

## 10. Host-side optional overrides

### Optional

- [ ] `ISO_DIR`
- [ ] `ISO_NAME`
- [ ] `ISO_PATH`
- [ ] `VM_DIR`
- [ ] `KS_DIR`
- [ ] `OEMDRV_ISO`
- [ ] `HOST_INT_IP`

### Notes

- Only needed if you do **not** want the script defaults.
- `HOST_INT_IP` is important if the AAP bundle HTTP server should bind to a different host address than the default `192.168.122.1`.

---

## 11. Recommended minimum data set to gather before first run

If you want the shortest practical checklist, gather these first:

- [ ] Red Hat CDN username/password
- [ ] Red Hat offline token
- [ ] Red Hat access token
- [ ] RHEL ISO URL
- [ ] AAP bundle URL
- [ ] Automation Hub token
- [ ] Shared domain and realm
- [ ] Shared admin username/password
- [ ] Satellite / AAP / IdM internal IPs and hostnames
- [ ] Satellite org and location
- [ ] IdM DS password
- [ ] AAP deployment model choice (enterprise multi-node `inventory.j2` or growth single-node `inventory-growth.j2`; DEMO is auto-selected with `--demo`)

---

## 12. Suggested run order

1. Fill in the required values
2. Run:
   - `./run_rhis_install_sequence.sh --reconfigure`
   - During `--reconfigure`, an interactive **inventory architecture submenu** will appear
     to select the AAP installer deployment model (enterprise or growth; use `--demo` to skip)
3. Verify values were written to:
   - `~/.ansible/conf/env.yml`
4. Clean old lab state if needed:
   - `./run_rhis_install_sequence.sh --demokill`
5. Build the demo stack:
   - `./run_rhis_install_sequence.sh --demo`
6. Optional: run a fast validation sweep after cleanup / before a full rebuild:
  - `./run_rhis_install_sequence.sh --test=fast --demo`
7. Optional: run the broader integration-style test sweep:
  - `./run_rhis_install_sequence.sh --test=full --demo`

---

## 13. Quick source links

- Red Hat Customer Portal: https://access.redhat.com/
- Red Hat Downloads: https://access.redhat.com/downloads/
- Red Hat Hybrid Cloud Console: https://console.redhat.com/
- Token / API access page: https://console.redhat.com/openshift/token
- Red Hat SSO token endpoint used by script: https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token

---

## 14. Final sanity check before running

- [ ] Domain and hostnames are **not** placeholders like `example.com`
- [ ] URLs are current authenticated download URLs
- [ ] Tokens are still valid
- [ ] Host has enough free disk space for ISO + qcow2 images + AAP bundle
- [ ] If using test mode, review `~/.ansible/conf/ansible-provisioner.log` after the run
- [ ] KVM/libvirt is working (`virsh list --all` succeeds)
- [ ] Your chosen internal IPs do not conflict with an existing network
