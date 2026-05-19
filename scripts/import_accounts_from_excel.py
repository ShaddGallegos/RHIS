#!/usr/bin/env python3
"""
Import account rows from Excel (.xlsx/.xls) and emit a deduplicated
`node_common_users` YAML suitable for Ansible consumption.

Usage examples:
  scripts/import_accounts_from_excel.py users.xlsx -o local/vars/node_common_users.yml
  scripts/import_accounts_from_excel.py sheet1.xlsx sheet2.xls --sheet 0

The script attempts to auto-detect common column names for username,
groups, comment, ssh_key and shell. Deduplication is performed by
username (case-insensitive). Fields from earlier rows are preserved
unless missing, in which case later rows may fill them.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List, Optional

try:
    import pandas as pd
except Exception as exc:  # pragma: no cover - best-effort import
    print("ERROR: pandas is required to run this script. Install with 'pip install pandas openpyxl xlrd'", file=sys.stderr)
    raise

try:
    import yaml
except Exception as exc:  # pragma: no cover
    print("ERROR: PyYAML is required. Install with 'pip install PyYAML'", file=sys.stderr)
    raise


COL_CANDIDATES = {
    "name": ["name", "username", "user", "login", "uid"],
    "comment": ["comment", "fullname", "full_name", "displayname", "display_name", "description", "email"],
    "groups": ["groups", "group", "roles"],
    "ssh_key": ["ssh_key", "sshkey", "ssh_key_data", "public_key", "pubkey"],
    "shell": ["shell", "shell_path", "login_shell"],
}


def pick_column(columns: List[str], candidates: List[str]) -> Optional[str]:
    cols_lower = {c.lower(): c for c in columns}
    for cand in candidates:
        if cand.lower() in cols_lower:
            return cols_lower[cand.lower()]
    return None


def read_workbook(path: Path, sheet: Optional[str] = None) -> pd.DataFrame:
    # Let pandas pick the engine; try a couple of fallbacks for older xls
    try:
        df = pd.read_excel(path, sheet_name=sheet)
    except Exception:
        # Try explicit engines for robustness
        for engine in ("openpyxl", "xlrd"):
            try:
                df = pd.read_excel(path, sheet_name=sheet, engine=engine)
                break
            except Exception:
                df = None
        if df is None:
            raise
    return df


def extract_users_from_df(df: pd.DataFrame) -> List[Dict]:
    if df is None or df.empty:
        return []
    columns = list(df.columns)
    col_map = {}
    for field, candidates in COL_CANDIDATES.items():
        match = pick_column(columns, candidates)
        col_map[field] = match

    users: Dict[str, Dict] = {}
    for _, row in df.iterrows():
        # name is required or fall back to email/comment
        raw_name = None
        if col_map.get("name"):
            raw_name = row.get(col_map["name"])
        if not raw_name and col_map.get("comment"):
            raw_name = row.get(col_map["comment"])  # maybe email
        if raw_name is None or (isinstance(raw_name, float) and pd.isna(raw_name)):
            # skip rows without any usable identifier
            continue
        name = str(raw_name).strip()
        if not name:
            continue
        key = name.lower()

        entry = users.get(key, {})
        # ensure `name` present and other fields set if available
        entry.setdefault("name", name)
        # comment
        if col_map.get("comment"):
            val = row.get(col_map["comment"]) if col_map["comment"] in row.index else None
            if val is not None and not (isinstance(val, float) and pd.isna(val)):
                entry.setdefault("comment", str(val).strip())
        # groups (normalize to comma separated string)
        if col_map.get("groups"):
            val = row.get(col_map["groups"]) if col_map["groups"] in row.index else None
            if val is not None and not (isinstance(val, float) and pd.isna(val)):
                if isinstance(val, (list, tuple)):
                    entry.setdefault("groups", ",".join(map(str, val)))
                else:
                    entry.setdefault("groups", str(val).strip())
        # ssh_key
        if col_map.get("ssh_key"):
            val = row.get(col_map["ssh_key"]) if col_map["ssh_key"] in row.index else None
            if val is not None and not (isinstance(val, float) and pd.isna(val)):
                entry.setdefault("ssh_key", str(val).strip())
        # shell
        if col_map.get("shell"):
            val = row.get(col_map["shell"]) if col_map["shell"] in row.index else None
            if val is not None and not (isinstance(val, float) and pd.isna(val)):
                entry.setdefault("shell", str(val).strip())

        users[key] = entry

    # return list sorted by name
    return sorted(users.values(), key=lambda x: x.get("name", ""))


def write_yaml_users(users: List[Dict], outpath: Optional[Path] = None) -> None:
    payload = {"node_common_users": users}
    text = yaml.safe_dump(payload, sort_keys=False, default_flow_style=False, allow_unicode=True)
    if outpath:
        outpath.parent.mkdir(parents=True, exist_ok=True)
        outpath.write_text(text, encoding="utf-8")
        print(f"Wrote {len(users)} unique users to {outpath}", file=sys.stderr)
    else:
        print(text)


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Import accounts from Excel and produce unique node_common_users YAML")
    p.add_argument("files", nargs="+", help="Excel file(s) to read (.xlsx, .xls)")
    p.add_argument("-s", "--sheet", help="Sheet name or index to read (default: first sheet)")
    p.add_argument("-o", "--output", help="Output YAML file path (default: stdout)")
    args = p.parse_args(argv)

    accumulated: List[Dict] = []
    for f in args.files:
        path = Path(f).expanduser().resolve()
        if not path.exists():
            print(f"WARN: file not found: {path}", file=sys.stderr)
            continue
        try:
            df = read_workbook(path, sheet=args.sheet)
        except Exception as exc:
            print(f"ERROR reading {path}: {exc}", file=sys.stderr)
            continue
        users = extract_users_from_df(df)
        accumulated.extend(users)

    # Deduplicate accumulated list by lowercase name, preserving first-seen values
    seen: Dict[str, Dict] = {}
    for u in accumulated:
        key = u.get("name", "").lower()
        if not key:
            continue
        if key not in seen:
            seen[key] = u
        else:
            # merge missing fields from later rows
            existing = seen[key]
            for k, v in u.items():
                if k not in existing or not existing[k]:
                    existing[k] = v

    final_users = sorted(seen.values(), key=lambda x: x.get("name", ""))
    outpath = Path(args.output) if args.output else None
    write_yaml_users(final_users, outpath)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
