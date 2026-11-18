"""Finding the vcraft binary, for the tools that drive it from Python.

Kept apart from `vcraft_tool.auto`, which installs its import hook when imported: the
pytest plugin needs the binary but must not turn every `import x` of a test session into
a search for `x.v`.
"""

from __future__ import annotations

import os
import shutil


def vcraft_binary() -> str:
    """The vcraft binary: `VCRAFT_BIN`, the one bundled with this package, or PATH."""
    override = os.environ.get("VCRAFT_BIN")
    if override:
        return override
    try:
        from vcraft_tool._launch import _binary

        return _binary()
    except (ImportError, SystemExit):
        pass
    found = shutil.which("vcraft")
    if found:
        return found
    raise ImportError("vcraft is not installed: `pip install vcraft`, or set VCRAFT_BIN")
