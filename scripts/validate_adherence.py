#!/usr/bin/env python3
"""Simple validator that ensures docs/assistant-adherence-rules.md exists and is non-empty.

This script is intentionally small: the CI gate fails if the file is missing or empty.
"""
import os
import sys


P = os.path.join("docs", "assistant-adherence-rules.md")


def fail(msg: str):
    print("ERROR:", msg)
    sys.exit(1)


def main():
    if not os.path.isfile(P):
        fail(f"{P} not found. Add the adherence rules file to docs/")
    if os.path.getsize(P) == 0:
        fail(f"{P} is empty. Please populate with the adherence rules.")
    print(f"OK: {P} exists and is non-empty")


if __name__ == '__main__':
    main()
