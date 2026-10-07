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
import re
import shutil
import stat
import subprocess
import sys
import sysconfig
import tempfile
import venv
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

# The tag of the machine running the suite, e.g. `linux_x86_64` or
# `macosx_11_0_arm64`. pip refuses a wheel tagged for another platform, so a
# hard-coded Linux tag fails the install step on every other host.
PLATFORM = sysconfig.get_platform().replace("-", "_").replace(".", "_")


class _Abort(Exception):
    """Stops the suite after a failure the remaining checks depend on."""


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
        wheel.write_bytes(packer.build_wheel("0.1.0", PLATFORM,
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
            t.check("metadata names the oldest supported Python",
                    "Requires-Python: >=3.11" in meta, meta[:200])
            # PyPI renders the description from the METADATA body; without a
            # content type it shows the Markdown source as plain text, and with
            # no body at all the project page is empty.
            head, _, body = meta.partition("\n\n")
            t.check("the README is the description, as Markdown",
                    "Description-Content-Type: text/markdown" in head
                    and body.startswith("# vcraft"), head[-200:])
            t.check("the description has no repository-relative links",
                    not re.search(r"\]\((?!https?://|mailto:|#)", body),
                    str(re.findall(r"\]\((?!https?://|mailto:|#)[^)]*\)", body)[:3]))
            t.check("the licence is declared and shipped",
                    "License-Expression: MIT" in head
                    and "vcraft-0.1.0.dist-info/licenses/LICENSE" in names, head[:400])
            t.check("the project links to its repository and changelog",
                    "Project-URL: Source, https://github.com/" in head
                    and "Project-URL: Changelog," in head, head[:600])
            # PyPI rejects the whole upload on one unknown classifier, so they are
            # checked against the canonical list when it is installed.
            try:
                from trove_classifiers import classifiers as known
            except ImportError:
                print("  skip no trove-classifiers to validate against")
            else:
                listed = [line.split(": ", 1)[1] for line in head.splitlines()
                          if line.startswith("Classifier: ")]
                unknown = [c for c in listed if c not in known]
                t.check("every classifier is one PyPI accepts", not unknown, str(unknown))
            tag = z.read("vcraft-0.1.0.dist-info/WHEEL").decode()
            t.check("the wheel tag names the platform",
                    f"Tag: py3-none-{PLATFORM}" in tag, tag)
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
        again = packer.build_wheel("0.1.0", PLATFORM, binary, vlib)
        t.check("the same inputs give the same bytes",
                again == wheel.read_bytes())

        print("launcher")
        # Installed with pip into a venv, like every other suite does: stdlib
        # `extractall` no longer restores permission bits on 3.14, so only a
        # real installer proves the installed binary executes.
        venv_dir = tmp / "venv"
        venv.EnvBuilder(with_pip=True, clear=True).create(venv_dir)
        vpython = venv_dir / "bin" / "python"
        named = out / f"vcraft-0.1.0-py3-none-{PLATFORM}.whl"
        wheel.rename(named)
        wheel = named
        proc = subprocess.run(
            [str(vpython), "-m", "pip", "install", "--no-index",
             "--no-deps", str(wheel)],
            capture_output=True, text=True)
        installed = proc.returncode == 0
        t.check("pip installs the tool wheel", installed,
                (proc.stderr or proc.stdout).strip()[-300:])
        if not installed:
            # Everything below runs the installed launcher; without it each
            # step would crash rather than report.
            raise _Abort
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
            real = packer.build_wheel("0.1.0", PLATFORM,
                                      real_bin, real_vlib)
            real_wheel = out / f"vcraft-0.1.0-py3-none-{PLATFORM}.whl"
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
    except _Abort:
        print("  skip the remaining checks need the installed launcher")
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
