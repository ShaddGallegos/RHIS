#!/usr/bin/env python3
"""
Scan the repository for likely hard-coded secrets (simple heuristic) and
write a report to artifacts_user/hardcoded_secrets_report.txt.

This is intentionally conservative: it reports suspicious matches for
manual review rather than making automatic replacements.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "artifacts_user" / "hardcoded_secrets_report.txt"

# Heuristics: regex patterns to look for
PATTERNS = {
    "password_word": re.compile(r"(?i)\b(password|passwd|pwd)\b"),
    "password_assignment": re.compile(r"(?i)\b(password|passwd|pwd)\b\s*[:=]\s*['\"]?[^'\"\s]{3,}"),
    "ssh_pass_var": re.compile(r"(?i)SSH_PASS\s*[=:]"),
    "global_admin_password": re.compile(r"global_admin_password"),
    "hardcoded_redhat_default": re.compile(r"\bredhat\b", re.I),
}

EXCLUDE_DIRS = {" .git", " .venv-ansible", "node_modules", "venv", "__pycache__"}

def is_binary(contents: bytes) -> bool:
    return b"\0" in contents

def scan() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    findings = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # prune common virtualenv and git dirs
        rel = os.path.relpath(dirpath, ROOT)
        if rel.startswith("."):
            # keep root .files
            pass
        skip = False
        for excl in (".venv-ansible", ".git", "venv", "node_modules", ".mypy_cache"):
            if excl in dirpath:
                skip = True
                break
        if skip:
            continue
        for fname in filenames:
            path = Path(dirpath) / fname
            # skip large files
            try:
                if path.stat().st_size > 2_000_000:
                    continue
            except Exception:
                continue
            try:
                data = path.read_bytes()
            except Exception:
                continue
            if is_binary(data):
                continue
            text = None
            try:
                text = data.decode("utf-8", errors="ignore")
            except Exception:
                continue
            for name, pat in PATTERNS.items():
                for m in pat.finditer(text):
                    # context snippet
                    start = max(0, m.start() - 60)
                    end = min(len(text), m.end() + 60)
                    snippet = text[start:end].replace("\n", " ")
                    findings.append((str(path.relative_to(ROOT)), name, snippet))

    with OUT.open("w", encoding="utf-8") as fh:
        if not findings:
            fh.write("No suspicious hard-coded secrets found.\n")
        else:
            fh.write("Suspicious hard-coded items (review manually):\n\n")
            for p, kind, snippet in findings:
                fh.write(f"{p} :: {kind} :: {snippet}\n\n")
    print(f"Wrote secrets scan report: {OUT}")
    return 0

if __name__ == '__main__':
    raise SystemExit(scan())
