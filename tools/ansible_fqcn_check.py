#!/usr/bin/env python3
"""
Scan repository YAML files for bare Ansible module names (non-FQCN)
and exit non-zero if any are found. This is used by CI to enforce FQCN usage.

Return code: 0 = OK, 1 = found violations
"""
import re
import sys
from pathlib import Path

# Modules considered 'builtin' or posix that should be FQCN-prefixed
MODULES = {
    'package', 'service', 'set_fact', 'template', 'copy', 'file', 'slurp',
    'command', 'shell', 'tempfile', 'stat', 'fail', 'debug', 'wait_for',
    'uri', 'lineinfile', 'getent', 'authorized_key', 'include_vars',
    'unarchive', 'get_url', 'synchronize', 'user', 'group', 'find',
    'ansible_facts', 'ansible.builtin',
}

MODULE_RE = re.compile(r'^(?P<indent>[ \t]*)(?P<key>[a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(?:#.*)?$')

def check_file(path: Path):
    violations = []
    try:
        text = path.read_text(encoding='utf-8')
    except Exception:
        return violations
    for i, line in enumerate(text.splitlines(), start=1):
        m = MODULE_RE.match(line)
        if not m:
            continue
        key = m.group('key')
        # Skip explicit FQCNs
        if '.' in key:
            continue
        # Skip common YAML keys that are not module names
        if key in ('name','hosts','vars','become','become_user','become_method','gather_facts','when','register','tags','delegate_to','changed_when','failed_when','notify','loop','with_items','args','environment','connection','roles'):
            continue
        if key in MODULES:
            violations.append((i, key, line.strip()))
    return violations

def main():
    repo_root = Path(__file__).resolve().parent.parent
    exts = ('.yml', '.yaml')
    all_violations = {}
    for p in repo_root.rglob('*'):
        if p.is_file() and p.suffix in exts:
            # skip some directories
            if '/.git/' in str(p) or '/.venv/' in str(p) or '/venv/' in str(p):
                continue
            v = check_file(p)
            if v:
                all_violations[p.relative_to(repo_root)] = v

    if all_violations:
        print('FQCN violations detected:')
        for f, items in all_violations.items():
            print(f'File: {f}')
            for lineno, key, snippet in items:
                print(f'  L{lineno}: module "{key}" used without FQCN -> "{snippet}"')
        sys.exit(1)
    print('No FQCN violations found.')
    sys.exit(0)

if __name__ == '__main__':
    main()
