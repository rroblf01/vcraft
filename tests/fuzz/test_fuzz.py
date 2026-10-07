#!/usr/bin/env python3
"""Random and hostile arguments through every argument reader.

Builds `examples/hello`, then calls each function with values drawn from a pool of
valid, borderline and wrong inputs: huge and negative ints, NaN and infinities,
surrogates and embedded NULs, empty and very long strings, bytes-likes, sequences of
the wrong element type, objects whose `__index__` or `__float__` raises, and missing
or surplus arguments. Nothing may crash the interpreter, and every failure has to be
an ordinary Python exception of an expected kind.

The draws are seeded, so a failure reproduces. Each round runs in a fresh process,
so a crash is reported with the seed instead of ending the suite.

    python3 tests/fuzz/test_fuzz.py [rounds] [calls-per-round]
"""

from __future__ import annotations

import subprocess
import sys
import sysconfig
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PYTHON_DIR = ROOT / "examples" / "hello" / "python"

ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 8
CALLS = int(sys.argv[2]) if len(sys.argv) > 2 else 20_000

WORKER = r'''
import math, random, resource, sys

# A ceiling on this worker's own address space, so a draw that makes the extension
# allocate gigabytes fails this seed instead of exhausting the machine. Linux only:
# macOS does not enforce RLIMIT_AS.
if sys.platform.startswith("linux"):
    limit = 3 * 1024 ** 3
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
sys.path.insert(0, sys.argv[1])
import hello_native as m
seed, calls = int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)

class BadIndex:
    def __index__(self):
        raise RuntimeError("index refused")

class BadFloat:
    def __float__(self):
        raise RuntimeError("float refused")

class BigIndex:
    def __index__(self):
        return 2**70

class Flaky:
    """A sequence whose items fail half-way through."""
    def __len__(self):
        return 4
    def __getitem__(self, i):
        if i == 2:
            raise KeyError(i)
        if i >= 4:
            raise IndexError(i)
        return i

def ints():
    return rng.choice([0, 1, -1, 2**31 - 1, -2**31, 2**63 - 1, -2**63, 2**63, -2**63 - 1,
                       2**64, 10**40, -10**40, True, False, rng.randrange(-2**70, 2**70)])

def floats():
    return rng.choice([0.0, -0.0, 1.5, float("nan"), float("inf"), float("-inf"),
                       1e308, -1e-308, 5e-324, rng.uniform(-1e9, 1e9)])

def strs():
    return rng.choice(["", "a", "España", "日本語", "\x00inner\x00nul", "\ud800",
                       "x" * rng.randrange(0, 100_000), "😀" * 100, "123", "-0", "  42 "])

def blobs():
    return rng.choice([b"", b"\x00" * 10, bytes(range(256)), bytearray(b"abc"),
                       memoryview(b"view"), memoryview(bytearray(64))[::2],
                       b"x" * rng.randrange(0, 200_000)])

def seqs():
    k = rng.randrange(0, 50)
    return rng.choice([[rng.randrange(-100, 100) for _ in range(k)],
                       tuple(range(k)), [1, "two", 3], [1.5, None], [2**64],
                       range(k), Flaky(), [BadIndex()], [[1]], (), "abc"])

def anything():
    return rng.choice([ints, floats, strs, blobs, seqs,
                       lambda: rng.choice([None, object(), BadIndex(), BadFloat(),
                                           BigIndex(), {"k": 1}, {1, 2}, m])])()

def small_anything():
    """`anything`, but never an int large enough to be an allocation size.

    `count_up(n)`, `squares(n)` and `repeat(s, n)` allocate n elements, which is the
    function's job: 2**31 of them is 16 GiB, in vcraft as with any binding. What is
    fuzzed here is the conversion, not the size of what the user's code then builds.
    """
    value = anything()
    if isinstance(value, int) and not isinstance(value, bool) and abs(value) > 100_000:
        return rng.randrange(-5, 2000)
    return value

# Functions whose arguments size an allocation.
SIZED = {m.count_up, m.squares, m.repeat}

# function -> the generator for each parameter; a wrong-type draw replaces one of them.
SIGNATURES = {
    m.add: [ints, ints],
    m.greet: [strs],
    m.divide: [floats, floats],
    m.parse_int: [strs],
    m.first_char: [strs],
    m.repeat: [strs, lambda: rng.randrange(-5, 50)],
    m.total: [seqs],
    m.total64: [seqs],
    m.mean: [lambda: [floats() for _ in range(rng.randrange(0, 20))]],
    m.count_up: [lambda: rng.randrange(-5, 2000)],
    m.halves: [lambda: [floats() for _ in range(rng.randrange(0, 20))]],
    m.squares: [lambda: rng.randrange(-5, 2000)],
    m.words: [strs],
    m.boxed: [ints],
    m.identity: [anything],
    m.checksum: [blobs],
    m.echoed: [blobs],
}
EXPECTED = (TypeError, ValueError, OverflowError, RuntimeError, ZeroDivisionError,
            KeyError, IndexError, UnicodeError, MemoryError, BufferError)

functions = list(SIGNATURES)
c = m.Counter()
for _ in range(calls):
    f = rng.choice(functions)
    args = [gen() for gen in SIGNATURES[f]]
    roll = rng.random()
    wrong = small_anything if f in SIZED else anything
    if roll < 0.2 and args:
        args[rng.randrange(len(args))] = wrong()
    elif roll < 0.25:
        args.append(wrong())
    elif roll < 0.3 and args:
        args.pop()
    try:
        f(*args)
    except EXPECTED:
        pass
    # Methods and attributes take the same hostile values.
    try:
        rng.choice([lambda: c.set_step(ints()), lambda: setattr(c, "value", anything()),
                    lambda: c.increment(), lambda: c.double()])()
    except EXPECTED:
        pass
print("ok")
'''


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


def main() -> int:
    build()
    t = Suite()
    print(f"{ROUNDS} rounds of {CALLS:,} calls")
    for seed in range(ROUNDS):
        proc = subprocess.run([sys.executable, "-c", WORKER, str(PYTHON_DIR), str(seed), str(CALLS)],
                              capture_output=True, text=True, timeout=900)
        t.check(f"seed {seed}", proc.returncode == 0 and proc.stdout.strip() == "ok",
                f"exit {proc.returncode}: {(proc.stderr or proc.stdout).strip()[-500:]}")
    print()
    if t.failures:
        print(f"{len(t.failures)} failure(s): {', '.join(t.failures)}")
        return 1
    print(f"all {t.passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
