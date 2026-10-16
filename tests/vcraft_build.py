"""Shared build helpers for the suites.

Most suites drive their prerequisites through the shell scripts in `scripts/`, which is
what a person on a POSIX host does by hand. That cannot work on Windows: a `.sh` file has
no shebang to run there, `make` does not exist, and V names its output `.exe` and its
shared objects `.dll`. So the same builds are available here in Python, where
`subprocess` hands V its arguments without a shell on any platform.

On POSIX these functions call the scripts and change nothing; only the Windows branch is
new. That keeps the one implementation the suites have always used authoritative where it
already runs, and gives Windows a path that does not go through an emulated shell.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
VLIB = ROOT / "vlib"
BUILD = ROOT / "build"

WINDOWS = os.name == "nt"
DARWIN = sysconfig.get_platform().startswith("macosx")
LINUX = not WINDOWS and not DARWIN

# V appends this to an executable's name on Windows and to nothing elsewhere, so every
# path this module hands back for a built program already carries it.
EXE = ".exe" if WINDOWS else ""

# The `vcraft` CLI this repository builds into `bin/`.
VCRAFT = ROOT / "bin" / ("vcraft.exe" if WINDOWS else "vcraft")


def v_binary() -> str:
    """The V compiler to build with: `$VCRAFT_V`, else the `v` on PATH."""
    override = os.environ.get("VCRAFT_V")
    if override:
        return override
    for name in ("v", "v.exe"):
        found = shutil.which(name)
        if found:
            return found
    raise SystemExit("the V compiler is not on PATH; put it there or set VCRAFT_V")


def _run(cmd: list[str], cwd: Path | str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([str(c) for c in cmd], cwd=str(cwd) if cwd else None,
                          capture_output=True, text=True)


def run_v(args: list[str], cwd: Path | str | None = None) -> subprocess.CompletedProcess:
    """Run V with the safety flags the wrapper script would pass.

    `-new-compiler` stops V retrying a failed C compile by bootstrapping the whole
    compiler from source, and `-no-parallel` with `VJOBS` bounds the memory a build
    holds. On POSIX the wrapper script is still what runs, so its cgroup ceiling applies
    where it can; on Windows there is no wrapper and the flags are set here.
    """
    if not WINDOWS:
        return _run([SCRIPTS / "vcraft-v.sh", *args], cwd=cwd or ROOT)
    env = dict(os.environ)
    env["VJOBS"] = os.environ.get("VCRAFT_JOBS", "2")
    env["V_MACOS_V3_NO_FALLBACK"] = "1"
    env["V_C_ERROR_BUG_REPORT_DISABLED"] = "1"
    env.pop("VEXE", None)
    cmd = [v_binary(), "-new-compiler", "-no-parallel", *[str(a) for a in args]]
    return subprocess.run(cmd, cwd=str(cwd or ROOT), env=env, capture_output=True, text=True)


def python_include() -> str:
    return sysconfig.get_paths()["include"]


def ext_suffix() -> str:
    return sysconfig.get_config_var("EXT_SUFFIX") or (".pyd" if WINDOWS else ".so")


def venv_python(venv_dir: Path) -> Path:
    """The interpreter inside a venv, in the layout the platform uses."""
    return venv_dir / ("Scripts/python.exe" if WINDOWS else "bin/python")


def venv_scripts(venv_dir: Path) -> Path:
    """The directory a venv puts console scripts in."""
    return venv_dir / ("Scripts" if WINDOWS else "bin")


def venv_platlib(venv_dir: Path) -> Path:
    """The venv's platform-specific site-packages directory.

    POSIX nests it under `lib/python<X.Y>/site-packages`; Windows puts it at
    `Lib/site-packages` with no version directory.
    """
    if WINDOWS:
        return venv_dir / "Lib" / "site-packages"
    return next((venv_dir / "lib").glob("python*/site-packages"))


def host_target() -> str:
    """The canonical `--target` name of the machine running the suite."""
    machine = platform.machine().lower()
    if sys.platform == "darwin":
        return "macos-arm64" if machine == "arm64" else "macos-x86_64"
    if WINDOWS:
        # `platform.machine()` says `AMD64`, and the target is `windows-amd64`.
        arch = "aarch64" if machine in ("aarch64", "arm64") else "amd64"
        return f"windows-{arch}"
    arch = "aarch64" if machine in ("aarch64", "arm64") else "x86_64"
    # musl on Alpine, glibc elsewhere: the libc is part of the target.
    libc = "musl" if "musl" in (sysconfig.get_config_var("HOST_GNU_TYPE") or "") else "gnu"
    return f"linux-{arch}-{libc}"


def _sanitize() -> tuple[list[str], str]:
    """The extra V flags and cflags for a sanitizer build, or nothing."""
    if not os.environ.get("VCRAFT_SANITIZE") or WINDOWS:
        return [], ""
    cflags = "-fsanitize=address,undefined -fno-omit-frame-pointer -g"
    return ["-cc", "gcc", "-ldflags", "-fsanitize=address,undefined"], cflags


def link_flags(module: str) -> list[str]:
    """Flags that let a shared object resolve the `Py*` symbols at import.

    Apple's linker refuses unresolved symbols in a shared object unless told so. Windows
    cannot resolve them at all -- a PE image's imports are fixed at link time -- so the
    interpreter's import library has to be linked in. ELF leaves them to the import, and
    a version script keeps V's runtime out of the dynamic symbol table.

    On Windows V's C compiler is MinGW gcc (the bundled TCC cannot link the MS import
    library), and a gcc-built DLL imports the MinGW runtime -- `libgcc_s_seh-1.dll`,
    `libwinpthread-1.dll`, `libssp-0.dll` -- which lives in the compiler's bin
    directory, off the loader's path when a user imports the wheel. `-static` folds
    all of it into the extension. The interpreter's import library is named by full
    path so `-static` cannot send the linker looking for a static libpython that does
    not exist; the import of `python314.dll` itself stays dynamic.
    """
    if DARWIN:
        return ["-ldflags", "-undefined dynamic_lookup"]
    if WINDOWS:
        libdir = sysconfig.get_config_var("LIBDIR") or ""
        if not libdir:
            base = sysconfig.get_config_var("installed_base") or sysconfig.base_prefix
            libdir = str(Path(base) / "libs")
        ldlib = sysconfig.get_config_var("LDLIBRARY") or "python3.dll"
        stem = os.path.splitext(ldlib)[0]
        lib = Path(libdir) / f"{stem}.lib"
        return ["-ldflags", f"-static {lib.as_posix()}"]
    if LINUX:
        BUILD.mkdir(exist_ok=True)
        exports = BUILD / f"{module}.exports"
        exports.write_text("{\n\tglobal: PyInit_%s;\n\tlocal: *;\n};\n" % module)
        return ["-ldflags", f"-Wl,--version-script={exports}"]
    return []


def _generator() -> Path:
    out = BUILD / "vc-generate"
    BUILD.mkdir(exist_ok=True)
    # `-enable-globals` because the code generator keeps the enum registry in a module
    # global.
    proc = run_v(["-enable-globals", "-o", out, "-path", f"{VLIB}|@vlib",
                  ROOT / "cmd" / "vc-generate"])
    if proc.returncode != 0:
        raise SystemExit(f"cannot build the generator:\n{proc.stdout}\n{proc.stderr}")
    return Path(str(out) + EXE)


def build_example(example: str = "hello", module: str = "hello_native") -> None:
    """Build `examples/<example>` into `<project>/python/<module><suffix>`."""
    if not WINDOWS:
        result = _run([SCRIPTS / "build-example.sh", example, module])
        if result.returncode != 0:
            raise SystemExit(f"build failed:\n{result.stdout}\n{result.stderr}")
        return
    project = ROOT / "examples" / example
    gen = _generator()
    result = _run([gen, project, module, module])
    if result.returncode != 0:
        raise SystemExit(f"the generator failed:\n{result.stdout}\n{result.stderr}")
    (project / "python").mkdir(exist_ok=True)
    suffix = ext_suffix()
    output = project / "python" / f"{module}{suffix}"
    sanitize, sanitize_cflags = _sanitize()
    proc = run_v(["-enable-globals", "-shared", "-o", output, *sanitize,
                  *link_flags(module), "-path", f"{VLIB}|@vlib",
                  "-cflags", f"-I{python_include()} {sanitize_cflags}".rstrip(), project])
    if proc.returncode != 0:
        raise SystemExit(f"build failed:\n{proc.stdout}\n{proc.stderr}")
    for appended in (".dylib", ".dll"):
        moved = Path(str(output) + appended)
        if not output.exists() and moved.exists():
            moved.replace(output)


def build_runtime() -> None:
    """Build the runtime test extension into `build/vcraft_runtime_check<suffix>`."""
    if not WINDOWS:
        result = _run([SCRIPTS / "build-runtime-tests.sh"])
        if result.returncode != 0:
            raise SystemExit(f"build failed:\n{result.stdout}\n{result.stderr}")
        return
    name = "vcraft_runtime_check"
    BUILD.mkdir(exist_ok=True)
    suffix = ext_suffix()
    output = BUILD / f"{name}{suffix}"
    sanitize, sanitize_cflags = _sanitize()
    proc = run_v(["-shared", "-o", output, *sanitize, *link_flags(name),
                  "-path", f"{VLIB}|@vlib",
                  "-cflags", f"-I{python_include()} {sanitize_cflags}".rstrip(),
                  ROOT / "tests" / "runtime"])
    if proc.returncode != 0:
        raise SystemExit(f"build failed:\n{proc.stdout}\n{proc.stderr}")
    for appended in (".dylib", ".dll"):
        moved = Path(str(output) + appended)
        if not output.exists() and moved.exists():
            moved.replace(output)


def build_vcraft() -> None:
    """Build the CLI into `bin/vcraft[.exe]`."""
    if not WINDOWS:
        result = _run([SCRIPTS / "build-vcraft.sh"])
        if result.returncode != 0 or not VCRAFT.exists():
            raise SystemExit(f"cannot build {VCRAFT}:\n{result.stdout}\n{result.stderr}")
        return
    VCRAFT.parent.mkdir(exist_ok=True)
    proc = run_v(["-enable-globals", "-o", VCRAFT, "-path", f"{VLIB}|@vlib",
                  ROOT / "cmd" / "vcraft"])
    if proc.returncode != 0 or not VCRAFT.exists():
        raise SystemExit(f"cannot build {VCRAFT}:\n{proc.stdout}\n{proc.stderr}")


def build_wheel_test(out_dir: Path | None = None) -> None:
    """Build the example and package it as a wheel with vcraft's own writer."""
    if not WINDOWS:
        result = _run([SCRIPTS / "build-wheel-test.sh"])
        if result.returncode != 0:
            raise SystemExit(f"build failed:\n{result.stdout}\n{result.stderr}")
        return
    out_dir = out_dir or BUILD
    build_example("hello", "hello_native")
    extension = ROOT / "examples" / "hello" / "python" / f"hello_native{ext_suffix()}"
    if not extension.exists():
        raise SystemExit("no extension was built")
    out_dir.mkdir(parents=True, exist_ok=True)
    program = out_dir / "build_wheel"
    proc = run_v(["-enable-globals", "-o", program, "-path", f"{VLIB}|@vlib",
                  ROOT / "tests" / "wheel"])
    if proc.returncode != 0:
        raise SystemExit(f"cannot build the wheel writer:\n{proc.stdout}\n{proc.stderr}")
    tag = subprocess.run([sys.executable, str(ROOT / "tests" / "wheel" / "wheel_tag.py")],
                         capture_output=True, text=True, check=True).stdout.strip()
    result = _run([str(program) + EXE, "--binary", extension, "--out", out_dir, "--tag", tag])
    if result.returncode != 0:
        raise SystemExit(f"the wheel writer failed:\n{result.stdout}\n{result.stderr}")


def run_script(name: str, *args: str) -> subprocess.CompletedProcess:
    """Run a `scripts/*.sh` helper, through bash where there is no shebang to honour."""
    path = SCRIPTS / name
    cmd = ["bash", str(path), *args] if WINDOWS else [str(path), *args]
    return _run(cmd)


def check_slot_ids() -> subprocess.CompletedProcess:
    """Compare vcraft's hard-coded slot ids with the installed CPython headers.

    Skipped on Windows. The driver script needs a POSIX `bash`, and the `bash` a Windows
    runner has on PATH is the WSL launcher, which has no distribution to run. The ids are
    macros with the same values on every platform, so the Linux jobs already cover them.
    """
    if WINDOWS:
        return subprocess.CompletedProcess([], 0, "skipped: no POSIX bash on this host\n", "")
    return run_script("check-slot-ids.sh")
