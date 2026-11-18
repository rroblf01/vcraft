#!/usr/bin/env python3
"""Regenerate the GitHub Actions workflows kept in templates/ci/.

They are what `vcraft new --with-ci` and `vcraft generate-ci` write, for a project named
`mypkg`, in the three shapes the matrix takes:

    templates/ci/build.yml               one wheel per CPython (the default)
    templates/ci/build-abi3.yml          `abi3 = "3.11"`: one stable-ABI wheel per platform
    templates/ci/build-free-threading.yml  `free-threading = true`: 3.13t and later

They are kept as text for reading and copying: rename `mypkg`/`mypkg_native`, or better,
run `vcraft generate-ci` in the project. They live outside .github/workflows, so they never
run here.

    python3 scripts/update-ci-templates.py          # rewrite them from bin/vcraft
    python3 scripts/update-ci-templates.py --check  # exit 1 if any is out of date
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "templates" / "ci"
VARIANTS = {
    "build.yml": "",
    "build-abi3.yml": 'abi3 = "3.11"\n',
    "build-free-threading.yml": "free-threading = true\n",
}


def generate(vcraft: Path) -> dict[str, str]:
    out = {}
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-ci-templates-"))
    try:
        for name, setting in VARIANTS.items():
            work = tmp / name.removesuffix(".yml")
            work.mkdir()
            subprocess.run([str(vcraft), "new", "mypkg"], cwd=work, check=True,
                           capture_output=True)
            project = work / "mypkg"
            manifest = project / "vcraft.toml"
            manifest.write_text(manifest.read_text().replace("[build]\n", "[build]\n" + setting, 1))
            subprocess.run([str(vcraft), "generate-ci"], cwd=project, check=True,
                           capture_output=True)
            out[name] = (project / ".github" / "workflows" / "build.yml").read_text()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--vcraft", type=Path, default=ROOT / "bin" / "vcraft")
    args = parser.parse_args()
    if not args.vcraft.exists():
        subprocess.run([str(ROOT / "scripts" / "build-vcraft.sh")], check=True)
    fresh = generate(args.vcraft)
    stale = [n for n, text in fresh.items()
             if not (OUT / n).exists() or (OUT / n).read_text() != text]
    if args.check:
        if stale:
            print(f"out of date: {', '.join(stale)}; run scripts/update-ci-templates.py")
            return 1
        print("ok: templates/ci matches vcraft generate-ci")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in fresh.items():
        (OUT / name).write_text(text)
        print(f"wrote templates/ci/{name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
