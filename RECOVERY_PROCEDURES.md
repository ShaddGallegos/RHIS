# RHIS Recovery Procedures

## Situation: Config-as-Code Phases Failed (IdM, Satellite, AAP)

**Status Date:** 2026-03-24  
**Issue:** IdM and Satellite playbooks failed; AAP SSH callback timeout

### Root Causes Identified

1. **IdM Phase Failure:** Missing Jinja2 template `chrony.j2` in provisioner container
   - Error: `Could not find or access 'chrony.j2'`
   - Location: `/rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2`
   - **Status:** ✅ **FIXED** - Template injected into running container

2. **Satellite Phase Failure:** Package lock contention during system update check
   - Task: "Check on system update" retried 960 times over ~167 seconds
   - Likely cause: dnf lock waited too long before timeout
   - Known issue: iptables service check already has `ignore_errors: true`

3. **AAP VM Callback Timeout:** SSH callback phase couldn't reach aap-26 during provisioning
   - Error: `Cannot reach aap-26 via SSH. Setup not attempted.`
   - Status: VM is running and SSH is accessible post-install
   - Reason: Callback occurs during VM provisioning (before SSH keys distributed)

### Infrastructure Status Summary

| Component | State | SSH | Status |
|-----------|-------|-----|--------|
| satellite-618 | running | ✓ | Playbook failed - retry available |
| aap-26 | running | ✓ | Callback timeout - SSH setup needed |
| idm | running | ✓ | Playbook failed - retry available |

### Emergency Fixes Applied

#### 1. IdM and Satellite chrony.j2 Templates 
```bash
# Templates created and injected into rhis-provisioner container:
/rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2           # ✅ FIXED
/rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2  # ✅ FIXED
```

**Action Taken:** Fallback chrony template configured and copied into container via `podman cp`

---

## Recovery Procedures

### Option A: Retry Config-as-Code (Recommended - Simple)

The easiest recovery is to re-run the config-as-code phases now that templates are fixed:

```bash
# SSH into IdM and run the IdM playbook retry
ssh root@10.168.128.3

# Then inside the provisioner container:
podman exec -it rhis-provisioner /bin/bash

# Inside container, run IdM playbook with the fixed templates:
ansible-playbook \
  --inventory /rhis/vars/external_inventory/hosts \
  --vault-password-file /rhis/vars/vault/.vaultpass.container \
  --extra-vars @/rhis/vars/vault/env.yml \
  --limit scenario_idm \
  /rhis/rhis-builder-idm/main.yml

# Then run Satellite playbook (with same parameters but different limit/playbook):
ansible-playbook \
  --inventory /rhis/vars/external_inventory/hosts \
  --vault-password-file /rhis/vars/vault/.vaultpass.container \
  --extra-vars @/rhis/vars/vault/env.yml \
  --limit scenario_satellite \
  /rhis/rhis-builder-satellite/main.yml
```

**Expected Outcome:** 
- IdM playbook should complete (chrony template now present)
- Satellite playbook should progress past chrony and system update checks

---

### Option B: Re-run Full RHIS Installer

To restart from scratch with all fixes applied:

```bash
# Backup any important logs/configs:
cp -r /var/log/rhis /var/log/rhis.backup.2026-03-24

# Stop the container (it will be recreated with patches on next run):
podman rm -f rhis-provisioner

# Clean up old VM state if desired:
# sudo virsh destroy satellite-618 aap-26 idm
# sudo virsh undefine satellite-618 aap-26 idm

# Re-run the installer with auto-config enabled:
cd /home/sgallego/GIT/RHIS
./rhis_install.sh

# At the menu, select:
# Option 2: Container Deployment (Podman)
# Then proceed with "Config-as-Code" or full workflow
```

**Pros:** Starts fresh, all patches applied automatically  
**Cons:** Must recreate VMs and infrastructure

---

### Option C: Manual Phase Re-execution

To re-run individual phases with full diagnostic output:

```bash
# Connect to provisioner container:
podman exec -it -e ANSIBLE_DEBUG=1 rhis-provisioner /bin/bash

# Verify templates exist:
ls -la /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2
ls -la /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2

# Run IdM with verbose output:
cd /rhis
ansible-playbook -vvv \
  --inventory /rhis/vars/external_inventory/hosts \
  --vault-password-file /rhis/vars/vault/.vaultpass.container \
  --extra-vars @/rhis/vars/vault/env.yml \
  --limit scenario_idm \
  /rhis/rhis-builder-idm/main.yml 2>&1 | tee /tmp/idm-playbook.log

# Check IdM web UI readiness (post-playbook gate):
curl -v -k https://10.168.128.3/ipa/ui/
```

---

### Option D: Isolated Component Testing

Test each component independently:

```bash
# Test IdM SSH connectivity and basic services:
ssh root@10.168.128.3 "ipactl status && systemctl status ipa httpd"

# Test Satellite SSH connectivity:
ssh root@10.168.128.1 "systemctl status httpd"

# Test AAP SSH connectivity (if not yet configured):
ssh root@10.168.128.2 "whoami"
```

---

## Hotfix Details

### Templates Injected

**Content of chrony.j2 (both IdM and Satellite roles):**
```jinja2
# RHIS fallback chrony template (auto-generated when upstream template is missing)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
pool 2.rhel.pool.ntp.org iburst
```

This provides:
- NTP pool configuration (RHEL default)
- Drift file for clock tracking
- Makestep for initial large steps
- RTC sync for hardware clock

---

## Verification

After remediation, verify all phases pass:

```bash
# Check IdM
curl -k https://10.168.128.3/ipa/ui/ && echo "✓ IdM UI reached"

# Check Satellite
curl -k https://10.168.128.1/ && echo "✓ Satellite web reached"

# Check AAP (after setup completes)
curl -k https://10.168.128.2/ && echo "✓ AAP web reached"

# Check final health summary in logs
tail -40 /var/log/rhis/latest.log | grep -A 20 "RHIS Health Summary"
```

---

## Logs and Diagnostics

**Main RHIS Log:**
```
/var/log/rhis/rhis_install_20260324-084739_pid1986366.log
```

**Container Logs:**
```bash
podman logs rhis-provisioner
```

**VM Kickstart Logs (SSH into each VM):**
```bash
ssh root@10.168.128.3 cat /root/ks-post.log    # IdM
ssh root@10.168.128.1 cat /root/ks-post.log    # Satellite
ssh root@10.168.128.2 cat /root/aap-setup-ready.log  # AAP
```

---

## Known Issues & Workarounds

### Issue: "Check on system update" timeout
- **Symptom:** 960 retries over multiple minutes
- **Cause:** dnf package lock contention
- **Workaround:** Reduce `--async_timeout` setting in playbook or wait for system to settle

### Issue: AAP SSH callback timeout
- **Symptom:** "Cannot reach aap-26 via SSH" during deferred callback
- **Cause:** SSH keys not yet on aap-26 during provisioning
- **Workaround:** AAP will still be provisioned; manually setup SSH after VM completes first boot

### Issue: Missing templates in container
- **Symptom:** Ansible template not found errors
- **Cause:** Provisioner container image outdated
- **Workaround:** Use `podman cp` to inject templates (completed), or rebuild container image

---

## Next Steps

1. **Immediate:** Try Option A (re-run config-as-code phases)
2. **If successful:** Document what worked and close this issue
3. **If not:** Proceed to Option B (full RHIS re-run) or Option C (manual diagnostics)
4. **Long-term:** Consider rebuilding provisioner container image with latest rhis-builder roles

---

**Last Updated:** 2026-03-24 15:45 UTC
**Status:** RECOVERY IN PROGRESS
