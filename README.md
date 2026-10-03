# vcraft

**Native Python extensions for V, written in V.**

`vcraft` is to the V language what **PyO3 + maturin** is to Rust: a set of bindings for the CPython C API, plus a build and packaging toolchain that turns a directory of V source files into a distributable Python wheel.

There is **no Rust and no C++ in the pipeline**. A `.v` file compiles to a CPython extension module, the annotations you write on your V declarations become the Python API surface, and `vcraft build` produces a wheel you can upload to PyPI.

```v
// src/lib.v
module mi_extension_nativa

// Adds two integers and returns the result.
@[vc_fn]
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

- [Table of contents](#table-of-contents)
- [Why](#why)
- [How it works](#how-it-works)
- [Try it](#try-it)
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
| Binding generation | `#[pyfunction]`    | `@[vc_fn]`                      |
| Class bindings     | `#[pyclass]`       | `@[vc_class]`                   |
| Error translation  | `Result<T, E>`     | `!T` / `error` / `recover()`    |
| GIL handling       | `Python::detach`   | `@[vc_gil]`                     |
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
| Annotation      | Applies to      | Effect                                                     |
| --------------- | --------------- | ---------------------------------------------------------- |
| `@[vc_fn]`      | `pub fn`        | Exports the function as a module-level Python callable      |
| `@[vc_class]`   | `pub struct`    | Creates a Python type backed by the V struct                |
| `@[vc_methods]` | methods         | Adds the method to the class of its receiver                |
| `@[vc_field]`   | struct fields   | Exposes the field as an attribute of the instance           |
| `@[vc_property]`| methods         | Registers the method as a Python `property`                 |
| `@[vc_static]`  | methods         | Registers the method as a `staticmethod`                    |
| `@[vc_raw]`     | `pub fn`        | Skips marshalling; you receive and return `voidptr` yourself |
| `@[vc_gil]`     | `pub fn`        | Runs the call with the GIL released                         |

Names are taken from the V declaration, verbatim. Doc comments become `__doc__`, the
marshalled signature becomes `__text_signature__`, and the same source also produces
a `.pyi` stub, so `help()` and a type checker see the same thing.

The prefix is part of the name rather than a namespace because V rejects two
annotations sharing one: `@[vc.fn]` and `@[vc.raw]` on the same declaration is
`duplicate attribute 'vc'`.

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
// A counter with state.
//
// Fields must be scalars. A V string inside a Python object would be a pointer
// that V's collector cannot see, because it does not scan memory CPython
// allocated, so the string would be reclaimed while Python still held it. Reach a
// string through a method, which marshals it properly.
@[vc_class]
pub struct Counter {
mut:
	// value is the running total.
	@[vc_field] value int
	@[vc_field] step int
}

// new_counter builds a Counter. It takes no arguments; the convention is that
// `new_<Class>` is the constructor, and an instance is made by calling the type.
pub fn new_counter() &Counter {
	return &Counter{ step: 1 }
}

// increment adds step to value and returns the new total.
@[vc_methods]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}

// set_step changes how much each increment adds.
@[vc_methods]
pub fn (mut c Counter) set_step(step int) {
	c.step = step
}

// is_zero reports whether the value is still zero.
@[vc_methods]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}
```

```python
>>> c = m.Counter()
>>> repr(c)
'Counter(value: 0, step: 1)'
>>> c.increment(), c.increment()
(1, 2)
>>> c.step = 5
>>> c.increment()
7
>>> c.is_zero
False
>>> c.value = 100
>>> c
Counter(value: 100, step: 5)
```

A class becomes a CPython heap type created with `PyType_FromSpec`. The state lives
in a block CPython allocates, the V struct is copied in before a method runs and
back out after, and `tp_dealloc` frees the block.

An `@[vc_field]` becomes a read/write attribute. Assigning the wrong type raises
`TypeError`, and deleting one raises `AttributeError`: both come for free from
registering a setter, rather than from a hand-written check per field. An
`@[vc_property]` method becomes a read-only property, and a plain `@[vc_methods]`
method takes arguments like any other exposed function.

The constructor runs in `tp_new` and takes no arguments, so `Counter(1)` is a
`TypeError`. That is deliberate: there is no implied `__init__` signature to keep
in sync with a V constructor that could change shape. Give the constructor
parameters and you would have to keep two signatures aligned by hand.

Docstrings reach `__doc__` on the type, its methods, its properties and its fields.

Cycles are not yet collected. Nothing in a class holds a reference back to its
instance, so an instance is freed as soon as Python drops it; a class that grew a
field pointing at another `Counter` would need `tp_traverse` and `tp_clear`.

---

## Errors and panics

A `!T` return becomes a Python exception:

```v
// Greet someone by name.
@[vc_fn]
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

A bare `error('...')` carries nothing but a message, so it becomes a
`RuntimeError`. That is right often enough to hide the problem: Python code that
divides by zero expects `ZeroDivisionError`, and an `except ZeroDivisionError`
around a call into a V extension silently stops matching. So a failure that means a
particular exception says so:

```v
// Divides two floats, refusing a zero divisor.
@[vc_fn]
pub fn divide(a f64, b f64) !f64 {
	if b == 0.0 {
		return vcraft.raise_domain(.zero_division_error, 'division by zero')
	}
	return a / b
}
```

```python
>>> m.divide(1.0, 0.0)
ZeroDivisionError: division by zero
```

The exception is chosen where the failure happens rather than in the wrapper,
because V gives a wrapper nothing to choose from: every error arrives as an
`IError` holding a message, and a bare message does not say whether it was a
`ValueError` or a `ZeroDivisionError`. `raise_domain` sets the Python exception and
returns an error, and the wrapper's `error_is_set` check stops the value from
reaching Python as a result. A wrapper never overwrites an exception that is already
set, so the choice survives.

A custom V error struct cannot carry the choice. V 0.5.2 rejects a value whose type
is not `IError`, and a struct that implements `msg()` is not one, so the exception
travels out of band through the pending Python exception instead of inside the error
value.

Argument marshalling failures are separate and never reach your code: a wrong
argument type is a `TypeError` and the wrong number of arguments is a `TypeError`,
both naming the parameter.

### Panics

A V `panic` prints a message and calls `exit(1)`, which inside CPython would take
the whole interpreter down with it. V 0.5 has Go-style recovery, so every generated
wrapper installs a frame:

```v
fn _vcraft_generated__wrap_first_char(text string) string {
	defer {
		if message := recover() {
			vcraft.raise_runtime_error('panic in V code: ${message}')
		}
	}
	return first_char(text)
}
```

```python
>>> m.first_char('')
RuntimeError: panic in V code: substr(0, 1) out of bounds (len=0) s=
>>> m.add(2, 3)          # the interpreter is still fine
5
```

A recovered panic is raised rather than reaching Python as a half-written result,
which is what the wrapper's `error_is_set` check after the call is for. Panic state
is thread-local in V, so this stays correct under free threading.

The guard is inlined per trampoline rather than shared through a helper. V emits no
forward declaration for a generic function called across modules, so a shared
wrapper fails to compile with an implicit-declaration error.

`@[vc_gil]` marks a function as pure V with no Python interaction. The GIL is
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

A project from scratch, end to end:

```console
$ ./scripts/build-vcraft.sh
$ vcraft new mypkg
$ cd mypkg && vcraft develop
$ python -c "import mypkg_native as m; print(m.greet('world'))"
Hello, world!
```

Packaging configuration lives in `vcraft.toml`, not in `v.mod`. `v.mod` is V's
manifest and names the V module; a wheel also needs a distribution name, a version,
a licence and a `Requires-Python`, and none of those are V's business.

See [`vlib/vcraft_project/README.md`](vlib/vcraft_project/README.md) for the TOML
subset that is parsed, and for the compiler constraints that shaped it.

---

## Wheels

```console
$ ./scripts/build-wheel-test.sh
/home/you/vpy/build/vcraft_demo-0.1.0-cp314-cp314-manylinux_2_17_x86_64.whl
$ pip install build/vcraft_demo-0.1.0-cp314-cp314-manylinux_2_17_x86_64.whl
```

A wheel is written from scratch in V: DEFLATE, the ZIP container, `METADATA`, `WHEEL`,
`RECORD` with SHA-256, the compatibility tag, and the file name.

zlib is not linked. It is on most build hosts but not all, and linking it makes the
extension depend on a shared library the manylinux and musllinux images have to agree
on. About 250 lines of fixed-Huffman DEFLATE is cheaper than that or than vendoring
zlib, and the output is read by every unzip. A `.so` compresses to roughly 43%.

`RECORD` carries base64 digests with the URL-safe alphabet and no padding, because pip
compares the string. A hex digest installs and then fails verification on every file.

The details that are easy to get wrong are written up in
[`vlib/vcraft_wheel/README.md`](vlib/vcraft_wheel/README.md). The shortest version:

- The distribution name is **escaped**, a run of `-_.` becoming `_`. The version is
  escaped too, but only its dashes: `-` becomes `_` and `.` stays `.`. Writing `0-1-0`
  looks equivalent because PEP 440 agrees it is the same version, but the installer
  splits the file name on `-` and pip rejects it with "wrong number of parts".
- The `.dist-info` directory is named after the distribution, never the module. pip
  checks this before opening the archive.
- The extension goes at the archive root. A directory named after the module is a
  namespace package, and Python resolves one without opening the files inside it, so
  the wheel installs and then imports as an empty module with `__file__` of `None`.

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

## Try it

The repository ships two working examples, both built by hand rather than by
`vcraft`, because they predate the code generator.

A CPython extension module written in V, built with `v -shared`, imported by
CPython 3.14:

```console
$ ./scripts/build-probe.sh
$ python3 examples/probe/test_probe.py
...
gate 0 passed
```

The runtime itself, exercised through a hand-written extension that uses it exactly
as the generated glue will:

```console
$ ./scripts/build-runtime-tests.sh
$ python3 tests/runtime/test_runtime.py
...
all 36 checks passed
```

And the code generator, end to end: it runs the real generator, checks the shape of
the glue it produced, then runs the real compiler and exercises the module:

```console
$ ./scripts/build-example.sh hello hello_native
$ python3 tests/codegen/test_codegen.py
...
all 47 checks passed
```

`examples/hello` is a working project with seven annotated functions covering scalars,
strings, a sequence, a void return, error propagation and the raw escape hatch. You
write the seven functions; the generator writes the rest.

That second one covers module construction, `METH_NOARGS` and `METH_FASTCALL`,
integers and floats and strings and bytes and lists in both directions, docstrings,
`error` and `panic` translation, and reference counting. Read
[`examples/probe/README.md`](examples/probe/README.md) for what the first one proves
and [`vlib/vcraft/README.md`](vlib/vcraft/README.md) for the compiler behaviours the
runtime uncovered, and [`vlib/vcraft_codegen/README.md`](vlib/vcraft_codegen/README.md)
for the ones the generator did.

---

## Roadmap

- [x] **Gate 0**: a V shared object that CPython imports as an extension module
- [x] **Runtime**: `PyObj`, module construction, marshalling, argument parsing,
      error and panic translation, covered by 36 checks
- [x] **Code generator**: annotations, docstrings, signatures, `.pyi` stubs,
      covered by 92 checks against a working example
- [x] **Classes**: instances, scalar fields as read/write attributes, methods,
      properties, `__repr__`, docstrings and `__dealloc__`
- [ ] Classes: `__eq__`, `__hash__`, inheritance from V, cycle collection
- [x] **Errors**: `!T` translation, `raise_domain` for a specific Python exception,
      `recover()`-based panic capture
- [ ] Errors: custom V error types carrying an exception class
- [x] **Wheels**: DEFLATE, ZIP container, `METADATA`, `WHEEL`, `RECORD` with SHA-256,
      tag computation and PEP 427 file names, verified by a real `pip install`
- [ ] Wheels: `sdist`, editable installs, `.pyc` embedding
- [x] **CLI**: `vcraft new`, `build`, `develop`, `sdist`, `publish`, `info`, `clean`
- [x] **abi3**: stable-ABI builds with multi-phase initialisation, verified by a real
      `pip install`
- [x] **PEP 517**: `pip install .` and `pip install <sdist>` both work
- [ ] Free-threaded builds, cross-compilation, `--target`
- [ ] Free-threaded builds, cross-compilation, `--target`
- [ ] GitHub Actions: `vcraft-action@v1`, `generate-ci`, manylinux and musllinux
      images
- [ ] Zero-copy buffers, `@[vc_gil]`, iterators
- [ ] Apple Silicon, Windows and musllinux verification

See [Status](#status) for what actually works today.

---

## Status

Early development. The central bet is **verified**: see
[`examples/probe`](examples/probe) for a CPython extension module written in V,
built with `v -shared` and imported from CPython 3.14. It exercises module
creation, `METH_NOARGS` and `METH_FASTCALL` builtins, argument marshalling,
error propagation and docstrings, and it checks that the dynamic symbol table
exposes only `PyInit_probe`.

```
$ ./scripts/build-probe.sh
$ python3 examples/probe/test_probe.py
...
gate 0 passed
```

Building it produced six compiler constraints that shaped the design. They are the
kind that produce a wrong answer rather than an error, so they are written up in
full in [`vlib/vcraft/README.md`](vlib/vcraft/README.md) and summarised here:

1. The V C backend emits no prototypes for `fn C.` declarations, so a module that
   binds to CPython **must** `#include <Python.h>`. Without it gcc applies the
   implicit `int` return rule, truncates the returned `PyObject *` to 32 bits,
   and the interpreter segfaults on a module that loaded cleanly.
2. A sibling `.c.v` file only exports its declarations to the module named by its
   own `module` line.
3. CPython's builtin exception types are data symbols, so each one needs a small C
   accessor, with a header.
4. A generic function called across modules gets no forward declaration and does
   not compile, so the panic guard is inlined per trampoline instead of shared.
5. A `mut` receiver method on a struct from another module generates C that
   passes the struct by value where a pointer is expected. That rules out a reader
   object with a cursor, and is why the argument helpers take an explicit index.
6. A file matching `*_test.v` is compiled as a V test file and its module export is
   silently dropped.

One further note on running the compiler at all. A bare `v` invocation is not safe
unattended: when a C compilation fails, V retries by bootstrapping the whole V
compiler from source, which builds all of `vlib/v` and is easily a multi-gigabyte,
multi-minute event. `-new-compiler` disables that retry and surfaces the real error
instead. `scripts/vcraft-v.sh` is the single entry point for invoking V in this
repository; it passes `-new-compiler`, bounds `VJOBS` and parallelism, and puts a
kernel-enforced ceiling on the build. A normal build peaks around 100 MiB.

The code generator, classes and the wheel writer are being written. Do not depend on
this yet.

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

**The generated glue is V, not a foreign language.** Since the generated file is
compiled by V alongside your code, it can call your functions with their real
types. There is no tagged union, no serialisation step and no reflection at
runtime, so the cost of a call is a C call plus the conversions you asked for.

**The CPython headers are included, never re-declared.** V does not emit
prototypes for `fn C.` declarations, so any module that binds to CPython must
`#include <Python.h>` rather than rely on V to declare them. See finding 1 in
[`examples/probe/README.md`](examples/probe/README.md).

**`METH_FASTCALL` is the default calling convention.** It is the cheapest way
CPython can pass positional arguments, and it lets the generated wrapper read the
arguments as a borrowed pointer array. Keyword arguments fall back to
`METH_FASTCALL | METH_KEYWORDS`.

**Annotations come from the source text.** V's parse tree does not keep
declaration attributes; they live in the type checker. V's own `v.astquery`
module documents the same limitation and advises reading the source. `vcraft`
therefore parses declarations with `v.astquery` and then reads the `@[...]` block
immediately above each one. It works on files that do not compile, which keeps
error messages about broken annotations useful.

**C struct mirrors use `voidptr` and `mut:`.** V's ownership rules would demand
initialisers for reference-typed fields, and a zero-initialised literal has to be
able to produce C's all-zero sentinels such as the `PyMethodDef` terminator.
Describing pointers as `voidptr` inside a `mut:` section sidesteps both.

**CPython data symbols get C accessors.** `PyExc_TypeError` and friends are
data, not functions, and V cannot name a C global. The runtime ships a small C
file of accessors with a header, pulled in with `#flag @VMODROOT/c/...`.

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

**The runtime API is stateless.** `vcraft/args.v` is a set of plain functions and
the generated glue keeps the call state in its own locals, passing argument indices
explicitly. The obvious design, a reader object with a `consumed` cursor, cannot be
compiled at all: see constraint 5 above.

**Nothing is installed system-wide.** `vcraft` builds into the project's `build/`
and installs into the active virtualenv. The V runtime module ships with `vcraft`
and is passed to the compiler with `-path`, so `VMODULES` is never touched.

**A module name ending in `_test` is rejected.** V would treat the file as a test
file and silently drop its module export. `vcraft new` says so instead of producing
an empty shared object.

---

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Ricardo Robles Fernández
