#!/usr/bin/env python3
"""Compares PyO3, vcraft and zig-maturin on the same nine workloads.

Every backend is measured in fresh subprocesses so that one backend's allocator,
garbage collector or imported runtime never shows up in another's numbers: one
process for speed, and one process per memory scenario.

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

FLOATS = [i * 0.5 for i in range(100_000)]
BYTES = bytes(range(256)) * 400

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
    "expect_positive(err)": (
        "try:\n    m.expect_positive(-1)\nexcept ValueError:\n    pass",
        "raise + catch per call",
    ),
    "Counter()": ("m.Counter()", "object construction"),
    "c.increment()": ("c.increment()", "method call"),
}

# label -> (statement run `loops` times, loops). Each runs in its own process.
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
    "Counter() x1M": ("m.Counter()", 1_000_000),
}

# label -> (statement, expected). Exceptions are recorded, not raised.
CORRECTNESS = {
    "add small": ("m.add(2, 3)", 5),
    "add 2**40": ("m.add(2**40, 1)", 2**40 + 1),
    "fib(20)": ("m.fib(20)", 6765),
    "count_primes(100)": ("m.count_primes(100)", 25),
    "sum_floats": ("m.sum_floats([1.5, 2.5])", 4.0),
    "make_range(3)": ("m.make_range(3)", [0, 1, 2]),
    "greet unicode": ("m.greet('España')", "Hello, España!"),
    "checksum 3 bytes": ("m.checksum(b'\\x01\\x02\\xff')", 258),
    "expect_positive ok": ("m.expect_positive(41)", 41),
    "expect_positive raises": ("m.expect_positive(-1)", "ValueError"),
    "add 2**63 overflows": ("m.add(2**63, 0)", "OverflowError"),
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
    correctness = {}
    for label, (stmt, expected) in CORRECTNESS.items():
        if module == "pure_python" and expected == "OverflowError":
            correctness[label] = "n/a"
            continue
        try:
            got = eval(stmt, {"m": m})
            ok = got == expected
            correctness[label] = "ok" if ok else f"wrong: {got!r}"
        except Exception as exc:  # noqa: BLE001
            name = type(exc).__name__
            correctness[label] = "ok" if name == expected else f"{name}: {exc}"

    c = m.Counter()
    env = {"m": m, "c": c, "FLOATS": FLOATS, "BYTES": BYTES}
    repeat = 3 if quick else 7
    speed = {}
    for label, (stmt, _) in SPEED.items():
        timer = timeit.Timer(stmt, globals=env)
        number, _ = timer.autorange()
        if not quick:
            number *= 2
        best = min(timer.repeat(repeat=repeat, number=number))
        speed[label] = best / number * 1e9  # ns per call

    return {"correctness": correctness, "speed_ns": speed}


def worker_memory(module: str, scenario: str) -> dict:
    m = importlib.import_module(module)
    stmt, loops = MEMORY[scenario]
    code = compile(stmt, "<bench>", "eval")
    env = {"m": m}
    eval(code, env)  # warm up: first-call allocations are not the scenario
    gc.collect()
    before = rss()
    for _ in range(loops):
        eval(code, env)
    gc.collect()
    first = rss()
    for _ in range(loops):
        eval(code, env)
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

    out.append("\n### Correctness\n")
    out.append("| check | " + " | ".join(names) + " |")
    out.append("|---" * (len(names) + 1) + "|")
    for label in CORRECTNESS:
        row = [results["backends"][n]["speed"].get("correctness", {}).get(label, "—")
               for n in names]
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
