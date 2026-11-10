#!/usr/bin/env python3
"""Build a project twice and verify the artefacts are byte-identical."""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VCRAFT = ROOT / "bin" / "vcraft"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        subprocess.run([str(VCRAFT), "new", "demo"], cwd=str(td), check=True)
        proj = td / "demo"
        out1 = td / "out1"
        out2 = td / "out2"
        out1.mkdir()
        out2.mkdir()
        for out in (out1, out2):
            r = run([str(VCRAFT), "build", "--release", "--out-dir", str(out)], cwd=str(proj))
            if r.returncode != 0:
                print("build failed:", r.stderr or r.stdout)
                return 1
            r = run([str(VCRAFT), "sdist", "--out-dir", str(out)], cwd=str(proj))
            if r.returncode != 0:
                print("sdist failed:", r.stderr or r.stdout)
                return 1
        for kind in ("*.whl", "*.tar.gz"):
            a = sorted(out1.glob(kind))
            b = sorted(out2.glob(kind))
            if not a or not b:
                print(f"missing {kind}")
                return 1
            ha = sha256_file(a[0])
            hb = sha256_file(b[0])
            if ha != hb:
                print(f"NOT reproducible ({kind}): {ha} != {hb}")
                return 1
            print(f"reproducible {kind}: {ha}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY