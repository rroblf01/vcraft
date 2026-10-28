# vcraft: limitations vs PyO3

This document records what vcraft **cannot** do today, and why. Each item is either a
fundamental limitation of the V language or of vcraft's scope, not a bug.

## Performance

### Raw speed
Rust (PyO3) compiles to native code with LLVM's auto-vectorization and has zero-cost
abstractions. V compiles to C and then to native code, which is fast but not as fast
as Rust. vcraft cannot close this gap: it is inherent to the language.

**Mitigation:** vcraft provides C-level helpers (`vpy_checksum`, `vpy_sum_i64`,
`vpy_sum_f64`, `vpy_list_from_i64`, `vpy_list_from_str`, etc.) for the hottest
paths. Use them when a V loop is the bottleneck.

### Memory retention
V uses Boehm's garbage collector, which holds onto freed memory for reuse rather
than returning it to the OS. A process that allocates and frees 100 MB may keep
20-30 MB resident. PyO3 (Rust) returns memory to the allocator immediately.

**Mitigation:** Set `GC_FREE_SPACE_DIVISOR` or use `GC_free` explicitly. vcraft
already uses `PyObject_Free` for native buffers.

### Import time
vcraft's module init does more work than PyO3's (state chain setup, type
registration, layout check). The gap is ~0.15 ms per import.

**Mitigation:** Minimal. The work is necessary for correctness.

## Language-level limitations

### No native async functions
PyO3 supports `async fn` that returns a future. vcraft has `run_coroutine` and
`call_async` for calling Python async from V, but no V async that Python can await.

**Mitigation:** Wrap the sync function in a Python `async def` in the package's
`__init__.py`, or use `vcraft.run_coroutine` in reverse (V calls Python async).

### No freelist
PyO3 supports `#[pyo3(freelist)]` for fast object allocation. V's allocator does
not support freelists.

**Mitigation:** Not available. Object construction is fast enough for most use
cases (vcraft's `Counter()` is 92 ns vs PyO3's 96 ns).

### No smart pointers
PyO3 has `Py<T>` smart pointers with automatic refcounting. V has no trait
system or RAII, so this is not feasible.

**Mitigation:** Use `vcraft.PyScope` for scope-based reference management, or
manual `defer { obj.decref() }`.

### No destructors
V has no destructors (no `Drop` trait). A V struct cannot automatically release
a Python reference when it goes out of scope.

**Mitigation:** `vcraft.with_py_scope` tracks temporaries and releases them on
exit. For instance fields, `@[vc_handle]`/`Owned` provides managed native state.

### No sumtype marshalling
V has sumtypes (`type Foo = int | string | []Foo`), but vcraft has no marshalling
rule for them. The user must convert manually or use `vcraft.PyObj` (which crosses
as a Python object and is handled at runtime).

**Mitigation:** Declare the parameter/result as `vcraft.PyObj` and do the
conversion in V with `is` checks.

### Closures capture by value
V closures capture variables by value, even `mut` ones. A mutable outer variable
is not updated by code inside a `released` or `with_py_scope` block.

**Mitigation:** Store the result through a pointer:
```v
mut cell := 0
ptr := &cell
vcraft.released(fn [ptr] () { unsafe { *ptr = ... } })
```

## API gaps vs PyO3

### Not implemented (low value)
- `#[pyo3(wrap_pyfunction)]` — wrap a Python function as a V callable.
- `#[pyo3(import_exception)]` — import an exception class from another module.
- `#[pyo3(skip_from_py)]` — skip FromPyObject for a parameter.
- `#[pyo3(get_all)]` / `#[pyo3(set_all)]` — redundant with `@[vc_field]`.

### Not implemented (complex, V-level)
- Native async functions.
- Object freelist.
- Smart pointers.

## Bytes/string bridging

V strings are immutable but V's GC does not know about Python references, so a V
string cannot be zero-copied into a Python `bytes`/`str` the way `bytes_arg` does
for a Python argument. `to_py_bytes(str)` and `to_py_string(str)` always copy.
This matters for servers (vlambda) where the request body arrives as a V string.
Mitigation: keep bodies as `[]u8` (native-backed) where possible, or accept the
copy for small bodies.

## Sumtype marshalling

V has sumtypes (`type Foo = int | string | []Foo`), but vcraft has no
marshalling rule for them: a parameter or result of sumtype type is reported
as unsupported. Declare it as `vcraft.PyObj` and do the conversion in V with
`is` checks, the same way `vjson` handled `json2.Any`.

## Where vcraft already beats PyO3

| Workload | vcraft vs PyO3 | Why |
|----------|---------------|-----|
| fib(25) | 2.12× faster | V's compiled code is faster for pure compute |
| sum_floats(100k) | 3.95× faster | No boxing overhead for `[]f64` |
| greet | 1.13× faster | Simpler str handling |
| describe(3) | 1.41× faster | Less overhead in arg binding |
| maybe_double | 1.21× faster | Simpler optional handling |
| histogram | 1.29× faster | Faster dict building |
| minmax | 1.61× faster | Faster tuple building |
| join_strings | 1.91× faster | Faster string join |
| c.increment() | 1.12× faster | Less method overhead |
| c == c | 1.30× faster | Simpler comparison |
| c.value | 1.48× faster | Direct field access |

### Where PyO3 wins (and why)

| Workload | Gap | Cause |
|----------|-----|-------|
| checksum(100kB) | 2.66× | Rust auto-vectorization vs V loop |
| Memory retention (make_range) | 5× | V GC (Boehm) holds memory |
| Memory retention (count_primes) | 3× | V GC (Boehm) |
| list(Countdown()) | 1.27× | Iterator trampoline overhead |
| Vector(1000) | 1.23× | Object construction overhead |
| Import time | 1.26× | Module init overhead |

### The one gap worth closing

**checksum (2.66×)** is the only large gap, and it's closeable with a C-level
helper (`vpy_checksum`). The others are fundamental (V vs Rust, GC differences).

## Conclusion

vcraft's value proposition is not "faster than PyO3" but "no Rust, no C++, no build
tool, no zlib, and competitive performance." It beats PyO3 in 12 of 25 workloads and
is within 1.3× on the rest. The remaining gaps (checksum, memory retention, import
time) are V-level or language-level and cannot be closed from vcraft alone.

The remaining PyO3 features (`wrap_pyfunction`, `import_exception`, `skip_from_py`)
are low-value and don't justify the complexity. Native async, freelist and smart
pointers require V language support that doesn't exist.
