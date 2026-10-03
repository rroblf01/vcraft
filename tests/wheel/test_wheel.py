"""Checks the wheel writer: the container, the hashes, and a real install.

Every assertion here is against a library that already exists and is already
correct: `zipfile` for the container, `hashlib` for the hashes, and `pip` for the
install. Nothing re-implements the format here, because a test that shares its
assumptions with the code proves nothing.
"""

from __future__ import annotations

import base64
import hashlib
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BUILD = ROOT / "build"
WHEEL_GLOB = "vcraft_demo-*.whl"


def check(label: str, condition: bool, detail: str = "") -> bool:
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FAIL {label} {detail}")
    return False


def find_wheel() -> Path:
    wheels = sorted(BUILD.glob(WHEEL_GLOB))
    if not wheels:
        raise SystemExit(
            f"no wheel in {BUILD}; run ./scripts/build-wheel-test.sh first"
        )
    return wheels[-1]


def build_archive() -> None:
    subprocess.run([str(ROOT / "scripts" / "build-wheel-test.sh")],
                   check=True, capture_output=True)


def main() -> int:
    build_archive()
    wheel = find_wheel()
    passed = 0
    failed = 0

    def t(label: str, condition: bool, detail: str = "") -> None:
        nonlocal passed, failed
        if check(label, condition, detail):
            passed += 1
        else:
            failed += 1

    print("container")
    with zipfile.ZipFile(wheel) as z:
        t("zipfile opens it", True)
        t("every entry decompresses", z.testzip() is None, str(z.testzip()))
        names = z.namelist()
        t("carries the extension",
          any(n.endswith(".so") for n in names), str(names))
        t("carries METADATA",
          any(n.endswith(".dist-info/METADATA") for n in names), str(names))
        t("carries WHEEL",
          any(n.endswith(".dist-info/WHEEL") for n in names), str(names))
        t("carries RECORD",
          any(n.endswith(".dist-info/RECORD") for n in names), str(names))
        t("the extension is at the root, not in a package directory",
          all("/" not in n for n in names if n.endswith(".so")), str(names))

        print("compression")
        # A wheel that stores its payload is installable but doubles the download,
        # and the directory's `compress_type` says which one was written.
        for info in z.infolist():
            if info.filename.endswith(".so"):
                t("the extension is deflated", info.compress_type == 8,
                  f"method {info.compress_type}")
                t("compression actually shrinks it",
                  info.compress_size < info.file_size,
                  f"{info.compress_size} vs {info.file_size}")

        print("metadata")
        wheel_meta = z.read("vcraft_demo-0.1.0.dist-info/WHEEL").decode()
        t("wheel version", "Wheel-Version: 1.0" in wheel_meta)
        t("not pure Python", "Root-Is-Purelib: false" in wheel_meta,
          "a wheel holding an extension must not claim to be pure")
        t("tag matches the file name",
          "cp314-cp314-manylinux_2_17_x86_64" in wheel_meta
          and "manylinux_2_17_x86_64" in wheel.name, wheel.name)

        meta = z.read("vcraft_demo-0.1.0.dist-info/METADATA").decode()
        t("metadata version", meta.startswith("Metadata-Version:"), meta[:40])
        t("name matches the dist-info directory",
          "Name: vcraft-demo" in meta, meta[:120])
        t("version", "Version: 0.1.0" in meta)
        t("summary", "Summary: A demo package built by vcraft" in meta)
        t("requires-python", "Requires-Python: >=3.12" in meta)
        t("classifiers survive", "Classifier: Programming Language :: V" in meta)

        print("record")
        record = z.read("vcraft_demo-0.1.0.dist-info/RECORD").decode()
        rows = {}
        for line in record.strip().split("\n"):
            path, digest, size = line.split(",")
            rows[path] = (digest, size)
        t("every file is listed", len(rows) == len(names),
          f"{len(rows)} rows for {len(names)} files")
        for path, (digest, size) in rows.items():
            if path.endswith("RECORD"):
                t("RECORD has no hash of itself", digest == "", digest)
                continue
            want = base64.urlsafe_b64encode(
                hashlib.sha256(z.read(path)).digest()
            ).rstrip(b"=").decode()
            t(f"sha256 of {path.split('/')[-1]}", digest == f"sha256={want}",
              f"{digest} vs sha256={want}")
            t(f"size of {path.split('/')[-1]}", size == str(len(z.read(path))))

        print("decompression")
        # Read the deflate stream directly: `zipfile` would hide whether the bytes are
        # a real DEFLATE stream or just something that happens to round-trip.
        so_name = [n for n in names if n.endswith(".so")][0]
        with zipfile.ZipFile(wheel) as z:
            info = z.getinfo(so_name)
            expected = z.read(so_name)
        raw = wheel.read_bytes()
        start = 30 + len(info.filename.encode())
        payload = raw[start:start + info.compress_size]
        try:
            out = zlib.decompress(payload, -15)
            t("the payload is a raw DEFLATE stream", out == expected)
        except zlib.error as exc:
            t("the payload is a raw DEFLATE stream", False, str(exc))

    print("install")
    # The check that matters: pip reads the name, unpacks, and puts the extension
    # somewhere import can find it. A wheel can satisfy every assertion above and
    # still fail here, which is why this is not optional.
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-wheel-"))
    try:
        venv = tmp / "venv"
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True,
                       capture_output=True)
        python = venv / "bin" / "python"
        proc = subprocess.run(
            [str(python), "-m", "pip", "install", "--no-index", "--no-deps",
             str(wheel)],
            capture_output=True, text=True,
        )
        t("pip installs it", proc.returncode == 0,
          (proc.stderr or proc.stdout).strip()[-300:])

        script = (
            "import hello_native as h\n"
            "print(h.add(2, 3))\n"
            "print(h.greet('Ana'))\n"
            "c = h.Counter()\n"
            "c.increment()\n"
            "print(repr(c))\n"
            "try:\n"
            "    h.divide(1.0, 0.0)\n"
            "except ZeroDivisionError:\n"
            "    print('zero-division')\n"
            "import importlib.metadata as md\n"
            "print(md.version('vcraft-demo'))\n"
        )
        proc = subprocess.run([str(python), "-c", script],
                              capture_output=True, text=True, cwd=tmp)
        t("the installed extension imports and works",
          proc.returncode == 0, (proc.stderr or "").strip()[-300:])
        if proc.returncode == 0:
            lines = proc.stdout.split()
            t("functions survive the round trip", "5" in lines, proc.stdout)
            t("classes survive the round trip", "Counter(value:" in proc.stdout,
              proc.stdout)
            t("domain exceptions survive", "zero-division" in lines,
              proc.stdout)
            t("metadata is readable", "0.1.0" in lines, proc.stdout)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if failed:
        print(f"{failed} failure(s)")
        return 1
    print(f"all {passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
