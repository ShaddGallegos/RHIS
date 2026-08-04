#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: wait_for_ssh.sh [-t TIMEOUT] [-i INTERVAL] [-p PORT] [-u USER] [-k KEYFILE] [-q] host

Wait for SSH to become reachable on a host. Returns 0 when reachable, 3 on timeout.

Options:
  -t TIMEOUT   Total seconds to wait (default: 300)
  -i INTERVAL  Poll interval in seconds (default: 5)
  -p PORT      TCP port to check (default: 22)
  -u USER      SSH username for auth probe (default: root)
  -k KEYFILE   SSH identity file to pass to ssh for probing
  -q           Quiet; suppress progress output
  -h           Show this help and exit
USAGE
}

timeout=300
interval=5
port=22
user=root
keyfile=""
quiet=0

OPTIND=1
while getopts ":t:i:p:u:k:qh" opt; do
    case "$opt" in
        t) timeout=$OPTARG ;;
        i) interval=$OPTARG ;;
        p) port=$OPTARG ;;
        u) user=$OPTARG ;;
        k) keyfile=$OPTARG ;;
        q) quiet=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
    usage
    exit 2
fi

host="$1"

start_ts=$(date +%s)
end_ts=$((start_ts + timeout))

# Interactive spinner only when stdout is a TTY and not quiet.
interactive=0
spinner_chars="|/-\\"
spinner_pos=0
if [ "$quiet" -eq 0 ] && [ -t 1 ]; then
    interactive=1
    printf "Waiting up to %ss for SSH on %s:%s... " "$timeout" "$host" "$port"
else
    [ $quiet -eq 0 ] && printf "Waiting up to %ss for SSH on %s:%s...\n" "$timeout" "$host" "$port"
fi

while :; do
    now=$(date +%s)
    if [ "$now" -ge "$end_ts" ]; then
        # Move to a clean line if we were showing an interactive spinner
        if [ "$interactive" -eq 1 ]; then
            printf '\n'
        fi
        [ $quiet -eq 0 ] && printf "[TIMEOUT] %s:%s not reachable after %ss\n" "$host" "$port" "$timeout" >&2
        exit 3
    fi

    # Fast TCP probe using bash /dev/tcp if available
    if timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1; then
        ssh_opts=( -o BatchMode=yes -o PreferredAuthentications=none -o PasswordAuthentication=no -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o LogLevel=ERROR )
        if [ -n "$keyfile" ]; then ssh_opts+=( -i "$keyfile" ); fi
        err=$(ssh "${ssh_opts[@]}" "${user}@${host}" true 2>&1 || true)
        rc=$?
        if [ $rc -eq 0 ]; then
            if [ "$interactive" -eq 1 ]; then printf '\n'; fi
            [ $quiet -eq 0 ] && printf "SSH accepted on %s:%s\n" "$host" "$port"
            exit 0
        fi
        if printf '%s' "$err" | grep -Eqi 'permission denied|authentication failed|denied \(publickey\)|too many authentication failures|no supported authentication methods'; then
            if [ "$interactive" -eq 1 ]; then printf '\n'; fi
            [ $quiet -eq 0 ] && printf "SSH reachable (auth failure) on %s:%s\n" "$host" "$port"
            exit 0
        fi
    else
        # Fallback to nc if available for TCP probe
        if command -v nc >/dev/null 2>&1; then
            if nc -z -w3 "$host" "$port" >/dev/null 2>&1; then
                ssh_opts=( -o BatchMode=yes -o PreferredAuthentications=none -o PasswordAuthentication=no -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o LogLevel=ERROR )
                if [ -n "$keyfile" ]; then ssh_opts+=( -i "$keyfile" ); fi
                err=$(ssh "${ssh_opts[@]}" "${user}@${host}" true 2>&1 || true)
                rc=$?
                if [ $rc -eq 0 ]; then
                    if [ "$interactive" -eq 1 ]; then printf '\n'; fi
                    [ $quiet -eq 0 ] && printf "SSH accepted on %s:%s\n" "$host" "$port"
                    exit 0
                fi
                if printf '%s' "$err" | grep -Eqi 'permission denied|authentication failed|denied \(publickey\)|too many authentication failures|no supported authentication methods'; then
                    if [ "$interactive" -eq 1 ]; then printf '\n'; fi
                    [ $quiet -eq 0 ] && printf "SSH reachable (auth failure) on %s:%s\n" "$host" "$port"
                    exit 0
                fi
            fi
        fi
    fi

    if [ "$interactive" -eq 1 ]; then
        now=$(date +%s)
        elapsed=$((now - start_ts))
        printf '\rWaiting for SSH on %s:%s... %s (%ss/%ss) ' "$host" "$port" "${spinner_chars:spinner_pos:1}" "$elapsed" "$timeout"
        spinner_pos=$(( (spinner_pos + 1) % ${#spinner_chars} ))
    else
        [ $quiet -eq 0 ] && printf '.'
    fi
    sleep "$interval"
done

