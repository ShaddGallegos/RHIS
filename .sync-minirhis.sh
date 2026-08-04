#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration ---
SOURCE_DIR="${SOURCE_DIR:-$SCRIPT_DIR}"
DEST_DIR="${DEST_DIR:-}"
BRANCH="shadd"
REMOTE="shaddfork"
BASE_REMOTE="origin"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Secrets and Large Files
SECRET_KEYWORDS="password|api_key|secret|private_key|token|auth_token|xoxb-|xoxp-|hooks\.slack\.com"
MAX_FILE_SIZE_MB=45

resolve_dest_dir() {
    local preferred_dir="$HOME/GIT/rhis-builder-kvm-lz"
    local legacy_dir="$HOME/GIT/minirhis-builder-kvm-lz"
    
    if [ -n "$DEST_DIR" ]; then echo "$DEST_DIR"; return 0; fi
    if [ -d "$preferred_dir/.git" ]; then echo "$preferred_dir"; return 0; fi
    if [ -d "$legacy_dir/.git" ]; then echo "$legacy_dir"; return 0; fi
    echo "$legacy_dir"
}

get_github_owner_repo_from_remote() {
    local remote_name="$1"
    local url path
    url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
    [ -n "$url" ] || return 1
    case "$url" in
        git@github.com:*) path="${url#git@github.com:}" ;;
        https://github.com/*) path="${url#https://github.com/}" ;;
        http://github.com/*) path="${url#http://github.com/}" ;;
        *) return 1 ;;
    esac
    path="${path%.git}"
    printf '%s\n' "$path"
}

# --- Ansible Vault helpers ---
vault_password_file() {
    # Return a usable vault password file path on stdout, or fail (non-zero) if none found
    local candidates=("$HOME/.ansible/conf/.vaultpass.txt" "$HOME/.ansible/conf/.vaultpass" "${ANSIBLE_VAULT_PASSWORD_FILE:-}")
    local p
    for p in "${candidates[@]}"; do
        [ -n "$p" ] || continue
        if [ -f "$p" ] && [ -r "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

ensure_vault_password_file() {
    if vault_password_file >/dev/null 2>&1; then
        return 0
    fi
    echo "Warning: No Ansible vault password file found at ~/.ansible/conf/.vaultpass.txt" >&2
    return 1
}

verify_env_yml_decrypt() {
    local vfile ansible_vault_cmd
    if ! vfile="$(vault_password_file)"; then
        echo "Skipping vault decryption check: no vault password file found" >&2
        return 0
    fi
    if command -v ansible-vault >/dev/null 2>&1; then
        ansible_vault_cmd="$(command -v ansible-vault)"
    elif [ -x "$HOME/.ansible/venv-ansible-core/bin/ansible-vault" ]; then
        ansible_vault_cmd="$HOME/.ansible/venv-ansible-core/bin/ansible-vault"
    else
        echo "ansible-vault not found; skipping decryption verification" >&2
        return 0
    fi

    if [ ! -f "$HOME/.ansible/conf/env.yml" ]; then
        echo "No env.yml to check at $HOME/.ansible/conf/env.yml" >&2
        return 0
    fi

    if "$ansible_vault_cmd" view "$HOME/.ansible/conf/env.yml" --vault-password-file "$vfile" >/dev/null 2>&1; then
        return 0
    else
        echo "[WARNING] Failed to decrypt $HOME/.ansible/conf/env.yml using $vfile" >&2
        return 1
    fi
}

DEST_DIR="$(resolve_dest_dir)"

# --- Flag Detection ---
INFO_ONLY=false
if [[ "${1:-}" == "--info" ]]; then
    INFO_ONLY=true
fi

# --- 1. Info Mode Logic ---
if [ "$INFO_ONLY" = true ]; then
    echo "Retrieving Pull Request information..."
    cd "$DEST_DIR" || exit 1
    
    BASE_REPO="$(get_github_owner_repo_from_remote "$BASE_REMOTE")" || { echo "Error: Could not determine upstream repo"; exit 1; }
    HEAD_REPO="$(get_github_owner_repo_from_remote "$REMOTE")" || { echo "Error: Could not determine fork repo"; exit 1; }
    HEAD_OWNER="${HEAD_REPO%%/*}"
    HEAD_REF="${HEAD_OWNER}:${BRANCH}"

    PR_DATA=$(gh pr list --repo "$BASE_REPO" --head "$HEAD_REF" --json number,title,state,url,updatedAt --jq '.[0]' 2>/dev/null || echo "")

    if [ -n "$PR_DATA" ] && [ "$PR_DATA" != "null" ]; then
        echo "--------------------------------------------------"
        echo "Current Pull Request Details:"
        echo "  Title:  $(echo "$PR_DATA" | jq -r .title)"
        echo "  Number: #$(echo "$PR_DATA" | jq -r .number)"
        echo "  State:  $(echo "$PR_DATA" | jq -r .state)"
        echo "  URL:    $(echo "$PR_DATA" | jq -r .url)"
        echo "  Last Updated: $(echo "$PR_DATA" | jq -r .updatedAt)"
        echo "--------------------------------------------------"
    else
        echo "No active Pull Request found for branch '$BRANCH' in $BASE_REPO."
    fi

    REPO_URL=$(git remote get-url "$REMOTE" 2>/dev/null || echo "Unknown")
    echo ""
    echo "Clone Info:"
    echo "  git clone -b $BRANCH $REPO_URL"
    echo "--------------------------------------------------"
    exit 0
fi

# --- 2. Scanning and Exclusion Logic ---
# Verify Ansible vault decryption (non-fatal) before scanning.
# This surfaces missing/invalid vault password early but does not abort sync.
if ! ensure_vault_password_file >/dev/null 2>&1; then
    echo "Note: No Ansible vault password file found at ~/.ansible/conf/.vaultpass.txt; skipping decryption check." >&2
else
    verify_env_yml_decrypt || echo "[WARNING] Failed to decrypt $HOME/.ansible/conf/env.yml" >&2
fi

echo "Scanning $SOURCE_DIR for secrets and large files..."

RSYNC_EXCLUDES=("--exclude=.*" "--exclude=training_data/")

mapfile -t SENSITIVE_FILES < <(grep -rEil "$SECRET_KEYWORDS" "$SOURCE_DIR" --exclude-dir=".git" --exclude="$(basename "$0")" || true)
mapfile -t LARGE_FILES < <(find "$SOURCE_DIR" -type f -size +"${MAX_FILE_SIZE_MB}M" -not -path '*/.*' || true)

EXCLUDE_LIST=("${SENSITIVE_FILES[@]}" "${LARGE_FILES[@]}")

mkdir -p "$DEST_DIR"
touch "$DEST_DIR/.gitignore"

if ! grep -qx "RHIS/training_data/" "$DEST_DIR/.gitignore" 2>/dev/null; then
    echo "RHIS/training_data/" >> "$DEST_DIR/.gitignore"
fi

if [ ${#EXCLUDE_LIST[@]} -gt 0 ]; then
    echo "Excluding ${#EXCLUDE_LIST[@]} detected files."
    for file in "${EXCLUDE_LIST[@]}"; do
        rel_path="${file#$SOURCE_DIR/}"
        if [ -n "$rel_path" ] && [[ "$rel_path" != "." ]] && [[ "$rel_path" != ".gitignore" ]]; then
            if ! grep -qx "$rel_path" "$DEST_DIR/.gitignore"; then
                echo "$rel_path" >> "$DEST_DIR/.gitignore"
            fi
            RSYNC_EXCLUDES+=("--exclude=$rel_path")
        fi
    done
fi

# --- 3. Sync ---
echo "Syncing files to $DEST_DIR..."
rsync -av --delete "${RSYNC_EXCLUDES[@]}" "$SOURCE_DIR/" "$DEST_DIR/"

# --- 4. Git Operations ---
cd "$DEST_DIR" || exit 1
git checkout "$BRANCH" || git checkout -b "$BRANCH"

echo "Staging changes..."
git add -f .gitignore
git add -A

git ls-files -c -i --exclude-standard | xargs -r git rm --cached

if [ -z "$(git status --short)" ]; then
    echo "Success: No changes to sync."
else
    echo "Committing..."
    git commit -m "Sync: Cleaned update ($TIMESTAMP)"

    echo "Pushing to $REMOTE..."
    if ! git push "$REMOTE" "$BRANCH"; then
        echo "Error: Push rejected. If GitHub detects secrets, run 'git reset --hard $REMOTE/$BRANCH' to clear local history."
        exit 1
    fi
fi

# --- 5. Pull Request Management ---
echo "Managing Pull Request via gh CLI..."

BASE_REPO="$(get_github_owner_repo_from_remote "$BASE_REMOTE")" || { echo "Error: Could not determine upstream repo"; exit 1; }
HEAD_REPO="$(get_github_owner_repo_from_remote "$REMOTE")" || { echo "Error: Could not determine fork repo"; exit 1; }
HEAD_OWNER="${HEAD_REPO%%/*}"
HEAD_REF="${HEAD_OWNER}:${BRANCH}"

PR_NUMBER=$(gh pr list --repo "$BASE_REPO" --head "$HEAD_REF" --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$PR_NUMBER" ]; then
    echo "Updating existing Pull Request #$PR_NUMBER..."
    gh pr edit "$PR_NUMBER" \
        --repo "$BASE_REPO" \
        --title "Sync RHIS to rhis-builder ($TIMESTAMP)" \
        --body "Updating builder with latest changes. Last sync: $TIMESTAMP. Training data and secrets excluded."
else
    echo "Creating new Pull Request..."
    gh pr create \
        --repo "$BASE_REPO" \
        --title "Sync RHIS to rhis-builder ($TIMESTAMP)" \
        --body "Automated sync of RHIS source. Large files and training data excluded for security. Generated on: $TIMESTAMP" \
        --base main \
        --head "$HEAD_REF"
fi

echo "Workflow complete!"

# --- 6. Final Summary and Clone Info ---
REPO_URL=$(git remote get-url "$REMOTE" 2>/dev/null || echo "Unknown")

echo "--------------------------------------------------"
echo "Push Details:"
echo "  Repository: $REPO_URL"
echo "  Branch:     $BRANCH"
echo ""
echo "To clone this specific work elsewhere, use:"
echo "  git clone -b $BRANCH $REPO_URL"
echo "--------------------------------------------------"
