#!/usr/bin/env python3
"""Build an sdist, rebuild from it, and verify the extension imports."""

from __future__ import annotations

import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VCRAFT = ROOT / "bin" / "vcraft"


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        proj = td / "demo"
        subprocess.run([str(VCRAFT), "new", "demo"], cwd=str(td), check=True)
        # build sdist
        r = run([str(VCRAFT), "sdist", "--out-dir", str(td / "out")], cwd=str(proj))
        if r.returncode != 0:
            print("sdist failed:", r.stderr or r.stdout)
            return 1
        sdists = list((td / "out").glob("*.tar.gz"))
        if not sdists:
            print("no sdist produced")
            return 1
        # extract
        extract = td / "extracted"
        extract.mkdir()
        with tarfile.open(sdists[0]) as tf:
            # The "data" filter (3.12+, backported to 3.11.4) refuses links and paths
            # that leave the directory, which an sdist never needs.
            if hasattr(tarfile, "data_filter"):
                tf.extractall(extract, filter="data")
            else:
                tf.extractall(extract)
        extracted_proj = next(extract.iterdir())
        # build wheel from extracted sdist
        r = run([str(VCRAFT), "build", "--release", "--out-dir", str(td / "wheel")],
                cwd=str(extracted_proj))
        if r.returncode != 0:
            print("build from sdist failed:", r.stderr or r.stdout)
            return 1
        wheels = list((td / "wheel").glob("*.whl"))
        if not wheels:
            print("no wheel produced from sdist")
            return 1
        # install and import
        venv = td / "venv"
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        pip = venv / "bin" / "pip"
        subprocess.run([str(pip), "install", str(wheels[0])], check=True,
                       capture_output=True, text=True)
        py = venv / "bin" / "python"
        r = subprocess.run([str(py), "-c", "import demo; print(demo.greet('world'))"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("import failed:", r.stderr or r.stdout)
            return 1
        print("sdist round-trip ok:", r.stdout.strip())
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY