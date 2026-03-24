# IMMEDIATE ACTION: Re-run Config-as-Code Phases

## Status
✅ **Templates Fixed** - chrony.j2 injected into rhis-provisioner container  
✅ **Container Ready** - Provisioner still running, patches applied  
⏳ **Next Step** - Re-run IdM and Satellite playbooks

---

## Quick Recovery (5 minutes)

### Step 1: Verify Templates Are In Place
```bash
podman exec rhis-provisioner test -f /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2 && echo "✓ IdM template OK"
podman exec rhis-provisioner test -f /rhis/rhis-builder-satellite/roles/satellite_pre/templates/chrony.j2 && echo "✓ Satellite template OK"
```

### Step 2: Re-run IdM Phase
```bash
podman exec -it -e ANSIBLE_CONFIG=/rhis/vars/vault/rhis-ansible.cfg rhis-provisioner \
  ansible-playbook \
    --inventory /rhis/vars/external_inventory/hosts \
    --vault-password-file /rhis/vars/vault/.vaultpass.container \
    --extra-vars @/rhis/vars/vault/env.yml \
    --limit scenario_idm \
    /rhis/rhis-builder-idm/main.yml
```

**Expected:** Playbook runs to completion. Look for:
- ✓ `27 ok, 6 changed, 26 skipped`  
- ✓ No "chrony.j2" not found errors
- ✓ Final block: "Apply role idm_primary" should succeed

### Step 3: Re-run Satellite Phase  
```bash
podman exec -it -e ANSIBLE_CONFIG=/rhis/vars/vault/rhis-ansible.cfg rhis-provisioner \
  ansible-playbook \
    --inventory /rhis/vars/external_inventory/hosts \
    --vault-password-file /rhis/vars/vault/.vaultpass.container \
    --extra-vars '{"satellite_disconnected":false,"register_to_satellite":false,"satellite_pre_use_idm":false,"async_timeout":14400,"async_delay":15}' \
    --limit scenario_satellite \
    /rhis/rhis-builder-satellite/main.yml
```

**Expected:** Similar to IdM - should progress past chrony and system update checks

### Step 4: Verify Success
```bash
# IdM Web UI
curl -k https://10.168.128.3/ipa/ui/ && echo "✓ IdM is UP"

# Satellite Web UI  
curl -k https://10.168.128.1/ && echo "✓ Satellite is UP"

# Check install logs for health summary
tail -50 /var/log/rhis/latest.log | grep -A 15 "RHIS Health Summary"
```

---

## If Something Still Fails

**Check the error message carefully:**
- Contains "chrony.j2"? → Template didn't copy correctly; retry Step 1-2
- Contains "Could not find the requested service"? → Service check issue; see RECOVERY_PROCEDURES.md Option C
- "Assertion failed" or "unreachable"? → Network/SSH issue; verify VM connectivity first

**For detailed diagnostics:**
```bash
# Check container template files directly
podman exec rhis-provisioner ls -la /rhis/rhis-builder-idm/roles/idm_pre/templates/
podman exec rhis-provisioner cat /rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2

# Check VM SSH access
ssh -o ConnectTimeout=3 root@10.168.128.3 "hostname && uptime"
ssh -o ConnectTimeout=3 root@10.168.128.1 "hostname && uptime"

# Look at full playbook logs
podman exec rhis-provisioner tail -200 /rhis/ansible.log 2>/dev/null | tail -100
```

---

## AAP Note

AAP callback failed due to SSH mesh timeout during provisioning. This is **expected** and non-blocking:
- ✓ VM aap-26 is running
- ✓ SSH access works post-boot
- ⚠ Manual AAP configuration will be needed

See RECOVERY_PROCEDURES.md for AAP recovery options.

---

## Questions?

1. **Container won't accept `podman exec` commands?** → Container may have crashed. Restart: `podman rm -f rhis-provisioner && cd /home/sgallego/GIT/RHIS && ./rhis_install.sh`
2. **Which VM failed?** → Check `/var/log/rhis/latest.log` for playbook output
3. **Do I need to restart the VMs?** → No, they're fine. Just re-run the playbooks.

---

**Created:** 2026-03-24  
**Type:** Emergency Recovery Guide
