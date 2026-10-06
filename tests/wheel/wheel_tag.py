"""Prints the wheel tag of the running interpreter, e.g. `cp313-cp313-linux_x86_64`.

Shared by `scripts/build-wheel-test.sh`, which stamps it on the wheel, and
`test_wheel.py`, which expects it, so the two cannot disagree.
"""

import sys
import sysconfig


def tag() -> str:
    version = f"{sys.version_info[0]}{sys.version_info[1]}"
    abi = "cp" + version + ("t" if sysconfig.get_config_var("Py_GIL_DISABLED") else "")
    platform = sysconfig.get_platform().replace("-", "_").replace(".", "_")
    return f"cp{version}-{abi}-{platform}"


if __name__ == "__main__":
    print(tag())
