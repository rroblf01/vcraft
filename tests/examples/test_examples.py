"""The examples gallery builds and its programs pass.

Each project under examples/ named in GALLERY is built with bin/vcraft into a scratch
directory (the tree is left as it was) and its `test_*.py` is run with the built module
importable. NumPy is optional: the NumPy kernel's own test checks plain buffers without
it and NumPy results with it.

    python3 tests/examples/test_examples.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tests"))

import vcraft_build  # noqa: E402

GALLERY = ["async_server", "csv_parser", "numpy_kernel", "with_c", "fuzzy_match"]
VCRAFT = vcraft_build.VCRAFT


def main() -> int:
    vcraft_build.build_vcraft()
    failures = []
    passed = 0
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-examples-"))
    try:
        for name in GALLERY:
            source = ROOT / "examples" / name
            project = tmp / name
            # Copied so a build's generated files never land in the checkout.
            shutil.copytree(source, project, ignore=shutil.ignore_patterns(
                "build", "dist", ".vcraft", "__pycache__", "_vcraft_generated.v"))
            proc = subprocess.run([str(VCRAFT), "build", "--release", "--skip-audit"],
                                  cwd=project, capture_output=True, text=True)
            built = sorted((project / "dist" / "build").glob("*.so")) + sorted(
                (project / "dist" / "build").glob("*.pyd"))
            if proc.returncode != 0 or not built:
                print(f"  FAIL {name} builds\n{(proc.stderr or proc.stdout)[-1500:]}")
                failures.append(name)
                continue
            print(f"  ok   {name} builds")
            passed += 1
            env = dict(os.environ, PYTHONPATH=os.pathsep.join(
                [str(built[0].parent), str(project)]))
            for test in sorted(project.glob("test_*.py")):
                run = subprocess.run([sys.executable, str(test)], cwd=project, env=env,
                                     capture_output=True, text=True, timeout=600)
                if run.returncode != 0:
                    print(f"  FAIL {name}: {test.name}\n{(run.stderr or run.stdout)[-1500:]}")
                    failures.append(f"{name}/{test.name}")
                else:
                    print(f"  ok   {name}: {run.stdout.strip().splitlines()[-1]}")
                    passed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    if failures:
        print(f"{len(failures)} failure(s): {', '.join(failures)}")
        return 1
    print(f"all {passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
