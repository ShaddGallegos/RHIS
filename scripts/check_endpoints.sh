#!/bin/bash

# Configuration
TARGETS=("10.168.128.1" "10.168.128.2" "10.168.128.3")
PROTOCOLS=("http" "https")
TIMEOUT=5

# Remediation / SSH settings (override via env vars)
REMEDIATE=${REMEDIATE:-true}
# Try these SSH users (order matters). Can be overridden by exporting SSH_USERS as a space-separated string.
SSH_USERS=(${SSH_USERS:-admin root installer $USER})
SSH_USER=${SSH_USER:-root}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/minirhis-aap}
SSH_CERT=${SSH_CERT:-}
SSH_PASS=${SSH_PASS:-redhat}
LOG_DIR=${LOG_DIR:-./logs/endpoints}
mkdir -p "$LOG_DIR"

# Table Header
printf "%-15s | %-8s | %-10s | %-20s\n" "IP Address" "Protocol" "State" "HTTP/Error Code"
echo "--------------------------------------------------------------------------"

check_url() {
        proto=$1; ip=$2
        response=$(curl -s -k -L -I --connect-timeout $TIMEOUT -w "%{http_code}" "$proto://$ip" -o /dev/null)
        echo "$?:$response"
}

can_ssh() {
        timeout 3 bash -c "</dev/tcp/$1/22" >/dev/null 2>&1
}

ssh_remote_exec() {
                ip=$1
                logfile=$2
                user=${3:-$SSH_USER}

                # build ssh options
                ssh_opts=( -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 )
                [ -n "$SSH_CERT" ] && ssh_opts+=( -o CertificateFile="$SSH_CERT" )
                if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
                                ssh_opts+=( -i "$SSH_KEY" )
                fi

                if [ -f "$SSH_KEY" ] || [ -n "$SSH_CERT" ]; then
                                ssh "${ssh_opts[@]}" "$user@$ip" 'bash -s' >"$logfile" 2>&1 <<'REMOTE'
echo "REMOTE_CONNECTED: $(hostname) $(date)"
echo "=== listening ports ==="
ss -ltnp || true
echo "=== web service status ==="
systemctl status nginx --no-pager || true
systemctl status httpd --no-pager || true
echo "=== remediation: start web service if present and inactive ==="
if command -v nginx >/dev/null 2>&1; then
    if ! systemctl is-active --quiet nginx; then
        echo "Starting nginx..."
        systemctl start nginx || echo "nginx start failed"
        systemctl enable --now nginx || true
    fi
elif command -v httpd >/dev/null 2>&1; then
    if ! systemctl is-active --quiet httpd; then
        echo "Starting httpd..."
        systemctl start httpd || echo "httpd start failed"
        systemctl enable --now httpd || true
    fi
else
    echo "No nginx/httpd binary found"
fi
echo "=== firewall ==="
if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --add-service={http,https} --permanent || true
        firewall-cmd --reload || true
        firewall-cmd --list-all || true
    else
        echo "firewalld not running"
    fi
fi
echo "=== podman/container runtime ==="
command -v podman >/dev/null 2>&1 && podman ps --no-trunc || echo "podman not present"
echo "=== recent journal for nginx/httpd ==="
journalctl -u nginx -n 200 --no-pager 2>/dev/null || journalctl -u httpd -n 200 --no-pager 2>/dev/null || true
echo "REMOTE_DONE"
REMOTE
                                return $?
                fi

                if command -v sshpass >/dev/null 2>&1; then
                                sshpass -p "$SSH_PASS" ssh "${ssh_opts[@]}" "$user@$ip" 'bash -s' >"$logfile" 2>&1 <<'REMOTE'
echo "REMOTE_CONNECTED: $(hostname) $(date)"
echo "=== listening ports ==="
ss -ltnp || true
echo "=== web service status ==="
systemctl status nginx --no-pager || true
systemctl status httpd --no-pager || true
echo "=== remediation: start web service if present and inactive ==="
if command -v nginx >/dev/null 2>&1; then
        if ! systemctl is-active --quiet nginx; then
                echo "Starting nginx..."
                systemctl start nginx || echo "nginx start failed"
                systemctl enable --now nginx || true
        fi
elif command -v httpd >/dev/null 2>&1; then
        if ! systemctl is-active --quiet httpd; then
                echo "Starting httpd..."
                systemctl start httpd || echo "httpd start failed"
                systemctl enable --now httpd || true
        fi
else
        echo "No nginx/httpd binary found"
fi
echo "=== firewall ==="
if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
                firewall-cmd --add-service={http,https} --permanent || true
                firewall-cmd --reload || true
                firewall-cmd --list-all || true
        else
                echo "firewalld not running"
        fi
fi
echo "=== podman/container runtime ==="
command -v podman >/dev/null 2>&1 && podman ps --no-trunc || echo "podman not present"
echo "=== recent journal for nginx/httpd ==="
journalctl -u nginx -n 200 --no-pager 2>/dev/null || journalctl -u httpd -n 200 --no-pager 2>/dev/null || true
echo "REMOTE_DONE"
REMOTE
                                return $?
                fi

                echo "No SSH key/cert and sshpass not available" >"$logfile"
                return 2
}

for ip in "${TARGETS[@]}"; do
        for proto in "${PROTOCOLS[@]}"; do
                url="${proto}://${ip}"

                resp=$(check_url "$proto" "$ip")
                exit_status=${resp%%:*}
                response=${resp#*:}

                if [ "$exit_status" -eq 0 ]; then
                        if [[ "$response" =~ ^[23] ]]; then
                                state="UP"
                        else
                                state="ISSUE"
                        fi
                        result_code="$response"
                else
                        state="DOWN"
                        case $exit_status in
                                7)  result_code="Conn Refused (7)" ;;
                                28) result_code="Timeout (28)" ;;
                                6)  result_code="DNS/Host Fail (6)" ;;
                                35) result_code="SSL Handshake Fail (35)" ;;
                                60) result_code="Peer Cert/SSL (60)" ;;
                                *)  result_code="Exit Code $exit_status" ;;
                        esac
                fi

                printf "%-15s | %-8s | %-10s | %-20s\n" "$ip" "$proto" "$state" "$result_code"

                if [ "$state" = "DOWN" ] && [ "$REMEDIATE" = "true" ]; then
                        # Only attempt remediation when SSH is available
                        if can_ssh "$ip"; then
                                logf="$LOG_DIR/${ip}_$(date +%s).log"
                                echo "Attempting remote diagnostics/remediation on $ip (logs: $logf)..."
                                ssh_remote_exec "$ip" "$logf"
                                echo "Remote log saved: $logf"

                                # Re-check after remediation
                                resp_after=$(check_url "$proto" "$ip")
                                exit_status_after=${resp_after%%:*}
                                response_after=${resp_after#*:}
                                if [ "$exit_status_after" -eq 0 ] && [[ "$response_after" =~ ^[23] ]]; then
                                        printf "%-15s | %-8s | %-10s | %-20s\n" "$ip" "$proto" "UP" "$response_after"
                                else
                                        printf "%-15s | %-8s | %-10s | %-20s\n" "$ip" "$proto" "STILL_DOWN" "$response_after (code:$exit_status_after)"
                                fi
                        else
                                echo "SSH not available to $ip; skipping remote remediation."
                        fi
                fi

        done
        echo "--------------------------------------------------------------------------"
done
