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
# The version the real binary reports: the one env.v stamps, not this fixture's.
STAMPED = re.search(r"pub const version = '([^']+)'",
                    (ROOT / "vlib" / "vcraft_project" / "env.v").read_text()).group(1)

PLATFORM = sysconfig.get_platform().replace("-", "_").replace(".", "_")

sys.path.insert(0, str(ROOT / "tests"))
import vcraft_build  # noqa: E402

WINDOWS = vcraft_build.WINDOWS
# The name the packer gives the binary for this host's platform tag: `vcraft.exe`
# on Windows, the bare name everywhere else.
BIN_NAME = "vcraft.exe" if PLATFORM.startswith("win") else "vcraft"


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
    # A dylib next to the binary, like the `libgc.dylib` the macOS release ships: the
    # packer has to carry it so the wheel is self-contained.
    (bindir / "libgc.dylib").write_bytes(b"fake-dylib")
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
                    f"vcraft_tool/bin/{BIN_NAME}" in names, str(names[:6]))
            t.check("a dylib next to the binary ships",
                    "vcraft_tool/bin/libgc.dylib" in names, str(names[:8]))
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
            # Dot-directories survive the rewrite: `.github/...` is not `./github`.
            t.check("dot-directory links keep their dot",
                    packer.pypi_readme("[w](.github/workflows) [l](./LICENSE)", "9.9.9")
                    == "[w](https://github.com/rroblf01/vcraft/blob/vcraft/v9.9.9/.github/workflows) "
                    "[l](https://github.com/rroblf01/vcraft/blob/vcraft/v9.9.9/LICENSE)",
                    packer.pypi_readme("[w](.github/workflows) [l](./LICENSE)", "9.9.9"))
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
            info = z.getinfo(f"vcraft_tool/bin/{BIN_NAME}")
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

        print("a Windows wheel")
        win_wheel = out / "win.whl"
        win_wheel.write_bytes(packer.build_wheel("0.1.0", "win_amd64", binary, vlib))
        with zipfile.ZipFile(win_wheel) as z:
            names = z.namelist()
            # Windows loads `vcraft.exe`; a wheel that shipped the bare name would
            # install and then fail to find its own binary.
            t.check("the Windows binary is vcraft.exe",
                    "vcraft_tool/bin/vcraft.exe" in names
                    and "vcraft_tool/bin/vcraft" not in names,
                    str([n for n in names if "/bin/" in n]))
            t.check("the Windows wheel tag names win_amd64",
                    "Tag: py3-none-win_amd64" in z.read(
                        "vcraft-0.1.0.dist-info/WHEEL").decode(),
                    z.read("vcraft-0.1.0.dist-info/WHEEL").decode())

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
        vpython = vcraft_build.venv_python(venv_dir)
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
        if WINDOWS:
            # The stub is a POSIX shell script, which Windows cannot exec, and there
            # is no shell-script spelling of it to use: the installed-launcher path
            # is checked against the real binary below instead.
            print("  skip the stub launcher needs a shell to run")
        else:
            proc = subprocess.run(
                [str(vcraft_build.venv_scripts(venv_dir) / BIN_NAME), "new", "demo"],
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
        real_bin = vcraft_build.VCRAFT
        real_vlib = ROOT / "vlib"
        if WINDOWS:
            # The stub above could not run, so build the real binary and let this
            # section exercise the installed launcher on Windows too.
            vcraft_build.build_vcraft()
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
                        f"vcraft_tool/bin/{BIN_NAME}" in names)
            proc = subprocess.run(
                [str(vpython), "-m", "pip", "install", "--no-index",
                 "--no-deps", "--force-reinstall", str(real_wheel)],
                capture_output=True, text=True)
            t.check("pip installs the real wheel", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-300:])
            proc = subprocess.run(
                [str(vcraft_build.venv_scripts(venv_dir) / BIN_NAME), "version"],
                capture_output=True, text=True)
            t.check("the installed console script runs the real binary",
                    proc.returncode == 0 and proc.stdout.strip() == STAMPED,
                    (proc.stderr or proc.stdout).strip()[-200:])
            # The path the published action takes: `pip install vcraft`, then its console
            # script builds a project. The cli suite runs `bin/vcraft` itself, so it never
            # covers the wheel's launcher, which is where a Windows-only failure hides --
            # a launcher that starts the binary but where the build writes no wheel.
            tool = str(vcraft_build.venv_scripts(venv_dir) / BIN_NAME)
            scaffolds = tmp / "installed-scaffold"
            scaffolds.mkdir()
            proc = subprocess.run([tool, "new", "demo"], cwd=scaffolds,
                                  capture_output=True, text=True)
            t.check("the installed tool scaffolds a project", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-300:])
            project = scaffolds / "demo"
            proc = subprocess.run([tool, "build", "--abi3", "3.11"], cwd=project,
                                  capture_output=True, text=True)
            t.check("the installed tool builds an abi3 project", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-400:])
            produced = list((project / "dist").glob("*.whl"))
            t.check("the installed tool wrote a wheel", len(produced) == 1,
                    str([p.name for p in (project / "dist").glob("*")]))
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
