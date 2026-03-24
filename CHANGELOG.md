# RHIS Change Log

This file tracks repository changes from this point forward.

## Entry format

- **Timestamp:** `YYYY-MM-DD HH:MM:SS TZ`
- **Area:** file(s) or component(s)
- **Summary:** short description of what changed
- **Reason:** why the change was made

---

## 2026-03-24 09:51:57 MDT

### 2026-03-24 09:51:57 MDT — Emergency recovery: Missing provisioner templates
- **Area:** `RECOVERY_PROCEDURES.md`, `QUICK_RECOVERY.md`, (provisioner container patches applied)
- **Summary:**
  - Diagnosed config-as-code phase failures: IdM/Satellite playbooks failed due to missing `chrony.j2` template in provisioner container.
  - Root cause: Provisioner container image (`quay.io/parmstro/rhis-provisioner-9-2.5:latest`) missing rhis-builder roles/templates.
  - Applied emergency hotfix: Injected fallback chrony.j2 templates into running provisioner container for both IdM and Satellite roles via `podman cp`.
  - Created comprehensive recovery procedures documentation with 4 recovery options (retry phases, full restart, manual execution, isolated testing).
  - Created quick reference recovery guide for immediate phase re-execution with step-by-step instructions.
  - Verified templates now in place; ready for playbook retry.
- **Reason:** Unblock failed deployment; provide clear recovery path for user without full infrastructure rebuild.

---

## 2026-03-23 17:39:04 MDT

### 2026-03-23 17:39:04 MDT — Script hardening and orchestration updates
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added container playbook hotfix preflight with verify/fail-fast controls.
  - Added/remediated IdM update task patching (`disable_gpg_check`, firmware exclusion) and Satellite pre-task non-fatal handling.
  - Added/normalized `SATELLITE_PRE_USE_IDM` handling and injected IdM integration vars for Satellite flows.
  - Added startup installer-host collection visibility check and unified required collection source list.
  - Added AAP callback wait progress monitor (heartbeat, % progress, remaining time, stage transitions, fail-fast stall detection).
  - Improved manual rerun guidance with container prerequisite checks and root-auth fallback template.
  - Enforced VM build creation order: `IdM -> Satellite -> AAP`.
- **Reason:** Improve reliability, visibility, and deterministic dependency order while reducing repeated operator troubleshooting.

### 2026-03-23 17:39:04 MDT — Documentation alignment
- **Area:** `README.md`, `CHECKLIST.md`, `Doc/README.md`, `host_vars/README.md`, `inventory/README.md`
- **Summary:**
  - Updated docs to match current runtime behavior and dependency order.
  - Documented AAP callback progress/fail-fast controls and collection preflight behavior.
  - Updated manual rerun notes to include container availability prerequisite.
- **Reason:** Keep operator documentation synchronized with script behavior.

## 2026-03-24 07:28:21 MDT

### 2026-03-24 07:28:21 MDT — SSH mesh fallback hardening
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added installer-user + passwordless `sudo` fallback for root SSH key bootstrap on RHIS nodes.
  - Added installer-user + `sudo` fallback when collecting root public keys.
  - Added installer-user + `sudo` fallback when distributing root trust keys.
- **Reason:** Prevent RHIS from aborting when direct `root@<node>` SSH is not ready yet but the installer/admin account is already available.

### 2026-03-24 07:35:18 MDT — Managed container patch persistence
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added top-level RHIS-managed container patch functions for Satellite and IdM playbook component fixes.
  - Container startup/reuse now automatically reapplies and verifies these patches on every deployment or restart of `rhis-provisioner`.
  - Current managed patches include the Satellite `chrony.j2` fallback, non-fatal foreman service check patch, and IdM update-task GPG/firmware guard patch.
- **Reason:** Ensure all container component fixes are maintained by the script itself and are consistently re-applied whenever a new provisioner container is deployed through RHIS.

### 2026-03-24 07:51:02 MDT — Per-run installer logging under /var/log/rhis
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added run-log configuration and startup log initialization for each script invocation.
  - Script now ensures `/var/log/rhis` exists and writes a timestamped per-run logfile.
  - Added output mirroring (`tee`) so each RHIS run is captured while still printing live to console.
  - Added/updated `latest.log` symlink in `/var/log/rhis` for quick access to most recent run.
- **Reason:** Provide durable, per-run operational logs for troubleshooting and auditability of each `rhis_install.sh` execution.

### 2026-03-24 07:54:03 MDT — Automatic run-log retention/pruning
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added `RHIS_RUN_LOG_KEEP_COUNT` (default `30`) to control retained per-run installer logs.
  - Added automatic pruning of old `/var/log/rhis/rhis_install_*.log` files after logging initialization.
  - Retention keeps newest logs by mtime and removes older files beyond the configured count.
- **Reason:** Prevent unbounded growth of `/var/log/rhis` while preserving recent execution history.

### 2026-03-24 08:09:44 MDT — Root SSH mesh defaults to best-effort
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added `RHIS_REQUIRE_ROOT_SSH_MESH` (default `0`) to control whether root mesh failures are fatal.
  - Updated `setup_rhis_ssh_mesh()` so installer-user mesh remains mandatory, while root-key bootstrap/collection/distribution failures warn-and-continue by default.
  - Added runtime summary output for `RHIS_REQUIRE_ROOT_SSH_MESH`.
- **Reason:** Avoid aborting full workflow when root key auth is not fully ready on one node (for example IdM), while still allowing strict enforcement when explicitly required.

### 2026-03-24 08:15:26 MDT — SSH key/known_hosts stability hardening for rebuilt RHIS nodes
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added dedicated persistent installer-host RHIS SSH key path (`RHIS_INSTALLER_SSH_KEY_DIR`) so RHIS mesh operations no longer depend on/churn default `~/.ssh/id_rsa`.
  - Updated SSH mesh bootstrap/copy-id paths to use the dedicated RHIS installer key.
  - Added known_hosts refresh for RHIS node IPs/hostnames (`RHIS_REFRESH_KNOWN_HOSTS`, default enabled) to remove stale host keys and reseed current keys after VM rebuild cycles.
  - Added runtime/help visibility for these new SSH stability controls.
- **Reason:** Prevent recurring host-key-change breakage and avoid impacting the static installer host’s primary SSH identity during repeated RHIS rebuild/install cycles.

### 2026-03-24 08:45:25 MDT — Config-only auth resilience preflight
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added config-as-code preflight call to refresh SSH trust baseline (`setup_rhis_ssh_mesh`) before phase playbooks (best-effort in this path).
  - Added config-as-code preflight root password normalization (`fix_vm_root_passwords`) before phase execution to improve root fallback reliability.
- **Reason:** Reduce repeated phase failures in container config-only/rerun workflows caused by SSH trust drift and root password mismatch between current vault values and guest state.

### 2026-03-24 09:17:24 MDT — /etc/hosts sync for RHIS external interfaces
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added `sync_rhis_external_hosts_entries()` to discover RHIS VM external/NAT interface IPs via `virsh domifaddr` and write them to a managed `/etc/hosts` block.
  - Added managed markers (`# BEGIN RHIS EXTERNAL HOSTS` / `# END RHIS EXTERNAL HOSTS`) so reruns replace/update entries cleanly instead of duplicating lines.
  - Wired sync calls into VM settle flow (`create_rhis_vms`) and config-as-code preflight (`run_rhis_config_as_code`) for recurring refresh.
- **Reason:** Ensure installer-host name resolution has up-to-date external interface mappings after VM reprovision/re-IP events.

### 2026-03-24 09:21:37 MDT — Fix missing IdM chrony.j2 template during idm_pre
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added managed container hotfix creation for `/rhis/rhis-builder-idm/roles/idm_pre/templates/chrony.j2` (fallback template) alongside existing Satellite chrony fallback.
  - Extended container hotfix verification checks to require both Satellite and IdM `chrony.j2` template files.
  - Added IdM chrony template preflight application in config-as-code hotfix path and before IdM phase/fallback playbook execution.
- **Reason:** Prevent `TASK [idm_pre : Configure time servers]` failures caused by missing `chrony.j2` in the IdM role templates.

### 2026-03-24 09:28:18 MDT — IdM Web UI readiness gate + diagnostics
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added IdM Web UI readiness controls (`RHIS_IDM_WEB_UI_TIMEOUT`, `RHIS_IDM_WEB_UI_INTERVAL`) and runtime config visibility.
  - Added automated post-IdM remediation/start checks for key services (`ipa`, `httpd`, `pki-tomcatd@pki-tomcat`) with `/ipa/ui` HTTPS readiness probing.
  - Added focused IdM Web UI diagnostics (service state, listener ports, local curl status) and integrated them into IdM failure handling.
  - IdM phase now marks status as failed when web UI readiness does not converge, instead of reporting a false-success state.
- **Reason:** Ensure the workflow only reports IdM success when the actual IdM web UI is reachable and healthy.

### 2026-03-24 09:43:07 MDT — Cross-component post-install healthcheck/remediation framework
- **Area:** `rhis_install.sh`
- **Summary:**
  - Added post-install healthcheck controls: `RHIS_ENABLE_POST_HEALTHCHECK`, `RHIS_HEALTHCHECK_AUTOFIX`, `RHIS_HEALTHCHECK_RERUN_COMPONENT`.
  - Added healthcheck stage after phase execution/retries to validate IdM, Satellite, and AAP service/web readiness.
  - Added automatic remediation attempts for failed checks and optional targeted component playbook reruns when remediation is insufficient.
  - Wired all healthcheck activity into existing log stream (`/var/log/rhis/...`) so failures, fixes, and final status are captured in the RHIS install log.
- **Reason:** Provide after-the-fact validation that role-delivered functionality is actually operational, with auto-fix and component-level rerun fallback when possible.
