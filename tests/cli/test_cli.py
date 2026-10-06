"""Checks the `vcraft` CLI end to end.

Every step runs the real binary against a real project: scaffold, build, install, use.
Nothing here stubs the compiler or the wheel writer, because the failures worth
catching are the ones where the pieces disagree, and a stubbed test cannot see that.

The install checks use a fresh virtualenv each time. Installing into the ambient
environment would make the suite depend on what else is installed, which is the same
class of mistake `vcraft develop` is written to avoid.
"""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import venv
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
VCRAFT = ROOT / "bin" / "vcraft"

# The oldest CPython vcraft supports, and so the lowest stable-ABI floor it accepts.
# The abi3 checks build at this floor so the wheel the suite installs on the running
# interpreter, whichever supported version it is, is also the widest one vcraft makes.
ABI3_FLOOR = "3.11"


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

    def equal(self, label: str, got, expected) -> None:
        self.check(label, got == expected, f"got {got!r}, want {expected!r}")


def build_binary() -> None:
    proc = subprocess.run([str(ROOT / "scripts" / "build-vcraft.sh")],
                          capture_output=True, text=True)
    if proc.returncode != 0 or not VCRAFT.exists():
        raise SystemExit(f"cannot build {VCRAFT}:\n{proc.stdout}\n{proc.stderr}")


def vcraft(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run([str(VCRAFT), *args], cwd=cwd, capture_output=True, text=True)


def host_target() -> str:
    """The canonical `--target` name of the machine running the suite."""
    machine = platform.machine().lower()
    if sys.platform == "darwin":
        return "macos-arm64" if machine == "arm64" else "macos-x86_64"
    arch = "aarch64" if machine in ("aarch64", "arm64") else "x86_64"
    return f"linux-{arch}-gnu"


def make_venv(path: Path, with_pip: bool = False) -> Path:
    # `with_pip` is off by default because a venv with pip takes several seconds and
    # `develop` only needs an interpreter. The one check that installs a wheel turns it
    # on for that venv alone.
    venv.EnvBuilder(with_pip=with_pip, clear=True).create(path)
    return path


def main() -> int:
    build_binary()
    t = Suite()

    print("binary")
    t.check("the binary exists", VCRAFT.exists(), str(VCRAFT))
    proc = vcraft("version", cwd=ROOT)
    t.check("version", proc.returncode == 0 and proc.stdout.strip() != "",
            proc.stderr.strip())
    proc = vcraft("help", cwd=ROOT)
    t.check("help", proc.returncode == 0 and "vcraft new" in proc.stdout)
    proc = vcraft("nonsense", cwd=ROOT)
    t.check("an unknown command fails", proc.returncode != 0)
    t.check("an unknown command explains itself", "unknown command" in proc.stderr,
            proc.stderr.strip())

    # Resolved, because on macOS the temporary directory is under `/var`, a symlink to
    # `/private/var`, and vcraft writes the physical path the working directory reports.
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-cli-")).resolve()
    try:
        print("new")
        proc = vcraft("new", "mypkg", cwd=tmp)
        t.check("new succeeds", proc.returncode == 0, proc.stderr.strip())
        project = tmp / "mypkg"
        t.check("vcraft.toml", (project / "vcraft.toml").exists())
        t.check("v.mod", (project / "v.mod").exists())
        t.check("the V source", (project / "src" / "mypkg_native.v").exists())
        t.check("the README", (project / "README.md").exists())
        t.check(".gitignore", (project / ".gitignore").exists())
        t.check("editable build output is ignored",
                "/.vcraft/" in (project / ".gitignore").read_text(),
                (project / ".gitignore").read_text())
        t.check("no glue is scaffolded",
                not (project / "src" / "_vcraft_generated.v").exists(),
                "the glue is regenerated on every build and would go stale")

        toml = (project / "vcraft.toml").read_text()
        t.check("the manifest names the package", 'name = "mypkg"' in toml, toml)
        t.check("the manifest names the module", 'module = "mypkg_native"' in toml)
        t.check("the manifest has classifiers", "[[classifier]]" in toml)
        t.check("the manifest has a minimum version", "minimum-version" in toml)

        vmod = (project / "v.mod").read_text()
        t.check("v.mod declares base_url", 'base_url: "src"' in vmod, vmod)
        t.check("v.mod requires vcraft", 'requires: ["vcraft"]' in vmod, vmod)
        t.check("v.mod names the V module", '"mypkg_native"' in vmod, vmod)

        proc = vcraft("new", "mypkg", cwd=tmp)
        t.check("new refuses to overwrite", proc.returncode != 0, proc.stdout)
        t.check("and says why", "already exists" in proc.stderr, proc.stderr.strip())

        # Inheritance, on a project of its own: a chain three deep, declared
        # subclass-first, which is the order that breaks anything relying on declaration
        # order, and the diagnostics for the ways `@[vc_base]` can be wrong.
        inh = tmp / "inh"
        (inh / "src").mkdir(parents=True)
        (inh / "v.mod").write_text(
            'Module {\n\tname: "inh_native"\n\tbase_url: "src"\n'
            '\trequires: ["vcraft"]\n}\n')
        (inh / "vcraft.toml").write_text(
            '[package]\nname = "inh"\nversion = "0.1.0"\n'
            'description = "inheritance"\n\n[build]\nmodule = "inh_native"\n'
            'source = "src"\noutput = "python"\n')
        source = inh / "src" / "inh_native.v"

        def chain_source(extra: str = "") -> str:
            return (
                "module inh_native\n\nimport vcraft\n\n"
                "@[vc_class]\n@[vc_base(Mid)]\npub struct Grandchild {\nmut:\n"
                "\t@[vc_field] depth int\n}\n\n"
                "@[vc_class]\n@[vc_base(Root)]\npub struct Mid {\nmut:\n"
                "\t@[vc_field] mid int\n}\n\n"
                "@[vc_class]\npub struct Root {\nmut:\n\t@[vc_field] root int\n}\n\n"
                "@[vc_fn]\npub fn new_root() &Root {\n\treturn &Root{ root: 1 }\n}\n\n"
                "@[vc_fn]\npub fn new_mid() &Mid {\n\treturn &Mid{ mid: 2 }\n}\n\n"
                "@[vc_fn]\npub fn new_grandchild() &Grandchild {\n"
                "\treturn &Grandchild{ depth: 3 }\n}\n\n"
                "@[vc_methods]\npub fn (mut g Grandchild) total() int {\n"
                "\tmut mid := unsafe { &Mid(vcraft.state_at(1)) }\n"
                "\tmut root := unsafe { &Root(vcraft.state_at(2)) }\n"
                "\treturn mid.mid + root.root\n}\n\n"
                "@[vc_methods]\npub fn (mut g Grandchild) bump_root() {\n"
                "\tmut root := unsafe { &Root(vcraft.state_at(2)) }\n"
                "\troot.root += 10\n}\n" + extra)

        print("inheritance")
        source.write_text(chain_source(), encoding="utf-8")
        proc = vcraft("build", cwd=inh)
        t.check("a chain declared subclass-first builds", proc.returncode == 0,
                proc.stderr.strip()[-500:])
        if proc.returncode == 0:
            built = sorted(inh.glob("dist/build/*.so"))
            t.check("the extension is written", len(built) == 1, built)
            if built:
                probe = subprocess.run(
                    [sys.executable, "-c",
                     "import sys\n"
                     "sys.path.insert(0, sys.argv[1])\n"
                     "import inh_native as m\n"
                     "g = m.Grandchild()\n"
                     "print(g.total(), g.root, g.mid, g.depth)\n"
                     "g.bump_root()\n"
                     "print(g.total(), g.root, repr(g))\n"
                     "print([t.__name__ for t in m.Grandchild.__mro__])\n",
                     str(built[0].parent)], capture_output=True, text=True)
                t.check("the chain imports and runs", probe.returncode == 0,
                        probe.stderr.strip()[-400:])
                lines = probe.stdout.splitlines()
                t.check("both generations are reachable from a method",
                        lines[:1] == ["3 1 2 3"], probe.stdout)
                t.check("a write to the root's state reaches the instance",
                        lines[1:2] == ["13 11 Grandchild(root: 11, mid: 2, depth: 3)"],
                        probe.stdout)
                t.check("the mro is the whole chain",
                        lines[2:3] == ["['Grandchild', 'Mid', 'Root', 'object']"],
                        probe.stdout)

        def diagnostic(label: str, source_text: str, needle: str) -> None:
            source.write_text(source_text, encoding="utf-8")
            out = vcraft("build", cwd=inh)
            t.check(f"{label} fails", out.returncode != 0, out.stdout[-200:])
            t.check(f"{label} says why", needle in out.stderr, out.stderr.strip()[-300:])

        diagnostic("a base that is not a class",
                   chain_source().replace("@[vc_base(Root)]", "@[vc_base(Nope)]"),
                   "is not a class in this project")
        diagnostic("two classes inheriting from each other",
                   chain_source().replace("@[vc_base(Root)]", "@[vc_base(Grandchild)]"),
                   "is a cycle")
        diagnostic("a class inheriting from itself",
                   chain_source().replace("@[vc_base(Mid)]", "@[vc_base(Grandchild)]", 1),
                   "cannot inherit from itself")
        deep = "module inh_native\n\nimport vcraft\n\n"
        for i in range(11):
            deep += "@[vc_class]\n"
            if i:
                deep += f"@[vc_base(C{i - 1})]\n"
            deep += f"pub struct C{i} {{\nmut:\n\t@[vc_field] f{i} int\n}}\n\n"
        diagnostic("a chain deeper than the runtime publishes", deep,
                   "vcraft can publish at most 8")

        print("info")
        proc = vcraft("info", cwd=project)
        t.check("info succeeds", proc.returncode == 0, proc.stderr.strip())
        # `info` prints a label and, when there is one, a value. A flag line has only
        # a label, so a split that yields one part is a flag rather than a broken line.
        info: dict[str, str] = {}
        for line in proc.stdout.splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2:
                info[parts[0]] = parts[1].strip()
        t.check("info reports the name", info.get("name", "").strip() == "mypkg",
                proc.stdout)
        t.check("info reports the module",
                info.get("module", "").strip() == "mypkg_native", proc.stdout)
        t.check("info reports the python version",
                info.get("python", "").strip().startswith("3."),
                proc.stdout)
        t.check("info reports the extension suffix",
                ".so" in info.get("extension", ""), proc.stdout)
        t.check("info reports where vlib is",
                info.get("vlib", "").strip() == str(ROOT / "vlib"), proc.stdout)

        print("targets")
        # `--target` planning is pure: it names the OS, the architecture, the tag and
        # the compiler without touching a toolchain, so every one of these runs
        # everywhere, including where the compiler for the target is not installed.
        proc = vcraft("info", "--target", "linux-aarch64-gnu", cwd=project)
        t.check("aarch64 resolves", proc.returncode == 0
                and "target-arch      aarch64" in proc.stdout
                and "platform-tag     linux_aarch64" in proc.stdout, proc.stdout)
        proc = vcraft("info", "--target", "linux-x86_64-musl", "--musllinux", "1_2",
                      cwd=project)
        t.check("a musl policy resolves", proc.returncode == 0
                and "platform-tag     musllinux_1_2_x86_64" in proc.stdout, proc.stdout)
        proc = vcraft("info", "--target", "linux-aarch64-gnu", "--manylinux", "2_17",
                      cwd=project)
        t.check("a manylinux policy resolves", proc.returncode == 0
                and "platform-tag     manylinux_2_17_aarch64" in proc.stdout, proc.stdout)
        proc = vcraft("info", "--target", "bogus", cwd=project)
        t.check("an unknown target fails", proc.returncode != 0)
        t.check("and names itself", "unknown target" in proc.stderr, proc.stderr.strip())
        proc = vcraft("info", "--target", "linux-x86_64-musl", "--manylinux", "2_17",
                      cwd=project)
        t.check("manylinux on musl fails", proc.returncode != 0)
        t.check("and says why", "needs a gnu target" in proc.stderr,
                proc.stderr.strip())
        proc = vcraft("build", "--target", "linux-aarch64-gnu", "--dry-run",
                      cwd=project)
        t.check("a dry run plans without a toolchain", proc.returncode == 0
                and "platform-tag     linux_aarch64" in proc.stdout
                and "aarch64-linux-gnu-gcc" in proc.stdout, proc.stdout)
        t.check("a dry run writes nothing",
                not list((project / "dist").glob("*aarch64*")))
        proc = vcraft("build", "--target", "linux-aarch64-gnu", cwd=project)
        t.check("a real aarch64 build needs its compiler", proc.returncode != 0)
        t.check("and names it", "aarch64-linux-gnu-gcc" in proc.stderr,
                proc.stderr.strip()[-300:])
        proc = vcraft("build", "--target", "linux-aarch64-gnu",
                      "--platform", "manylinux_2_17_x86_64", cwd=project)
        t.check("a platform that disagrees with the target fails",
                proc.returncode != 0)
        t.check("and says which implies which", "implies" in proc.stderr,
                proc.stderr.strip())
        proc = vcraft("develop", "--dry-run", cwd=project)
        t.check("develop has nothing dry to run", proc.returncode != 0)

        print("build")
        proc = vcraft("build", cwd=project)
        t.check("build succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        wheels = list((project / "dist").glob("*.whl"))
        t.check("a wheel is written", len(wheels) == 1,
                str([w.name for w in (project / 'dist').glob('*')]))
        if not wheels:
            print()
            print(f"{len(t.failures)} failure(s)")
            return 1
        wheel = wheels[0]

        t.check("the glue is generated",
                (project / "src" / "_vcraft_generated.v").exists())
        t.check("a stub is generated",
                (project / "python" / "mypkg_native" / "_stubs.pyi").exists(),
                str(list((project / "python").rglob("*.pyi"))))
        stub = (project / "python" / "mypkg_native" / "_stubs.pyi").read_text()
        t.check("the stub declares the functions", "def greet(" in stub, stub)
        t.check("the stub declares the class", "class Counter:" in stub, stub)
        t.check("the stub declares the fields", "    value: int" in stub, stub)

        name = wheel.name
        t.check("the name has no dots in the version",
                "-0.1.0-" in name, name)
        t.check("the tag names the interpreter", "cp3" in name, name)
        t.check("the tag names the platform", "_x86_64" in name or "_arm64" in name
                or "_amd64" in name or "universal2" in name, name)

        with zipfile.ZipFile(wheel) as z:
            t.check("the wheel is a valid archive", z.testzip() is None)
            entries = z.namelist()
            t.check("the extension is at the root",
                    any(n.endswith(".so") and "/" not in n for n in entries),
                    str(entries))
            t.check("METADATA", any(n.endswith("METADATA") for n in entries))
            t.check("WHEEL", any(n.endswith("dist-info/WHEEL") for n in entries))
            t.check("RECORD", any(n.endswith("dist-info/RECORD") for n in entries))
            wheel_meta = z.read(
                next(n for n in entries if n.endswith("dist-info/WHEEL"))).decode()
            t.check("the wheel is not pure Python",
                    "Root-Is-Purelib: false" in wheel_meta, wheel_meta)

        print("python helpers")
        helper = project / "python" / "mypkg_helper.py"
        helper.write_text(
            '"""A helper shipped with the wheel."""\n\n\n'
            'def marker() -> str:\n'
            '    return "helper-source"\n')
        manifest = project / "vcraft.toml"
        original_manifest = manifest.read_text()
        try:
            source_out = tmp / "out-source"
            proc = vcraft("build", "--out-dir", str(source_out), cwd=project)
            t.check("a build with Python succeeds", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-400:])
            source_wheels = sorted(source_out.glob("*.whl"))
            t.check("a source wheel is written", len(source_wheels) == 1,
                    str(list(source_out.glob("*"))))
            if source_wheels:
                with zipfile.ZipFile(source_wheels[0]) as z:
                    entries = z.namelist()
                    t.check("source Python is packaged",
                            "mypkg_helper.py" in entries, str(entries))
                    t.check("type stubs are not packaged",
                            not any(n.endswith(".pyi") for n in entries),
                            str(entries))
                source_target = tmp / "venv-source"
                make_venv(source_target, with_pip=True)
                proc = subprocess.run(
                    [str(source_target / "bin" / "python"), "-m", "pip", "install",
                     "--no-index", "--no-deps", str(source_wheels[0])],
                    capture_output=True, text=True)
                t.check("pip installs source Python", proc.returncode == 0,
                        (proc.stderr or proc.stdout).strip()[-300:])
                proc = subprocess.run(
                    [str(source_target / "bin" / "python"), "-c",
                     "import mypkg_helper\nprint(mypkg_helper.marker())"],
                    capture_output=True, text=True, cwd=tmp)
                t.check("packaged source imports", proc.returncode == 0
                        and proc.stdout.strip() == "helper-source",
                        (proc.stderr or proc.stdout).strip()[-300:])

            print("sourceless python")
            manifest.write_text(original_manifest.replace(
                'minimum-version = "3.11"\n',
                'minimum-version = "3.11"\nembed-pyc = true\n'))
            pyc_out = tmp / "out-pyc"
            proc = vcraft("build", "--out-dir", str(pyc_out), cwd=project)
            t.check("a sourceless build succeeds", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-400:])
            pyc_wheels = sorted(pyc_out.glob("*.whl"))
            t.check("a sourceless wheel is written", len(pyc_wheels) == 1,
                    str(list(pyc_out.glob("*"))))
            if pyc_wheels:
                with zipfile.ZipFile(pyc_wheels[0]) as z:
                    entries = z.namelist()
                    t.check("compiled Python is packaged",
                            "mypkg_helper.pyc" in entries, str(entries))
                    t.check("source Python is omitted",
                            "mypkg_helper.py" not in entries, str(entries))
                    data = z.read("mypkg_helper.pyc")
                    t.check("the bytecode has a header", len(data) > 16,
                            str(len(data)))
                pyc_target = tmp / "venv-pyc"
                make_venv(pyc_target, with_pip=True)
                proc = subprocess.run(
                    [str(pyc_target / "bin" / "python"), "-m", "pip", "install",
                     "--no-index", "--no-deps", str(pyc_wheels[0])],
                    capture_output=True, text=True)
                t.check("pip installs sourceless Python", proc.returncode == 0,
                        (proc.stderr or proc.stdout).strip()[-300:])
                proc = subprocess.run(
                    [str(pyc_target / "bin" / "python"), "-c",
                     "import mypkg_helper\n"
                     "print(mypkg_helper.marker())\n"
                     "print(mypkg_helper.__file__)"],
                    capture_output=True, text=True, cwd=tmp)
                t.check("sourceless Python imports", proc.returncode == 0
                        and "helper-source" in proc.stdout
                        and proc.stdout.strip().endswith(".pyc"),
                        (proc.stderr or proc.stdout).strip()[-300:])
        finally:
            manifest.write_text(original_manifest)
            helper.unlink(missing_ok=True)

        print("build twice")
        first = wheel.read_bytes()
        proc = vcraft("build", cwd=project)
        t.check("a rebuild succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        t.check("the rebuild is identical", wheel.read_bytes() == first,
                "a build that is not reproducible makes a diff meaningless")

        print("an explicit native target")
        # Naming the host's own target must change nothing: same tag, same suffix, same
        # bytes. If the explicit path diverged from the default one, this is where it
        # shows, rather than in a wheel someone uploads.
        explicit_out = tmp / "out-explicit-target"
        proc = vcraft("build", "--target", host_target(), "--out-dir",
                      str(explicit_out), cwd=project)
        t.check("an explicit native target builds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        explicit_wheels = sorted(explicit_out.glob("*.whl"))
        t.check("it writes one wheel", len(explicit_wheels) == 1,
                str(list(explicit_out.glob("*"))))
        if explicit_wheels:
            t.check("and it is the default wheel byte for byte",
                    explicit_wheels[0].read_bytes() == first,
                    "the explicit path diverged from the default one")

        print("install the wheel with pip")
        target = tmp / "venv-wheel"
        make_venv(target, with_pip=True)
        proc = subprocess.run(
            [str(target / "bin" / "python"), "-m", "pip", "install", "--no-index",
             "--no-deps", str(wheel)],
            capture_output=True, text=True)
        t.check("pip installs the wheel", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        script = (
            "import mypkg_native as m\n"
            "print(m.greet('pip'))\n"
            "print(m.add(2, 3))\n"
            "print(repr(m.Counter()))\n"
            "print(m.parse_int('1234'))\n"
        )
        proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t.check("the installed wheel works", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])
        if proc.returncode == 0:
            lines = proc.stdout.split()
            t.check("greet", "Hello," in proc.stdout, proc.stdout)
            t.check("add", "5" in lines, proc.stdout)
            t.check("the class is constructible", "Counter(value: 0, step: 1)"
                    in proc.stdout, proc.stdout)
            t.check("parse_int", "1234" in lines, proc.stdout)

        print("develop")
        target = tmp / "venv-develop"
        make_venv(target)
        env = dict(os.environ, VIRTUAL_ENV=str(target))
        proc = subprocess.run([str(VCRAFT), "develop"], cwd=project, env=env,
                              capture_output=True, text=True)
        t.check("develop succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        t.check("develop says where it installed",
                "installed into" in proc.stdout, proc.stdout)
        t.check("develop is editable by default", "(editable)" in proc.stdout,
                proc.stdout)
        platlib = next((target / "lib").glob("python*/site-packages"))
        pth = platlib / "_mypkg_editable.pth"
        t.check("an editable pointer is installed", pth.exists(),
                str(list(platlib.glob("*.pth"))))
        installed = list((target / "lib").rglob("mypkg_native*.so"))
        t.check("no copied extension shadows the editable build", not installed,
                str([str(p) for p in (target / "lib").rglob("*.so")]))
        dist_info = next(platlib.glob("mypkg-0.1.0.dist-info"))
        t.check("editable metadata is installed", dist_info.is_dir(),
                str(list(platlib.glob("mypkg*"))))
        t.check("the installed metadata names the pointer",
                "_mypkg_editable.pth" in (dist_info / "RECORD").read_text(),
                (dist_info / "RECORD").read_text())
        t.check("the install is marked editable",
                '"editable":true' in (dist_info / "direct_url.json").read_text().replace(" ", ""),
                (dist_info / "direct_url.json").read_text())
        t.check("the pointer names the build output",
                str(project / "dist" / "build") in pth.read_text(),
                pth.read_text())
        proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t.check("the developed extension works", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])
        if proc.returncode == 0:
            t.check("develop produced a working class",
                    "Counter(value: 0, step: 1)" in proc.stdout, proc.stdout)

        # The class must come out initialised, not holding whatever the allocator left.
        # That is the difference between a constructor that ran and one that did not,
        # and it is invisible in the build log.
        proc = subprocess.run(
            [str(target / "bin" / "python"), "-c",
             "import mypkg_native as m;c=m.Counter();print(c.is_zero,c.increment())"],
            capture_output=True, text=True, cwd=tmp)
        t.check("the constructor runs", proc.stdout.strip() == "True 1",
                proc.stdout.strip() or proc.stderr.strip()[-200:])

        print("develop --copy")
        copy_target = tmp / "venv-develop-copy"
        make_venv(copy_target)
        copy_env = dict(os.environ, VIRTUAL_ENV=str(copy_target))
        proc = subprocess.run([str(VCRAFT), "develop", "--copy"], cwd=project,
                              env=copy_env, capture_output=True, text=True)
        t.check("a copy install succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        t.check("a copy install says where it installed",
                "installed into" in proc.stdout and "(editable)" not in proc.stdout,
                proc.stdout)
        copy_platlib = next((copy_target / "lib").glob("python*/site-packages"))
        t.check("a copy installs the extension",
                len(list(copy_platlib.glob("mypkg_native*.so"))) == 1,
                str(list(copy_platlib.glob("*.so"))))
        t.check("a copy removes the editable pointer",
                not list(copy_platlib.glob("*_editable.pth")),
                str(list(copy_platlib.glob("*.pth"))))
        proc = subprocess.run([str(copy_target / "bin" / "python"), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t.check("the copied extension works", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])

        print("abi3")
        # An abi3 build goes through CPython's multi-phase initialisation and the
        # stable API, neither of which the normal path touches. A refactor that only
        # ever builds one of them leaves the other broken in a way no other test sees.
        proc = vcraft("build", "--abi3", ABI3_FLOOR, cwd=project)
        t.check("an abi3 build succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        abi_wheels = list((project / "dist").glob("*abi3*.whl"))
        t.check("an abi3 wheel is written", len(abi_wheels) == 1,
                str([w.name for w in (project / "dist").glob("*.whl")]))
        if abi_wheels:
            abi = abi_wheels[0]
            # PEP 425: the tag names the floor, not the interpreter that built it.
            # `cp314-cp312-...` is what a naive tag builder produces and every
            # installer rejects it with "no wheels with a matching Python version tag".
            # `mypkg-0.1.0-cp311-abi3-linux_x86_64.whl`: five parts, and the
            # interpreter field is the floor the stable ABI starts at.
            parts = abi.name[:-len(".whl")].split("-")
            t.check("the wheel name has five parts", len(parts) == 5, abi.name)
            t.check("the ABI field is abi3", parts[3] == "abi3", abi.name)
            t.check("the tag names the floor",
                    parts[2] == "cp" + ABI3_FLOOR.replace(".", ""), abi.name)
            with zipfile.ZipFile(abi) as z:
                t.check("the extension is named .abi3.so",
                        any(n.endswith(".abi3.so") for n in z.namelist()),
                        str(z.namelist()))
                t.check("the abi3 wheel is a valid archive", z.testzip() is None)
                # The floor is hex, not decimal: `Py_LIMITED_API` for 3.11 is
                # `0x030b0000`, and `0x03110000` reads as a 3.17 floor. The headers
                # then use the function form of `Py_TYPE`, which only 3.14 exports,
                # so the wheel imports on 3.14 and fails everywhere older. `nm` sees
                # what the import would hit, without needing the older interpreters.
                if sys.platform.startswith("linux") and shutil.which("nm"):
                    so_name = next(n for n in z.namelist() if n.endswith(".abi3.so"))
                    unpacked = tmp / "abi3-unpacked"
                    unpacked.mkdir(exist_ok=True)
                    (unpacked / "ext.so").write_bytes(z.read(so_name))
                    undefined = subprocess.run(
                        ["nm", "-D", str(unpacked / "ext.so")],
                        capture_output=True, text=True).stdout
                    t.check("no 3.14-only Py_TYPE reference",
                            not any(line.split()[-1] == "Py_TYPE" and " U " in line
                                    for line in undefined.splitlines()),
                            "U Py_TYPE in the abi3 extension")

            target = tmp / "venv-abi3"
            make_venv(target, with_pip=True)
            proc = subprocess.run(
                [str(target / "bin" / "python"), "-m", "pip", "install", "--no-index",
                 "--no-deps", str(abi)],
                capture_output=True, text=True)
            t.check("pip installs the abi3 wheel", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-300:])
            proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                                  capture_output=True, text=True, cwd=tmp)
            t.check("the abi3 wheel works", proc.returncode == 0,
                    (proc.stderr or "").strip()[-300:])
            if proc.returncode == 0:
                t.check("abi3 functions", "Hello," in proc.stdout, proc.stdout)
                t.check("abi3 classes",
                        "Counter(value: 0, step: 1)" in proc.stdout, proc.stdout)

            print("back to a normal build")
            proc = vcraft("build", cwd=project)
            t.check("a normal build still succeeds after an abi3 one",
                    proc.returncode == 0, (proc.stderr or proc.stdout).strip()[-300:])
            normal = [w for w in (project / "dist").glob("*.whl")
                      if "abi3" not in w.name]
            t.check("the normal wheel is written again", len(normal) == 1)
            proc = subprocess.run(
                [str(target / "bin" / "python"), "-m", "pip", "install", "--no-index",
                 "--no-deps", "--force-reinstall", str(normal[0])],
                capture_output=True, text=True)
            t.check("and installs over the abi3 one", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-300:])
            proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                                  capture_output=True, text=True, cwd=tmp)
            t.check("the normal build still has its classes", proc.returncode == 0
                    and "Counter(value: 0, step: 1)" in proc.stdout,
                    (proc.stderr or proc.stdout).strip()[-300:])

        print("error type diagnostics")
        # `@[vc_error]` on something that cannot be one has to be reported, because a
        # silently ignored annotation means a `!T` function that compiles and fails as a
        # RuntimeError, which is exactly the mistake the annotation exists to prevent.
        err = tmp / "errtypes"
        (err / "src").mkdir(parents=True)
        (err / "v.mod").write_text(
            'Module {\n\tname: "errtypes_native"\n\tbase_url: "src"\n'
            '\trequires: ["vcraft"]\n}\n')
        (err / "vcraft.toml").write_text(
            '[package]\nname = "errtypes"\nversion = "0.1.0"\n'
            'description = "error types"\n\n[build]\nmodule = "errtypes_native"\n'
            'source = "src"\noutput = "python"\n')
        err_source = err / "src" / "errtypes_native.v"

        def err_project(body: str) -> str:
            return "module errtypes_native\n\nimport vcraft\n\n" + body

        def err_diagnostic(label: str, body: str, needle: str) -> None:
            err_source.write_text(err_project(body), encoding="utf-8")
            out = vcraft("build", cwd=err)
            t.check(f"{label} fails", out.returncode != 0, out.stdout[-200:])
            t.check(f"{label} says why", needle in out.stderr,
                    out.stderr.strip()[-300:])

        err_diagnostic("an error type with no msg()", """
@[vc_error]
pub struct NoMsg {
pub:
	detail string
}

pub fn (e NoMsg) code() int { return 0 }
""", "has no `msg()` method")

        err_diagnostic("an error type with no code()", """
@[vc_error]
pub struct NoCode {
pub:
	detail string
}

pub fn (e NoCode) msg() string { return e.detail }
""", "has no `code()` method")

        err_diagnostic("an error type with two candidate fields", """
@[vc_error]
pub struct Ambiguous {
pub:
	exc    vcraft.PyObj
	other  vcraft.PyObj
	detail string
}

pub fn (e Ambiguous) msg() string { return e.detail }
pub fn (e Ambiguous) code() int { return 0 }
""", "which one holds the Python exception is ambiguous")

        # And the two that have to work.
        err_source.write_text(err_project("""
@[vc_error]
pub struct Rejected {
pub:
	detail string
}

pub fn (e Rejected) msg() string { return e.detail }
pub fn (e Rejected) code() int { return int(vcraft.PyExc(.value_error)) }

@[vc_fn]
pub fn parse(text string) !int {
	if text.len == 0 {
		return Rejected{ detail: 'nothing to parse' }
	}
	return text.len
}
"""), encoding="utf-8")
        proc = vcraft("build", cwd=err)
        t.check("an error type builds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        if proc.returncode == 0:
            built = sorted(err.glob("dist/build/*.so"))
            t.check("the extension is written", len(built) == 1, built)
            if built:
                probe = subprocess.run(
                    [sys.executable, "-c",
                     "import sys\n"
                     "sys.path.insert(0, sys.argv[1])\n"
                     "import errtypes_native as m\n"
                     "print(m.parse('abc'))\n"
                     "try:\n"
                     "    m.parse('')\n"
                     "except ValueError as exc:\n"
                     "    print(type(exc).__name__, exc)\n",
                     str(built[0].parent)], capture_output=True, text=True)
                t.check("and runs", probe.returncode == 0,
                        probe.stderr.strip()[-400:])
                # `splitlines`, not `split`: the message has a space in it.
                t.check("code() names the exception Python sees",
                        probe.stdout.splitlines() == ["3", "ValueError nothing to parse"],
                        probe.stdout)

        print("iterator and nogil diagnostics")
        # A half pair compiles and then fails at the call, with nothing pointing at
        # the missing annotation, so each half is reported where it is declared.
        it = tmp / "itertypes"
        (it / "src").mkdir(parents=True)
        (it / "v.mod").write_text(
            'Module {\n\tname: "it_native"\n\tbase_url: "src"\n'
            '\trequires: ["vcraft"]\n}\n')
        (it / "vcraft.toml").write_text(
            '[package]\nname = "ittypes"\nversion = "0.1.0"\n'
            'description = "iterators"\n\n[build]\nmodule = "it_native"\n'
            'source = "src"\noutput = "python"\n')
        it_source = it / "src" / "it_native.v"

        def it_project(body: str) -> str:
            return "module it_native\n\nimport vcraft\n\n" + body

        def it_diagnostic(label: str, body: str, needle: str) -> None:
            it_source.write_text(it_project(body), encoding="utf-8")
            out = vcraft("build", cwd=it)
            t.check(f"{label} fails", out.returncode != 0, out.stdout[-200:])
            t.check(f"{label} says why", needle in out.stderr,
                    out.stderr.strip()[-300:])

        it_diagnostic("next without iter", """
@[vc_class]
pub struct Lonely {
mut:
\t@[vc_field] current int
}

@[vc_methods]
@[vc_next]
pub fn (mut c Lonely) advance() int {
\treturn c.current
}
""", "no `@[vc_iter]`")

        it_diagnostic("iter without next", """
@[vc_class]
pub struct Stuck {
mut:
\t@[vc_field] current int
}

@[vc_methods]
@[vc_iter]
pub fn (mut c Stuck) rewind() {
}
""", "no `@[vc_next]`")

        it_diagnostic("an iterator with arguments", """
@[vc_class]
pub struct Nosy {
mut:
\t@[vc_field] current int
}

@[vc_methods]
@[vc_iter]
pub fn (mut c Nosy) rewind(from int) {
}
""", "takes none")

        it_diagnostic("an iterator with a return value", """
@[vc_class]
pub struct Greedy {
mut:
\t@[vc_field] current int
}

@[vc_methods]
@[vc_iter]
pub fn (mut c Greedy) rewind() int {
\treturn c.current
}
""", "must return nothing")

        it_diagnostic("nogil on a raw function", """
@[vc_fn]
@[vc_raw]
@[vc_gil]
pub fn touch(ptr voidptr) voidptr {
\treturn ptr
}
""", "contradicts `@[vc_raw]`")

        print("abi3 with cycles")
        # `Py_TPFLAGS_HAVE_GC` reaches CPython differently under the stable ABI: the type
        # object's own traverse has to come through `PyType_GetSlot`, because
        # `PyTypeObject` is opaque there and `tp_traverse` cannot be reached as a member.
        # A cycle in an abi3 build is the case that tells the two paths apart.
        native = project / "src" / "mypkg_native.v"
        saved = native.read_text()
        native.write_text(saved + """
@[vc_class]
pub struct Node {
mut:
	@[vc_field] label int
	@[vc_ref(Node)] peer vcraft.PyObj
}

@[vc_methods]
pub fn (mut n Node) link(other voidptr) {
	n.peer = vcraft.retain(other)
}
""")
        try:
            proc = vcraft("build", "--abi3", ABI3_FLOOR, cwd=project)
            t.check("an abi3 build with a reference field succeeds",
                    proc.returncode == 0, (proc.stderr or proc.stdout).strip()[-400:])
            if proc.returncode == 0:
                abi_cycles = [w for w in (project / "dist").glob("*abi3*.whl")]
                t.check("the wheel is written", len(abi_cycles) == 1, abi_cycles)
                target2 = tmp / "venv-abi3-cycles"
                make_venv(target2, with_pip=True)
                proc = subprocess.run(
                    [str(target2 / "bin" / "python"), "-m", "pip", "install",
                     "--no-index", "--no-deps", str(abi_cycles[0])],
                    capture_output=True, text=True)
                t.check("pip installs it", proc.returncode == 0,
                        (proc.stderr or proc.stdout).strip()[-300:])
                probe = (
                    "import gc\n"
                    "import mypkg_native as m\n"
                    # Garbage left over from start-up would otherwise be counted
                    # too: some CPython builds leave a couple of dozen objects.
                    "gc.collect()\n"
                    "a = m.Node()\n"
                    "b = m.Node()\n"
                    "a.label = 1\n"
                    "b.label = 2\n"
                    "a.link(b)\n"
                    "b.link(a)\n"
                    "print(repr(a))\n"
                    "del a, b\n"
                    "print(gc.collect())\n"
                )
                proc = subprocess.run([str(target2 / "bin" / "python"), "-c", probe],
                                      capture_output=True, text=True, cwd=tmp)
                t.check("it runs", proc.returncode == 0,
                        (proc.stderr or "").strip()[-400:])
                if proc.returncode == 0:
                    # `splitlines`, not `split`: the repr contains spaces.
                    lines = proc.stdout.splitlines()
                    t.check("the cycle renders with a guard",
                            lines[0] == "Node(label: 1, peer: Node(label: 2, peer: Node(...)))",
                            proc.stdout)
                    t.check("and the collector frees it", lines[1] == "2", proc.stdout)
        finally:
            native.write_text(saved)
            vcraft("build", cwd=project)

        print("sdist")
        proc = vcraft("sdist", cwd=project)
        t.check("sdist succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        sdists = list((project / "dist").glob("*.tar.gz"))
        t.check("an sdist is written", len(sdists) == 1,
                str([w.name for w in (project / "dist").glob("*.tar.gz")]))
        if sdists:
            import tarfile
            with tarfile.open(sdists[0]) as tf:
                members = tf.getnames()
                top = sdists[0].name[:-len(".tar.gz")]
                # `tarfile` strips the trailing slash from a directory member, so the
                # name compares equal either way.
                t.check("the archive unpacks into name-version",
                        any(m.rstrip("/") == top for m in members), str(members[:3]))
                t.check("it carries the V manifest", top + "/v.mod" in members)
                t.check("it carries the packaging manifest",
                        top + "/vcraft.toml" in members)
                t.check("it carries the V sources",
                        top + "/src/mypkg_native.v" in members)
                t.check("it carries Python sources",
                        top + "/python/mypkg_native/_stubs.pyi" in members,
                        str(members))
                # Without these the sdist is a source tree with no way to build it: pip
                # untars, reads pyproject.toml, and finds nothing.
                t.check("it carries pyproject.toml", top + "/pyproject.toml" in members)
                t.check("it carries the build backend",
                        top + "/vcraft_build.py" in members)
                t.check("it carries PKG-INFO", top + "/PKG-INFO" in members)
                dirs = [m for m in tf.getmembers() if m.isdir()]
                t.check("the top entry is a directory and not a file",
                        any(m.name.rstrip("/") == top for m in dirs),
                        str([(m.name, m.type) for m in tf.getmembers()[:2]]))
                info = tf.extractfile(top + "/PKG-INFO").read().decode()
                t.check("PKG-INFO names the package", "Name: mypkg" in info, info[:120])
                t.check("PKG-INFO has a version", "Version: 0.1.0" in info)

        print("pep 517")
        # `pip install .` goes through the backend rather than through vcraft's own
        # commands, so it is the only check that the generated backend is right.
        target = tmp / "venv-backend"
        make_venv(target, with_pip=True)
        env = dict(os.environ, VCRAFT_BIN=str(VCRAFT))
        proc = subprocess.run(
            [str(target / "bin" / "python"), "-m", "pip", "install", "--no-index",
             "--no-build-isolation", "--no-deps", "."],
            cwd=project, env=env, capture_output=True, text=True)
        t.check("pip install . succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t.check("the project built by pip works", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])
        if proc.returncode == 0:
            t.check("pip-installed functions", "Hello," in proc.stdout, proc.stdout)

        print("pip install -e .")
        # PEP 660 goes through `build_editable`, not `build`, so this is the only
        # check that the generated backend has the editable hooks and that the
        # resulting wheel points at build output which survives the install.
        editable_target = tmp / "venv-editable"
        make_venv(editable_target, with_pip=True)
        proc = subprocess.run(
            [str(editable_target / "bin" / "python"), "-m", "pip", "install",
             "--no-index", "--no-build-isolation", "--no-deps", "-e", "."],
            cwd=project, env=env, capture_output=True, text=True)
        t.check("pip install -e . succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-400:])
        proc = subprocess.run([str(editable_target / "bin" / "python"), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t.check("the editable project works", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])
        proc = subprocess.run(
            [str(editable_target / "bin" / "python"), "-c",
             "import importlib.metadata\n"
             "import json\n"
             "import mypkg_native as m\n"
             "direct = json.loads(importlib.metadata.distribution('mypkg').read_text('direct_url.json'))\n"
             "print(m.__file__)\n"
             "print(direct['dir_info']['editable'])\n"
             "print(direct['url'])\n"],
            capture_output=True, text=True, cwd=tmp)
        t.check("editable metadata is readable", proc.returncode == 0,
                (proc.stderr or "").strip()[-300:])
        if proc.returncode == 0:
            lines = proc.stdout.splitlines()
            t.check("the editable extension resolves to stable build output",
                    lines[0].startswith(str(project / ".vcraft" / "editable" / "build")),
                    proc.stdout)
            t.check("editable metadata marks the source tree",
                    lines[1:] == ["True", project.as_uri()], proc.stdout)

        print("editable wheels are not publishable")
        # An editable wheel points at the builder's disk. `publish` has to refuse it
        # before choosing an uploader, because the refusal is the only thing standing
        # between a local path and PyPI.
        editable_wheels = sorted((project / ".vcraft" / "editable").glob("*.whl"))
        t.check("an editable wheel was staged", len(editable_wheels) == 1,
                str(list((project / ".vcraft" / "editable").glob("*"))))
        if editable_wheels:
            backup = tmp / "wheel-backup"
            backup.mkdir(exist_ok=True)
            saved = []
            try:
                for wheel_path in (project / "dist").glob("*.whl"):
                    saved.append((wheel_path, backup / wheel_path.name))
                    wheel_path.rename(backup / wheel_path.name)
                shutil.copy(editable_wheels[0], project / "dist" / editable_wheels[0].name)
                proc = vcraft("publish", cwd=project)
                t.check("publish refuses an editable wheel", proc.returncode != 0,
                        (proc.stdout or proc.stderr).strip()[-300:])
                t.check("and says why",
                        "cannot be uploaded" in (proc.stderr or proc.stdout),
                        (proc.stderr or proc.stdout).strip()[-300:])
            finally:
                for wheel_path in (project / "dist").glob("*.whl"):
                    wheel_path.unlink()
                for original, staged in saved:
                    staged.rename(original)

        print("pip install an sdist")
        if sdists:
            target = tmp / "venv-sdist"
            make_venv(target, with_pip=True)
            env = dict(os.environ, VCRAFT_BIN=str(VCRAFT))
            proc = subprocess.run(
                [str(target / "bin" / "python"), "-m", "pip", "install", "--no-index",
                 "--no-build-isolation", "--no-deps", str(sdists[0])],
                env=env, capture_output=True, text=True)
            t.check("pip installs an sdist", proc.returncode == 0,
                    (proc.stderr or proc.stdout).strip()[-400:])
            proc = subprocess.run([str(target / "bin" / "python"), "-c", script],
                                  capture_output=True, text=True, cwd=tmp)
            t.check("the sdist-built extension works", proc.returncode == 0,
                    (proc.stderr or "").strip()[-300:])

        print("generate-ci")
        proc = vcraft("generate-ci", cwd=project)
        t.check("generate-ci succeeds", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        workflow = project / ".github" / "workflows" / "build.yml"
        t.check("a workflow is written", workflow.exists())
        if workflow.exists():
            text = workflow.read_text()
            t.check("it names the job", "jobs:" in text, text[:200])
            t.check("it runs on a matrix", "matrix:" in text)
            t.check("matrix expressions have double braces",
                    "${{ matrix.os }}" in text and "${{ matrix.target }}" in text,
                    text[:600])
            t.check("it builds with the action",
                    "uses: rroblf01/vcraft/actions/vcraft-action@v1" in text,
                    "an action reference needs owner/repo/path@ref")
            t.check("it uploads a wheel", "upload-artifact" in text)
            t.check("it is marked generated", "Generated by vcraft" in text)
            # A YAML value like `3.10` unquoted is a float, and comes back as `3.1`,
            # which is a version nobody publishes.
            t.check("versions are quoted", 'python: "3.11"' in text, text[:800])
            t.check("the matrix has cells",
                    text.count("- target:") >= 4, str(text.count("- target:")))
            t.check("the plain matrix tags macOS honestly too",
                    "macosx-arm64" in text and "universal2" not in text, text[:600])
            t.check("linux cells build in containers",
                    "ghcr.io/rroblf01/vcraft-manylinux" in text, text)

        print("the action and the release workflows")
        # The workflow above references an action and images that have to exist as
        # files here first: a consumer's CI fails with "action not found" rather than
        # with anything pointing back at the generator.
        try:
            import yaml
        except ImportError:
            print("  skip no PyYAML for the workflow files")
            yaml = None
        if yaml is not None:
            action = (ROOT / "actions" / "vcraft-action" / "action.yml").read_text()
            definition = yaml.safe_load(action)
            t.check("the action is composite",
                    definition["runs"]["using"] == "composite", str(definition["runs"]))
            t.check("the action takes a container",
                    "container" in definition["inputs"], str(definition["inputs"]))
            t.check("the action takes args",
                    "args" in definition["inputs"], str(definition["inputs"]))
            for workflow_file in [
                    "ci.yml", "release-images.yml", "release-action.yml",
                    "release-vcraft.yml"]:
                path = ROOT / ".github" / "workflows" / workflow_file
                t.check(f"{workflow_file} exists", path.exists(), str(path))
                if path.exists():
                    try:
                        parsed = yaml.safe_load(path.read_text())
                        t.check(f"{workflow_file} parses",
                                isinstance(parsed, dict) and "jobs" in parsed,
                                str(list(parsed)))
                    except Exception as exc:  # noqa: BLE001
                        t.check(f"{workflow_file} parses", False, str(exc))
            ci = yaml.safe_load(
                (ROOT / ".github" / "workflows" / "ci.yml").read_text())
            matrix = ci["jobs"]["tests"]["strategy"]["matrix"]
            # Either an `include:` list of cells or a plain list of runners;
            # both spellings mean the same thing and the check accepts both so
            # the workflow stays editable.
            runners = [cell.get("os", "") for cell in matrix.get("include", [])
                       if isinstance(cell, dict)]
            runners += [os for os in matrix.get("os", []) if isinstance(os, str)]
            t.check("CI runs where the developers cannot",
                    any(r.startswith("macos-") for r in runners), str(runners))
            t.check("CI runs every suite",
                    all(path in (ROOT / ".github" / "workflows" / "ci.yml").read_text()
                        for path in ["tests/project/check_toml.py",
                                     "tests/packaging/test_pack.py",
                                     "tests/wheel/test_wheel.py",
                                     "tests/runtime/test_runtime.py",
                                     "tests/codegen/test_codegen.py",
                                     "tests/cli/test_cli.py"]),
                    "a suite CI never runs is a suite that rots")
            ci_text = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
            t.check("CI builds V from a pinned commit, not a release",
                    "V_COMMIT" in ci_text and "releases/download" not in ci_text,
                    "no V release is newer than the flags vcraft passes")
            t.check("CI covers free-threading with the GIL disabled",
                    "PYTHON_GIL=0" in ci_text and "3.13t" in ci_text, ci_text[-500:])
            images = yaml.safe_load(
                (ROOT / ".github" / "workflows" / "release-images.yml").read_text())
            dockerfiles = set()
            for match in re.finditer(r"dockerfile:\s*(\S+)",
                                     (ROOT / ".github" / "workflows" / "release-images.yml").read_text()):
                dockerfiles.add(match.group(1))
            t.check("every image the release builds is a file here",
                    dockerfiles == {"docker/manylinux.Dockerfile",
                                    "docker/musllinux.Dockerfile"} and
                    all((ROOT / name).exists() for name in dockerfiles),
                    str(sorted(dockerfiles)))
            release = yaml.safe_load(
                (ROOT / ".github" / "workflows" / "release-vcraft.yml").read_text())
            t.check("the release builds per platform",
                    set(cell.get("asset", "") for cell in
                        release["jobs"]["build"]["strategy"]["matrix"]["include"])
                    == {"linux-x86_64", "macos-arm64"})
            publish = release["jobs"]["publish-pypi"]
            release_text = (ROOT / ".github" / "workflows" / "release-vcraft.yml").read_text()
            t.check("PyPI publish waits for every platform",
                    publish["needs"] == ["build"], str(publish.get("needs")))
            t.check("PyPI publish is tag-gated twice",
                    "vcraft/v*" in release_text
                    and "refs/tags/vcraft/v" in str(publish.get("if", "")),
                    str(publish.get("if", "")))
            t.check("PyPI publish uses trusted publishing",
                    publish.get("environment") == "pypi"
                    and publish.get("permissions", {}).get("id-token") == "write",
                    str({k: publish.get(k) for k in ("environment", "permissions")}))
            t.check("the Linux tool wheel carries a tag PyPI accepts",
                    "--platform manylinux_2_28_x86_64" in release_text
                    and "--platform linux_x86_64" not in release_text,
                    "PyPI rejects linux_x86_64 wheels")
            t.check("the macOS binary honours its tag's macOS version",
                    'MACOSX_DEPLOYMENT_TARGET: "11.0"' in release_text)
            t.check("the release uploads wheels, not tarballs",
                    "gh-action-pypi-publish" in release_text
                    and "tar -czf" not in release_text, release_text[-300:])
            t.check("releases can never be cancelled mid-upload",
                    "cancel-in-progress: false" in release_text)

        print("abi3 changes the matrix")
        manifest = project / "vcraft.toml"
        original = manifest.read_text()
        manifest.write_text(original.replace('minimum-version = "3.11"',
                                             'minimum-version = "3.11"\nabi3 = "3.12"'))
        proc = vcraft("info", cwd=project)
        t.check("abi3 is read from the manifest",
                "abi3" in proc.stdout and "3.12" in proc.stdout, proc.stdout)
        proc = vcraft("generate-ci", cwd=project)
        t.check("generate-ci succeeds with abi3", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        text = workflow.read_text()
        # One wheel covers every interpreter from the floor up, so one cell per platform
        # is the whole matrix rather than one per interpreter.
        t.check("the abi3 matrix covers linux and macos, not windows",
                text.count("- target:") == 5, str(text.count("- target:")))
        t.check("no windows cell is emitted",
                "windows-latest" not in text, text[:600])
        t.check("macOS is tagged with the architecture actually built",
                "macosx-arm64" in text and "universal2" not in text, text[:600])
        t.check("the abi3 matrix names the abi3 tag", "cp312-abi3-" in text, text[:600])
        # Quoted values only: the action step itself has an unquoted `container:`
        # line passing the matrix value through.
        t.check("linux cells build in the published images",
                text.count('container: "ghcr') == 4, str(text.count('container: "ghcr')))
        t.check("the manylinux cell names its target",
                "--target linux-x86_64-gnu --manylinux 2_28" in text, text)
        t.check("the musllinux cell names its target",
                "--target linux-x86_64-musl --musllinux 1_2" in text, text)
        t.check("aarch64 cells run on arm runners",
                text.count("ubuntu-24.04-arm") == 2, str(text.count("ubuntu-24.04-arm")))
        manifest.write_text(original)

        print("free-threading changes the matrix")
        # A free-threaded cell without an interpreter is a cell that fails: the
        # build refuses to guess which `python3` is free-threaded, so the matrix
        # names setup-python's free-threaded interpreter and passes it explicitly.
        manifest.write_text(original.replace('minimum-version = "3.11"',
                                             'minimum-version = "3.11"\nfree-threading = true'))
        proc = vcraft("generate-ci", cwd=project)
        t.check("generate-ci succeeds with free-threading", proc.returncode == 0,
                (proc.stderr or proc.stdout).strip()[-300:])
        text = workflow.read_text()
        # 3.13t and 3.14t, each on Linux and macOS.
        t.check("the free-threaded matrix is one cell per version and platform",
                text.count("- target:") == 4, str(text.count("- target:")))
        t.check("macOS cells name a free-threaded interpreter",
                'python: "3.13t"' in text and 'python: "3.14t"' in text, text[:1200])
        t.check("and pass setup-python's exact interpreter to the build",
                "steps.python.outputs.python-path" in text, text[-1500:])
        t.check("linux free-threaded cells build in the manylinux image",
                "--interpreter /opt/python/cp313-cp313t/bin/python" in text
                and "--interpreter /opt/python/cp314-cp314t/bin/python" in text,
                text[:1500])
        manifest.write_text(original)

        print("the plain matrix follows minimum-version")
        manifest.write_text(original)
        proc = vcraft("generate-ci", cwd=project)
        text = workflow.read_text()
        t.check("the default 3.11 floor builds 3.11 to 3.14",
                all(f"cp{v}-cp{v}/bin/python" in text for v in ("311", "312", "313", "314")),
                text[:1500])
        manifest.write_text(original.replace('minimum-version = "3.11"',
                                             'minimum-version = "3.14"'))
        proc = vcraft("generate-ci", cwd=project)
        text = workflow.read_text()
        t.check("a 3.14 floor builds nothing older",
                "cp313-cp313" not in text and "cp314-cp314" in text, text[:1500])
        t.check("wheels are checked inside their container",
                'check: "/opt/python/cp314-cp314/bin/python"' in text
                and 'docker run' in text, text[-1500:])
        manifest.write_text(original)

        print("unsupported versions are refused before compiling")
        proc = vcraft("build", "--abi3", "3.10", "--dry-run", cwd=project)
        t.check("an abi3 floor below 3.11 is refused",
                proc.returncode != 0 and "3.11" in proc.stderr, proc.stderr.strip())
        proc = vcraft("build", "--abi3", "3.99", "--dry-run", cwd=project)
        t.check("an abi3 floor above the interpreter is refused",
                proc.returncode != 0 and "newer than the interpreter" in proc.stderr,
                proc.stderr.strip())
        proc = vcraft("build", "--abi3", ABI3_FLOOR, "--free-threading",
                      "--interpreter", sys.executable, "--dry-run", cwd=project)
        t.check("abi3 with free-threading is refused",
                proc.returncode != 0 and "cannot be combined" in proc.stderr,
                proc.stderr.strip())

        print("macOS tags keep their promise")
        # The version in a macOS tag is the oldest system the binary loads on, and
        # only MACOSX_DEPLOYMENT_TARGET makes the compiler honour it.
        env = {k: v for k, v in os.environ.items() if k != "MACOSX_DEPLOYMENT_TARGET"}
        proc = subprocess.run([str(VCRAFT), "build", "--target", "macos-arm64",
                               "--dry-run"], cwd=project, env=env,
                              capture_output=True, text=True)
        t.check("a macOS build sets the deployment target its tag names",
                "-macosx_11_0_arm64" in proc.stdout
                and "MACOSX_DEPLOYMENT_TARGET=11.0" in proc.stdout, proc.stdout)
        proc = subprocess.run([str(VCRAFT), "build", "--target", "macos-arm64",
                               "--dry-run"], cwd=project,
                              env={**env, "MACOSX_DEPLOYMENT_TARGET": "13.0"},
                              capture_output=True, text=True)
        t.check("a deployment target the caller set moves the tag",
                "-macosx_13_0_arm64" in proc.stdout, proc.stdout)
        # Apple's linker refuses the undefined `Py*` symbols every extension leaves
        # for the interpreter, so without this no macOS build links at all.
        t.check("a macOS build lets the interpreter resolve CPython's symbols",
                "-undefined dynamic_lookup" in proc.stdout, proc.stdout)
        t.check("V never retries a failed build with its 0.5.2 release",
                "-new-compiler" in proc.stdout, proc.stdout)

        print("errors")
        proc = vcraft("build", "--out-dir", cwd=project)
        t.check("a missing option value fails", proc.returncode != 0)
        t.check("and says which option", "--out-dir" in proc.stderr,
                proc.stderr.strip())

        empty = tmp / "empty"
        empty.mkdir()
        proc = vcraft("build", cwd=empty)
        t.check("build outside a project fails", proc.returncode != 0)
        t.check("and suggests new", "vcraft new" in proc.stderr,
                proc.stderr.strip())

        proc = vcraft("clean", cwd=project)
        t.check("clean succeeds", proc.returncode == 0, proc.stderr.strip())
        t.check("clean removes dist", not (project / "dist").exists())
        t.check("clean removes editable build output",
                not (project / ".vcraft").exists())
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
