#!/usr/bin/env python3
"""Run a tiny benchmark and fail if it regresses beyond the committed baseline."""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON_DIR = ROOT / "examples" / "hello" / "python"
BASELINE = ROOT / "benchmark" / "baseline.json"
VCRAFT = ROOT / "bin" / "vcraft"

# Build the example first.
subprocess.run([str(ROOT / "scripts" / "build-example.sh"), "hello", "hello_native"],
               check=True, capture_output=True)

sys.path.insert(0, str(PYTHON_DIR))
import hello_native as m  # noqa: E402

N = 200_000
start = time.perf_counter()
for _ in range(N):
    m.greet("world")
elapsed = time.perf_counter() - start
ops = N / elapsed

result = {"greet_ops_per_sec": ops}
print(f"greet: {ops:,.0f} ops/s")

if not BASELINE.exists():
    BASELINE.write_text(json.dumps(result, indent=2) + "\n")
    print("baseline written:", BASELINE)
    sys.exit(0)

baseline = json.loads(BASELINE.read_text())
limit = baseline["greet_ops_per_sec"] * 0.8  # 20% regression tolerance
if ops < limit:
    print(f"REGRESSION: {ops:,.0f} < {limit:,.0f} (baseline {baseline['greet_ops_per_sec']:,.0f})")
    sys.exit(1)
print("ok: no regression")
