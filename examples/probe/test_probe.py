#!/usr/bin/env python3
"""Gate 0: a shared object compiled by V loads as a CPython extension module.

Uses only the standard library, so it runs against any CPython with no virtual
environment and no installed packages:

    cd examples/probe
    ../../scripts/build-probe.sh
    python3 test_probe.py
"""

import subprocess
import sys
import sysconfig
from pathlib import Path

HERE = Path(__file__).resolve().parent


def find_extension() -> Path | None:
    """Locate the built module, accepting either a plain or a tagged name."""
    preferred = HERE / f"probe{sysconfig.get_config_var('EXT_SUFFIX') or '.so'}"
    if preferred.exists():
        return preferred
    candidates = sorted(HERE.glob("probe*.so"))
    return candidates[0] if candidates else None


SO = find_extension()

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


def main() -> int:
    if not SO.exists():
        print(f"missing {SO}; run scripts/build-probe.sh first")
        return 1

    sys.path.insert(0, str(HERE))

    print("module definition")
    import probe  # noqa: E402

    check("module imports", probe.__name__ == "probe")
    check("module __doc__", "V compiler" in (probe.__doc__ or ""))
    check(
        "extension file name",
        probe.__file__.endswith(
            sysconfig.get_config_var("EXT_SUFFIX") or ".so"
        ),
        f"got {probe.__file__}",
    )

    print("METH_NOARGS")
    check("answer() == 42", probe.answer() == 42, f"got {probe.answer()!r}")
    check("answer.__doc__", probe.answer.__doc__ == "Return the answer.")
    check("is a builtin", type(probe.answer).__name__ == "builtin_function_or_method")

    print("METH_FASTCALL and argument marshalling")
    check("add(2, 3) == 5", probe.add(2, 3) == 5)
    check("add(-5, 5) == 0", probe.add(-5, 5) == 0)
    check("add(int, int) docstring", probe.add.__doc__ == "add(a, b)")

    print("error propagation")
    for call, expected in (
        (lambda: probe.add(1), "takes exactly 2"),
        (lambda: probe.add(1, 2, 3), "takes exactly 2"),
        (lambda: probe.add(1, "x"), "cannot be interpreted as an integer"),
        (lambda: probe.add(1, None), "cannot be interpreted as an integer"),
    ):
        try:
            call()
        except TypeError as exc:
            check(f"TypeError for {expected[:24]!r}", expected in str(exc), f"got {exc}")
        else:
            check(f"TypeError for {expected[:24]!r}", False, "no exception raised")

    print("dynamic symbol table")
    out = subprocess.run(
        ["nm", "-D", "--defined-only", str(SO)], capture_output=True, text=True
    ).stdout
    exported = [
        line.split()[-1]
        for line in out.splitlines()
        if len(line.split()) == 3 and line.split()[1] in ("T", "D", "B", "R", "W")
    ]
    check("PyInit_probe is exported", "PyInit_probe" in exported)
    check(
        "nothing else from the module leaks",
        set(exported) <= {"PyInit_probe", "_v_interface_exports"},
        f"extra symbols: {sorted(set(exported) - {'PyInit_probe', '_v_interface_exports'})}",
    )

    print()
    if failures:
        print(f"{len(failures)} failure(s): {', '.join(failures)}")
        return 1
    print("gate 0 passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
