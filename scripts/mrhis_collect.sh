#!/bin/bash
set -e

echo "HOST: $(hostname -f 2>/dev/null || hostname)"
date
hostnamectl 2>/dev/null || true
cat /etc/os-release 2>/dev/null || true
cat /etc/redhat-release 2>/dev/null || true
uname -a 2>/dev/null || true

echo "--- user checks ---"
id admin 2>/dev/null || echo "admin:NOT_PRESENT"
getent passwd admin || true

echo "--- SELinux ---"
getenforce 2>/dev/null || echo getenforce:unknown
if command -v sestatus >/dev/null 2>&1; then
  sestatus || true
fi

echo "--- Firewall ---"
systemctl is-active firewalld 2>/dev/null || echo firewalld:unknown
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --state 2>/dev/null || true
fi

echo "--- Cockpit ---"
if rpm -q cockpit >/dev/null 2>&1; then rpm -q cockpit || true; else echo cockpit:not-installed; fi
systemctl is-enabled cockpit.socket 2>/dev/null || echo cockpit.socket:unknown
systemctl is-active cockpit.socket 2>/dev/null || echo cockpit.socket:unknown

echo "--- SSHD config snippets ---"
grep -E '^[[:space:]]*PasswordAuthentication|^[[:space:]]*PermitRootLogin|^[[:space:]]*AuthorizedKeysFile' /etc/ssh/sshd_config 2>/dev/null || true

echo "--- Packages summary ---"
echo "package_count: $(rpm -qa 2>/dev/null | wc -l 2>/dev/null || echo unknown)"
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null | sort | grep -E 'cockpit|openssh-server|openssh-clients|python3|ansible|sssd|ipa|httpd|sssd-ad|sssd-ipa|ipa-server' | sed -n '1,200p' || true

echo "--- ansible/python ---"
ansible --version 2>/dev/null | head -n1 || echo ansible:not-installed
python3 --version 2>/dev/null || echo python3:not-installed
which sshd 2>/dev/null || echo sshd:not-found

echo "--- Enabled services (first 200) ---"
systemctl list-unit-files --type=service --state=enabled | sed -n '1,200p' || true

echo "--- Disk/Memory/Time ---"
df -h / 2>/dev/null || true
free -m 2>/dev/null || true
timedatectl status 2>/dev/null || true

echo "--- authorized_keys admin ---"
grep -n "rhis-installer-host" ~/.ssh/authorized_keys 2>/dev/null || echo NOTFOUND
