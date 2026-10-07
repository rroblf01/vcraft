#!/usr/bin/env python3
"""Leak checks for the generated glue and the runtime.

Builds `examples/hello` through `scripts/build-example.sh`, then runs every scenario
in a fresh process, twice in a row. A heap that has settled adds nothing the second
time; a leak adds the same amount again. Two things are measured:

- Python objects, with `tracemalloc`: exact, and blind to V's own heap, so the
  collector's normal plateau is not mistaken for a leak. One object kept per call,
  over the calls of a batch, is far above the threshold.
- Peak RSS, for V-side memory that keeps growing, with a looser threshold.

Borrowed arguments are also checked for reference counts that drift.

    python3 tests/memory/test_leaks.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import sysconfig
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PYTHON_DIR = ROOT / "examples" / "hello" / "python"

# What the second batch may add on top of the first.
PY_GROWTH_LIMIT = 64 * 1024          # bytes of live Python objects
RSS_GROWTH_LIMIT = 4 * 1024 * 1024   # bytes of peak RSS

# label -> (setup, statement repeated per call, calls per batch). Each statement makes
# fresh objects, so a reader that keeps a reference to anything it touched leaks it.
SCENARIOS = {
    "str in, str out": ("", "m.greet('world')", 100_000),
    "str built in V": ("", "m.repeat('ab', 500)", 20_000),
    "list of str out": ("", "m.words('alpha beta gamma delta')", 50_000),
    "list of int out": ("", "m.count_up(1000)", 5_000),
    "new list of float in": ("", "m.mean([i * 0.5 for i in range(1000)])", 5_000),
    "new list of int in": ("", "m.total(list(range(1000)))", 5_000),
    "new bytes in, copy out": ("", "m.echoed(bytes(range(256)) * 40)", 10_000),
    "new bytearray through a view": ("", "m.checksum(bytearray(b'x' * 4096))", 10_000),
    "error raised and caught": (
        "", "try:\n    m.parse_int('nope')\nexcept ValueError:\n    pass", 50_000),
    "object out, owned": ("", "m.boxed(12345)", 100_000),
    "object in, borrowed": ("obj = object()", "m.identity(obj)", 100_000),
    "instances created and freed": ("", "m.Counter().increment()", 100_000),
    "reference cycles": (
        "",
        "a = m.Pair()\nb = m.Pair()\na.link(b)\nb.link(a)\ndel a, b",
        20_000),
    "iteration": ("", "list(m.Countdown())", 20_000),
    # Each thread registers with V's collector on its first call and unregisters
    # when it exits: a registration that is never undone grows with every thread.
    "short-lived threads": (
        "import threading",
        "t = threading.Thread(target=m.greet, args=('thread',))\nt.start()\nt.join()",
        2_000),
}

# Calls whose argument the glue only borrows: its reference count must not move.
BORROWED = {
    "identity": ("obj = object()", "m.identity(obj)", "obj"),
    "greet": ("obj = 'someone'", "m.greet(obj)", "obj"),
    "total": ("obj = list(range(100))", "m.total(obj)", "obj"),
    "checksum": ("obj = b'abc' * 100", "m.checksum(obj)", "obj"),
}

WORKER = r"""
import gc, json, resource, sys, tracemalloc
# A ceiling on the worker's address space, so a scenario that runs away fails here
# instead of exhausting the machine. Linux only: macOS does not enforce RLIMIT_AS.
if sys.platform.startswith("linux"):
    resource.setrlimit(resource.RLIMIT_AS, (3 * 1024 ** 3, 3 * 1024 ** 3))
sys.path.insert(0, sys.argv[1])
import hello_native as m
setup, stmt, calls = json.loads(sys.argv[2])
env = {"m": m}
exec(setup, env)
code = compile(stmt, "<scenario>", "exec")

def peak():
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return value if sys.platform == "darwin" else value * 1024

def batch():
    for _ in range(calls):
        exec(code, env)
    gc.collect()

batch()                       # warm up: first-call caches are not the scenario
tracemalloc.start()
batch()
first_py, first_rss = tracemalloc.get_traced_memory()[0], peak()
batch()
second_py, second_rss = tracemalloc.get_traced_memory()[0], peak()
print(json.dumps({"py": second_py - first_py, "rss": second_rss - first_rss}))
"""

REFCOUNT = r"""
import json, sys
sys.path.insert(0, sys.argv[1])
import hello_native as m
setup, stmt, name = json.loads(sys.argv[2])
env = {"m": m}
exec(setup, env)
code = compile(stmt, "<call>", "exec")
exec(code, env)
before = sys.getrefcount(env[name])
for _ in range(10_000):
    exec(code, env)
print(json.dumps({"drift": sys.getrefcount(env[name]) - before}))
"""


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


def build() -> None:
    print("building the example")
    proc = subprocess.run([str(ROOT / "scripts" / "build-example.sh"), "hello", "hello_native"],
                          capture_output=True, text=True)
    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    if proc.returncode != 0 or not (PYTHON_DIR / f"hello_native{suffix}").exists():
        raise SystemExit(f"build failed:\n{proc.stdout}\n{proc.stderr}")


def run(script: str, payload) -> dict:
    proc = subprocess.run([sys.executable, "-c", script, str(PYTHON_DIR), json.dumps(payload)],
                          capture_output=True, text=True, timeout=900)
    if proc.returncode != 0:
        return {"error": (proc.stderr or proc.stdout).strip()[-400:]}
    return json.loads(proc.stdout)


def kib(n: int) -> str:
    return f"{n / 1024:,.0f} KiB"


def main() -> int:
    build()
    t = Suite()

    print("second batch adds nothing")
    for label, (setup, stmt, calls) in SCENARIOS.items():
        r = run(WORKER, [setup, stmt, calls])
        if "error" in r:
            t.check(label, False, r["error"])
            continue
        t.check(f"{label}: Python objects", r["py"] < PY_GROWTH_LIMIT,
                f"{kib(r['py'])} more after {calls:,} calls")
        t.check(f"{label}: peak RSS", r["rss"] < RSS_GROWTH_LIMIT,
                f"{kib(r['rss'])} more after {calls:,} calls")

    print("borrowed arguments keep their reference count")
    for label, payload in BORROWED.items():
        r = run(REFCOUNT, list(payload))
        t.check(label, r.get("drift") == 0, str(r))

    print()
    if t.failures:
        print(f"{len(t.failures)} failure(s): {', '.join(t.failures)}")
        return 1
    print(f"all {t.passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
