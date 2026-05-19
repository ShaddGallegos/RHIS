#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_ENV_DIR="${ANSIBLE_ENV_DIR:-$HOME/.ansible/conf}"
INVENTORY="${MINIRHIS_INVENTORY_FILE:-${PWD}/local/vars/external_inventory/hosts.yml}"
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASS_FILE:-${ANSIBLE_ENV_DIR}/.vaultpass.txt}"
LOG_DIR="${LOG_DIR:-/var/log/minirhis}"

mkdir -p "${LOG_DIR}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--inventory <path>] [--dest <dir>] [--vault-pass <file>] [--dry-run]
Collect per-node /var/tmp/minirhis-<host>-report.json files from inventory hosts
and aggregate them into a single JSON file in the logs directory.
EOF
    exit 0
}

DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --inventory) INVENTORY="$2"; shift 2 ;;
        --dest) LOG_DIR="$2"; shift 2 ;;
        --vault-pass) VAULT_PASS_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1"; usage ;;
    esac
done

command -v ansible-inventory >/dev/null 2>&1 || { echo "ansible-inventory not found in PATH" >&2; exit 2; }

echo "Using inventory: ${INVENTORY}"
echo "Destination logs: ${LOG_DIR}"

tmpfile=$(mktemp)
ansible-inventory -i "${INVENTORY}" --list > "${tmpfile}"
hosts_list=$(python3 - <<PY
import json
data=json.load(open('${tmpfile}'))
hosts=set()
def collect(o):
    if isinstance(o, dict):
        for k,v in o.items():
            if k=='hosts' and isinstance(v, list):
                hosts.update(v)
            else:
                collect(v)
    elif isinstance(o, list):
        for item in o:
            collect(item)
collect(data)
print('\n'.join(sorted(hosts)))
PY
)
rm -f "${tmpfile}"

if [[ -z "${hosts_list// /}" ]]; then
    echo "No hosts found in inventory ${INVENTORY}" >&2
    exit 1
fi

echo "Discovered hosts:"
echo "${hosts_list}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry-run mode, exiting before fetch."
    exit 0
fi

extra_args=()
if [[ -n "${VAULT_PASS_FILE:-}" && -f "${VAULT_PASS_FILE}" ]]; then
    extra_args+=("--vault-password-file" "${VAULT_PASS_FILE}")
fi

declare -a successes
declare -a failures

for host in ${hosts_list}; do
    echo "Fetching report from ${host} ..."
    ansible_cmd=(ansible -i "${INVENTORY}" "${host}" -m fetch -a "src=/var/tmp/minirhis-${host}-report.json dest=${LOG_DIR}/ flat=yes")
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        ansible_cmd+=("${extra_args[@]}")
    fi
    if "${ansible_cmd[@]}"; then
        successes+=("${host}")
    else
        failures+=("${host}")
    fi
done

export LOG_DIR
echo "Combining fetched reports into ${LOG_DIR}/minirhis-reports-aggregated.json"
python3 - <<PY
import json, glob, os
log_dir = os.environ.get('LOG_DIR')
files = glob.glob(os.path.join(log_dir, 'minirhis-*-report.json'))
out = []
for f in files:
    try:
        with open(f) as fh:
            out.append(json.load(fh))
    except Exception as e:
        print('skipping', f, e)
with open(os.path.join(log_dir, 'minirhis-reports-aggregated.json'), 'w') as of:
    json.dump(out, of, indent=2)
print('Wrote', os.path.join(log_dir, 'minirhis-reports-aggregated.json'))
PY

echo "Fetch summary: succeeded=${#successes[@]} failed=${#failures[@]}"
if [[ ${#failures[@]} -gt 0 ]]; then
    echo "Failed hosts: ${failures[*]}"
fi

echo "Done."
