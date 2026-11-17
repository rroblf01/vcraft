# Si vienes de PyO3 y maturin

vcraft hace para V lo que PyO3 y maturin hacen juntos para Rust: los bindings, el build y
el wheel. Casi todos los conceptos se corresponden uno a uno; la diferencia principal es
que vcraft no tiene una API a la que llamar para convertir valores. Anotas declaraciones V
normales y el generador escribe el código de unión, así que una firma como
`fn f(xs []f64) !f64` es todo el binding.

## Proyecto y herramientas

| maturin | vcraft |
| --- | --- |
| `maturin new` | `vcraft new <nombre>` |
| `maturin init` | `vcraft init` (conserva tu paquete, `[project]` y las demás tablas) |
| `maturin develop` | `vcraft develop` (editable por defecto), `vcraft develop --watch` |
| `maturin build --release` | `vcraft build --release` |
| `maturin build -i python3.12` / `--find-interpreter` | `--interpreter a,b,c` / `--find-interpreter` |
| `maturin build --target … --zig` | `vcraft build --target linux-aarch64-gnu --manylinux 2_17` |
| `maturin sdist` | `vcraft sdist` |
| `maturin publish` | `vcraft publish` |
| `maturin generate-ci github` | `vcraft generate-ci` (trusted publishing con un tag `v*`) |
| `maturin-action` | `rroblf01/vcraft/actions/vcraft-action@v1` |
| `[tool.maturin] python-source` | `[build] python-source` en `vcraft.toml` |
| `[tool.maturin] module-name` | `[package] module` |
| `Cargo.toml` | `v.mod` (el módulo V) más `vcraft.toml` (empaquetado) |
| el import hook de maturin | `import vcraft_tool.auto`, y `%%vcraft` en Jupyter |
| `pyo3-stub-gen` o un `.pyi` escrito a mano | se genera en cada build |

`[project]` en `pyproject.toml` sigue siendo la fuente de los metadatos, como con maturin.

## Funciones

| PyO3 | vcraft |
| --- | --- |
| `#[pyfunction] fn f(a: i64) -> i64` | `@[vc_fn] pub fn f(a int) int` |
| `#[pymodule]` + `wrap_pyfunction!` | nada: se registra cada `@[vc_fn]` del módulo |
| `PyResult<T>` | `!T` |
| argumento o resultado `Option<T>` | `?T` |
| `#[pyo3(signature = (a, b=1))]` | `@[vc_defaults: 'b=1']` |
| `*args: &PyTuple` | un último parámetro variádico `xs ...int` |
| `**kwargs: Option<&PyDict>` | `@[vc_kwargs]` en un parámetro `map[string]T` |
| `#[pyo3(name = "x")]` | `@[vc_rename: 'x']` |
| `py.allow_threads(|| …)` | `@[vc_nogil]` en la función |
| `async fn` (experimental-async) | `@[vc_async]`: un future de asyncio, el cuerpo en su propio hilo |
| `#[pyfunction(pass_module)]` | `@[vc_pass_module]` |
| `Bound<'py, PyAny>` | `vcraft.PyObj`, o `@[vc_raw]` para toda la llamada |

## Errores

| PyO3 | vcraft |
| --- | --- |
| `Err(PyValueError::new_err("…"))` | `return vcraft.raise_domain(.value_error, '…')` |
| cualquier `Err(e)` con `?` | propagación con `!`; un `error('…')` simple es un `RuntimeError` |
| `create_exception!(m, MyError, PyException)` | un struct `@[vc_error]` (ver Errores) |
| un panic de Rust → `PanicException` | un panic de V → `RuntimeError`, y el intérprete sigue |

## Clases

| PyO3 | vcraft |
| --- | --- |
| `#[pyclass] struct T` | `@[vc_class] pub struct T` |
| `#[pyo3(get, set)] x: i64` | `@[vc_field] x int` |
| `#[new] fn new() -> Self` | `@[vc_fn] pub fn new_t() &T` |
| `#[pymethods] fn m(&self)` | `@[vc_method] pub fn (t &T) m()` (`mut t T` para modificar) |
| `#[getter]` / `#[setter]` | `@[vc_property]` / `@[vc_property_set]` |
| `#[staticmethod]` / `#[classmethod]` | `@[vc_static]` / `@[vc_classmethod]` |
| `#[pyclass(extends = Base)]` | `@[vc_base(Base)]` |
| `#[pyclass(frozen, eq, hash)]` | funciones `@[vc_eq]` y `@[vc_hash]` |
| `__str__`, `__call__`, `__bool__` | `@[vc_str]`, `@[vc_call]`, `@[vc_bool]` |
| `__len__`, `__getitem__`, `__contains__` | `@[vc_len]`, `@[vc_getitem]`, `@[vc_contains]` |
| `__iter__` / `__next__` | `@[vc_iter]` / `@[vc_next]` |
| `__add__`, `__lt__`, … | `@[vc_add]`, `@[vc_lt]`, … (y `@[vc_radd]`, …) |
| `__getattr__` / `__setattr__` | `@[vc_getattr]` / `@[vc_setattr]` |
| campo `Py<Other>` | campo `@[vc_ref]` |
| `#[pyclass(dict)]`, `__match_args__` | `__match_args__` se genera a partir de los campos |
| `__getbuffer__` | campo `@[vc_buffer]`, resultado `@[vc_memoryview]` |

Los campos son escalares; el estado gestionado por V (mapas, arrays, cadenas) vive detrás
de un `@[vc_handle] vcraft.Owned` creado con `vcraft.own_gc(...)`, porque el colector de V
no ve la memoria que reservó CPython (ver Clases).

## Crates y sus equivalentes

| Crate de Rust | vcraft |
| --- | --- |
| `numpy` (rust-numpy) | `vcraft.NdArray` de entrada, `vcraft.NdOut` de salida; sin depender de NumPy |
| `chrono` | `time.Time` ↔ `datetime`, `time.Duration` ↔ `timedelta` |
| `rust_decimal` | `vcraft.Decimal` ↔ `decimal.Decimal`, exacto |
| `num-bigint` | `big.Integer` ↔ `int` de cualquier tamaño |
| `serde_json::Value` / `pythonize` | `json2.Any` ↔ cualquier valor con forma de JSON |
| `pyo3-log` | `vcraft.log_info(...)` y similares, hacia `logging` |

## Un ejemplo completo

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

## Qué cambia

- **Memoria.** Los objetos V los recoge el propio colector Boehm de V, que corre dentro de
  la extensión y sigue al `gc.collect()` de Python; no hay lifetimes ni handles `Py<T>`
  que gestionar. Los argumentos `str` se prestan durante la llamada: haz `.clone()` de lo
  que guardes.
- **Toolchain.** Un único compilador V fijado, instalado en la caché de vcraft con
  `vcraft toolchain install`; sin Cargo, sin Rust, sin zlib.
- **Carencias.** Lo que PyO3 tiene y vcraft no está en
  [LIMITATIONS.md](https://github.com/rroblf01/vcraft/blob/main/LIMITATIONS.md), y las
  decisiones de no añadir algo en
  [DECISIONS.md](https://github.com/rroblf01/vcraft/blob/main/DECISIONS.md).
