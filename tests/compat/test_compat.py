"""vcraft projects build with the packaging tools people already use.

A project made by `vcraft new` is built through its PEP 517 backend by each frontend
found on this machine, and every wheel is installed into a fresh virtualenv and imported:

- `pip wheel .` (pip from a fresh virtualenv);
- `python -m build` (sdist, then a wheel built from that sdist), from a uv virtualenv;
- `uv build`, when `uv` is on PATH;
- `pytest --vcraft-develop`, the plugin the vcraft wheel installs, from a uv virtualenv
  holding that wheel and pytest;
- `cibuildwheel` with the published vcraft-manylinux image, only when
  VCRAFT_TEST_CIBUILDWHEEL=1 (it pulls a container image and needs docker).

A frontend that is not available is reported as skipped, not failed. The backend finds
the vcraft under test through VCRAFT_BIN.

    python3 tests/compat/test_compat.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import venv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))

import vcraft_build  # noqa: E402

VCRAFT = vcraft_build.VCRAFT
venv_python = vcraft_build.venv_python


class Suite:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passed = 0

    def check(self, label: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"  ok   {label}")
        else:
            self.failures.append(label)
            print(f"  FAIL {label}\n{detail}")


def fresh_venv(path: Path, with_pip: bool = False) -> Path:
    venv.EnvBuilder(with_pip=with_pip, clear=True).create(path)
    return venv_python(path)


def imports(t: Suite, label: str, wheel: Path, tmp: Path) -> None:
    """Install `wheel` into a new virtualenv and import the module from it."""
    target = tmp / f"check-{label}"
    python = fresh_venv(target, with_pip=True)
    proc = subprocess.run([str(python), "-m", "pip", "install", "-q", "--no-index", str(wheel)],
                          capture_output=True, text=True)
    run = subprocess.run([str(python), "-c", "import compatpkg as m; print(m.add(2, 3))"],
                         capture_output=True, text=True, cwd=tmp)
    t.check(f"{label}: the wheel installs and imports",
            proc.returncode == 0 and run.stdout.strip() == "5",
            (proc.stderr + run.stderr).strip()[-500:])


def pytest_plugin(t: Suite, uv: str | None, tmp: Path) -> None:
    """`pytest --vcraft-develop` rebuilds a project before its tests import it.

    Runs the real plugin from the vcraft wheel, packed from this checkout, in a virtualenv
    nobody activated (`.venv/bin/python -m pytest`), which is how an IDE runs tests.
    """
    print("pytest --vcraft-develop")
    if uv is None:
        print("  skip uv is not on PATH")
        return
    platform = sysconfig.get_platform().replace("-", "_").replace(".", "_")
    dist = tmp / "tool-dist"
    subprocess.run([sys.executable, str(ROOT / "scripts" / "pack-vcraft-wheel.py"),
                    "--version", "0.0.0", "--platform", platform, "--bin", str(VCRAFT),
                    "--vlib", str(ROOT / "vlib"), "--out-dir", str(dist)],
                   check=True, capture_output=True)
    tool_wheel = next(dist.glob("vcraft-*.whl"))

    def make_venv(name: str) -> Path | None:
        target = tmp / name
        subprocess.run([uv, "venv", "-q", "--python", sys.executable, str(target)],
                       check=True, capture_output=True)
        got = subprocess.run([uv, "pip", "install", "-q", "--python", str(venv_python(target)),
                              str(tool_wheel), "pytest"], capture_output=True, text=True)
        return target if got.returncode == 0 else None

    first = make_venv("venv-pytest")
    if first is None:
        print("  skip pytest could not be installed (offline?)")
        return
    subprocess.run([str(VCRAFT), "new", "plugpkg"], cwd=tmp, check=True, capture_output=True)
    project = tmp / "plugpkg"
    source = project / "src" / "plugpkg_native.v"
    tests = project / "tests" / "test_plugpkg.py"
    env = {k: v for k, v in os.environ.items() if k != "VIRTUAL_ENV"}

    def pytest(venv_dir: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([str(venv_python(venv_dir)), "-m", "pytest", "-q", "-p",
                               "no:cacheprovider", *args, "tests"], cwd=project, env=env,
                              capture_output=True, text=True)

    def report(proc: subprocess.CompletedProcess) -> str:
        return (proc.stdout + proc.stderr).strip()[-800:]

    proc = pytest(first, "--vcraft-develop")
    t.check("the first run builds, installs and imports the project",
            proc.returncode == 0 and "4 passed" in proc.stdout, report(proc))

    source.write_text(source.read_text().replace("return a + b\n", "return a + b + 100\n"))
    tests.write_text(tests.read_text().replace("m.add(2, 3), 5)", "m.add(2, 3), 105)"))
    proc = pytest(first, "--vcraft-develop")
    t.check("a change to the V source reaches the tests", proc.returncode == 0, report(proc))

    source.write_text(source.read_text().replace("return a + b + 100\n", "return a + b\n"))
    proc = pytest(first)
    t.check("without the option nothing is rebuilt", proc.returncode == 0, report(proc))

    good = source.read_text()
    source.write_text(good + "\npub fn broken( {\n")
    proc = pytest(first, "--vcraft-develop")
    t.check("a failed build stops the run with the compiler's output",
            proc.returncode != 0 and "vcraft develop failed" in proc.stdout + proc.stderr,
            report(proc))
    source.write_text(good)

    tests.write_text(tests.read_text().replace("m.add(2, 3), 105)", "m.add(2, 3), 5)"))
    pyproject = project / "pyproject.toml"
    pyproject.write_text(pyproject.read_text() + "\n[tool.pytest.ini_options]\nvcraft_develop = true\n")
    proc = pytest(first)
    t.check("vcraft_develop = true in pyproject.toml turns it on", proc.returncode == 0,
            report(proc))

    # The sources are unchanged since the last build, so the build stamp says "up to
    # date"; a second virtualenv still has to get the install.
    second = make_venv("venv-pytest-2")
    if second is None:
        print("  skip pytest could not be installed a second time")
        return
    proc = pytest(second)
    t.check("an unchanged tree still installs into a new virtualenv", proc.returncode == 0,
            report(proc))


def main() -> int:
    vcraft_build.build_vcraft()
    t = Suite()
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-compat-"))
    env = dict(os.environ, VCRAFT_BIN=str(VCRAFT))
    env.pop("VIRTUAL_ENV", None)
    try:
        subprocess.run([str(VCRAFT), "new", "compatpkg"], cwd=tmp, check=True,
                       capture_output=True)
        project = tmp / "compatpkg"
        # The backend file is written by the first build; a fresh project has it too.
        subprocess.run([str(VCRAFT), "build", "--skip-audit"], cwd=project, check=True,
                       capture_output=True)
        shutil.rmtree(project / "dist")

        print("pip wheel")
        pip_python = fresh_venv(tmp / "venv-pip", with_pip=True)
        out = tmp / "out-pip"
        proc = subprocess.run([str(pip_python), "-m", "pip", "wheel", "-q", "--no-deps",
                               "-w", str(out), str(project)], env=env, capture_output=True,
                              text=True)
        wheels = sorted(out.glob("compatpkg-*.whl"))
        t.check("pip wheel builds the project", proc.returncode == 0 and len(wheels) == 1,
                (proc.stderr or proc.stdout).strip()[-800:])
        if wheels:
            imports(t, "pip", wheels[0], tmp)

        print("python -m build")
        uv = shutil.which("uv")
        if uv is None:
            print("  skip uv is not on PATH, so `build` cannot be installed")
        else:
            build_venv = tmp / "venv-build"
            subprocess.run([uv, "venv", "-q", "--python", sys.executable, str(build_venv)],
                           check=True, capture_output=True)
            got = subprocess.run([uv, "pip", "install", "-q", "--python",
                                  str(venv_python(build_venv)), "build"],
                                 capture_output=True, text=True)
            if got.returncode != 0:
                print("  skip `build` could not be installed (offline?)")
            else:
                out = tmp / "out-build"
                proc = subprocess.run([str(venv_python(build_venv)), "-m", "build",
                                       "--outdir", str(out), str(project)], env=env,
                                      capture_output=True, text=True)
                sdists = sorted(out.glob("compatpkg-*.tar.gz"))
                wheels = sorted(out.glob("compatpkg-*.whl"))
                t.check("python -m build writes an sdist and a wheel built from it",
                        proc.returncode == 0 and len(sdists) == 1 and len(wheels) == 1,
                        (proc.stderr or proc.stdout).strip()[-800:])
                if wheels:
                    imports(t, "build", wheels[0], tmp)

        pytest_plugin(t, uv, tmp)

        print("uv build")
        if uv is None:
            print("  skip uv is not on PATH")
        else:
            out = tmp / "out-uv"
            proc = subprocess.run([uv, "build", "--python", sys.executable, "--out-dir",
                                   str(out), str(project)], env=env, capture_output=True,
                                  text=True)
            wheels = sorted(out.glob("compatpkg-*.whl"))
            t.check("uv build writes a wheel", proc.returncode == 0 and len(wheels) == 1,
                    (proc.stderr or proc.stdout).strip()[-800:])
            if wheels:
                imports(t, "uv", wheels[0], tmp)

        print("cibuildwheel")
        if os.environ.get("VCRAFT_TEST_CIBUILDWHEEL") != "1":
            print("  skip set VCRAFT_TEST_CIBUILDWHEEL=1 (pulls a container image, needs docker)")
        elif uv is None or shutil.which("docker") is None:
            print("  skip needs uv and docker")
        else:
            cibw_venv = tmp / "venv-cibw"
            subprocess.run([uv, "venv", "-q", "--python", sys.executable, str(cibw_venv)],
                           check=True, capture_output=True)
            subprocess.run([uv, "pip", "install", "-q", "--python", str(venv_python(cibw_venv)),
                            "cibuildwheel"], check=True, capture_output=True)
            version = subprocess.run([str(VCRAFT), "version"], capture_output=True,
                                     text=True).stdout.strip()
            tag = f"cp{sys.version_info.major}{sys.version_info.minor}"
            cibw_env = dict(env, CIBW_BUILD=f"{tag}-manylinux_x86_64",
                            CIBW_MANYLINUX_X86_64_IMAGE=f"ghcr.io/rroblf01/vcraft-manylinux:{version}",
                            CIBW_ENVIRONMENT="VCRAFT_BIN=vcraft")
            cibw_env.pop("VCRAFT_BIN", None)
            out = tmp / "out-cibw"
            proc = subprocess.run([str(venv_python(cibw_venv)), "-m", "cibuildwheel",
                                   "--platform", "linux", "--output-dir", str(out),
                                   str(project)], env=cibw_env, capture_output=True, text=True)
            wheels = sorted(out.glob("compatpkg-*manylinux*.whl"))
            t.check("cibuildwheel builds a manylinux wheel with the vcraft image",
                    proc.returncode == 0 and len(wheels) == 1,
                    (proc.stderr or proc.stdout).strip()[-800:])
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
