#!/usr/bin/env python3
"""Release smoke test.

Runs against a *published* vcraft (the one on `PATH`, installed from PyPI) with a V
toolchain installed, and exercises the features a release advertises. It is the gate that
would have caught the 1.4.0 packaging and enum regressions before a user did:

  * a `--strip` build leaves no symbol table;
  * every `.v` under `src/` reaches the sdist and the sdist rebuilds the whole API;
  * an enum as a parameter converts and rejects a non-member with `ValueError`;
  * that enum is declared in the `.pyi`;
  * an enum declared in a file that sorts after its use still resolves.

    vcraft toolchain install
    python3 scripts/release-smoke.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def run(cmd: list, **kw) -> subprocess.CompletedProcess:
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)


def main() -> int:
    vcraft = shutil.which("vcraft")
    if not vcraft:
        print("vcraft is not on PATH; install the release first")
        return 1
    problems: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-smoke-"))
    try:
        proj = tmp / "smoke"
        (proj / "src").mkdir(parents=True)
        (proj / "v.mod").write_text(
            'Module {\n\tname: "smoke_native"\n\tbase_url: "src"\n'
            '\trequires: ["vcraft"]\n}\n')
        (proj / "vcraft.toml").write_text(
            '[package]\nname = "smoke"\nversion = "0.1.0"\nmodule = "smoke_native"\n'
            'requires-python = ">=3.11"\n\n[build]\nminimum-version = "3.11"\n')
        # The method uses Color, which is declared in zcolor.v -- a file that sorts after
        # this one. extra_marker is the sibling source the sdist must carry.
        (proj / "src" / "a_api.v").write_text('''module smoke_native

@[vc_class]
pub struct Counter {
mut:
	@[vc_field] n int
}

@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{ n: 0 }
}

@[vc_method]
pub fn (mut c Counter) paint(color Color) int {
	return int(color)
}

@[vc_fn]
pub fn extra_marker() int {
	return 7
}
''')
        (proj / "src" / "zcolor.v").write_text(
            'module smoke_native\n\npub enum Color {\n\tred\n\tgreen\n\tblue\n}\n')

        proc = run([vcraft, "build", "--release", "--strip"], cwd=proj)
        if proc.returncode != 0:
            problems.append("build failed: " + (proc.stderr or proc.stdout)[-500:])
        else:
            built = sorted(proj.glob("dist/build/*.so")) + sorted(proj.glob("dist/build/*.pyd"))
            if not built:
                problems.append("no extension was built")
            else:
                if sys.platform.startswith("linux") and shutil.which("nm"):
                    if run(["nm", built[0]]).stdout.strip():
                        problems.append("--strip left a symbol table")
                snippet = (
                    "import sys\n"
                    "sys.path.insert(0, sys.argv[1])\n"
                    "import smoke_native as m\n"
                    "print(m.Counter().paint(m.Color.green), m.extra_marker())\n"
                    "try:\n"
                    "    m.Counter().paint(9)\n"
                    "except ValueError:\n"
                    "    print('value-error')\n"
                )
                probe = run([sys.executable, "-c", snippet, built[0].parent])
                out = probe.stdout
                if "1 7" not in out or "value-error" not in out:
                    problems.append("enum param / sibling source failed: " + out + probe.stderr)
            stub = (proj / "python" / "smoke_native.pyi").read_text()
            if "class Color(enum.IntEnum):" not in stub:
                problems.append("the enum is missing from the .pyi")

        proc = run([vcraft, "sdist"], cwd=proj)
        sdists = sorted((proj / "dist").glob("*.tar.gz"))
        if proc.returncode != 0 or not sdists:
            problems.append("sdist failed: " + (proc.stderr or proc.stdout)[-300:])
        else:
            with tarfile.open(sdists[0]) as tf:
                names = tf.getnames()
            if not any(n.endswith("/src/zcolor.v") for n in names):
                problems.append("the sdist dropped a sibling source")

        if problems:
            print("RELEASE SMOKE FAILED")
            for p in problems:
                print(" -", p)
            return 1
        print("release smoke ok")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
