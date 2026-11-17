# vcraft: limitations vs PyO3

## Build system and PyPI

### Not self-contained for PyPI
`requires = []` and a local backend mean an sdist cannot be built on a user's machine
without V and vcraft. This is inherent (V is a host tool, not a Python dependency),
so only pre-built wheels are distributed. Use `vcraft toolchain install` to get the
pinned V, or install vcraft from PyPI and let it fetch its own toolchain.

### Editable installs
`vcraft develop` depends on `dist/build` plus a `.pth`. `vcraft clean` removes them
and breaks imports until a rebuild. Run `vcraft develop` again, or `vcraft check` to
detect the drift.

### V compilation cache
V has no incremental compilation cache that vcraft can rely on: every build
recompiles the extension and its glue from scratch. `vcraft`'s own incremental
build stamp (`.vcraft/build-stamp`) only skips the *whole* build when nothing
changed; it does not speed up a partial rebuild. Use `--jobs` to parallelise.

This document records what vcraft **cannot** do today, and why. Each item is either a
fundamental limitation of the V language or of vcraft's scope, not a bug.

## Performance

Measured with `benchmark/ab.py` (PyO3 0.29, CPython 3.13, Linux x86_64); the full table
and how each number was reached are in `benchmark/HISTORY.md`.

### Raw speed
vcraft is ahead of or level with PyO3 on 24 of the 26 benchmark workloads: the call
path, argument binding, strings, containers, classes, iteration and the error path.
The two it loses, `count_primes` and `make_range` (~1.1×), are the user's own loops as
V lowers them -- an `int`-index store with a sign and bound check, and `array_push`
copying each element through `memcpy` -- which vcraft cannot change without changing
the user's code or V (see `benchmark/V_UPSTREAM.md`).

**Mitigation:** `@[direct_array_access]` on the hot function, or the C-level helpers
(`vpy_sum_i64`, `vpy_sum_f64`, `vpy_list_from_i64`, ...).

### Memory retention
V uses Boehm's garbage collector: a temporary lives until the next collection rather
than until the end of its scope. vcraft runs a full V collection that unmaps freed pages
whenever Python runs a full collection (`gc.collect()` or its own), so a process that
collects gets the memory back; between collections an allocation-heavy loop keeps a few
MiB more than PyO3 (`make_range` 2-3 MiB against 0.9).

**Mitigation:** `gc.collect()` where memory matters, or `gc-free-space-divisor` to
collect more often.

### Import time
Level with PyO3 since the collector stopped reading `/proc/self/maps` at start-up
(0.58 ms against 0.59).

## Language-level limitations

### No native async functions
PyO3 supports `async fn` that returns a future. vcraft has `run_coroutine` and
`call_async` for calling Python async from V, but no V async that Python can await.

**Mitigation:** Wrap the sync function in a Python `async def` in the package's
`__init__.py`, or use `vcraft.run_coroutine` in reverse (V calls Python async).

### No freelist
PyO3 supports `#[pyo3(freelist)]`. vcraft does not, by decision (see `DECISIONS.md`):
construction is already ahead of PyO3 (`Counter()` 73 ns against 91), and reusing
instance memory by hand means reproducing CPython's GC and managed-dict headers, which
change between versions.

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


## Where vcraft stands against PyO3

| Workload | vcraft / PyO3 |
|----------|---------------|
| fib(25) | 0.48× |
| sum_floats(100k) | 0.29× |
| minmax(100k) | 0.51× |
| echo_bytes(100kB) | 0.49× |
| join_strings(10k) | 0.59× |
| c == c | 0.54× |
| list(Countdown()) | 0.73× |
| Counter() | 0.80× |
| greet | 0.82× |
| checksum(100kB) | 0.94× |
| Vector(1000), vector.total(), complex_scale | 1.00-1.02× |
| count_primes(1e6), make_range(100k) | 1.10-1.11× |

Wheels are about 6% smaller than maturin's for the same workloads (dynamic-Huffman
DEFLATE written by vcraft itself), and a clean release build is faster.

## Conclusion

vcraft's value proposition is "no Rust, no C++, no build tool, no zlib" with performance
that now matches or beats PyO3 on almost every workload. What remains is V-level (two
loop shapes, a tracing collector) or language-level (no destructors or smart pointers).
