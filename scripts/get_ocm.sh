#!/usr/bin/env bash
set -euo pipefail
# Small helper to obtain the Red Hat `ocm` CLI.
# Usage: tools/get_ocm.sh [--force] [--url URL] [--dest DIR]

TARGET_DIR="${1:-tools/ocm}"
FORCE=0
URL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --url) URL_OVERRIDE="$2"; shift 2 ;;
    --dest) TARGET_DIR="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--force] [--url URL] [--dest DIR]"; exit 0 ;;
    *) shift ;;
  esac
done

mkdir -p "$TARGET_DIR"
if [[ -x "$TARGET_DIR/ocm" && $FORCE -ne 1 ]]; then
  echo "ocm already installed at $TARGET_DIR/ocm (use --force to reinstall)"
  exit 0
fi

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$ARCH" in
  x86_64|amd64) MACHINE="linux_amd64";;
  aarch64|arm64) MACHINE="linux_arm64";;
  *) MACHINE="${OS}_${ARCH}";;
esac

CANDIDATES=()
if [[ -n "$URL_OVERRIDE" ]]; then
  CANDIDATES+=("$URL_OVERRIDE")
fi

# Try a variety of likely mirrors and naming conventions (zip, tar.gz, raw)
CANDIDATES+=(
  # Red Hat content gateway (various name patterns)
  "https://developers.redhat.com/content-gateway/rest/browse/pub/cgw/ocm/latest/ocm_${MACHINE}.zip"
  "https://developers.redhat.com/content-gateway/rest/browse/pub/cgw/ocm/latest/ocm-${MACHINE}.zip"
  "https://developers.redhat.com/content-gateway/rest/browse/pub/cgw/ocm/latest/ocm_${MACHINE}.tar.gz"
  "https://developers.redhat.com/content-gateway/rest/browse/pub/cgw/ocm/latest/ocm-${MACHINE}.tar.gz"

  # GitHub releases (try common asset namings)
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm_${MACHINE}.zip"
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm-${MACHINE}.zip"
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm_${MACHINE}.tar.gz"
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm-${MACHINE}.tar.gz"
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm_${MACHINE}"
  "https://github.com/openshift-online/ocm-cli/releases/latest/download/ocm-${MACHINE}"

  "https://github.com/openshift-online/ocm/releases/latest/download/ocm_${MACHINE}.zip"
  "https://github.com/openshift-online/ocm/releases/latest/download/ocm-${MACHINE}.zip"
  "https://github.com/openshift-online/ocm/releases/latest/download/ocm_${MACHINE}.tar.gz"
  "https://github.com/openshift-online/ocm/releases/latest/download/ocm-${MACHINE}.tar.gz"

  # OpenShift mirror
  "https://mirror.openshift.com/pub/openshift-v4/clients/ocm/latest/ocm-${MACHINE}.tar.gz"
  "https://mirror.openshift.com/pub/openshift-v4/clients/ocm/latest/ocm_${MACHINE}.tar.gz"
  "https://mirror.openshift.com/pub/openshift-v4/clients/ocm/latest/ocm-${MACHINE}.zip"
)

TMPZIP="$(mktemp --tmpdir ocm_XXXXXX)"
cleanup() { rm -f "$TMPZIP"; }
trap cleanup EXIT

downloaded=0
for url in "${CANDIDATES[@]}"; do
  echo "Trying $url"
  if curl -fL -o "$TMPZIP" "$url"; then
    downloaded=1
    echo "Downloaded $url"
    break
  else
    echo "Failed: $url"
  fi
done

if [[ $downloaded -eq 1 ]]; then
  extracted=0

  # Try unzip first
  if command -v unzip >/dev/null 2>&1; then
    if unzip -o "$TMPZIP" -d "$TARGET_DIR" >/dev/null 2>&1; then
      extracted=1
    fi
  fi

  # Try tar.gz
  if [[ $extracted -eq 0 ]]; then
    if tar -tzf "$TMPZIP" >/dev/null 2>&1; then
      tar -xzf "$TMPZIP" -C "$TARGET_DIR"
      extracted=1
    fi
  fi

  # If download is a raw executable, move it into place
  if [[ $extracted -eq 0 ]]; then
    if command -v file >/dev/null 2>&1 && file "$TMPZIP" | grep -qi 'executable'; then
      mv "$TMPZIP" "$TARGET_DIR/ocm"
      chmod +x "$TARGET_DIR/ocm"
      echo "ocm saved to $TARGET_DIR/ocm"
      exit 0
    fi
  fi

  # Look for an ocm binary in extracted contents
  ocmbin="$(find "$TARGET_DIR" -maxdepth 3 -type f -name 'ocm' -print -quit 2>/dev/null || true)"
  if [[ -n "$ocmbin" ]]; then
    chmod +x "$ocmbin" || true
    if [[ "$ocmbin" != "$TARGET_DIR/ocm" ]]; then
      mv "$ocmbin" "$TARGET_DIR/ocm" 2>/dev/null || cp -f "$ocmbin" "$TARGET_DIR/ocm"
    fi
    echo "ocm extracted to $TARGET_DIR/ocm"
    exit 0
  fi

  echo "No ocm binary found in archive; contents:"
  ls -la "$TARGET_DIR"
  echo "Will attempt go install fallback"
fi

# go install fallback
if command -v go >/dev/null 2>&1; then
  echo "Attempting 'go install github.com/openshift-online/ocm-cli/cmd/ocm@latest' (requires internet and Go >=1.17)"
  if go install github.com/openshift-online/ocm-cli/cmd/ocm@latest; then
    BINPATH=""
    if [[ -n "${GOBIN-}" && -f "${GOBIN}/ocm" ]]; then
      BINPATH="${GOBIN}/ocm"
    else
      GOPATH="${GOPATH:-$(go env GOPATH)}"
      if [[ -f "${GOPATH}/bin/ocm" ]]; then
        BINPATH="${GOPATH}/bin/ocm"
      fi
    fi
    if [[ -n "$BINPATH" ]]; then
      cp "$BINPATH" "$TARGET_DIR/ocm"
      chmod +x "$TARGET_DIR/ocm"
      echo "ocm installed to $TARGET_DIR/ocm (from $BINPATH)"
      exit 0
    else
      echo "go install succeeded but binary not found in expected locations"
    fi
  else
    echo "go install failed"
  fi
else
  echo "Go not found; cannot use go install fallback"
fi

echo "Failed to obtain ocm. Try passing a direct URL with --url or install manually."
exit 2
