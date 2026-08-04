#!/usr/bin/env bash
set -euo pipefail
# Install or expose repo-local tools (symlink into /usr/local/bin or add to PATH)
# Usage: scripts/install-tools.sh [--symlink] [--path] [--all] [--dest DIR] [--sudo] [--force] [--dry-run]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
DO_SYMLINK=0
DO_PATH=0
DO_ALL=0
DEST_DIR="/usr/local/bin"
FORCE=0
SUDO=0

usage(){
  cat <<'USAGE'
Usage: install-tools.sh [--symlink] [--path] [--all] [--dest DIR] [--sudo] [--force] [--dry-run]

Options:
  --symlink        Create symlinks for executables under REPO/tools into DEST (default /usr/local/bin)
  --path           Add REPO/tools to your shell rc (bash/zsh) PATH
  --all            Perform both --symlink and --path
  --dest DIR       Target directory for symlinks (default: /usr/local/bin)
  --sudo           Use sudo when creating symlinks if DEST is not writable
  --force          Overwrite existing files at DEST when creating symlinks
  --dry-run        Print actions without making changes
  -h|--help        Show this help

Example: $0 --all --dest /usr/local/bin --sudo
USAGE
}

if [ $# -eq 0 ]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --symlink) DO_SYMLINK=1; shift ;;
    --path) DO_PATH=1; shift ;;
    --all) DO_ALL=1; shift ;;
    --dest) DEST_DIR="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --sudo) SUDO=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$DO_ALL" -eq 1 ]; then
  DO_SYMLINK=1; DO_PATH=1
fi

log(){ printf '%s\n' "$*"; }

if [ "$DO_SYMLINK" -eq 1 ]; then
  if [ ! -d "$REPO_ROOT/tools" ]; then
    log "No tools directory found at $REPO_ROOT/tools; nothing to symlink.";
  else
    log "Preparing to create symlinks from $REPO_ROOT/tools (including one-level subdirs) to $DEST_DIR"
    # Find executables at depth 1 or 2 (tools/ and tools/*)
    while IFS= read -r f; do
      [ -e "$f" ] || continue
      if [ -f "$f" ] && [ -x "$f" ]; then
        base="$(basename "$f")"
        target="$DEST_DIR/$base"
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$f" ]; then
          log "skip: $target already points to $f"
          continue
        fi
        if [ -e "$target" ] && [ ! -L "$target" ] && [ "$FORCE" -ne 1 ]; then
          log "skip: $target exists and is not a symlink (use --force to overwrite)"
          continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
          log "DRY-RUN: would create symlink: $target -> $f"
          continue
        fi
        # Create parent dir if needed
        if [ ! -d "$DEST_DIR" ]; then
          if [ "$SUDO" -eq 1 ]; then
            sudo mkdir -p "$DEST_DIR"
          else
            mkdir -p "$DEST_DIR"
          fi
        fi
        if [ -w "$DEST_DIR" ]; then
          ln -sfn "$f" "$target"
          log "created: $target -> $f"
        else
          if [ "$SUDO" -eq 1 ]; then
            sudo ln -sfn "$f" "$target"
            log "created (sudo): $target -> $f"
          else
            log "need sudo or write access to create $target; rerun with --sudo or choose a different --dest"
          fi
        fi
      else
        log "skip: $f (not an executable file)"
      fi
    done < <(find "$REPO_ROOT/tools" -mindepth 1 -maxdepth 2 -type f -executable 2>/dev/null)
  fi
fi

if [ "$DO_PATH" -eq 1 ]; then
  export_line="export PATH=\"$REPO_ROOT/tools:\$PATH\" # MRHIS tools"
  added=0
  # Detect user shells and target rc files
  SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
  RC_CANDIDATES=()
  case "$SHELL_NAME" in
    zsh) RC_CANDIDATES+=("$HOME/.zshrc") ;;
    bash) RC_CANDIDATES+=("$HOME/.bashrc" "$HOME/.profile") ;;
    *) RC_CANDIDATES+=("$HOME/.profile" "$HOME/.bashrc") ;;
  esac

  for rc in "${RC_CANDIDATES[@]}"; do
    if [ -f "$rc" ] && grep -q "$REPO_ROOT/tools" "$rc" 2>/dev/null; then
      log "skip: $rc already contains $REPO_ROOT/tools"
      added=1
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY-RUN: would append PATH export to $rc (or create file if missing)"
      added=1
      continue
    fi
    # create file if missing
    if [ ! -f "$rc" ]; then
      touch "$rc" || true
    fi
    # backup
    cp -a "$rc" "$rc.bak.mrhis.$(date +%s)" || true
    printf "\n# MRHIS tools: add repository-local tools to PATH\n%s\n" "$export_line" >> "$rc"
    log "appended PATH export to $rc (backup: ${rc}.bak.mrhis.*)"
    added=1
  done
  if [ "$added" -eq 1 ]; then
    log "Done. Please open a new shell or run: source <rc-file> to pick up changes."
  fi
fi

log "install-tools.sh finished"
