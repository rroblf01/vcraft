#!/usr/bin/env python3
"""Assemble the pip-installable vcraft wheel for one platform.

vcraft itself is a compiled binary plus its V modules, not a Python package,
so there is nothing for a Python build backend to build: the release workflow
compiles the binary per platform and this script wraps each result in a wheel.
Same distribution trick as the `cmake` and `ninja` PyPI packages.

Layout inside the wheel::

    vcraft_tool/__init__.py      version only
    vcraft_tool/__main__.py      `python -m vcraft_tool`
    vcraft_tool/_launch.py       finds bin/vcraft next to itself and execs it
    vcraft_tool/bin/vcraft      the compiled binary, executable bit preserved
    vcraft_tool/vlib/...        the V modules `-path` points at when building
    vcraft-0.1.0.dist-info/...  METADATA with the README as its description,
                                and licenses/LICENSE

Deliberately no sdist: a source distribution of a launcher with no binary
installs something that cannot run. Wheels only.

Usage:
    scripts/pack-vcraft-wheel.py --version 0.1.0 --platform linux_x86_64 \
        --bin bin/vcraft --vlib vlib --out-dir dist
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/rroblf01/vcraft"

SUMMARY = ("Native Python extensions written in V: CPython bindings, "
           "a code generator and a wheel builder in one tool")

KEYWORDS = "v,vlang,python-extension,cpython,bindings,ffi,wheel,build-backend,pyo3,maturin"

CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Environment :: Console",
    "Intended Audience :: Developers",
    "Operating System :: MacOS",
    "Operating System :: POSIX :: Linux",
    "Programming Language :: Other",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3 :: Only",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: Python :: 3.13",
    "Programming Language :: Python :: 3.14",
    "Programming Language :: Python :: Implementation :: CPython",
    "Topic :: Software Development :: Build Tools",
    "Topic :: Software Development :: Code Generators",
    "Topic :: Software Development :: Compilers",
    "Topic :: System :: Software Distribution",
]

# A Markdown link or image whose target is a path in the repository rather than a
# URL or an in-page anchor.
_RELATIVE_LINK = re.compile(r"(\]\()(?!https?://|mailto:|#)([^)\s]+)(\))")


def pypi_readme(text: str, version: str) -> str:
    """The README as PyPI should render it.

    PyPI shows the description on its own page, where a link such as
    `vlib/vcraft/README.md` resolves against pypi.org and 404s. Each one is pointed
    at the file on GitHub, at the tag this version was released from, so the page
    keeps describing the release it belongs to after `main` moves on.
    """
    base = f"{REPOSITORY}/blob/vcraft/v{version}/"
    return _RELATIVE_LINK.sub(lambda m: m.group(1) + base + m.group(2).removeprefix("./")
                              + m.group(3), text)


def metadata(version: str, readme: str) -> str:
    """Core metadata 2.4: License-Expression and License-File need it."""
    head = [
        "Metadata-Version: 2.4",
        "Name: vcraft",
        f"Version: {version}",
        f"Summary: {SUMMARY}",
        f"Keywords: {KEYWORDS}",
        "Author: Ricardo Robles",
        "License-Expression: MIT",
        "License-File: LICENSE",
        f"Project-URL: Homepage, {REPOSITORY}",
        f"Project-URL: Source, {REPOSITORY}",
        f"Project-URL: Documentation, {REPOSITORY}#readme",
        f"Project-URL: Changelog, {REPOSITORY}/blob/main/CHANGELOG.md",
        f"Project-URL: Issues, {REPOSITORY}/issues",
        *(f"Classifier: {c}" for c in CLASSIFIERS),
        "Requires-Python: >=3.11",
        "Description-Content-Type: text/markdown; charset=UTF-8; variant=GFM",
    ]
    # The description is the message body, after one blank line, as in an email.
    return "\n".join(head) + "\n\n" + pypi_readme(readme, version)

INIT_PY = '''"""The vcraft pip package: a launcher for the bundled binary."""
__version__ = "{version}"
'''

MAIN_PY = '''"""`python -m vcraft_tool`."""
from vcraft_tool._launch import main

main()
'''

LAUNCH_PY = '''"""Launch the bundled vcraft binary.

The binary lives next to this file, whatever directory pip installed the
package into, so it is located relative to `__file__` rather than through
PATH: a `vcraft` from somewhere else on PATH would be a different version,
and silently running it is how a stale binary debugs the wrong project.
"""
from __future__ import annotations

import os
import sys


def _binary() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    exe = os.path.join(here, "bin", "vcraft")
    if not os.path.isfile(exe):
        raise SystemExit(f"vcraft binary not found at {exe}")
    return exe


def main() -> None:
    exe = _binary()
    os.execv(exe, [exe, *sys.argv[1:]])


if __name__ == "__main__":
    main()
'''

# Fixed timestamps keep the wheel byte-identical across rebuilds of the same
# inputs. pip does not care, but a rebuild that differs for no reason makes
# every diff meaningless.
ZIP_DATE = (2020, 1, 1, 0, 0, 0)


def _record_hash(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return "sha256=" + base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def _add(archive: zipfile.ZipFile, name: str, data: bytes,
         executable: bool = False) -> None:
    info = zipfile.ZipInfo(name, date_time=ZIP_DATE)
    # Unix attributes, or unzip restores the binary without its executable
    # bit and the installed `vcraft` command fails with "permission denied".
    # The file-type bits are part of it: pip only treats an entry as
    # executable when `stat.S_ISREG` matches, so bare `0o755` is ignored and
    # the bit has to be `0o100755`.
    info.create_system = 3
    info.external_attr = ((0o100000 | (0o755 if executable else 0o644)) << 16)
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, data)


def build_wheel(version: str, platform: str, binary: Path, vlib: Path,
                readme: Path = ROOT / "README.md",
                license_file: Path = ROOT / "LICENSE") -> bytes:
    import io

    dist_info = f"vcraft-{version}.dist-info"
    buf = io.BytesIO()
    record_rows: list[str] = []

    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as archive:
        def put(name: str, data: bytes, executable: bool = False) -> None:
            _add(archive, name, data, executable)
            record_rows.append(f"{name},{_record_hash(data)},{len(data)}")

        put("vcraft_tool/__init__.py", INIT_PY.format(version=version).encode())
        put("vcraft_tool/__main__.py", MAIN_PY.encode())
        put("vcraft_tool/_launch.py", LAUNCH_PY.encode())
        put("vcraft_tool/bin/vcraft", binary.read_bytes(), executable=True)
        for path in sorted(vlib.rglob("*")):
            if path.is_dir():
                continue
            put(f"vcraft_tool/vlib/{path.relative_to(vlib).as_posix()}",
                path.read_bytes())
        put(f"{dist_info}/METADATA",
            metadata(version, readme.read_text(encoding="utf-8")).encode())
        put(f"{dist_info}/licenses/LICENSE", license_file.read_bytes())
        wheel_file = (
            "Wheel-Version: 1.0\n"
            "Generator: vcraft pack script\n"
            "Root-Is-Purelib: false\n"
            f"Tag: py3-none-{platform}\n"
        )
        put(f"{dist_info}/WHEEL", wheel_file.encode())
        entry_points = "[console_scripts]\nvcraft = vcraft_tool._launch:main\n"
        put(f"{dist_info}/entry_points.txt", entry_points.encode())
        record_rows.append(f"{dist_info}/RECORD,,")
        archive.writestr(
            zipfile.ZipInfo(f"{dist_info}/RECORD", date_time=ZIP_DATE),
            "\n".join(record_rows) + "\n",
        )
    return buf.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True,
                        help="PEP 440 version, e.g. 0.1.0 (no leading v)")
    parser.add_argument("--platform", required=True,
                        help="wheel platform tag, e.g. linux_x86_64")
    parser.add_argument("--bin", required=True, help="built bin/vcraft")
    parser.add_argument("--vlib", required=True, help="vlib directory")
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    binary = Path(args.bin)
    vlib = Path(args.vlib)
    if not binary.is_file():
        print(f"error: no binary at {binary}", file=sys.stderr)
        return 1
    if not (vlib / "vcraft").is_dir() or not (vlib / "vcraft_project").is_dir():
        print(f"error: {vlib} does not look like vcraft's vlib", file=sys.stderr)
        return 1
    if args.version.startswith("v"):
        print("error: version must not start with v", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    name = f"vcraft-{args.version}-py3-none-{args.platform}.whl"
    (out_dir / name).write_bytes(
        build_wheel(args.version, args.platform, binary, vlib))
    print(str(out_dir / name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
