# vcraft

**Native Python extensions for V, written in V.**

`vcraft` is to the V language what **PyO3 + maturin** is to Rust: a set of bindings for the CPython C API, plus a build and packaging toolchain that turns a directory of V source files into a distributable Python wheel.

There is **no Rust and no C++ in the pipeline**. A `.v` file compiles to a CPython extension module, the annotations you write on your V declarations become the Python API surface, and `vcraft build` produces a wheel you can upload to PyPI.

```v
// src/lib.v
module mi_extension_nativa

// Suma dos enteros y los devuelve.
@[vc.fn]
pub fn add(a int, b int) int {
	return a + b
}
```

```python
>>> import mi_extension_nativa as m
>>> m.add(2, 3)
5
```

```bash
vcraft new mi_extension_nativa
cd mi_extension_nativa
vcraft develop
vcraft build --release
```

---

## Table of contents

- [Why](#why)
- [How it works](#how-it-works)
- [The annotation vocabulary](#the-annotation-vocabulary)
- [Type marshalling](#type-marshalling)
- [Classes and properties](#classes-and-properties)
- [Errors and panics](#errors-and-panics)
- [The command line](#the-command-line)
- [Generated project layout](#generated-project-layout)
- [Continuous integration](#continuous-integration)
- [Configuration](#configuration)
- [Roadmap](#roadmap)
- [Status](#status)
- [Requirements](#requirements)
- [Design notes](#design-notes)
- [License](#license)

---

## Why

V compiles to fast native code through a tiny C backend and has no runtime dependencies of its own. That makes it a good fit for native Python extensions, but there has been no equivalent of PyO3: writing to the CPython C API from V means hand-declaring every foreign function, hand-writing the module initialiser, and hand-rolling the wheel.

`vcraft` removes all three chores.

|                    | Rust ecosystem     | vcraft                          |
| ------------------ | ------------------ | ------------------------------- |
| Native bindings    | PyO3               | `vlib/vcraft` (written in V)    |
| Binding generation | `#[pyfunction]`    | `@[vc.fn]`                      |
| Class bindings     | `#[pyclass]`       | `@[vc.class]`                   |
| Error translation  | `Result<T, E>`     | `!T` / `error` / `recover()`    |
| GIL handling       | `Python::detach`   | `@[vc.gil]`                     |
| Build tool         | maturin            | `vcraft build`                  |
| Local install      | `maturin develop`  | `vcraft develop`                |
| CI                 | `maturin-action`   | `vcraft-action@v1`              |
| Dependency install | `cargo add`        | `v import`                      |

---

## How it works

A CPython extension module is nothing more than a shared library that exports a
single symbol, `PyInit_<name>`. V can already produce exactly that:

```
v -shared -o mi_extension_nativa/_core.cpython-314-x86_64-linux-gnu.so src/
```

Three properties of V's `-shared` mode make this work cleanly:

1. **Symbol control.** `-shared` compiles with `-fvisibility=hidden` and
   `-Wl,--exclude-libs,ALL`, so only declarations carrying an `@[export: '...']`
   attribute appear in the dynamic symbol table. `PyInit_mi_extension_nativa` is
   exported; nothing else is.
2. **Automatic lifecycle.** V emits `_vinit_caller` and `_vcleanup_caller` as ELF
   constructors and destructors, so the V runtime and its garbage collector are
   initialised when CPython `dlopen`s the module and torn down when it is unloaded.
   No manual init hook is needed.
3. **No link against `libpython`.** Extension modules leave the `Py*` symbols
   undefined; the dynamic linker resolves them against the already-loaded
   `libpython` in the global scope. This is how every CPython extension works, and
   it is why a wheel built for one CPython minor version stays tied to it.

On top of that, `vcraft` adds a code generator. It parses your V sources,
discovers the annotated declarations, and emits the glue that CPython needs:

```
src/lib.v  ──vcraft codegen──▶  src/_vcraft_generated.v
                                          │
                                          ▼
                         v -shared  ──▶  mi_extension_nativa/
                                            ├── __init__.py
                                            ├── helpers.py
                                            ├── _stubs.pyi
                                            └── _core.cpython-314-x86_64-linux-gnu.so
                                          │
                                          ▼
                              dist/mi_extension_nativa-0.1.0-cp314-cp314-linux_x86_64.whl
```

The generated glue is a normal V file. It calls your functions with their real V
types, so a call from Python becomes a direct C call with no intermediate
marshalling layer and no boxing.

---

## The annotation vocabulary

Annotations are read from your source text. V keeps declaration attributes in the
type checker rather than in the parse tree, so `vcraft` reads the `@[...]` block
that immediately precedes each declaration. Any name works; these are the ones
`vcraft` recognises.

| Annotation      | Applies to      | Effect                                                     |
| --------------- | --------------- | ---------------------------------------------------------- |
| `@[vc.fn]`      | `pub fn`        | Exports the function as a module-level Python callable      |
| `@[vc.class]`   | `pub struct`    | Creates a Python type backed by the V struct                |
| `@[vc.methods]` | methods         | Adds the method to the class of its receiver                |
| `@[vc.field]`   | struct fields   | Exposes the field as an attribute of the instance           |
| `@[vc.property]`| methods         | Registers the method as a Python `property`                 |
| `@[vc.static]`  | methods         | Registers the method as a `staticmethod`                    |
| `@[vc.raw]`     | `pub fn`        | Skips marshalling; you receive and return `voidptr` yourself |
| `@[vc.gil]`     | `pub fn`        | Runs the call with the GIL released                         |

Names are taken from the V declaration, verbatim. Doc comments become `__doc__`,
and the marshalled signature becomes `__text_signature__`, so `help()` works
without a hand-written stub.

---

## Type marshalling

Values are converted with direct CPython calls whenever a fast path exists — for
example a V `int` becomes `PyLong_AsLongLong`, not a round trip through a
generic value tree.

| V                                | Python                       | Notes                                    |
| -------------------------------- | ---------------------------- | ---------------------------------------- |
| `bool`                           | `bool`                       |                                          |
| `i8` … `i64`, `isize`            | `int`                        | Range-checked on the way out             |
| `u8` … `u64`, `usize`            | `int`                        | Negative inputs raise                    |
| `f32`, `f64`                     | `float`                      |                                          |
| `rune`                           | `str` of length 1            |                                          |
| `string`                         | `str`                        | Decoded as UTF-8                         |
| `[]u8`                           | `bytes`                      | No copy                                  |
| `[]T` (contiguous)               | `list`, or `memoryview`      | Buffer protocol, no copy                 |
| `[N]T` (contiguous)              | `memoryview`                 | Buffer protocol, no copy                 |
| `map[string]V`                   | `dict`                       |                                          |
| `?T`                             | `T` or `None`                |                                          |
| `[N]T` / struct                  | `list` / `dict`              | Of field values                          |
| enum                             | `int`                        | As its `.name`, by default               |
| `voidptr`                        | `PyObject *`                 | Borrowed; you own the reference          |
| `&T`                             | `PyObject *` wrapping a `T`  | Stable identity across the call          |
| `void`, `!void`                  | `None`                       |                                          |
| `!T` / `T!`                      | `T` or raises                | See [Errors and panics](#errors-and-panics) |
| V function type `fn (Args) Ret`   | Python callable              | Arguments become a tuple                 |

Anything not in this table is a compile-time diagnostic pointing at the exact
file, line and column, not a runtime surprise.

---

## Classes and properties

```v
@[vc.class]
pub struct Counter {
mut:
	@[vc.field] value int
	@[vc.field] label string
}

@[vc.methods]
pub fn new_counter(label string) &Counter {
	return &Counter{ label: label }
}

@[vc.methods]
pub fn (c &Counter) increment(by int) int {
	c.value += by
	return c.value
}

@[vc.methods]
@[vc.property]
pub fn (c &Counter) doubled int {
	return c.value * 2
}
```

```python
>>> c = m.new_counter("hits")
>>> c.increment(4)
4
>>> c.doubled
8
>>> c.label
'hits'
```

Instances are created through your own `new_*` constructor, so there is no
implied `__init__` signature to keep in sync. The V pointer behind the instance is
released in `tp_dealloc`, reference cycles are handled by `tp_traverse` and
`tp_clear`, and immutable fields can additionally be exposed as `getset`
descriptors for faster reads than `__dict__`.

---

## Errors and panics

V error propagation and Python exceptions map onto each other directly:

```v
@[vc.fn]
pub fn greet(name string) !string {
	if name.len == 0 {
		return error('name must not be empty')
	}
	return 'Hello, ${name}!'
}
```

```python
>>> m.greet('')
RuntimeError: name must not be empty
```

Any `!T` value whose error stringifies becomes a `RuntimeError`. Failing that, it
becomes a `TypeError` for argument marshalling failures and `ValueError` for
domain violations, chosen by the code generator from the position of the failure.

V `panic` is a harder case. A V program panics by printing a message and calling
`exit(1)`, which inside CPython would take the whole interpreter down. V 0.5 has
Go-style recovery, so every generated wrapper installs a frame:

```v
fn _vcraft_generated__wrap_div(a f64, b f64) f64 {
	defer {
		if msg := recover() {
			vc.set_pending_panic(msg)
		}
	}
	return divide(a, b)
}
```

The panic is caught, enriched with the V file and line, and raised as a
`RuntimeError`. Panic state is thread-local in V, so this remains correct when the
extension is used from a free-threaded interpreter.

`@[vc.gil]` marks a function as pure V with no Python interaction. The GIL is
released around the call, so long-running V code runs in parallel the way
`py.allow_threads` does in PyO3.

---

## The command line

```
vcraft new <name>            scaffold a V project ready for Python
vcraft develop               build and install into the active virtualenv
vcraft build [options]       build a distributable wheel

    --release                compile with -prod
    --abi3 <version>         build one wheel usable from CPython <version> onwards
    --interpreter <path>     build against a specific interpreter
    --out-dir <dir>          output directory (default: dist/)
    --platform <tag>         override the platform tag
    --strip                  strip symbols from the extension
    --skip-audit             do not validate the resulting wheel

vcraft sdist                 build a source distribution
vcraft publish               upload to PyPI (delegates to twine or uv)
vcraft audit                 validate tags, RECORD and metadata of a wheel
vcraft test                  run `v test` and the Python test suite
vcraft generate-ci [github]  emit a ready-to-use CI workflow
vcraft clean                 remove build artefacts
```

`vcraft` never writes to a system location and never installs anything outside
the project. The V runtime module is located relative to the `vcraft` binary
itself and passed to the compiler with `-path`, so `VMODULES` is left untouched.

---

## Generated project layout

```
mi_extension_nativa/
├── pyproject.toml              PEP 621 metadata + vcraft build backend + cibuildwheel config
├── v.mod                       Module { name: 'mi_extension_nativa' }
├── README.md  LICENSE  .gitignore  .gitattributes
├── src/                        the V core
│   ├── lib.v                   your code
│   └── _vcraft_generated.v     generated, git-ignored
├── python/mi_extension_nativa/ the Python part
│   ├── __init__.py
│   ├── helpers.py
│   └── _stubs.pyi              generated, type-checked by pyright/mypy
├── tests/
│   ├── test_basics.py          run by CIBW_TEST_COMMAND
│   └── lib_test.v              run by `vcraft test`
└── .github/workflows/wheels.yml
```

Python and V coexist: pure-V packages get a generated `__init__.py` that
re-exports the extension, while mixed packages can put whatever Python they like
next to it. Both land in the same wheel.

---

## Continuous integration

`vcraft` is a PEP 517 build backend, so the entire
[cibuildwheel](https://cibuildwheel.pypa.io) ecosystem works with it unchanged.
That means one workflow covers Linux, macOS and Windows, every supported CPython,
and free-threaded builds, with no V-specific plumbing.

```yaml
name: wheels

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: pypa/cibuildwheel@v3
        env:
          CIBW_BEFORE_ALL_LINUX: "true"   # v is already in the image
      - uses: actions/upload-artifact@v4
        with:
          name: wheels
          path: wheelhouse/*.whl

  publish:
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      id-token: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: wheels
          path: dist
      - uses: pypa/gh-action-pypi-publish@release/v1
```

Linux wheels are built inside `ghcr.io/vcraft/manylinux`, an image derived from
`quay.io/pypa/manylinux_2_28` with the V compiler and `vcraft` already present, so
`CIBW_BEFORE_ALL_LINUX` has nothing left to install. A musllinux image based on
Alpine covers the musl targets.

For the one-liner experience, `vcraft-action@v1` mirrors `maturin-action`: it
downloads pinned `vcraft` and V releases, runs any `vcraft` command, and can do it
inside a manylinux container.

```yaml
- uses: vcraft/vcraft-action@v1
  with:
    vcraft-version: v0.1.0
    v-version: '0.5.2'
    args: build --release
```

`vcraft generate-ci github` writes the workflow above into
`.github/workflows/wheels.yml`.

---

## Configuration

Everything lives in `pyproject.toml` under `[tool.vcraft]`.

```toml
[project]
name = "mi-extension-nativa"
version = "0.1.0"
requires-python = ">=3.10"

[build-system]
requires = []
build-backend = "vcraft_build"
backend-path = ["_vcraft_build"]

[tool.vcraft]
abi3 = "3.10"            # or "off" for one wheel per CPython version
free-threading = true    # emit Py_mod_gil = Py_MOD_GIL_NOT_USED
gc = "boehm"             # "boehm" (default) or "none"
strip = true
target-dir = "build"
```

| Key               | Default   | Meaning                                                  |
| ----------------- | --------- | -------------------------------------------------------- |
| `abi3`            | `"off"`   | Minimum CPython for a single portable wheel               |
| `free-threading`  | `true`    | Declare the extension as GIL-free                         |
| `gc`              | `"boehm"` | V garbage collector mode passed to `v -gc`                |
| `strip`           | `true`    | Strip the extension                                       |
| `target-dir`      | `"build"` | Scratch directory for intermediate artefacts              |
| `min-manylinux`   | auto      | Oldest manylinux policy to claim                          |

---

## Roadmap

- [x] Compiling a V shared object that CPython imports (`PyInit_` export, ELF
      constructor lifecycle, unresolved `Py*` symbols)
- [ ] Runtime: `PyObject` wrapper, module construction, scalar and string
      marshalling, argument parsing
- [ ] Code generator: annotations, docstrings, signatures, `.pyi` stubs
- [ ] Classes: instances, fields, methods, properties, `__repr__`/`__eq__`
- [ ] Errors: `!T` translation and `recover()`-based panic capture
- [ ] Wheels: ZIP writer with DEFLATE, `METADATA`, `RECORD`, tag computation
- [ ] PEP 517 backend, `vcraft build` / `develop` / `sdist` / `audit`
- [ ] `abi3` and free-threaded builds
- [ ] GitHub Actions: `vcraft-action@v1`, `generate-ci`, manylinux and musllinux
      images
- [ ] Zero-copy buffers, `@[vc.gil]`, iterators
- [ ] Apple Silicon, Windows and musllinux verification

See [Status](#status) for what actually works today.

---

## Status

Early development. The plan this README describes is agreed and the feasibility
of the central bet has been verified against V 0.5.2, but the components are
being written now. The [Roadmap](#roadmap) tracks the order.

Do not depend on this yet.

---

## Requirements

- V compiler 0.5.2 or newer
- CPython 3.10 or newer
- A C toolchain: gcc, clang or MSVC, plus the CPython development headers
- Docker, only for manylinux wheels

On a normal Linux install the CPython headers are usually already present:

```
/usr/include/python3.14/Python.h
```

---

## Design notes

A few decisions worth knowing about, and why they were made.

**Annotations come from the source text.** V's parse tree does not keep
declaration attributes; they live in the type checker. V's own `v.astquery`
module documents the same limitation and advises reading the source. `vcraft`
therefore parses declarations with `v.astquery` and then reads the `@[...]` block
immediately above each one. It works on files that do not compile, which keeps
error messages about broken annotations useful.

**The generator emits V, not a foreign language.** Since the generated file is
compiled by V alongside your code, it can call your functions with their real
types. There is no tagged union, no serialisation step and no reflection at
runtime, so the cost of a call is a C call plus the conversions you asked for.

**The V garbage collector runs inside CPython.** V uses Boehm–Demers–Weiser by
default. It is statically linked into the extension, it does not replace the C
allocator, so it never interferes with CPython's own memory management, and V
0.5.2 already calls `GC_allow_register_threads()` during initialisation, which is
precisely the case of a host-created thread entering V code. Use
`[tool.vcraft] gc = "none"` if you would rather manage lifetimes yourself.

**Extension modules are process-scoped.** `PyInit_` is the single-phase
initialisation API, so a module loaded in one interpreter is shared by all of
them. Subinterpreter support would need the multi-phase API; the generated
glue is structured so that switch is a contained change.

**Nothing is installed system-wide.** `vcraft` builds into the project's `build/`
and installs into the active virtualenv. The V runtime module ships with
`vcraft` and is passed to the compiler with `-path`, so `VMODULES` is never
touched.

---

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Ricardo Robles Fernández
