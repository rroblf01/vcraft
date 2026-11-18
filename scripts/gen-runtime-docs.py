#!/usr/bin/env python3
"""Generate the runtime API reference from vlib/vcraft's own doc comments.

Every `pub fn`, `pub struct`, `pub enum` and `pub const` of the runtime module, with the
`//` comment block above it, grouped by source file, into docs/reference/runtime.en.md and
its Spanish twin (same listing, Spanish introduction). The comments are the source of
truth; this only arranges them.

    python3 scripts/gen-runtime-docs.py          # rewrite the two pages
    python3 scripts/gen-runtime-docs.py --check  # exit 1 if they are out of date
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "vlib" / "vcraft"
OUT = {"en": ROOT / "docs" / "reference" / "runtime.en.md",
       "es": ROOT / "docs" / "reference" / "runtime.es.md"}
DECL = re.compile(r"^pub (fn|struct|enum|const) ")

INTRO = {
    "en": """# Runtime API

The `vcraft` module every extension imports: conversions, errors, classes, buffers,
callbacks, Arrow and NumPy views, parallel loops, logging. Generated from the doc comments
in `vlib/vcraft` by `scripts/gen-runtime-docs.py`; CI checks it is current.

Functions the generated glue calls are listed too; the ones a project's own code reaches
for are described in the guide pages (errors, classes, types).
""",
    "es": """# API del runtime

El módulo `vcraft` que importa cada extensión: conversiones, errores, clases, buffers,
callbacks, vistas Arrow y NumPy, bucles paralelos, logging. Generado a partir de los
comentarios de documentación de `vlib/vcraft` con `scripts/gen-runtime-docs.py`; la CI
comprueba que está al día. Las descripciones son las del código, en inglés.

También aparecen las funciones que llama el código generado; las que usa el código de un
proyecto se explican en las páginas de la guía (errores, clases, tipos).
""",
}


def signature(lines: list[str], i: int) -> str:
    """The declaration up to its opening brace (or the whole line for a const)."""
    text = lines[i].rstrip()
    j = i
    while "{" not in text and j + 1 < len(lines) and not text.startswith("pub const"):
        j += 1
        text += " " + lines[j].strip()
    return text.split("{")[0].strip() if not text.startswith("pub const") else text.strip()


def collect() -> dict[str, list[tuple[str, str]]]:
    out: dict[str, list[tuple[str, str]]] = {}
    for path in sorted(SRC.glob("*.v")):
        if path.name.endswith("_test.v"):
            continue
        lines = path.read_text().splitlines()
        items = []
        for i, line in enumerate(lines):
            if not DECL.match(line):
                continue
            doc = []
            k = i - 1
            while k >= 0 and (lines[k].startswith("//") or lines[k].startswith("@[")):
                if lines[k].startswith("//"):
                    doc.insert(0, lines[k][2:].strip())
                k -= 1
            items.append((signature(lines, i), "\n".join(doc).strip()))
        if items:
            out[path.name] = items
    return out


def render(lang: str, items: dict[str, list[tuple[str, str]]]) -> str:
    parts = [INTRO[lang]]
    for name, decls in items.items():
        parts.append(f"\n## `{name}`\n")
        for sig, doc in decls:
            parts.append(f"\n```v\n{sig}\n```\n")
            if doc:
                parts.append("\n" + doc.replace("\t", "    ") + "\n")
    return "".join(parts).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    items = collect()
    stale = []
    for lang, path in OUT.items():
        text = render(lang, items)
        if args.check:
            if not path.exists() or path.read_text() != text:
                stale.append(path.name)
        else:
            path.write_text(text)
            print(f"wrote {path.relative_to(ROOT)}")
    if args.check:
        if stale:
            print(f"out of date: {', '.join(stale)}; run scripts/gen-runtime-docs.py")
            return 1
        print("ok: the runtime reference matches vlib/vcraft")
    return 0


if __name__ == "__main__":
    sys.exit(main())
