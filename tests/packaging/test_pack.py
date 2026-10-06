#!/usr/bin/env python3
"""Tests for the pip-installable vcraft wheel packer.

Loads `scripts/pack-vcraft-wheel.py` as a module and checks the wheel it
assembles: layout, metadata, hashes, the executable bit, determinism, and --
through a fake binary -- the launcher end to end. Nothing here needs the
network: even the launcher runs against a shell script standing in for the
real binary.
"""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import venv
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def load_packer():
    path = ROOT / "scripts" / "pack-vcraft-wheel.py"
    spec = importlib.util.spec_from_file_location("pack_vcraft_wheel", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def make_fixture(tmp: Path) -> tuple[Path, Path]:
    """A fake binary (a shell script echoing its arguments) and a tiny vlib."""
    bindir = tmp / "fakebin"
    bindir.mkdir()
    binary = bindir / "vcraft"
    binary.write_text('#!/bin/sh\necho "vcraft-stub $@"\n')
    binary.chmod(0o755)
    vlib = tmp / "fakelib"
    (vlib / "vcraft").mkdir(parents=True)
    (vlib / "vcraft" / "env.v").write_text("module vcraft\n")
    (vlib / "vcraft_project").mkdir()
    (vlib / "vcraft_project" / "env.v").write_text("module vcraft_project\n")
    return binary, vlib


def record_map(wheel: Path) -> dict[str, tuple[str, str]]:
    with zipfile.ZipFile(wheel) as z:
        rows = {}
        for line in z.read(
                next(n for n in z.namelist() if n.endswith("RECORD"))
        ).decode().splitlines():
            path, digest, size = line.split(",")
            rows[path] = (digest, size)
        return rows


def main() -> int:
    packer = load_packer()
    t = Suite()

    print("layout")
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-pack-"))
    try:
        binary, vlib = make_fixture(tmp)
        out = tmp / "dist"
        out.mkdir()
        wheel = out / "w.whl"
        wheel.write_bytes(packer.build_wheel("0.1.0", "linux_x86_64",
                                             binary, vlib))
        with zipfile.ZipFile(wheel) as z:
            names = z.namelist()
            t.check("launcher files are present",
                    all(n in names for n in [
                        "vcraft_tool/__init__.py",
                        "vcraft_tool/__main__.py",
                        "vcraft_tool/_launch.py",
                    ]), str(names[:6]))
            t.check("the binary ships",
                    "vcraft_tool/bin/vcraft" in names, str(names[:6]))
            t.check("vlib ships",
                    "vcraft_tool/vlib/vcraft/env.v" in names
                    and "vcraft_tool/vlib/vcraft_project/env.v" in names,
                    str([n for n in names if "/vlib/" in n]))
            t.check("no sdist layout",
                    not any(n.endswith((".tar.gz", "PKG-INFO")) for n in names),
                    str(names))
            meta = z.read("vcraft-0.1.0.dist-info/METADATA").decode()
            t.check("metadata names the version",
                    "Name: vcraft" in meta and "Version: 0.1.0" in meta,
                    meta[:120])
            tag = z.read("vcraft-0.1.0.dist-info/WHEEL").decode()
            t.check("the wheel tag names the platform",
                    "Tag: py3-none-linux_x86_64" in tag, tag)
            entry_points = z.read(
                "vcraft-0.1.0.dist-info/entry_points.txt").decode()
            t.check("a console script is declared",
                    entry_points == "[console_scripts]\n"
                    "vcraft = vcraft_tool._launch:main\n",
                    entry_points)
            init = z.read("vcraft_tool/__init__.py").decode()
            t.check("the version is stamped",
                    '__version__ = "0.1.0"' in init, init)
            info = z.getinfo("vcraft_tool/bin/vcraft")
            # The full mode, file-type bits included: the 0o7777 mask most
            # examples use drops exactly the bits this check is about.
            mode = info.external_attr >> 16
            t.check("the binary stays executable",
                    mode & 0o777 == 0o755, oct(mode))
            # pip only honours the bit when the file-type bits say regular
            # file: bare `0o755` is ignored and the install comes out 0o644.
            import stat
            t.check("the entry is a regular file",
                    stat.S_ISREG(mode), oct(mode))

        print("record")
        rows = record_map(wheel)
        with zipfile.ZipFile(wheel) as z:
            names = z.namelist()
            t.check("every file is listed", set(rows) == set(names),
                    f"{len(rows)} rows for {len(names)} files")
            ok = True
            for path, (digest, size) in rows.items():
                if path.endswith("RECORD"):
                    ok = ok and digest == "" and size == ""
                    continue
                data = z.read(path)
                want = "sha256=" + base64.urlsafe_b64encode(
                    hashlib.sha256(data).digest()).rstrip(b"=").decode()
                ok = ok and digest == want and size == str(len(data))
            t.check("hashes and sizes verify", ok)

        print("determinism")
        again = packer.build_wheel("0.1.0", "linux_x86_64", binary, vlib)
        t.check("the same inputs give the same bytes",
                again == wheel.read_bytes())

        print("launcher")
        # Installed with pip into a venv, like every other suite does: stdlib
        # `extractall` no longer restores permission bits on 3.14, so only a
        # real installer proves the installed binary executes.
        venv_dir = tmp / "venv"
        venv.EnvBuilder(with_pip=True, clear=True).create(venv_dir)
        vpython = venv_dir / "bin" / "python"
        named = out / "vcraft-0.1.0-py3-none-linux_x86_64.whl"
        wheel.rename(named)
        wheel = named
        proc = subprocess.run(
            [str(vpython), "-m", "pip", "install", "--no-index",
             "--no-deps", str(wheel)],
            capture_output=True, text=True)
        t.check("pip installs the tool wheel", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        proc = subprocess.run(
            [str(venv_dir / "bin" / "vcraft"), "new", "demo"],
            capture_output=True, text=True)
        t.check("the console script reaches the binary", proc.returncode == 0
                and proc.stdout.strip() == "vcraft-stub new demo",
                (proc.stderr or proc.stdout).strip()[-200:])
        proc = subprocess.run(
            [str(vpython), "-m", "vcraft_tool", "new", "demo"],
            capture_output=True, text=True)
        t.check("python -m reaches the binary too", proc.returncode == 0
                and proc.stdout.strip() == "vcraft-stub new demo",
                (proc.stderr or proc.stdout).strip()[-200:])

        print("the real payload")
        real_bin = ROOT / "bin" / "vcraft"
        real_vlib = ROOT / "vlib"
        if real_bin.exists():
            real = packer.build_wheel("0.1.0", "linux_x86_64",
                                      real_bin, real_vlib)
            real_wheel = out / "vcraft-0.1.0-py3-none-linux_x86_64.whl"
            real_wheel.write_bytes(real)
            with zipfile.ZipFile(real_wheel) as z:
                names = z.namelist()
                t.check("the real vlib ships whole",
                        "vcraft_tool/vlib/vcraft_codegen/collect.v" in names
                        and "vcraft_tool/vlib/vcraft_wheel/build.v" in names)
                t.check("the real binary ships",
                        "vcraft_tool/bin/vcraft" in names)
            proc = subprocess.run(
                [str(vpython), "-m", "pip", "install", "--no-index",
                 "--no-deps", "--force-reinstall", str(real_wheel)],
                capture_output=True, text=True)
            t.check("pip installs the real wheel", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-300:])
            proc = subprocess.run(
                [str(venv_dir / "bin" / "vcraft"), "version"],
                capture_output=True, text=True)
            t.check("the installed console script runs the real binary",
                    proc.returncode == 0 and proc.stdout.strip() == "0.1.0",
                    (proc.stderr or proc.stdout).strip()[-200:])
        else:
            print("  skip no built binary for the real payload")
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
