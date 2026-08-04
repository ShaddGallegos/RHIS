#!/usr/bin/env bash
# Lint variable casing in a bash script.
# - Global/config variables SHOULD be UPPERCASE
# - Function-local variables (declared with `local`) SHOULD be lowercase
# This script reports violations but does not modify files.

set -euo pipefail

file="${1:-MRHIS.sh}"
if [ ! -f "$file" ]; then
  echo "Usage: $0 path/to/script.sh" >&2
  exit 2
fi

awk '
BEGIN { err=0; inFunc=0; }
# skip comments and blank lines
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }

# Detect function start: name() {  or function name {
/^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*{/ { inFunc=1; delete localVars; next }
/^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*{/ { inFunc=1; delete localVars; next }

# Detect function end (simple heuristic)
/^[[:space:]]*}/ { inFunc=0; delete localVars; next }

# local declarations: record declared local var names for current function
/^[[:space:]]*local[[:space:]]+/ {
  line=$0
  sub(/^[[:space:]]*local[[:space:]]+/, "", line)
  n=split(line, arr, /[[:space:]]+/)
  for (i=1;i<=n;i++) {
    name=arr[i]
    sub(/=.*/ , "", name)
    sub(/[,;]$/, "", name)
    if (name ~ /^[A-Z]/) {
      print FILENAME ":" NR ": LOCAL_UPPERCASE: " name
      err=1
    }
    if (name != "") localVars[name]=1
  }
  next
}

# assignments (lowercase-leading names)
{
  # detect simple assignments at start of line: var=... or var = ...
  if ($0 ~ /^[[:space:]]*[a-z][a-z0-9_]*[[:space:]]*=/) {
    line=$0
    sub(/^[[:space:]]*/, "", line)
    sub(/=.*/, "", line)
    name=line
    sub(/[[:space:]]*$/, "", name)
    if (inFunc) {
      if (!(name in localVars)) {
        print FILENAME ":" NR ": GLOBAL_LOWERCASE: " name
        err=1
      }
    } else {
      print FILENAME ":" NR ": GLOBAL_LOWERCASE: " name
      err=1
    }
  }
}

END { if (err) exit 1 }
' "$file"

echo "Variable casing lint completed for $file"
