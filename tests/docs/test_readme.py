#!/usr/bin/env python3
"""Every V example in the README builds.

Each ```v block is written into a fresh project made by `vcraft new` and built with
`vcraft build`, so an example that drifts from what the generator or the compiler
accepts fails here rather than in a reader's first attempt. Two markers, as HTML
comments on the line before a block, which neither GitHub nor PyPI renders:

    <!-- readme-test: continue -->   build this block together with the one before
    <!-- readme-test: skip -->       an illustration, such as generated glue

    python3 tests/docs/test_readme.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VCRAFT = ROOT / "bin" / "vcraft"
BLOCK = re.compile(r"(?:<!-- readme-test: (\w+) -->\n)?```v\n(.*?)```", re.S)


class Suite:
    def __init__(self) -> None:
        self.passed = 0
        self.failures: list[str] = []

    def check(self, label: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"  ok   {label}")
        else:
            print(f"  FAIL {label} {detail}")
            self.failures.append(label)


def examples() -> list[tuple[str, str]]:
    """(label, source) per buildable example, with continued blocks joined."""
    text = (ROOT / "README.md").read_text()
    out: list[tuple[str, str]] = []
    for match in BLOCK.finditer(text):
        marker, code = match.group(1), match.group(2)
        line = text.count("\n", 0, match.start()) + 1
        # Each example brings its own module line; the project supplies one.
        code = "\n".join(l for l in code.splitlines() if not l.startswith("module "))
        if marker == "skip":
            continue
        if marker == "continue" and out:
            label, previous = out[-1]
            out[-1] = (f"{label}+{line}", previous + "\n" + code)
            continue
        if marker not in (None, "continue"):
            raise SystemExit(f"README.md:{line}: unknown readme-test marker {marker!r}")
        out.append((f"README.md:{line}", code))
    return out


def main() -> int:
    proc = subprocess.run([str(ROOT / "scripts" / "build-vcraft.sh")],
                          capture_output=True, text=True)
    if proc.returncode != 0 or not VCRAFT.exists():
        raise SystemExit(f"cannot build {VCRAFT}:\n{proc.stdout}\n{proc.stderr}")

    t = Suite()
    found = examples()
    print(f"{len(found)} examples")
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-readme-"))
    try:
        for i, (label, code) in enumerate(found):
            name = f"readme{i}"
            project = tmp / name
            subprocess.run([str(VCRAFT), "new", name, str(project)],
                           capture_output=True, text=True, check=True)
            (project / "src" / f"{name}_native.v").write_text(
                f"module {name}_native\n\nimport vcraft\n\n{code}\n")
            proc = subprocess.run([str(VCRAFT), "build", "--interpreter", sys.executable],
                                  cwd=project, capture_output=True, text=True, timeout=600)
            errors = [l for l in (proc.stderr + proc.stdout).splitlines() if "error" in l]
            t.check(f"{label} builds", proc.returncode == 0, " | ".join(errors[:3]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if t.failures:
        print(f"{len(t.failures)} failure(s): {', '.join(t.failures)}")
        return 1
    print(f"all {t.passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
