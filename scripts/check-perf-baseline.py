#!/usr/bin/env python3
"""Run a tiny benchmark and fail if it regresses well beyond the committed baseline.

The number compared is relative: calls per second of the extension's `greet` divided by
those of the same function written in Python, both timed in this process. An absolute
rate measured on one machine says nothing on another (a CI runner is several times
slower than a workstation), while the ratio mostly cancels the machine out. It still
moves between machines and Python versions, so only a halving fails: this guards
against a gross regression in the call path, not against a few percent, which is what
`benchmark/ab.py` is for.

    python3 scripts/check-perf-baseline.py            # check
    python3 scripts/check-perf-baseline.py --update   # record this machine's ratio
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON_DIR = ROOT / "examples" / "hello" / "python"
BASELINE = ROOT / "benchmark" / "baseline.json"
TOLERANCE = 0.5  # fail below half the baseline ratio

# Build the example first.
subprocess.run([str(ROOT / "scripts" / "build-example.sh"), "hello", "hello_native"],
               check=True, capture_output=True)

sys.path.insert(0, str(PYTHON_DIR))
import hello_native as m  # noqa: E402


def greet(name: str) -> str:
    return f"Hello, {name}!"


def rate(f) -> float:
    """Best of five runs: the fastest is the one least disturbed by the machine."""
    n = 200_000
    best = 0.0
    for _ in range(5):
        start = time.perf_counter()
        for _ in range(n):
            f("world")
        best = max(best, n / (time.perf_counter() - start))
    return best


native = rate(m.greet)
python = rate(greet)
ratio = native / python
print(f"greet: {native:,.0f} calls/s native, {python:,.0f} in Python, ratio {ratio:.3f}")

if "--update" in sys.argv or not BASELINE.exists():
    BASELINE.write_text(json.dumps({"greet_ratio_to_python": round(ratio, 3)}, indent=2) + "\n")
    print("baseline written:", BASELINE)
    sys.exit(0)

baseline = json.loads(BASELINE.read_text())["greet_ratio_to_python"]
if ratio < baseline * TOLERANCE:
    print(f"REGRESSION: ratio {ratio:.3f} < {baseline * TOLERANCE:.3f} "
          f"(half the baseline {baseline:.3f})")
    sys.exit(1)
print(f"ok: no regression (baseline ratio {baseline:.3f})")
