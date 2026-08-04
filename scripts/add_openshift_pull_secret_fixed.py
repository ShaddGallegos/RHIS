#!/usr/bin/env python3
import os
import sys
import subprocess
import tempfile
import shutil
import time
import yaml

HOME = os.path.expanduser("~")
ANSIBLE_ENV_DIR = os.path.join(HOME, ".ansible", "conf")
ANSIBLE_ENV_FILE = os.path.join(ANSIBLE_ENV_DIR, "env.yml")
VAULT_PASS_TEXT = os.path.join(ANSIBLE_ENV_DIR, ".vaultpass.text")
VAULT_PASS_TXT = os.path.join(ANSIBLE_ENV_DIR, ".vaultpass.txt")

if os.path.exists(VAULT_PASS_TEXT) and os.path.getsize(VAULT_PASS_TEXT) > 0:
    VAULT_PASS_FILE = VAULT_PASS_TEXT
elif os.path.exists(VAULT_PASS_TXT) and os.path.getsize(VAULT_PASS_TXT) > 0:
    VAULT_PASS_FILE = VAULT_PASS_TXT
else:
    print("No vault password file found in {}".format(ANSIBLE_ENV_DIR), file=sys.stderr)
    sys.exit(2)

if not os.path.isfile(ANSIBLE_ENV_FILE):
    print("No env.yml found at {}".format(ANSIBLE_ENV_FILE), file=sys.stderr)
    sys.exit(3)

PULL_SECRET_JSON = '''{"auths":{"cloud.openshift.com":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfZGI1MGFkZmQ3Yjg2NDk4ZDg1NTY1NTQzMTI0ZjU4ZWY6MjFJU0FDSU1QUDlZTFlKSFhFMjQwN0hCOUk3UU1NNTBUT0ZVWVk2NFY5UzZRV1FWRTlXNEVHVDZHM1ZCQ1VTMQ==","email":"shadd@redhat.com"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfZGI1MGFkZmQ3Yjg2NDk4ZDg1NTY1NTQzMTI0ZjU4ZWY6MjFJU0FDSU1QUDlZTFlKSFhFMjQwN0hCOUk3UU1NNTBUT0ZVWVk2NFY5UzZRV1FWRTlXNEVHVDZHM1ZCQ1VTMQ==","email":"shadd@redhat.com"},"registry.connect.redhat.com":{"auth":"fHVoYy1wb29sLWZlNWQ2ZmI5LWFhZWYtNDRiMi1hZGM0LTIwMzI5ODFmMDJiNDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmtNV05qWmpWbU5EaG1aamswTVRZM09URXdNV0V5TmpreE9USmxaVFJrWXlKOS5mVm5xZlRtWWMxUFBibTBsSVpIbGdqckxyMGNGRTNKOUlROWxOU1otYWtPYlI4eEtFVkIxdl84TkE1SzRhU3ZoNzJRNV9hQlhEUmI3dzZrUldGNnhBeGR6Q0pvdmFsYmwtU2lKWTd0M29nUnBxc1o4WF82WmdGSmpfbmVTc2RFandqYm50RzVMbnhpNmRJcnJDOV8tVlVmLU1fd3hScDRNa2RMUXV5SmN2NzZPTXZsYWM1M0FzZ01aeW1lazEtY2c3X0pic1QydXZTanhQbGxoOEZpSVMzS1BMdk1PalZLWW14NTNDR19Md01rVmg3cHdfSFdFbEVDVnF1WjBlS3k2bFBuWkZhb2VJUjFyTmlkWkxBY2h0YXRYSERVcURldGRBYkw1Qm1KVVVHSDI3YUFNZWVLcU4tRmlic19HM2RVemlFNFhLTVlZNl8wNWwzaW5uUEwzOF9kTWtMSUc0LUExRWtfbmp4YlBsQXNHN1dOY1E0dEdZNldxWGw1Ukxnb2ZQVUszazc5cTkxaTFBb2JuLWcwZ3lId2dVSEpvT0pqV0Q5R0xZRmJ4c212VnNZcWhTbzM5Yzg0ekdXWFJEWUx1c0lGbUlmYTNHdzBrTlNYTE5pMkk1N2lzMzY5dmMxQWNnczAzR0REYVVJUVl2UnF6VW1rdk5GZnZnV1dhM09TU3NWREk2blhHQXpRcGdkR0hOemMxelQ4ZEJ5WnUwVy1JZGZDNjRQakRWRHJQcXc1RER6czVsMlBxSG9WcXJieHUyS1c5dTJkTWt2UWo0TEpBbGFwRUQ1dmNxc2lqMS1reXZndk5jcFdVemhDTGdUQ3VWc2FsMk1JQXB1UWhWaVBZbmN2S3UyYS1VZFZfTlRFLThwak1jeHJYczU1U054SG43WU1lSjBFTW9DUQ==","email":"shadd@redhat.com"},"registry.redhat.io":{"auth":"fHVoYy1wb29sLWZlNWQ2ZmI5LWFhZWYtNDRiMi1hZGM0LTIwMzI5ODFmMDJiNDpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmtNV05qWmpWbU5EaG1aamswTVRZM09URXdNV0V5TmpreE9USmxaVFJrWXlKOS5mVm5xZlRtWWMxUFBibTBsSVpIbGdqckxyMGNGRTNKOUlROWxOU1otYWtPYlI4eEtFVkIxdl84TkE1SzRhU3ZoNzJRNV9hQlhEUmI3dzZrUldGNnhBeGR6Q0pvdmFsYmwtU2lKWTd0M29nUnBxc1o4WF82WmdGSmpfbmVTc2RFandqYm50RzVMbnhpNmRJcnJDOV8tVlVmLU1fd3hScDRNa2RMUXV5SmN2NzZPTXZsYWM1M0FzZ01aeW1lazEtY2c3X0pic1QydXZTanhQbGxoOEZpSVMzS1BMdk1PalZLWW14NTNDR19Md01rVmg3cHdfSFdFbEVDVnF1WjBlS3k2bFBuWkZhb2VJUjFyTmlkWkxBY2h0YXRYSERVcURldGRBYkw1Qm1KVVVHSDI3YUFNZWVLcU4tRmlic19HM2RVemlFNFhLTVlZNl8wNWwzaW5uUEwzOF9kTWtMSUc0LUExRWtfbmp4YlBsQXNHN1dOY1E0dEdZNldxWGw1Ukxnb2ZQVUszazc5cTkxaTFBb2JuLWcwZ3lId2dVSEpvT0pqV0Q5R0xZRmJ4c212VnNZcWhTbzM5Yzg0ekdXWFJEWUx1c0lGbUlmYTNHdzBrTlNYTE5pMkk1N2lzMzY5dmMxQWNnczAzR0REYVVJUVl2UnF6VW1rdk5GZnZnV1dhM09TU3NWREk2blhHQXpRcGdkR0hOemMxelQ4ZEJ5WnUwVy1JZGZDNjRQakRWRHJQcXc1RER6czVsMlBxSG9WcXJieHUyS1c5dTJkTWt2UWo0TEpBbGFwRUQ1dmNxc2lqMS1reXZndk5jcFdVemhDTGdUQ3VWc2FsMk1JQXB1UWhWaVBZbmN2S3UyYS1VZFZfTlRFLThwak1jeHJYczU1U054SG43WU1lSjBFTW9DUQ==","email":"shadd@redhat.com"}}}'''

# Decrypt existing file to plaintext
proc = subprocess.run(["ansible-vault", "view", "--vault-password-file", VAULT_PASS_FILE, ANSIBLE_ENV_FILE], capture_output=True, text=True)
if proc.returncode != 0:
    print(proc.stderr, file=sys.stderr)
    sys.exit(1)
plaintext = proc.stdout

# Load YAML, update, and write to temp file
try:
    data = yaml.safe_load(plaintext) or {}
except Exception as e:
    print("Failed to parse decrypted env.yml: {}".format(e), file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    data = {}

# Set the pull secret
data['OPENSHIFT_PULL_SECRET'] = PULL_SECRET_JSON

# Backup original encrypted file
backup = ANSIBLE_ENV_FILE + ".bak." + str(int(time.time()))
shutil.copy2(ANSIBLE_ENV_FILE, backup)

# Dump YAML to temp file
fd, tmpname = tempfile.mkstemp(prefix="env_plain_", suffix=".yml")
os.close(fd)
with open(tmpname, 'w') as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)

# Re-encrypt
proc2 = subprocess.run(["ansible-vault", "encrypt", "--vault-password-file", VAULT_PASS_FILE, tmpname], capture_output=True, text=True)
if proc2.returncode != 0:
    print(proc2.stderr, file=sys.stderr)
    os.unlink(tmpname)
    sys.exit(1)

# Move encrypted temp back into place
shutil.move(tmpname, ANSIBLE_ENV_FILE)
os.chmod(ANSIBLE_ENV_FILE, 0o600)
print("OK: updated {} (backup: {})".format(ANSIBLE_ENV_FILE, backup))
