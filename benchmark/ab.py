#!/usr/bin/env python3
"""Interleaved A/B comparison of builds of the same benchmark module.

`bench.py` measures each backend once, one after the other, so a machine that changes
state between backends (load, frequency scaling) moves the numbers by more than most
optimisations. This runs every variant in turn, round after round, and keeps the best
figure each variant reached for each workload: the variants share the same windows of
machine state, and noise only ever makes a run slower.

    python ab.py pyo3=.venv-pyo3/bin/python:bench_pyo3 \\
                 base=.venv-base/bin/python:bench_vcraft_native \\
                 new=.venv-new/bin/python:bench_vcraft_native \\
                 [--rounds 5] [--only 'Counter()' 'list(Countdown())'] [--import-runs 20]
                 [--memory]

Each variant is `label=python:module`. The first variant is the reference the ratios
are against; the last two are compared with each other as well.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import timeit
from pathlib import Path

HERE = Path(__file__).resolve().parent


def worker(module: str, mode: str, labels: list[str]) -> dict:
    sys.path.insert(0, str(HERE))
    import bench  # noqa: E402  (the workloads and their data live there)

    if mode == "import":
        return bench.worker_import(module)
    if mode == "memory":
        return bench.worker_memory(module, labels[0])
    import importlib

    m = importlib.import_module(module)
    env = {"m": m, "c": m.Counter(), "v": m.Vector(1000), "FLOATS": bench.FLOATS,
           "BYTES": bench.BYTES, "STRINGS": bench.STRINGS, "INTS": bench.INTS,
           "WORDS": bench.WORDS}
    out = {}
    for label, (stmt, _) in bench.SPEED.items():
        if labels and label not in labels:
            continue
        try:
            timer = timeit.Timer(stmt, globals=env)
            number, _ = timer.autorange()
            out[label] = min(timer.repeat(repeat=5, number=number)) / number * 1e9
        except (AttributeError, TypeError):
            out[label] = None
    return out


def run(python: str, *args: str) -> dict:
    proc = subprocess.run([python, str(Path(__file__).resolve()), "--worker", *args],
                          capture_output=True, text=True, cwd=HERE)
    if proc.returncode != 0:
        raise SystemExit(f"{python} {args}: {(proc.stderr or proc.stdout)[-800:]}")
    return json.loads(proc.stdout)


def fmt_ns(ns: float | None) -> str:
    if ns is None:
        return "—"
    if ns >= 1e6:
        return f"{ns / 1e6:.2f} ms"
    if ns >= 1e3:
        return f"{ns / 1e3:.1f} µs"
    return f"{ns:.0f} ns"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", nargs="+")
    parser.add_argument("variants", nargs="*")
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--only", nargs="+", default=[])
    parser.add_argument("--import-runs", type=int, default=0)
    parser.add_argument("--memory", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    if args.worker:
        module, mode, *labels = args.worker
        print(json.dumps(worker(module, mode, labels)))
        return 0

    variants = []
    for spec in args.variants:
        label, rest = spec.split("=", 1)
        python, module = rest.rsplit(":", 1)
        variants.append((label, python, module))
    names = [v[0] for v in variants]

    best: dict[str, dict[str, float]] = {n: {} for n in names}
    for r in range(args.rounds):
        print(f"round {r + 1}/{args.rounds}", file=sys.stderr, flush=True)
        # Alternate the order too, so no variant always runs first in a round.
        order = variants if r % 2 == 0 else list(reversed(variants))
        for label, python, module in order:
            for key, ns in run(python, module, "speed", *args.only).items():
                if ns is not None:
                    best[label][key] = min(ns, best[label].get(key, float("inf")))

    imports: dict[str, list[float]] = {n: [] for n in names}
    for _ in range(args.import_runs):
        for label, python, module in variants:
            imports[label].append(run(python, module, "import")["import_s"] * 1e3)

    memory: dict[str, dict] = {}
    if args.memory:
        sys.path.insert(0, str(HERE))
        import bench

        for label, python, module in variants:
            memory[label] = {scenario: run(python, module, "memory", scenario)
                             for scenario in bench.MEMORY}

    ref = names[0]
    pair = names[-2:] if len(names) >= 3 else names
    keys = list(best[names[-1]])
    head = "| workload | " + " | ".join(names) + f" | {names[-1]}/{ref} | {pair[1]}/{pair[0]} |"
    print(head)
    print("|" + "---|" * (len(names) + 3))
    for key in keys:
        vals = [best[n].get(key) for n in names]
        last = vals[-1]
        r_ref = f"{last / vals[0]:.2f}×" if vals[0] and last else "—"
        a, b = best[pair[0]].get(key), best[pair[1]].get(key)
        r_pair = f"{b / a:.2f}×" if a and b else "—"
        print(f"| {key} | " + " | ".join(fmt_ns(v) for v in vals) + f" | {r_ref} | {r_pair} |")
    if args.import_runs:
        print()
        print("| import (median ms) | " + " | ".join(
            f"{n}: {statistics.median(imports[n]):.3f}" for n in names) + " |")
    if memory:
        print()
        print("| memory scenario | " + " | ".join(names) + " |")
        print("|" + "---|" * (len(names) + 1))
        for scenario in memory[names[0]]:
            cells = []
            for n in names:
                m = memory[n][scenario]
                cells.append(f"{m['peak'] / 2**20:.1f} peak · {m['kept'] / 2**20:.1f} kept")
            print(f"| {scenario} | " + " | ".join(cells) + " |")
    if args.json:
        args.json.write_text(json.dumps({"speed": best, "import": imports,
                                         "memory": memory}, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
