#!/usr/bin/env python3
"""Tests for the vcraft runtime, driven through a hand-written extension.

It builds the extension itself through `scripts/build-runtime-tests.sh`, like the
other suites, and needs nothing but the standard library:

    python3 tests/runtime/test_runtime.py
"""

import subprocess
import sys
import sysconfig
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / "build"
MODULE = "vcraft_runtime_check"


def find_extension() -> Path | None:
    """Locate the built module, accepting either a plain or a tagged name."""
    preferred = BUILD / f"{MODULE}{sysconfig.get_config_var('EXT_SUFFIX') or '.so'}"
    if preferred.exists():
        return preferred
    candidates = sorted(BUILD.glob(f"{MODULE}*.so"))
    return candidates[0] if candidates else None


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

    def raises(self, label: str, exc_type, needle: str, call) -> None:
        try:
            result = call()
        except exc_type as exc:
            self.check(label, needle in str(exc), f"got {exc!r}")
        except Exception as exc:  # noqa: BLE001
            self.check(label, False, f"raised {type(exc).__name__}: {exc}")
        else:
            self.check(label, False, f"returned {result!r}, no exception")


def build() -> None:
    """Rebuild every time: a stale module would test yesterday's runtime."""
    print("building the runtime test extension")
    proc = subprocess.run([str(ROOT / "scripts" / "build-runtime-tests.sh")],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"build failed:\n{proc.stdout}\n{proc.stderr}")


def main() -> int:
    build()
    extension = find_extension()
    if extension is None:
        print(f"missing {BUILD}/{MODULE}*.so after a successful build")
        return 1

    sys.path.insert(0, str(BUILD))
    import vcraft_runtime_check as m

    t = Suite()

    print("module definition")
    t.check("module name", m.__name__ == MODULE)
    t.check("module __doc__", "vcraft runtime" in (m.__doc__ or ""))
    t.check(
        "extension suffix",
        m.__file__.endswith(sysconfig.get_config_var("EXT_SUFFIX") or ".so"),
        f"got {m.__file__}",
    )
    t.check("function docstring", m.answer.__doc__ == "Return the answer.")
    t.check("signature docstring", m.add.__doc__ == "add(a, b)")

    print("METH_NOARGS")
    t.equal("answer()", m.answer(), 42)

    print("METH_FASTCALL and integers")
    t.equal("add(2, 3)", m.add(2, 3), 5)
    t.equal("add(-5, 5)", m.add(-5, 5), 0)
    t.equal("add at large values", m.add(2**62, 2**61), 3 * 2**61)
    t.equal("add large negative", m.add(-(2**62), -(2**62)), -(2**63))

    print("strings and floats")
    t.equal("greet", m.greet("world"), "Hello, world!")
    t.equal("greet non-ascii", m.greet("mundo"), "Hello, mundo!")
    t.equal("describe positive", m.describe(1.5), "non-negative")
    t.equal("describe negative", m.describe(-1.5), "negative")
    t.equal("describe int widened to float", m.describe(2), "non-negative")

    print("None, bool and opaque objects")
    t.check("maybe(True)", m.maybe(True) == 42)
    t.check("maybe(False) is None", m.maybe(False) is None)
    t.equal("identity keeps the object", m.identity([1, 2, 3]), [1, 2, 3])
    t.check("identity returns the same object", m.identity(sentinel := []) is sentinel)
    t.equal("sum_all over a list", m.sum_all([1, 2, 3, 4]), 10)
    t.equal("sum_all over a tuple", m.sum_all((5, 5)), 10)
    t.equal("sum_all empty", m.sum_all([]), 0)

    print("layout check")
    major, minor = sys.version_info[:2]
    t.check("layout()", m.layout() == f"{major}.{minor} api=1013", f"got {m.layout()}")

    print("V error becomes RuntimeError")
    t.raises("greet('')", RuntimeError, "name must not be empty", lambda: m.greet(""))

    print("V panic becomes RuntimeError, interpreter survives")
    t.raises("division by zero", RuntimeError, "division by zero",
             lambda: m.checked(1, 0))
    t.raises("explicit panic", RuntimeError, "deliberate panic", lambda: m.boom())
    t.equal("still working afterwards", m.answer(), 42)
    t.equal("arith intact afterwards", m.add(20, 22), 42)

    print("argument errors are TypeError")
    t.raises("too few", TypeError, "takes 2 positional", lambda: m.add(1))
    t.raises("too many", TypeError, "takes at most", lambda: m.add(1, 2, 3))
    t.raises("str for int", TypeError, "expected int", lambda: m.add("x", 1))
    t.raises("bool for int", TypeError, "expected int", lambda: m.add(True, 1))
    t.raises("int for str", TypeError, "expected str", lambda: m.greet(5))
    t.raises("int for float", TypeError, "expected float", lambda: m.describe("x"))

    print("huge integers overflow cleanly")
    t.raises("beyond int64", OverflowError, "out of range", lambda: m.add(2**64, 1))

    print("symbol table")
    import subprocess

    out = subprocess.run(["nm", "-D", "--defined-only", str(extension)],
                         capture_output=True, text=True).stdout
    exported = {
        line.split()[-1]
        for line in out.splitlines()
        if len(line.split()) == 3 and line.split()[1] in ("T", "D", "B", "R", "W")
    }
    allowed = {f"PyInit_{MODULE}", "_v_interface_exports"}
    t.check("only PyInit is exported", exported <= allowed,
            f"extra: {sorted(exported - allowed)}")

    print()
    if t.failures:
        print(f"{len(t.failures)} failure(s): {', '.join(t.failures)}")
        return 1
    print(f"all {t.passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
