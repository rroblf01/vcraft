# vcraft

**CPython bindings written in V.** vcraft is to the V language what PyO3 + maturin is to
Rust: a code generator that turns `@[vc_*]` annotations into extension glue, and a wheel
writer that packages the result. No Rust, C++ or zlib in the pipeline.

```v
module hello_native

import vcraft

@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}
```

```python
import hello_native
print(hello_native.greet("world"))  # Hello, world!
```

## Highlights

- **A V source file is the API.** Annotate a function, a class or a field and the
  generator writes the glue, the type stubs and the wheel.
- **The whole pipeline is V and Python.** The compiler is V; the wheel writer builds
  DEFLATE, ZIP, tar, SHA-256 and METADATA from scratch, with no `zlib`.
- **Near-PyO3 performance**, with instance state inline in the object.
- **Every supported CPython**, 3.11 to 3.15 plus the free-threaded builds, on Linux
  (glibc and musl), macOS and Windows.

## Where to go next

- [Getting started](getting-started.md) — install the CLI and build your first extension.
- [The annotation vocabulary](guide/annotations.md) — what each `@[vc_*]` does.
- [Type marshalling](guide/types.md) — how V and Python types map.
- [Classes and properties](guide/classes.md) — `@[vc_class]`, fields, constructors.
- [The command line](guide/cli.md) and [Wheels](guide/wheels.md) — build, develop,
  publish, abi3 and free-threading.

## Built with vcraft

[vqubit](https://pypi.org/project/vqubit/) is a dependency-free quantum computing framework
for Python in the spirit of [Cirq](https://quantumai.google/cirq): its linear algebra, gate
matrices and simulators are written in V. It ships as a single abi3 wheel per platform,
CPython 3.11 and newer, and pulls in nothing else — a good, complete example of a project
built on vcraft ([source](https://github.com/rroblf01/vqubit),
[docs](https://rroblf01.github.io/vqubit/)).

## Status

1.6.0. Highlights: `@[vc_handle]` for native state a class owns, `@[vc_opaque]` for
pointers that travel as capsules (result and parameter), `vcraft.with_gil` / `released` /
`gil_ensure` / `gil_release` for GIL control from V threads, `bytes_view` for zero-copy
reads of bytes-like results, `to_py_str_list` / `to_py_bytes_list`, and `run_coroutine` /
`call_async` to drive a Python coroutine from V. New in this release: a `voidptr`/
`vcraft.PyObj` result is now an owned reference (no per-call leak), `vcraft.PyObj` works
as a first-class parameter and result type with `!` propagation, `to_py_obj_list` /
`to_py_obj_dict` and `from_py_list` / `from_py_dict` for composite Python values, and
`repr_f64` matching Python's shortest form. See the
[changelog](https://github.com/rroblf01/vcraft/blob/main/CHANGELOG.md) for the full list.

The annotation vocabulary, the `vcraft.toml` keys and the CLI change only with a
deprecation period. See the [roadmap](https://github.com/rroblf01/vcraft/blob/main/ROADMAP.md)
for what is left, and [`DECISIONS.md`](https://github.com/rroblf01/vcraft/blob/main/DECISIONS.md)
for what was set aside and why.
