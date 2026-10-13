#!/usr/bin/env python3
"""Compares PyO3, vcraft and zig-maturin on the same workloads.

Every backend is measured in fresh subprocesses so that one backend's allocator,
garbage collector or imported runtime never shows up in another's numbers: one
process for speed, one for correctness, one per reference probe, and one process
per memory scenario.

    python bench.py                  # run everything, write results.json and results.md
    python bench.py --quick          # fewer repeats, for checking the harness

The wheels must already be built and installed into the running interpreter;
`run.sh` does both.
"""

from __future__ import annotations

import argparse
import gc
import importlib
import json
import math
import os
import platform
import resource
import shutil
import subprocess
import sys
import tempfile
import time
import timeit
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

# name -> (importable module, project directory holding dist/)
BACKENDS = {
    "pyo3": ("bench_pyo3", HERE / "pyo3"),
    "vcraft": ("bench_vcraft_native", HERE / "vcraft"),
    "zig-maturin": ("bench_zig", HERE / "zig-maturin"),
    "python": ("pure_python", None),
}

BACKEND_BY_MODULE = {module: name for name, (module, _) in BACKENDS.items()}

FLOATS = [i * 0.5 for i in range(100_000)]
BYTES = bytes(range(256)) * 400
STRINGS = ["s%05d" % i for i in range(10_000)]

IMPORT_RUNS = 8

# label -> (statement, what it measures). `m` is the module, `c` a Counter instance.
SPEED = {
    "add": ("m.add(1, 2)", "call overhead"),
    "fib(25)": ("m.fib(25)", "pure compute, recursion"),
    "count_primes(1e6)": ("m.count_primes(1_000_000)", "compute + 1 MB native alloc"),
    "sum_floats(100k)": ("m.sum_floats(FLOATS)", "list[float] -> native"),
    "make_range(100k)": ("m.make_range(100_000)", "native -> list[int]"),
    "greet": ("m.greet('world')", "str in, new str out"),
    "checksum(100kB)": ("m.checksum(BYTES)", "bytes -> native, no copy"),
    "echo_bytes(100kB)": ("m.echo_bytes(BYTES)", "bytes in, fresh copy out"),
    "join_strings(10k)": ("m.join_strings(STRINGS)", "list[str] -> native -> str"),
    "expect_positive(err)": (
        "try:\n    m.expect_positive(-1)\nexcept ValueError:\n    pass",
        "raise + catch per call",
    ),
    "Counter()": ("m.Counter()", "object construction"),
    "c.increment()": ("c.increment()", "method call"),
    "c.add(1)": ("c.add(1)", "method call with an argument"),
    "c.value": ("c.value", "attribute read"),
}

# label -> (statement run `loops` times, loops). Each runs in its own process.
# The statements may be expressions or small statement blocks; they are exec'd.
MEMORY = {
    "greet x2M": ("m.greet('world')", 2_000_000),
    "make_range(100k) x200": ("m.make_range(100_000)", 200),
    "count_primes(10M) x5": ("m.count_primes(10_000_000)", 5),
    # A fresh list on every call, so a reader that keeps a reference to each item it
    # reads leaks the whole list. The speed workload reuses one list and cannot see it.
    "sum_floats(new 10k list) x500": ("m.sum_floats([i * 0.5 for i in range(10_000)])", 500),
    # Same idea for the buffer path: a view the reader does not release keeps the
    # whole object alive.
    "checksum(new 100kB) x500": ("m.checksum(bytes(range(256)) * 400)", 500),
    "echo_bytes(new 100kB) x500": ("m.echo_bytes(bytes(range(256)) * 400)", 500),
    "join_strings(new 1k strs) x500": (
        "m.join_strings(['s%05d' % i for i in range(1000)])", 500),
    "Counter() x1M": ("m.Counter()", 1_000_000),
    # The failure path allocates too: a raised exception must not keep the arguments,
    # the exception object, or the traceback. Success-only scenarios cannot see it.
    "expect_positive(-1) x500k": (
        "try:\n    m.expect_positive(-1)\nexcept ValueError:\n    pass", 500_000),
    "sum_floats(wrong elem) x200k": (
        "try:\n    m.sum_floats(['x'])\nexcept TypeError:\n    pass", 200_000),
}

class AnyOf:
    """A correctness case that accepts any of several outcomes.

    A plain list would be ambiguous with an expected list value (`make_range`),
    so membership is spelled out.
    """

    def __init__(self, *options):
        self.options = options


# label -> (statement, expected). Each runs in the importing process.
#
# `expected` is one of:
#   * a value: the call must return it and compare equal;
#   * the name of an exception class (a string): the call must raise exactly it;
#   * ``AnyOf(...)`` of the above: any one of them is accepted;
#   * "n/a": the case does not apply to this backend;
#   * a dict {backend: <one of the above>}, with an optional "*" fallback, when the
#     backends legitimately differ.
# A raised exception whose name equals a value-looking string is still a match, so a
# string return value and an exception name never collide in practice.
#
# `python` is a reference, not a binding: it is duck-typed, so it is "n/a" wherever the
# point of the case is that a C implementation must enforce (or reject) a type.
CORRECTNESS = {
    "add small": ("m.add(2, 3)", 5),
    "add zero": ("m.add(0, 0)", 0),
    "add negative": ("m.add(-5, 3)", -2),
    "add 2**40": ("m.add(2**40, 1)", 2**40 + 1),
    "add i64 max": ("m.add(2**63 - 1, 0)", 2**63 - 1),
    "add i64 min": ("m.add(-2**63, 0)", -2**63),
    # A bool is an int in CPython and PyLong_AsLongLong accepts it; a binding that
    # rejects the subclass is only stricter, not wrong, so both outcomes are accepted.
    "add bool": ("m.add(True, True)", AnyOf(2, "TypeError")),
    "add float rejected": ("m.add(1.0, 2)", {"python": "n/a", "*": "TypeError"}),
    "add str rejected": ("m.add('1', 2)", "TypeError"),
    "add 2**63 overflows": ("m.add(2**63, 0)", {"python": "n/a", "*": "OverflowError"}),
    "add 2**64-1 overflows": ("m.add(2**64 - 1, 0)", {"python": "n/a", "*": "OverflowError"}),
    "fib(0)": ("m.fib(0)", 0),
    "fib(1)": ("m.fib(1)", 1),
    "fib(20)": ("m.fib(20)", 6765),
    "fib(-1)": ("m.fib(-1)", -1),
    "fib float rejected": ("m.fib(3.0)", {"python": "n/a", "*": "TypeError"}),
    "count_primes(0)": ("m.count_primes(0)", 0),
    "count_primes(1)": ("m.count_primes(1)", 0),
    "count_primes(10)": ("m.count_primes(10)", 4),
    "count_primes(100)": ("m.count_primes(100)", 25),
    "count_primes negative": ("m.count_primes(-5)", 0),
    "sum_floats empty": ("m.sum_floats([])", 0.0),
    "sum_floats two": ("m.sum_floats([1.5, 2.5])", 4.0),
    "sum_floats negative": ("m.sum_floats([-1.5, -2.5])", -4.0),
    # PyFloat_AsDouble accepts an int where a float is expected.
    "sum_floats ints": ("m.sum_floats([1, 2, 3])", AnyOf(6.0, "TypeError")),
    "sum_floats nan": ("math.isnan(m.sum_floats([float('nan')]))", True),
    "sum_floats inf": ("m.sum_floats([float('inf'), 1.0])", float("inf")),
    "sum_floats str rejected": ("m.sum_floats('abc')", "TypeError"),
    "sum_floats mixed rejected": ("m.sum_floats([1.0, 'x'])", "TypeError"),
    "make_range(0)": ("m.make_range(0)", []),
    "make_range(1)": ("m.make_range(1)", [0]),
    "make_range(3)": ("m.make_range(3)", [0, 1, 2]),
    # list(range(-1)) is empty; a negative count is not a native allocation size.
    "make_range negative": ("m.make_range(-1)", []),
    "make_range float rejected": ("m.make_range(3.0)", "TypeError"),
    "greet empty": ("m.greet('')", "Hello, !"),
    "greet unicode": ("m.greet('España')", "Hello, España!"),
    # A non-BMP code point is four UTF-8 bytes; an embedded NUL is where a length
    # carried through a C string truncates.
    "greet emoji": ("m.greet('🐍')", "Hello, 🐍!"),
    "greet embedded NUL": ("m.greet('a\\x00b')", "Hello, a\x00b!"),
    "greet int rejected": ("m.greet(123)", {"python": "n/a", "*": "TypeError"}),
    "greet bytes rejected": ("m.greet(b'x')", {"python": "n/a", "*": "TypeError"}),
    "checksum empty": ("m.checksum(b'')", 0),
    "checksum 3 bytes": ("m.checksum(b'\\x01\\x02\\xff')", 258),
    # PyO3's `&[u8]` takes exact bytes; a buffer-protocol reader takes all of these.
    "checksum bytearray": ("m.checksum(bytearray(b'\\x01\\x02'))", {"pyo3": "n/a", "*": 3}),
    "checksum memoryview": ("m.checksum(memoryview(b'\\x01\\x02'))", {"pyo3": "n/a", "*": 3}),
    "checksum array": ("m.checksum(array.array('B', [1, 2, 3]))", {"pyo3": "n/a", "*": 6}),
    # A str is not a buffer, so it must not be read as bytes.
    "checksum str rejected": ("m.checksum('ab')", "TypeError"),
    "echo_bytes round trip": ("m.echo_bytes(b'\\x01\\x02\\xff')", b'\x01\x02\xff'),
    "echo_bytes empty": ("m.echo_bytes(b'')", b''),
    "echo_bytes from bytearray": ("m.echo_bytes(bytearray(b'ab'))", {"pyo3": "n/a", "*": b'ab'}),
    "join_strings empty": ("m.join_strings([])", ''),
    "join_strings single": ("m.join_strings(['a'])", 'a'),
    "join_strings 3 items": ("m.join_strings(['a', 'bb', 'ccc'])", 'a,bb,ccc'),
    "join_strings nonstr rejected": ("m.join_strings(['a', 1])", "TypeError"),
    "counter starts at 0": ("(lambda c: c.value)(m.Counter())", 0),
    "counter increment twice": ("(lambda c: [c.increment(), c.increment()])(m.Counter())", [1, 2]),
    "counter add and value": ("(lambda c: [c.add(2), c.add(3), c.value])(m.Counter())", [2, 5, 5]),
    "counter add negative": ("(lambda c: c.add(-2))(m.Counter())", -2),
    "expect_positive zero": ("m.expect_positive(0)", 0),
    "expect_positive ok": ("m.expect_positive(41)", 41),
    "expect_positive raises": ("m.expect_positive(-1)", "ValueError"),
    "expect_positive str rejected": ("m.expect_positive('x')", "TypeError"),
}

# label -> (setup, target expression, call expression, loops). Each runs in its own
# process. The target's refcount must not move while the extension borrows it: a
# reader that keeps a reference grows it by one per call, which RSS is too coarse to
# see in a short run.
REFS = {
    "sum_floats: borrowed list": ("xs = [1.0, 2.0, 3.0]", "xs", "m.sum_floats(xs)", 2_000),
    # The elements are runtime objects, not interned literals, so a reader that keeps
    # one reference per element read grows this count by one per call.
    "sum_floats: borrowed elements": (
        "xs = [float(i) + 0.5 for i in range(3)]", "xs[0]", "m.sum_floats(xs)", 2_000),
    "checksum: borrowed bytes": ("buf = b'abc' * 100", "buf", "m.checksum(buf)", 2_000),
    "checksum: borrowed bytearray": (
        "buf = bytearray(b'abc' * 100)", "buf", "m.checksum(buf)", 2_000),
    "checksum: borrowed memoryview": (
        "buf = memoryview(b'abc' * 100)", "buf", "m.checksum(buf)", 2_000),
    "echo_bytes: borrowed argument": (
        "buf = b'abc' * 100", "buf", "m.echo_bytes(buf)", 2_000),
    "method: borrowed self": ("obj = m.Counter()", "obj", "obj.increment()", 2_000),
}


# ------------------------------------------------------------------ worker side


def rss() -> int:
    """Resident set size of this process, in bytes."""
    try:
        import psutil
        return psutil.Process().memory_info().rss
    except ImportError:  # pragma: no cover - psutil is installed by run.sh
        return 0


def peak_rss() -> int:
    """Peak resident set size, in bytes. ru_maxrss is bytes on macOS, KiB on Linux."""
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return peak if sys.platform == "darwin" else peak * 1024


def worker_import(module: str) -> dict:
    gc.collect()
    before = rss()
    start = time.perf_counter()
    importlib.import_module(module)
    import_s = time.perf_counter() - start
    gc.collect()
    return {"import_s": import_s, "rss_import_bytes": rss() - before}


def worker_speed(module: str, quick: bool) -> dict:
    m = importlib.import_module(module)
    c = m.Counter()
    env = {"m": m, "c": c, "FLOATS": FLOATS, "BYTES": BYTES, "STRINGS": STRINGS}
    repeat = 3 if quick else 7
    speed = {}
    for label, (stmt, _) in SPEED.items():
        timer = timeit.Timer(stmt, globals=env)
        number, _ = timer.autorange()
        if not quick:
            number *= 2
        best = min(timer.repeat(repeat=repeat, number=number))
        speed[label] = best / number * 1e9  # ns per call
    return {"speed_ns": speed}


def correctness_env(m) -> dict:
    import array
    return {
        "m": m,
        "sys": sys,
        "gc": gc,
        "math": math,
        "memoryview": memoryview,
        "array": array,
    }


def expected_for(expected, backend: str):
    if isinstance(expected, dict):
        return expected.get(backend, expected.get("*"))
    return expected


def judge(want, got, exc_name) -> bool:
    """Whether a return value or a raised exception satisfies `want`."""
    options = want.options if isinstance(want, AnyOf) else (want,)
    for option in options:
        if exc_name is not None and option == exc_name:
            return True
        if exc_name is None and got == option:
            return True
    return False


def check_correctness(label: str, module: str, m, env: dict) -> str:
    stmt, expected = CORRECTNESS[label]
    want = expected_for(expected, BACKEND_BY_MODULE.get(module, module))
    if want is None or want == "n/a":
        return "n/a"
    try:
        got = eval(stmt, env)
    except Exception as exc:  # noqa: BLE001
        name = type(exc).__name__
        return "ok" if judge(want, None, name) else f"{name}: {exc}"
    return "ok" if judge(want, got, None) else f"wrong: {got!r}"


def worker_correctness(module: str) -> dict:
    m = importlib.import_module(module)
    env = correctness_env(m)
    return {"correctness": {label: check_correctness(label, module, m, env)
                            for label in CORRECTNESS}}


def worker_correctness_one(module: str, label: str) -> dict:
    m = importlib.import_module(module)
    return {"result": check_correctness(label, module, m, correctness_env(m))}


def worker_refs(module: str, label: str) -> dict:
    m = importlib.import_module(module)
    setup, target, call, loops = REFS[label]
    env = {"m": m}
    exec(setup, env)
    obj = eval(target, env)
    code = compile(call, "<bench>", "eval")
    try:
        eval(code, env)
    except Exception as exc:  # noqa: BLE001
        # The backend may not accept this argument at all (PyO3's `&[u8]` takes only
        # exact bytes). That is a semantic difference, not a reference leak.
        return {"unsupported": type(exc).__name__}
    gc.collect()
    before = sys.getrefcount(obj)
    for _ in range(loops):
        eval(code, env)
    gc.collect()
    after = sys.getrefcount(obj)
    return {"before": before, "after": after, "delta": after - before, "loops": loops}


def worker_memory(module: str, scenario: str) -> dict:
    m = importlib.import_module(module)
    stmt, loops = MEMORY[scenario]
    code = compile(stmt, "<bench>", "exec")
    env = {"m": m}
    exec(code, env)  # warm up: first-call allocations are not the scenario
    gc.collect()
    before = rss()
    for _ in range(loops):
        exec(code, env)
    gc.collect()
    first = rss()
    for _ in range(loops):
        exec(code, env)
    gc.collect()
    second = rss()
    return {
        "peak": peak_rss(),
        # What the first batch left resident: a collector's heap, or a leak.
        "kept": first - before,
        # What the identical second batch added: a plateaued heap adds nothing.
        "leak": second - first,
    }


# ------------------------------------------------------------------ parent side


def run_worker(*args: str) -> dict:
    proc = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--worker", *args],
                          capture_output=True, text=True, cwd=HERE)
    if proc.returncode != 0:
        return {"error": (proc.stderr or proc.stdout).strip()[-600:]}
    return json.loads(proc.stdout)


def run_correctness(module: str) -> dict:
    """Correctness for one backend, surviving a crash.

    The cases include hostile ones, and a binding bug can abort the process instead of
    raising. A single crashed worker would lose every row, so on a crash each case is
    re-run on its own and the one that dies is recorded rather than taking the rest.
    """
    result = run_worker(module, "correctness")
    if "correctness" in result:
        return result["correctness"]
    print("   correctness crashed, isolating each case", flush=True)
    out = {}
    for label in CORRECTNESS:
        one = run_worker(module, "correctness-one", label)
        out[label] = one["result"] if "result" in one else "crashed"
    return out


def wheel_sizes(project: Path | None) -> dict:
    if project is None:
        return {}
    wheels = sorted((project / "dist").glob("*.whl"))
    if not wheels:
        return {"error": "no wheel in dist/"}
    wheel = wheels[-1]
    with zipfile.ZipFile(wheel) as zf:
        ext = [i for i in zf.infolist() if i.filename.endswith((".so", ".pyd", ".dylib"))]
        if not ext:
            return {"wheel": wheel.stat().st_size, "error": "no extension in the wheel"}
        info = ext[0]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(zf.extract(info, tmp))
            stripped = None
            if shutil.which("strip"):
                # `-x` drops local symbols only: what every tool's own strip option does
                # for a shared object, which must keep its exported init symbol.
                if subprocess.run(["strip", "-x", str(path)], capture_output=True).returncode == 0:
                    stripped = path.stat().st_size
    return {
        "wheel_file": wheel.name,
        "wheel": wheel.stat().st_size,
        "extension": info.file_size,
        "extension_stripped": stripped,
        "files_in_wheel": len(zipfile.ZipFile(wheel).namelist()),
    }


def kib(n) -> str:
    return "—" if n is None else f"{n / 1024:,.0f} KiB"


def mib(n) -> str:
    return "—" if n is None else f"{n / 1024 / 1024:,.1f} MiB"


def fmt_ns(ns: float) -> str:
    if ns < 1_000:
        return f"{ns:,.0f} ns"
    if ns < 1_000_000:
        return f"{ns / 1_000:,.1f} µs"
    return f"{ns / 1_000_000:,.2f} ms"


def render(results: dict) -> str:
    names = list(results["backends"])
    native = [n for n in names if n != "python"]
    out = []
    env = results["environment"]
    out.append(f"Python {env['python']} · {env['machine']} · {env['platform']}\n")

    out.append("### Package size\n")
    out.append("| | " + " | ".join(native) + " |")
    out.append("|---" * (len(native) + 1) + "|")
    for key, label in [("wheel", "wheel"), ("extension", "extension (as built)"),
                       ("extension_stripped", "extension (strip -x)"),
                       ("files_in_wheel", "files in wheel")]:
        row = []
        for n in native:
            v = results["backends"][n]["sizes"].get(key)
            row.append(str(v) if key == "files_in_wheel" else kib(v))
        out.append(f"| {label} | " + " | ".join(row) + " |")
    if any("build_s" in results["backends"][n] for n in native):
        row = [f"{results['backends'][n].get('build_s', 0):.1f} s" for n in native]
        out.append("| clean release build | " + " | ".join(row) + " |")

    out.append("\n### Speed (time per call, lower is better; best of repeats)\n")
    out.append("| workload | measures | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 2) + "|")
    for label, (_, what) in SPEED.items():
        cells = []
        values = {n: results["backends"][n]["speed"].get("speed_ns", {}).get(label) for n in names}
        best = min((v for n, v in values.items() if v is not None and n != "python"), default=None)
        for n in names:
            v = values[n]
            if v is None:
                cells.append("—")
                continue
            cell = fmt_ns(v)
            if n != "python" and best is not None:
                cell += " **(best)**" if v == best else f" ({v / best:.2f}×)"
            cells.append(cell)
        out.append(f"| {label} | {what} | " + " | ".join(cells) + " |")

    out.append("\n### Memory\n")
    out.append("| | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 1) + "|")
    row = [kib(results["backends"][n]["import"].get("rss_bytes")) for n in names]
    out.append("| RSS added by `import` | " + " | ".join(row) + " |")
    row = [f"{results['backends'][n]['import'].get('warm_s', 0) * 1000:.2f} ms" for n in names]
    out.append("| import time (warm, median) | " + " | ".join(row) + " |")
    row = [f"{results['backends'][n]['import'].get('first_s', 0) * 1000:.2f} ms" for n in names]
    out.append("| import time (first after install) | " + " | ".join(row) + " |")
    out.append("\nEach scenario runs twice in a fresh process. *Peak* is the process's maximum")
    out.append("RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*")
    out.append("is what the identical second batch added on top, which is ~0 for a heap that")
    out.append("has plateaued.\n")
    out.append("| scenario | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 1) + "|")
    for label in MEMORY:
        row = []
        for n in names:
            r = results["backends"][n]["memory"].get(label, {})
            if "error" in r:
                row.append("error")
            else:
                row.append(f"{mib(r.get('peak'))} peak · {mib(r.get('kept'))} kept · "
                           f"{mib(r.get('leak'))} leak")
        out.append(f"| {label} | " + " | ".join(row) + " |")

    out.append("\n### Reference retention\n")
    out.append("Each probe calls the same borrowed argument many times in one process and")
    out.append("reports the change in `sys.getrefcount` of the argument (or of an item it")
    out.append("was handed). **0 is correct**; a positive number is one leaked reference per")
    out.append("call, which a heap that has plateaued hides from the memory table.\n")
    out.append("| probe | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 1) + "|")
    for label in REFS:
        row = []
        for n in names:
            r = results["backends"][n].get("refs", {}).get(label, {})
            if "error" in r:
                row.append("error")
            elif "unsupported" in r:
                row.append("unsupported")
            elif "delta" not in r:
                row.append("—")
            else:
                mark = "**0**" if r["delta"] == 0 else f"**+{r['delta']}**"
                row.append(f"{mark} ({r.get('before')}→{r.get('after')})")
        out.append(f"| {label} | " + " | ".join(row) + " |")

    out.append("\n### Correctness\n")
    out.append("| check | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 1) + "|")
    for label in CORRECTNESS:
        row = [results["backends"][n].get("correctness", {}).get(label, "—") for n in names]
        out.append(f"| {label} | " + " | ".join(c if c in ("ok", "n/a", "—") else f"`{c}`"
                                                 for c in row) + " |")
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", nargs="+")
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--only", nargs="+", choices=list(BACKENDS))
    parser.add_argument("--build-times", type=Path,
                        help="JSON of {backend: seconds} written by run.sh")
    args = parser.parse_args()

    if args.worker:
        module, mode, *rest = args.worker
        sys.path.insert(0, str(HERE))
        if mode == "import":
            result = worker_import(module)
        elif mode == "speed":
            result = worker_speed(module, quick=bool(rest and rest[0] == "quick"))
        elif mode == "correctness":
            result = worker_correctness(module)
        elif mode == "correctness-one":
            result = worker_correctness_one(module, rest[0])
        elif mode == "refs":
            result = worker_refs(module, rest[0])
        else:
            result = worker_memory(module, rest[0])
        print(json.dumps(result))
        return 0

    build_times = json.loads(args.build_times.read_text()) if args.build_times else {}
    results = {
        "environment": {
            "python": platform.python_version(),
            "machine": platform.machine(),
            "platform": platform.platform(),
        },
        "backends": {},
    }
    for name, (module, project) in BACKENDS.items():
        if args.only and name not in args.only:
            continue
        print(f"== {name}", flush=True)
        entry = {"sizes": wheel_sizes(project)}
        if name in build_times:
            entry["build_s"] = build_times[name]
        # The first import of a freshly installed extension pays for the OS checking
        # the new binary (macOS verifies its signature once), so it is reported apart
        # and the warm figure is the median of the rest.
        imports = [run_worker(module, "import") for _ in range(IMPORT_RUNS)]
        warm = sorted(imports[1:], key=lambda r: r.get("import_s", 0))
        entry["import"] = {
            "first_s": imports[0].get("import_s"),
            "warm_s": warm[len(warm) // 2].get("import_s"),
            "rss_bytes": warm[len(warm) // 2].get("rss_import_bytes"),
        }
        entry["speed"] = run_worker(module, "speed", "quick" if args.quick else "full")
        if "error" in entry["speed"]:
            print(entry["speed"]["error"], file=sys.stderr)
        print("   correctness", flush=True)
        entry["correctness"] = run_correctness(module)
        entry["refs"] = {}
        for label in REFS:
            print(f"   refs: {label}", flush=True)
            entry["refs"][label] = run_worker(module, "refs", label)
        entry["memory"] = {}
        for scenario in MEMORY:
            print(f"   memory: {scenario}", flush=True)
            entry["memory"][scenario] = run_worker(module, "memory", scenario)
        results["backends"][name] = entry

    (HERE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    table = render(results)
    (HERE / "results.md").write_text(table)
    print()
    print(table)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
