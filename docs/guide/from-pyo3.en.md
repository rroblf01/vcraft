# Coming from PyO3 and maturin

vcraft does for V what PyO3 and maturin do together for Rust: the bindings, the build
and the wheel. Most concepts map one to one; the main difference is that vcraft has no
API to call for marshalling. You annotate ordinary V declarations and the generator
writes the glue, so a signature such as `fn f(xs []f64) !f64` is the whole binding.

## Project and tooling

| maturin | vcraft |
| --- | --- |
| `maturin new` | `vcraft new <name>` |
| `maturin init` | `vcraft init` (keeps your package, `[project]` and other tables) |
| `maturin develop` | `vcraft develop` (editable by default), `vcraft develop --watch` |
| `maturin build --release` | `vcraft build --release` |
| `maturin build -i python3.12` / `--find-interpreter` | `--interpreter a,b,c` / `--find-interpreter` |
| `maturin build --target … --zig` | `vcraft build --target linux-aarch64-gnu --manylinux 2_17` |
| `maturin sdist` | `vcraft sdist` |
| `maturin publish` | `vcraft publish` |
| `maturin generate-ci github` | `vcraft generate-ci` (trusted publishing on a `v*` tag) |
| `maturin-action` | `rroblf01/vcraft/actions/vcraft-action@v1` |
| `[tool.maturin] python-source` | `[build] python-source` in `vcraft.toml` |
| `[tool.maturin] module-name` | `[package] module` |
| `Cargo.toml` | `v.mod` (the V module) plus `vcraft.toml` (packaging) |
| maturin import hook | `import vcraft_tool.auto`, and `%%vcraft` in Jupyter |
| `pyo3-stub-gen` or hand-written `.pyi` | generated on every build |

`[project]` in `pyproject.toml` stays the source of the metadata, as with maturin.

## Functions

| PyO3 | vcraft |
| --- | --- |
| `#[pyfunction] fn f(a: i64) -> i64` | `@[vc_fn] pub fn f(a int) int` |
| `#[pymodule]` + `wrap_pyfunction!` | nothing: every `@[vc_fn]` in the module is registered |
| `PyResult<T>` | `!T` |
| `Option<T>` argument or result | `?T` |
| `#[pyo3(signature = (a, b=1))]` | `@[vc_defaults: 'b=1']` |
| `*args: &PyTuple` | a variadic last parameter `xs ...int` |
| `**kwargs: Option<&PyDict>` | `@[vc_kwargs]` on a `map[string]T` parameter |
| `#[pyo3(name = "x")]` | `@[vc_rename: 'x']` |
| `py.allow_threads(|| …)` | `@[vc_nogil]` on the function |
| `async fn` (experimental-async) | `@[vc_async]`: an asyncio future, the body on its own thread |
| `#[pyfunction(pass_module)]` | `@[vc_pass_module]` |
| `Bound<'py, PyAny>` | `vcraft.PyObj`, or `@[vc_raw]` for the whole call |

## Errors

| PyO3 | vcraft |
| --- | --- |
| `Err(PyValueError::new_err("…"))` | `return vcraft.raise_domain(.value_error, '…')` |
| any `Err(e)` from `?` | `!` propagation; a plain `error('…')` is a `RuntimeError` |
| `create_exception!(m, MyError, PyException)` | a `@[vc_error]` struct (see Errors) |
| a Rust panic → `PanicException` | a V panic → `RuntimeError`, the interpreter keeps running |

## Classes

| PyO3 | vcraft |
| --- | --- |
| `#[pyclass] struct T` | `@[vc_class] pub struct T` |
| `#[pyo3(get, set)] x: i64` | `@[vc_field] x int` |
| `#[new] fn new() -> Self` | `@[vc_fn] pub fn new_t() &T` |
| `#[pymethods] fn m(&self)` | `@[vc_method] pub fn (t &T) m()` (`mut t T` to modify) |
| `#[getter]` / `#[setter]` | `@[vc_property]` / `@[vc_property_set]` |
| `#[staticmethod]` / `#[classmethod]` | `@[vc_static]` / `@[vc_classmethod]` |
| `#[pyclass(extends = Base)]` | `@[vc_base(Base)]` |
| `#[pyclass(frozen, eq, hash)]` | `@[vc_eq]` and `@[vc_hash]` functions |
| `__str__`, `__call__`, `__bool__` | `@[vc_str]`, `@[vc_call]`, `@[vc_bool]` |
| `__len__`, `__getitem__`, `__contains__` | `@[vc_len]`, `@[vc_getitem]`, `@[vc_contains]` |
| `__iter__` / `__next__` | `@[vc_iter]` / `@[vc_next]` |
| `__add__`, `__lt__`, … | `@[vc_add]`, `@[vc_lt]`, … (and `@[vc_radd]`, …) |
| `__getattr__` / `__setattr__` | `@[vc_getattr]` / `@[vc_setattr]` |
| `Py<Other>` field | `@[vc_ref]` field |
| `#[pyclass(dict)]`, `__match_args__` | `__match_args__` is generated from the fields |
| `__getbuffer__` | `@[vc_buffer]` field, `@[vc_memoryview]` result |

Fields are scalars; V-managed state (maps, arrays, strings) lives behind a
`@[vc_handle] vcraft.Owned` made with `vcraft.own_gc(...)`, because V's collector cannot
see memory CPython allocated (see Classes).

## Crates and their counterparts

| Rust crate | vcraft |
| --- | --- |
| `numpy` (rust-numpy) | `vcraft.NdArray` in, `vcraft.NdOut` out; no NumPy dependency |
| `chrono` | `time.Time` ↔ `datetime`, `time.Duration` ↔ `timedelta` |
| `rust_decimal` | `vcraft.Decimal` ↔ `decimal.Decimal`, exact |
| `num-bigint` | `big.Integer` ↔ `int` of any size |
| `serde_json::Value` / `pythonize` | `json2.Any` ↔ any JSON-shaped value |
| `pyo3-log` | `vcraft.log_info(...)` and siblings, into `logging` |

## A worked example

```rust
#[pyfunction]
#[pyo3(signature = (values, scale=1.0))]
fn mean(values: Vec<f64>, scale: f64) -> PyResult<f64> {
    if values.is_empty() {
        return Err(PyValueError::new_err("empty"));
    }
    Ok(values.iter().sum::<f64>() / values.len() as f64 * scale)
}
```

```v
@[vc_fn]
@[vc_defaults: 'scale=1.0']
pub fn mean(values []f64, scale f64) !f64 {
	if values.len == 0 {
		return vcraft.raise_domain(.value_error, 'empty')
	}
	mut sum := 0.0
	for v in values {
		sum += v
	}
	return sum / values.len * scale
}
```

## What is different

- **Memory.** V objects are collected by V's own Boehm collector, which runs inside the
  extension and follows Python's `gc.collect()`; there are no lifetimes or `Py<T>`
  handles to manage. `str` arguments are borrowed for the call: `.clone()` what you keep.
- **Toolchain.** One pinned V compiler, installed into vcraft's cache by
  `vcraft toolchain install`; no Cargo, no Rust, no zlib.
- **Gaps.** What PyO3 has and vcraft does not is listed in
  [LIMITATIONS.md](https://github.com/rroblf01/vcraft/blob/main/LIMITATIONS.md), and the
  decisions not to add something are in
  [DECISIONS.md](https://github.com/rroblf01/vcraft/blob/main/DECISIONS.md).
