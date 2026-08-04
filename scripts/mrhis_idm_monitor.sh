#!/bin/bash

# Monitor script for MRHIS IdM VM: tails qemu serial log and polls for guest IP/SSH
# Writes events to /tmp/mrhis_idm_watch.log

rm -f /tmp/mrhis_idm_watch.log
echo MONITOR_START:$(date) > /tmp/mrhis_idm_watch.log

tail -n +1 -F /var/log/libvirt/qemu/idm.log >> /tmp/mrhis_idm_watch.log 2>&1 &
tailpid=$!

while true; do
  ip=$(sudo virsh domifaddr idm 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n1 | cut -d/ -f1)
  echo "$(date) DOMIFADDR:$ip" >> /tmp/mrhis_idm_watch.log
  if [ -n "$ip" ]; then
    # Use centralized wait helper (non-blocking short check)
    if bash "$(dirname "$0")/wait_for_ssh.sh" -t 5 -i 1 -q "$ip" >/dev/null 2>&1; then
      echo "$(date) SSH_OPEN:$ip" >> /tmp/mrhis_idm_watch.log
      kill "$tailpid" >/dev/null 2>&1 || true
      exit 0
    fi
  fi
  sleep 10
done
