#!/usr/bin/env python3
"""Time what a new user goes through: from `pip install vcraft` to `import`.

In a fresh virtualenv and an empty VCRAFT_HOME (nothing cached), it installs vcraft, runs
`vcraft toolchain install`, `vcraft new`, `vcraft develop` and imports the result, and
prints each step's time. The toolchain step is the one that matters: with a prebuilt V
published for the platform it is a download of seconds, without one it is a compiler
build of minutes.

    python3 scripts/check-first-run.py             # the vcraft built from this tree
    python3 scripts/check-first-run.py --pypi      # the released vcraft from PyPI
    python3 scripts/check-first-run.py --budget 120

`--budget` fails the run when the whole path takes longer than that many seconds.
Everything happens under a temporary directory, removed afterwards.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import venv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def platform_tag() -> str:
    machine = platform.machine().lower()
    if sys.platform.startswith("linux"):
        return f"linux_{'aarch64' if machine in ('arm64', 'aarch64') else 'x86_64'}"
    if sys.platform == "darwin":
        return "macosx_11_0_arm64" if machine == "arm64" else "macosx_10_13_x86_64"
    return "win_amd64"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pypi", action="store_true", help="install the released vcraft")
    parser.add_argument("--budget", type=float, default=0, help="fail above this many seconds")
    args = parser.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="vcraft-first-run-"))
    steps: list[tuple[str, float]] = []
    env = dict(os.environ, VCRAFT_HOME=str(tmp / "home"))
    env.pop("VCRAFT_BIN", None)
    try:
        env_dir = tmp / "venv"
        venv.EnvBuilder(with_pip=True).create(env_dir)
        bindir = env_dir / ("Scripts" if os.name == "nt" else "bin")
        python = bindir / ("python.exe" if os.name == "nt" else "python")
        env["VIRTUAL_ENV"] = str(env_dir)
        env["PATH"] = str(bindir) + os.pathsep + env["PATH"]

        def step(label: str, command: list[str], cwd: Path = tmp) -> None:
            start = time.perf_counter()
            proc = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
            elapsed = time.perf_counter() - start
            steps.append((label, elapsed))
            print(f"  {elapsed:7.1f} s  {label}", flush=True)
            if proc.returncode != 0:
                raise SystemExit(f"{label} failed:\n{(proc.stderr or proc.stdout)[-1500:]}")

        if args.pypi:
            target = ["vcraft"]
        else:
            subprocess.run([str(ROOT / "scripts" / "build-vcraft.sh")], check=True,
                           capture_output=True)
            spec = importlib.util.spec_from_file_location("pack", ROOT / "scripts" / "pack-vcraft-wheel.py")
            version = subprocess.run([str(ROOT / "bin" / "vcraft"), "version"],
                                     capture_output=True, text=True).stdout.strip()
            subprocess.run([sys.executable, str(ROOT / "scripts" / "pack-vcraft-wheel.py"),
                            "--version", version, "--platform", platform_tag(),
                            "--bin", str(ROOT / "bin" / "vcraft"), "--vlib", str(ROOT / "vlib"),
                            "--out-dir", str(tmp / "wheel")], check=True, capture_output=True)
            target = [str(next((tmp / "wheel").glob("vcraft-*.whl")))]
            del spec
        vcraft = str(bindir / ("vcraft.exe" if os.name == "nt" else "vcraft"))
        step("pip install vcraft", [str(python), "-m", "pip", "install", "-q", *target])
        step("vcraft toolchain install", [vcraft, "toolchain", "install"])
        step("vcraft new firstrun", [vcraft, "new", "firstrun"])
        step("vcraft develop", [vcraft, "develop"], cwd=tmp / "firstrun")
        step("python -c 'import firstrun'", [str(python), "-c",
                                              "import firstrun; assert firstrun.add(2, 3) == 5"])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    total = sum(t for _, t in steps)
    print(f"  {total:7.1f} s  total, from nothing to a working import")
    if args.budget and total > args.budget:
        print(f"over budget: {total:.1f} s > {args.budget:.0f} s")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
