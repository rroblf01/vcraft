#!/usr/bin/env python3
"""Fail when a bilingual document lacks its counterpart.

For every ``*.en.md`` / ``*.es.md`` under ``docs/`` there must be a matching
file in the other language. Exits non-zero (and lists the missing files) when a
pair is incomplete.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

missing: list[str] = []
for path in sorted(DOCS.rglob("*.md")):
    name = path.name
    if name.endswith(".en.md"):
        counterpart = path.with_name(name[:-6] + ".es.md")
    elif name.endswith(".es.md"):
        counterpart = path.with_name(name[:-6] + ".en.md")
    else:
        continue
    if not counterpart.exists():
        missing.append(str(path.relative_to(ROOT)))

if missing:
    print("missing bilingual counterparts:")
    for m in missing:
        print("  " + m)
    sys.exit(1)

print("ok: all bilingual docs have their counterpart")