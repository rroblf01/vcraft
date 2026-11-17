"""V in a Jupyter or IPython notebook.

    %load_ext vcraft_tool.jupyter

    %%vcraft
    @[vc_fn]
    pub fn add(a int, b int) int {
        return a + b
    }

After the cell runs, `add` is defined in the notebook. Every name the cell exports is
copied into the user namespace; `%%vcraft name` also keeps the module itself under
`name`. Each version of a cell is its own module, so editing and re-running a cell loads
the new code -- an extension module cannot be reloaded in place.
"""

from __future__ import annotations

import hashlib

from vcraft_tool import auto


def compile_cell(source: str, name: str | None = None, namespace: dict | None = None):
    """Build `source`, import it, and copy its public names into `namespace`."""
    digest = hashlib.sha1(source.encode()).hexdigest()[:12]
    module_name = f"vcraft_cell_{digest}"
    module = auto.load(auto.build(source, module_name), module_name)
    if namespace is not None:
        for key in dir(module):
            if not key.startswith("_"):
                namespace[key] = getattr(module, key)
        if name:
            namespace[name] = module
    return module


def load_ipython_extension(ipython) -> None:
    """Register the `%%vcraft` cell magic."""

    def vcraft(line: str, cell: str):
        compile_cell(cell, line.strip() or None, ipython.user_ns)

    ipython.register_magic_function(vcraft, "cell", "vcraft")
