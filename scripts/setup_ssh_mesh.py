#!/usr/bin/env python3
import os
import re
import sys
import time
import tempfile
import threading
import subprocess
import socket
import getpass
import logging
from pathlib import Path
import paramiko
import yaml

# Suppress noisy internal paramiko background thread tracebacks from flooding console
logging.getLogger("paramiko").setLevel(logging.WARNING)

# -----------------------------------------------------------------------------
# TERMINAL VISUAL UTILITIES
# -----------------------------------------------------------------------------

class BackgroundSpinner:
    """A clean terminal spinner that runs in a background thread."""
    def __init__(self, message="Working"):
        self.message = message
        self._running = False
        self._thread = None

    def _spin(self):
        frames = ["-", "\\", "|", "/"]
        idx = 0
        while self._running:
            sys.stdout.write(f"\r {frames[idx]} {self.message}...")
            sys.stdout.flush()
            idx = (idx + 1) % len(frames)
            time.sleep(0.08)

    def start(self, message=None):
        if message:
            self.message = message
        self._running = True
        self._thread = threading.Thread(target=self._spin, daemon=True)
        self._thread.start()

    def stop(self, clear=True):
        self._running = False
        if self._thread:
            self._thread.join()
        if clear:
            sys.stdout.write("\r\033[K")
            sys.stdout.flush()


spinner = BackgroundSpinner()

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT CONFIGURATION & CHECKS
# -----------------------------------------------------------------------------
print("\n=== TASK 1: Environment Checks & Security Context Validation ===")
print("Validating that the script is run by an unprivileged user and asserting paths.")

INSTALL_USER = os.getlogin()
if INSTALL_USER == "root":
    print("ERROR: This script must not be run as root.", file=sys.stderr)
    sys.exit(1)

print(f"   [OK] Running safely as user: {INSTALL_USER}")

HOME = Path.home()
CONF_DIR = HOME / ".ansible" / "conf"
ENV_FILE = CONF_DIR / "env.yml"

VAULT_PASS_FILE = CONF_DIR / ".vault_pass.txt"
if not VAULT_PASS_FILE.exists():
    VAULT_PASS_FILE = CONF_DIR / ".vaultpass.txt"

if not CONF_DIR.exists() or not VAULT_PASS_FILE.exists():
    print(f"ERROR: Configuration directory or vault password missing in {CONF_DIR}", file=sys.stderr)
    sys.exit(1)

if not ENV_FILE.exists():
    ENV_FILE.touch(mode=0o600)

print("\n=== TASK 2: Ansible Vault Decryption & Credential Assurance ===")
print("Checking for target credentials in memory; prompting and updating vault dynamically if empty.")

vault_data = {}
if ENV_FILE.stat().st_size > 0:
    spinner.start("Decrypting Ansible Vault secrets file")
    with tempfile.NamedTemporaryFile(mode="w+", delete=True) as tmp_file:
        try:
            subprocess.run([
                "ansible-vault", "decrypt",
                "--vault-password-file", str(VAULT_PASS_FILE),
                str(ENV_FILE), "--output", tmp_file.name
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            tmp_file.seek(0)
            loaded_yaml = yaml.safe_load(tmp_file.read())
            if isinstance(loaded_yaml, dict):
                vault_data = loaded_yaml
        except subprocess.CalledProcessError:
            spinner.stop()
            print("ERROR: Ansible Vault decryption failed.", file=sys.stderr)
            sys.exit(1)
    spinner.stop()

vault_updated = False

if "admin_password" not in vault_data or not str(vault_data["admin_password"]).strip():
    print(f"WARNING: 'admin_password' missing inside local vault configuration.")
    new_admin_pass = getpass.getpass("Enter the remote cluster 'admin' password: ").strip()
    if not new_admin_pass:
        print("ERROR: Password cannot be blank.", file=sys.stderr)
        sys.exit(1)
    vault_data["admin_password"] = new_admin_pass
    vault_updated = True

if "root_password" not in vault_data or not str(vault_data["root_password"]).strip():
    print(f"WARNING: 'root_password' missing inside local vault configuration.")
    new_root_pass = getpass.getpass("Enter the remote cluster 'root' password: ").strip()
    if not new_root_pass:
        print("ERROR: Password cannot be blank.", file=sys.stderr)
        sys.exit(1)
    vault_data["root_password"] = new_root_pass
    vault_updated = True

if vault_updated:
    spinner.start("Re-encrypting new profile data into env.yml")
    try:
        with tempfile.NamedTemporaryFile(mode="w+", delete=False) as tmp_write:
            yaml.safe_dump(vault_data, tmp_write, default_flow_style=False)
            tmp_write_path = tmp_write.name

        subprocess.run([
            "ansible-vault", "encrypt",
            "--vault-password-file", str(VAULT_PASS_FILE),
            tmp_write_path, "--output", str(ENV_FILE)
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        if os.path.exists(tmp_write_path):
            os.remove(tmp_write_path)
        spinner.stop()
        print("Vault variables successfully updated and locked on disk.")
    except Exception as e:
        spinner.stop()
        print(f"ERROR: Failed to save updated vault configuration: {e}", file=sys.stderr)
        sys.exit(1)

ADMIN_PASS = vault_data["admin_password"]
ROOT_PASS = vault_data["root_password"]

print("\n=== TASK 3: Host parsing & Filtering ===")
print("Scraping /etc/hosts to isolate remote infrastructure nodes by FQDN while filtering duplicates and installer hosts.")

TARGET_KEYWORDS = ["satellite", "aap", "idm", "gittea", "openshift"]


def parse_remote_nodes_from_hosts(hosts_path="/etc/hosts"):
    """Prefer the managed MRHIS internal hosts block; fall back to keyword scan."""
    seen = set()
    ordered_nodes = []
    in_mrhis_block = False
    parsed_from_managed_block = False

    def add_node(node):
        node = (node or "").strip().lower()
        if not node:
            return
        if node in seen:
            return
        seen.add(node)
        ordered_nodes.append(node)

    with open(hosts_path, "r", encoding="utf-8") as hosts_file:
        for raw_line in hosts_file:
            line = raw_line.strip()
            if not line:
                continue

            if line.startswith("# BEGIN MRHIS INTERNAL HOSTS"):
                in_mrhis_block = True
                parsed_from_managed_block = True
                continue
            if line.startswith("# END MRHIS INTERNAL HOSTS"):
                in_mrhis_block = False
                continue

            if in_mrhis_block:
                if line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) < 2:
                    continue
                canonical_fqdn = parts[1]
                if "installer" in canonical_fqdn:
                    continue
                add_node(canonical_fqdn)

    if parsed_from_managed_block and ordered_nodes:
        return ordered_nodes

    # Backward-compatible fallback when managed block is absent or empty.
    seen.clear()
    ordered_nodes = []
    with open(hosts_path, "r", encoding="utf-8") as hosts_file:
        for raw_line in hosts_file:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) <= 1:
                continue

            canonical_fqdn = parts[1]
            if re.match(r"localhost|127\.0\.0\.1|::1", canonical_fqdn, re.IGNORECASE):
                continue
            if "installer" in canonical_fqdn.lower():
                continue

            line_hostnames_text = " ".join(parts[1:]).lower()
            if any(kw in line_hostnames_text for kw in TARGET_KEYWORDS):
                add_node(canonical_fqdn)

    return ordered_nodes

try:
    remote_nodes = parse_remote_nodes_from_hosts("/etc/hosts")
except IOError as e:
    print(f"ERROR: Cannot read /etc/hosts: {e}", file=sys.stderr)
    sys.exit(1)

if not remote_nodes:
    print("ERROR: No matching remote cluster target nodes found inside /etc/hosts.", file=sys.stderr)
    sys.exit(1)

print(f"Remote nodes detected: {', '.join(remote_nodes)}")

# -----------------------------------------------------------------------------
# 2. CORE SSH ENGINE HELPERS
# -----------------------------------------------------------------------------

def run_remote_cmd(host, user, password, cmd):
    """Executes a standard command over SSH with a micro-sleep to prevent flood throttling."""
    time.sleep(0.1)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(host, username=user, password=password, timeout=5)
        stdin, stdout, stderr = ssh.exec_command(cmd)
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        ssh.close()
        return out, err, True
    except Exception as e:
        return "", str(e), False


def run_remote_sudo_cmd(host, user, password, cmd):
    """Passes commands into an automated root bash shell via admin privilege escalation."""
    time.sleep(0.1)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(host, username=user, password=password, timeout=5)
        stdin, stdout, stderr = ssh.exec_command("sudo -S bash")
        
        stdin.write(password + "\n")
        stdin.write(cmd + "\n")
        stdin.channel.shutdown_write()
        
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        ssh.close()
        
        if "password for" in err:
            err = "\n".join([l for l in err.splitlines() if "password for" not in l]).strip()
        return out, err, True
    except Exception as e:
        return "", str(e), False

# -----------------------------------------------------------------------------
# 3. KEY GENERATION LOGIC (Installer Local Node)
# -----------------------------------------------------------------------------
print("\n=== TASK 4: Local SSH Key Initialization ===")
print(f"Securing local cryptographic keys for '{INSTALL_USER}' and 'root' on the deployment machine.")

local_ssh_dir = HOME / ".ssh"
local_ssh_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
local_key = local_ssh_dir / "id_rsa"
if not local_key.exists():
    spinner.start(f"Generating identity key for {INSTALL_USER}")
    subprocess.run(["ssh-keygen", "-t", "rsa", "-N", "", "-f", str(local_key), "-q"], check=True)
    spinner.stop()

with open(f"{local_key}.pub", "r") as f:
    INSTALLER_PUB_KEY = f.read().strip()

root_key_path = "/root/.ssh/id_rsa"
root_key_exists = subprocess.run(["sudo", "test", "-f", root_key_path]).returncode == 0

if not root_key_exists:
    spinner.start("Generating identity key for root via sudo escalation")
    subprocess.run(["sudo", "mkdir", "-p", "/root/.ssh"], check=True)
    subprocess.run(["sudo", "chmod", "700", "/root/.ssh"], check=True)
    subprocess.run(["sudo", "ssh-keygen", "-t", "rsa", "-N", "", "-f", root_key_path, "-q"], check=True)
    spinner.stop()

INSTALLER_ROOT_PUB_KEY = subprocess.check_output(["sudo", "cat", "/root/.ssh/id_rsa.pub"]).decode().strip()
print("   [OK] Local keys verified.")

# -----------------------------------------------------------------------------
# 4. REMOTE KEY GENERATION & KEY GATHERING
# -----------------------------------------------------------------------------
print("\n=== TASK 5: Remote Identity Discovery & Target Key Generation ===")
print("Connecting to all targeted remote nodes to generate missing admin/root SSH key pairs and collect public keys.")

admin_keys = {}
root_keys = {}

CMD_ADMIN_KEY_GEN = (
    "mkdir -p ~/.ssh && "
    "chmod 700 ~/.ssh && "
    "[ -f ~/.ssh/id_rsa ] || "
    "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q"
)

CMD_ROOT_KEY_GEN = (
    "mkdir -p /root/.ssh && "
    "chmod 700 /root/.ssh && "
    "[ -f /root/.ssh/id_rsa ] || "
    "ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -q"
)

for node in remote_nodes:
    spinner.start(f"Assuring keys and mapping identities on remote host: {node}")
    
    run_remote_cmd(node, "admin", ADMIN_PASS, CMD_ADMIN_KEY_GEN)
    pub_admin, _, _ = run_remote_cmd(node, "admin", ADMIN_PASS, "cat ~/.ssh/id_rsa.pub")
    admin_keys[node] = pub_admin
    
    run_remote_sudo_cmd(node, "admin", ADMIN_PASS, CMD_ROOT_KEY_GEN)
    pub_root, _, _ = run_remote_sudo_cmd(node, "admin", ADMIN_PASS, "cat /root/.ssh/id_rsa.pub")
    root_keys[node] = pub_root
    
    spinner.stop()
    print(f"   [OK] Synced and pulled keys from {node}")

# -----------------------------------------------------------------------------
# 5. IDEMPOTENT MATRIX KEY DISTRIBUTION
# -----------------------------------------------------------------------------
print("\n=== TASK 6: Mesh Matrix Mapping & Distribution ===")
print("Performing multi-directional key injections to establish authentic relationships:")
print(f"   1. Local {INSTALL_USER}@installer -> All Remote Admin Nodes")
print(f"   2. All Remote Admin Nodes -> Local {INSTALL_USER}@installer")
print("   3. Remote Admin to Remote Admin Complete Cross-Mesh")
print("   4. Remote Root to Remote Root Complete Cross-Mesh")

local_auth_keys = local_ssh_dir / "authorized_keys"
local_auth_keys.touch(mode=0o600, exist_ok=True)

CMD_INJECT_INSTALLER = (
    "mkdir -p ~/.ssh && "
    "chmod 700 ~/.ssh && "
    "touch ~/.ssh/authorized_keys && "
    "chmod 600 ~/.ssh/authorized_keys && "
    f"grep -qF '{INSTALLER_PUB_KEY}' ~/.ssh/authorized_keys || "
    f"echo '{INSTALLER_PUB_KEY}' >> ~/.ssh/authorized_keys"
)

for src_node in remote_nodes:
    spinner.start(f"Distributing and building auth mesh matrix for: {src_node}")
    
    run_remote_cmd(src_node, "admin", ADMIN_PASS, CMD_INJECT_INSTALLER)
    
    with open(local_auth_keys, "r+") as f:
        content = f.read()
        if admin_keys[src_node] and admin_keys[src_node] not in content:
            f.write(f"\n{admin_keys[src_node]}")

    for dest_node in remote_nodes:
        if admin_keys[src_node]:
            cmd_admin_mesh = (
                "mkdir -p ~/.ssh && "
                "touch ~/.ssh/authorized_keys && "
                f"grep -qF '{admin_keys[src_node]}' ~/.ssh/authorized_keys || "
                f"echo '{admin_keys[src_node]}' >> ~/.ssh/authorized_keys"
            )
            run_remote_cmd(dest_node, "admin", ADMIN_PASS, cmd_admin_mesh)
            
        if root_keys[src_node]:
            cmd_root_mesh = (
                "mkdir -p /root/.ssh && "
                "touch /root/.ssh/authorized_keys && "
                "chmod 600 /root/.ssh/authorized_keys && "
                f"grep -qF '{root_keys[src_node]}' /root/.ssh/authorized_keys || "
                f"echo '{root_keys[src_node]}' >> /root/.ssh/authorized_keys"
            )
            run_remote_sudo_cmd(dest_node, "admin", ADMIN_PASS, cmd_root_mesh)
            
    spinner.stop()
    print(f"   [OK] Matrix entries distributed for source: {src_node}")

# -----------------------------------------------------------------------------
# 6. VERIFICATION TESTING SUITE FUNCTION
# -----------------------------------------------------------------------------
def run_verification_suite(nodes_to_test):
    """Executes full diagnostic tests and returns a set of nodes that failed any test."""
    failed_nodes = set()
    
    print("\n" + "="*65)
    print("RUNNING DIAGNOSTIC VERIFICATION SUITE")
    print("="*65)

    print("\n[PART A] Running ICMP Network Ping Diagnostics...")
    for node in nodes_to_test:
        try:
            socket.gethostbyname(node)
            res = subprocess.run(["ping", "-c", "1", "-W", "2", node], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode == 0:
                print(f"   PING OK: installer -> {node}")
            else:
                print(f"   PING FAIL: installer -> {node}")
                failed_nodes.add(node)
        except socket.gaierror:
            print(f"   DNS RESOLVE FAIL: {node}")
            failed_nodes.add(node)

    print("\n[PART B] Testing Key-based Authentication: Local Installer -> Remote Admin Nodes...")
    for node in nodes_to_test:
        ssh_test = paramiko.SSHClient()
        ssh_test.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            ssh_test.connect(node, username="admin", key_filename=str(local_key), timeout=3, allow_agent=False)
            print(f"   PASS: {INSTALL_USER}@installer -> admin@{node}")
            ssh_test.close()
        except Exception as e:
            print(f"   FAIL: {INSTALL_USER}@installer -> admin@{node} (Error: {e})")
            failed_nodes.add(node)

    print("\n[PART C & D] Running Complete Cross-Node Mesh Diagnostics...")
    TEST_BACK_TEMPLATE = "ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o ConnectTimeout=2 {}@{} 'echo OK'"
    TEST_CROSS_TEMPLATE = "ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o ConnectTimeout=2 {}@{} 'echo OK'"

    for src_node in nodes_to_test:
        print(f"\nEvaluating outbound links from source: {src_node}")
        
        test_back_cmd = TEST_BACK_TEMPLATE.format(INSTALL_USER, socket.gethostname())
        _, _, ok = run_remote_cmd(src_node, "admin", ADMIN_PASS, test_back_cmd)
        if ok:
            print(f"   PASS: admin@{src_node} -> {INSTALL_USER}@installer")
        else:
            print(f"   FAIL: admin@{src_node} -> {INSTALL_USER}@installer")
            failed_nodes.add(src_node)

        for dest_node in remote_nodes:
            test_admin_cmd = TEST_CROSS_TEMPLATE.format("admin", dest_node)
            _, _, ok_admin = run_remote_cmd(src_node, "admin", ADMIN_PASS, test_admin_cmd)
            if ok_admin:
                print(f"   PASS: admin@{src_node} -> admin@{dest_node}")
            else:
                print(f"   FAIL: admin@{src_node} -> admin@{dest_node}")
                failed_nodes.add(src_node)
                failed_nodes.add(dest_node)

            test_root_cmd = TEST_CROSS_TEMPLATE.format("root", dest_node)
            _, _, ok_root = run_remote_cmd(src_node, "root", ROOT_PASS, test_root_cmd)
            if ok_root:
                print(f"   PASS: root@{src_node} -> root@{dest_node}")
            else:
                print(f"   FAIL: root@{src_node} -> root@{dest_node}")
                failed_nodes.add(src_node)
                failed_nodes.add(dest_node)
                
    return failed_nodes

# Run initial test pass
initial_failed_nodes = run_verification_suite(remote_nodes)

# -----------------------------------------------------------------------------
# 7. AUTOMATED REMEDIATION PHASE (Bypasses root lockout via admin escalation)
# -----------------------------------------------------------------------------
if initial_failed_nodes:
    print("\n=== TASK 7: Automated Remediation for Failed Nodes ===")
    print("Detected connection errors. Executing targeted structural SSH fixes via admin sudo channels.")
    
    # Corrects config parameters, standardizes root's password via chpasswd, and restarts sshd
    CMD_REMEDIATE_SSH = (
        f"echo 'root:{ROOT_PASS}' | chpasswd && "
        "for opt in 'PermitRootLogin yes' 'PubkeyAuthentication yes'; do "
        "  key=$(echo $opt | cut -d' ' -f1); "
        "  if grep -q \"^#*$key\" /etc/ssh/sshd_config; then "
        "    sed -i \"s/^#*$key.*/$opt/\" /etc/ssh/sshd_config; "
        "  else "
        "    echo \"$opt\" >> /etc/ssh/sshd_config; "
        "  fi; "
        "done && "
        "for opt in 'StrictHostKeyChecking no' 'ForwardX11 yes'; do "
        "  key=$(echo $opt | cut -d' ' -f1); "
        "  if grep -q \"^#*$key\" /etc/ssh/ssh_config; then "
        "    sed -i \"s/^#*$key.*/$opt/\" /etc/ssh/ssh_config; "
        "  else "
        "    echo \"$opt\" >> /etc/ssh/ssh_config; "
        "  fi; "
        "done && "
        "systemctl restart sshd"
    )

    remediate_targets = sorted(list(initial_failed_nodes))
    for node in remediate_targets:
        spinner.start(f"Applying configurations and syncing system parameters on {node}")
        out, err, success = run_remote_sudo_cmd(node, "admin", ADMIN_PASS, CMD_REMEDIATE_SSH)
        spinner.stop()
        if success:
            print(f"   [OK] Remediation executed on {node}")
        else:
            print(f"   [ERROR] Failed to apply changes to {node}: {err}", file=sys.stderr)

    print("\nRe-evaluating remediated systems...")
    final_failed_nodes = run_verification_suite(remediate_targets)
    
    if final_failed_nodes:
        print(f"\nWARNING: The following nodes still fail after configuration fixes: {', '.join(final_failed_nodes)}")
    else:
        print("\nAll initially failing systems verified as PASS following remediation changes.")
else:
    print("\nInitial run successful. No remediation required.")

print("\nMesh configuration run finalized.")
