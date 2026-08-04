#!/usr/bin/env bash
set -euo pipefail

# Mirror GitHub repos matching 'rhis' (case-insensitive) for a user to a Gitea
# instance and create the repos there under a target user (admin by default).
#
# Usage examples:
#   GITEA_ADMIN_PASSWORD=... bash scripts/mirror_github_repos_to_gitea.sh --dry-run
#   bash scripts/mirror_github_repos_to_gitea.sh --github-user parmstro --gitea-url http://gittea.prod.spg

GITHUB_USER_DEFAULT="parmstro"
GITHUB_API_DEFAULT="https://api.github.com"
GITEA_URL_DEFAULT="http://gittea.prod.spg"
GITEA_ADMIN_USER_DEFAULT="admin"
GITEA_TARGET_USER_DEFAULT="admin"

GITHUB_USER="${GITHUB_USER:-$GITHUB_USER_DEFAULT}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_API="${GITHUB_API:-$GITHUB_API_DEFAULT}"
GITEA_URL="${GITEA_URL:-$GITEA_URL_DEFAULT}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-$GITEA_ADMIN_USER_DEFAULT}"
GITEA_TARGET_USER="${GITEA_TARGET_USER:-$GITEA_TARGET_USER_DEFAULT}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-${ADMIN_PASS:-}}"

DRY_RUN=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --github-user USER        GitHub username to mirror (default: ${GITHUB_USER_DEFAULT})
  --github-token TOKEN      GitHub personal token (optional, increases API rate limit)
  --gitea-url URL           Base URL to Gitea (default: ${GITEA_URL_DEFAULT})
  --gitea-admin-user USER   Gitea admin user for API/auth (default: ${GITEA_ADMIN_USER_DEFAULT})
  --gitea-admin-pass PASS   Gitea admin password (or set env GITEA_ADMIN_PASSWORD / ADMIN_PASS)
  --target-user USER        Gitea target user to create repos under (default: ${GITEA_TARGET_USER_DEFAULT})
  --dry-run                 Print actions without performing clone/create/push
  -h, --help                Show this help

Examples:
  GITEA_ADMIN_PASSWORD=... bash $0 --dry-run
  bash $0 --github-user parmstro --gitea-url http://gittea.prod.spg
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --github-user) GITHUB_USER="$2"; shift 2 ;;
        --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
        --gitea-url) GITEA_URL="$2"; shift 2 ;;
        --gitea-admin-user) GITEA_ADMIN_USER="$2"; shift 2 ;;
        --gitea-admin-pass) GITEA_ADMIN_PASSWORD="$2"; shift 2 ;;
        --target-user) GITEA_TARGET_USER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

GITEA_URL="${GITEA_URL%/}"

if [ -z "${GITEA_ADMIN_PASSWORD:-}" ]; then
    if [ -t 0 ]; then
        printf "Gitea admin password for user %s: " "${GITEA_ADMIN_USER}"
        # shellcheck disable=SC2034
        read -r -s GITEA_ADMIN_PASSWORD
        echo
    else
        echo "GITEA_ADMIN_PASSWORD or ADMIN_PASS must be set in the environment when non-interactive" >&2
        exit 1
    fi
fi

auth_b64=$(printf '%s:%s' "${GITEA_ADMIN_USER}" "${GITEA_ADMIN_PASSWORD}" | base64 -w0 2>/dev/null || base64)
auth_header="Authorization: Basic ${auth_b64}"

tmpdir=$(mktemp -d)
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

echo "Listing public repos for GitHub user: ${GITHUB_USER} (filter: case-insensitive 'rhis')"

page=1
repos_found=()
while :; do
    gh_url="${GITHUB_API%/}/users/${GITHUB_USER}/repos?per_page=100&page=${page}"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        gh_json=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$gh_url")
    else
        gh_json=$(curl -s "$gh_url")
    fi
    # Count results
    count=$(printf '%s' "$gh_json" | jq 'length')
    if [ "$count" -eq 0 ]; then
        break
    fi
    # Extract names matching rhis (case-insensitive)
    mapfile -t matches < <(printf '%s' "$gh_json" | jq -r '.[] | select(.name | test("rhis"; "i")) | .name')
    for r in "${matches[@]}"; do
        repos_found+=("$r")
    done
    if [ "$count" -lt 100 ]; then
        break
    fi
    page=$((page + 1))
done

if [ ${#repos_found[@]} -eq 0 ]; then
    echo "No repositories matching 'rhis' found for user ${GITHUB_USER}."
    exit 0
fi

echo "Found ${#repos_found[@]} repo(s): ${repos_found[*]}"

for repo in "${repos_found[@]}"; do
    printf "\n--- Processing: %s ---\n" "${repo}"
    clone_url="https://github.com/${GITHUB_USER}/${repo}.git"
    gitea_repo_url="${GITEA_URL}/${GITEA_TARGET_USER}/${repo}.git"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN: would clone ${clone_url}"
        echo "DRY-RUN: would create ${GITEA_TARGET_USER}/${repo} on ${GITEA_URL} if missing"
        echo "DRY-RUN: would push mirror into ${gitea_repo_url}"
        continue
    fi

    echo "Cloning --mirror from ${clone_url}"
    git clone --mirror "${clone_url}" "${tmpdir}/${repo}.git" || { echo "Failed to clone ${repo}, skipping"; continue; }

    # Check if repo exists on Gitea
    status=$(curl -s -o /dev/null -w "%{http_code}" -H "${auth_header}" "${GITEA_URL}/api/v1/repos/${GITEA_TARGET_USER}/${repo}")
    if [ "${status}" = "200" ]; then
        echo "Repository ${GITEA_TARGET_USER}/${repo} already exists on ${GITEA_URL}."
    else
        echo "Creating ${GITEA_TARGET_USER}/${repo} on ${GITEA_URL} (HTTP status: ${status})"
        payload=$(jq -n --arg name "$repo" --argjson priv false '{name: $name, private: $priv}')
        create_status=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -H "${auth_header}" -X POST "${GITEA_URL}/api/v1/admin/users/${GITEA_TARGET_USER}/repos" -d "$payload")
        if [ "${create_status}" != "201" ] && [ "${create_status}" != "200" ]; then
            echo "Failed to create repository ${repo} on ${GITEA_URL} (status ${create_status}). Skipping."
            continue
        fi
        echo "Created repository ${GITEA_TARGET_USER}/${repo}"
    fi

    echo "Pushing mirror to ${gitea_repo_url}"
    # Use HTTP Basic auth via http.extraHeader to avoid embedding password in URL
    git --git-dir="${tmpdir}/${repo}.git" -c http.extraHeader="${auth_header}" push --mirror "${gitea_repo_url}" || { echo "Push failed for ${repo}"; continue; }
    echo "Mirrored ${repo} -> ${GITEA_TARGET_USER}/${repo}"
done

echo "All done. Temporary workdir: ${tmpdir} (removed on exit)"
