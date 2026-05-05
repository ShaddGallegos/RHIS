#!/usr/bin/env python3
"""
Simple repository-wide helper to prefix common Ansible modules with FQCN.

Usage: python3 tools/ansible_fqcnify.py [--apply]

By default it prints a dry-run summary. Use `--apply` to modify files in-place.
"""
import re
import sys
from pathlib import Path

# Mapping of common module names to their preferred FQCN
MAPPING = {
    # core modules -> ansible.builtin
    'package': 'ansible.builtin.package',
    'service': 'ansible.builtin.service',
    'set_fact': 'ansible.builtin.set_fact',
    'template': 'ansible.builtin.template',
    'copy': 'ansible.builtin.copy',
    'file': 'ansible.builtin.file',
    'slurp': 'ansible.builtin.slurp',
    'command': 'ansible.builtin.command',
    'shell': 'ansible.builtin.shell',
    'tempfile': 'ansible.builtin.tempfile',
    'stat': 'ansible.builtin.stat',
    'fail': 'ansible.builtin.fail',
    'debug': 'ansible.builtin.debug',
    'wait_for': 'ansible.builtin.wait_for',
    'uri': 'ansible.builtin.uri',
    'lineinfile': 'ansible.builtin.lineinfile',
    'getent': 'ansible.builtin.getent',
    'authorized_key': 'ansible.builtin.authorized_key',
    'include_vars': 'ansible.builtin.include_vars',
    'unarchive': 'ansible.builtin.unarchive',
    'get_url': 'ansible.builtin.get_url',
    'synchronize': 'ansible.builtin.synchronize',
    'user': 'ansible.builtin.user',
    'group': 'ansible.builtin.group',
    'find': 'ansible.builtin.find',
    'tempfile': 'ansible.builtin.tempfile',
    'wait_for': 'ansible.builtin.wait_for',
    'find': 'ansible.builtin.find',
}

# Modules that should use ansible.posix
POSIX = {
    'firewalld': 'ansible.posix.firewalld',
    'selinux': 'ansible.posix.selinux',
    'seboolean': 'ansible.posix.seboolean',
}

MODULES = {**MAPPING, **POSIX}

MODULE_RE = re.compile(r'^(?P<indent>[ \t]*)(?P<key>[a-zA-Z_][a-zA-Z0-9_]*)\s*:(?P<rest>.*)$')

def process_file(path: Path, apply: bool=False):
    text = path.read_text(encoding='utf-8')
    lines = text.splitlines()
    changed = False
    out_lines = []
    for line in lines:
        m = MODULE_RE.match(line)
        if not m:
            out_lines.append(line)
            continue
        key = m.group('key')
        indent = m.group('indent')
        rest = m.group('rest')
        # skip keys that already look like FQCN (contain a dot)
        if '.' in key:
            out_lines.append(line)
            continue
        if key in MODULES:
            new_key = MODULES[key]
            new_line = f"{indent}{new_key}:{rest}"
            if new_line != line:
                changed = True
                out_lines.append(new_line)
                continue
        out_lines.append(line)

    if changed:
        print(f"Modified: {path}")
        if apply:
            path.write_text('\n'.join(out_lines) + '\n', encoding='utf-8')
    return changed

def main():
    apply = False
    if len(sys.argv) > 1 and sys.argv[1] == '--apply':
        apply = True

    repo_root = Path(__file__).resolve().parent.parent
    exts = ('.yml', '.yaml')
    changed_files = []
    for p in repo_root.rglob('*'):
        if p.is_file() and p.suffix in exts:
            # skip some paths
            if '/.git/' in str(p):
                continue
            if 'roles/' in str(p) and p.name.endswith(('.md',)):
                continue
            if process_file(p, apply=apply):
                changed_files.append(p.relative_to(repo_root))

    if not apply:
        if changed_files:
            print('\nDry run complete. Files that would be modified:')
            for f in changed_files:
                print(' -', f)
            print('\nRe-run with --apply to update files in-place.')
        else:
            print('Dry run complete. No changes would be made.')
    else:
        if changed_files:
            print('\nApplied changes to the following files:')
            for f in changed_files:
                print(' -', f)
        else:
            print('Apply complete. No files needed modification.')

if __name__ == '__main__':
    main()
