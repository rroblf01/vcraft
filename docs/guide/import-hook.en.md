# Importing `.v` files and notebooks

Not every piece of V needs a project. For a script, an experiment or a notebook, the
`vcraft_tool` package that `pip install vcraft` brings in can build a single V file on
import, the way `pyximport` does for Cython.

## `import vcraft_tool.auto`

```python
import vcraft_tool.auto   # installs the import hook
import fastmath           # builds fastmath.v found on sys.path, then imports it

print(fastmath.square(12))
```

`fastmath.v` is the whole module:

```v
@[vc_fn]
pub fn square(x int) int {
	return x * x
}
```

- Without a `module` line one is added; with one, it must name the module being imported.
- The build is cached under `$VCRAFT_HOME/auto` (else `$XDG_CACHE_HOME/vcraft/auto`, else
  `~/.cache/vcraft/auto`), keyed by the source, the interpreter, the platform and the
  vcraft version. The first import compiles (seconds); later ones load the cached module.
- Editing the file rebuilds it on the next import in a new process. An extension module
  cannot be reloaded inside a running interpreter.
- Builds are `--release`. A compile error is raised as `ImportError` with the compiler's
  message.
- `vcraft_tool.auto.build(source, name)` builds V source held in a string and returns the
  path of the extension; `vcraft_tool.auto.load(path, name)` imports it.

The binary used is `$VCRAFT_BIN` when set, else the one bundled with the installed
`vcraft` package, else `vcraft` on `PATH`.

## Jupyter and IPython: `%%vcraft`

```python
%load_ext vcraft_tool.jupyter
```

```v
%%vcraft
@[vc_fn]
pub fn add(a int, b int) int {
	return a + b
}
```

After the cell runs, `add` is a name in the notebook. Every public name the cell exports
is copied into the user namespace; `%%vcraft mod` also binds the module itself to `mod`.
Each distinct cell text is its own module (`vcraft_cell_<hash>`), so editing and
re-running a cell loads the new code without restarting the kernel.

When the code outgrows a cell, `vcraft new` (or `vcraft init` in an existing Python
project) turns it into a package with a wheel.
