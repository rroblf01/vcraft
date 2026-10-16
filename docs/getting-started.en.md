# Getting started

## Requirements

- **A supported CPython**: 3.11 to 3.15, or a free-threaded 3.13t/3.14t/3.15t.
- **A C compiler** (gcc or clang) and the CPython headers, which most Python installs
  already include.
- **git and make**, once, to build the V compiler vcraft is tested with.

## 1. Install vcraft

```console
$ pip install vcraft
$ vcraft --version
```

## 2. Install the V compiler

`pip` ships the tool, not the toolchain, the same way maturin needs Rust. vcraft needs a V
newer than the 0.5.2 release, so it builds the commit it is tested with into its own cache
(about five minutes, once):

```console
$ vcraft toolchain install
$ vcraft toolchain          # which compiler vcraft uses, and whether it is the pinned one
```

vcraft finds it there by itself. `VCRAFT_V=/path/to/v` uses another V instead.

## 3. Create, develop and build a project

```console
$ vcraft new my_extension
$ cd my_extension
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop                      # build and install into the active venv
$ python main.py                      # the example `vcraft new` wrote
$ python -m unittest                  # the test under tests/
$ vcraft build --release              # dist/my_extension-0.1.0-cp314-cp314-<platform>.whl
```

`vcraft new` writes a Python package `my_extension` that re-exports the native module
`my_extension_native`, so `import my_extension` is the public name. Pass
`--module my_extension` if you would rather have no separate native module at all.

## 4. Ship it

`vcraft generate-ci` writes a GitHub Actions workflow that builds a wheel per supported
Python and platform, installs and imports each one, and is ready to publish to PyPI.

```console
$ vcraft generate-ci
```

## The shape of a project

```text
my_extension/
├── vcraft.toml          # the manifest: package, build, wheel, ci
├── v.mod                # the V module
├── src/
│   └── my_extension_native.v   # your V source, and the API
├── python/
│   ├── my_extension/__init__.py
│   ├── my_extension/py.typed
│   └── my_extension_native.pyi # written by the generator
├── tests/test_my_extension.py
└── main.py
```

The generated files (`src/_vcraft_generated.v`, `python/*.pyi`) are written on every
build; never edit them by hand.

## Next

- [The annotation vocabulary](guide/annotations.md)
- [Type marshalling](guide/types.md)
- [The command line](guide/cli.md)
