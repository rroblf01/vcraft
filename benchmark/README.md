# Benchmark: PyO3 vs vcraft vs zig-maturin

Three independent projects implementing the same workloads with the same semantics, one
per tool, plus a pure-Python reference:

| directory | tool | language | module |
|---|---|---|---|
| [`pyo3/`](pyo3) | PyO3 0.29 + maturin 1.15 | Rust | `bench_pyo3` |
| [`vcraft/`](vcraft) | vcraft (this repo) | V | `bench_vcraft_native` |
| [`zig-maturin/`](zig-maturin) | [zig-maturin](https://github.com/rroblf01/zig-maturin) 1.0.1 | Zig 0.16 | `bench_zig` |
| [`pure_python.py`](pure_python.py) | — | Python | `pure_python` |

## How to run it

```console
$ ./run.sh            # clean build of all three, install into .venv, benchmark
$ ./run.sh --quick    # fewer repeats, to check the harness
```

It needs `uv`, `cargo`, `zig` 0.16 and a `v` built at the commit pinned in `docker/` on
`PATH`. It installs nothing outside `benchmark/.venv`. `BENCH_PYTHON` picks the interpreter
(3.13 by default, the newest all three support).

The full result is written to [`results.md`](results.md) and [`results.json`](results.json).
Those hold the macOS run; the Linux run is kept beside them as
[`results-linux.md`](results-linux.md) and [`results-linux.json`](results-linux.json). The
header records the toolchain, so a stored run says which vcraft and which V it measured.

The older runs, the step-by-step vcraft work and the resolved findings are in
[`HISTORY.md`](HISTORY.md), oldest first. `results-linux.md` is the current full run.

## What is measured

| workload | what it measures |
|---|---|
| `add(1, 2)` | fixed cost of a call |
| `fib(25)` recursive | pure compute: quality of the generated code |
| `count_primes(1_000_000)` | compute plus a native 1 MB allocation |
| `sum_floats(100k list)` | `list[float]` → native conversion |
| `make_range(100_000)` | native → `list[int]` conversion |
| `greet('world')` | `str` in, new `str` out |
| `checksum(100k bytes)` | `bytes` → native with no copy (buffer protocol) |
| `echo_bytes(100k bytes)` | `bytes` in, fresh copy out |
| `join_strings(10k strs)` | `list[str]` → native → `str` |
| `expect_positive(-1)` under `try` | exception round trip per call |
| `Counter()` / `c.increment()` | object construction and method call |
| `c.add(1)` | method call with an argument |
| `c.value` / `c.is_zero` | attribute and property read |
| `c == c` | rich comparison (value equality) |
| `list(Countdown())` | construct and iterate |
| `describe(3)` | keyword arguments and defaults |
| `maybe_double(21)` | `?T` in and out |
| `histogram(10k words)` | `list[str]` → `dict` |
| `minmax(100k ints)` | `list[int]` → tuple |
| `reverse3([1, 2, 3])` | fixed-size `[N]T` in and out |
| `Vector(1000)` / `v.total()` | a class that owns a native `f64` buffer |
| `complex_scale(1+2j, 3)` | complex in and out |
| `Counter.zero()` | a static method |

- **Speed:** `timeit`, best of 7 repeats, in a dedicated process.
- **Memory:** each scenario runs in a fresh process, **twice in a row**.
  *Peak* is the process's maximum RSS. *Kept* is what stays resident after the first
  batch and `gc.collect()`. *Leak* is what the second batch, identical to the first, adds:
  a heap that has plateaued adds nothing, and a leak does.
- **Import:** 8 processes. The first is reported separately, because macOS verifies each
  freshly installed binary once; the "warm" figure is the median of the rest.
- **Size:** the wheel, the extension as built, and the extension after `strip -x`.
- **Correctness:** a matrix of edge cases rather than a single happy path — integer
  limits and overflow, an embedded NUL and a non-BMP code point in a `str`, empty and
  negative sizes, wrong-typed arguments, every buffer-like object against the bytes path,
  and the buffer, complex and static surface added in 1.2.0. Where the backends
  legitimately differ the expected outcome is written per backend, and a case the
  pure-Python reference cannot share (it is duck-typed, not a binding) is `n/a`. A backend
  without a workload — zig-maturin has no complex conversion, PyO3's `Vec<f64>` field does
  not speak the buffer protocol — is `n/a`, shown as `—` in the speed table. The cases run
  in one process; if a hostile one aborts it, the rest are re-run one by one so a single
  crash is a row rather than a lost run.
- **Reference retention:** each borrowed argument is passed many times in one process
  and its `sys.getrefcount` compared before and after. A reader that keeps a reference
  grows the count by one per call, which a heap that has already plateaued hides from
  the memory table.
- **Error paths:** the memory scenarios include calls that raise on every iteration, so
  a leaked exception, error string or argument on the failure path is measured instead
  of being averaged away by the success paths.
- **Threads:** an `lcg` loop (a serial integer dependency, no allocation, the same work
  in every backend) runs from 1 to 8 threads with the GIL released — `detach`,
  `allowThreads`, `@[vc_nogil]` — and the table reports wall time and parallel speedup.
  The pure-Python reference cannot release the GIL and is not measured.

Each tool compiles in its release mode: `cargo --release` (opt-level 3),
`vcraft build --release` (`v -prod`) and `zig-maturin build --release` (`ReleaseSafe`). All
three keep bounds checks.

## Results

The current run is [`results-linux.md`](results-linux.md): Linux x86_64 (AMD Ryzen 5
3600), CPython 3.13, vcraft 1.3.0, V 36be926, PyO3 0.29, zig-maturin 1.0.1. Time per
call, lower is better:

| workload | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| `add` | 71 ns | 73 ns | 77 ns | 37 ns |
| `fib(25)` | 237.3 µs | 112.0 µs | 359.9 µs | 9.36 ms |
| `count_primes(1e6)` | 2.00 ms | 2.22 ms | 2.03 ms | 98.07 ms |
| `sum_floats(100k)` | 881.1 µs | 223.3 µs | 1.37 ms | 1.59 ms |
| `make_range(100k)` | 2.29 ms | 2.45 ms | 2.46 ms | 2.37 ms |
| `greet` | 135 ns | 120 ns | 235 ns | 73 ns |
| `describe(3)` | 174 ns | 123 ns | 157 ns | 169 ns |
| `checksum(100kB)` | 14.9 µs | 39.6 µs | 41.0 µs | 2.28 ms |
| `join_strings(10k)` | 506.4 µs | 266.0 µs | 265.1 µs | 75.4 µs |
| `Counter()` | 96 ns | 92 ns | 78 ns | 97 ns |
| `c.add(1)` | 67 ns | 68 ns | 90 ns | 59 ns |
| `c.value` | 48 ns | 37 ns | 32 ns | 13 ns |
| `c.increment()` | 58 ns | 52 ns | 64 ns | 57 ns |
| `Vector(1000)` | 252 ns | 310 ns | 4.2 µs | 2.4 µs |
| `complex_scale(1+2j, 3)` | 94 ns | 97 ns | — | 65 ns |

What the numbers say:

- **Speed: all three generate comparable native code.** On `fib` vcraft leads PyO3 by
  about 2×, and the differences that remain are at the boundary: per-call cost and
  conversions. vcraft leads `sum_floats`, `greet`, `describe` (keyword binding),
  `minmax`, `histogram` and complex numbers; PyO3 is marginally ahead on a bare `add`
  and on `c.add`, and leads `checksum` (the byte loop V's C backend lowers worse, see
  below) and `count_primes`/`make_range` (V's array-write lowering). zig-maturin trails
  on calls by structure.
- **Method and attribute calls are at PyO3's level.** `c.value` (37 vs 48 ns),
  `c.increment` (52 vs 58) and `c.is_zero` are faster than PyO3; `c.add` is level (68 vs
  67). The nanosecond rows carry ±10% run-to-run noise (PyO3's own `c.value` moved
  46 → 48 ns between the 1.2.0 and 1.3.0 runs), so read them against [HISTORY.md](HISTORY.md),
  which has a controlled measurement; the clean benchmark signal is `Counter()`, 106 → 92 ns
  against a flat PyO3. The benchmark's subclass publishes a state chain, and its own
  trampolines pay for it; a class with no base does not.
- **Memory.** PyO3 and zig-maturin stay near pure Python; vcraft keeps its Boehm heap —
  `count_primes` leaves 28.9 MiB against 9.5 (19.6 MiB in the 1.2.0 run; the retained
  figure is noisy between runs), and `make_range` 4.6 against 0.9, all plateauing, not
  leaking. Import RSS is the lowest of the three (760 KiB against PyO3's 788). No scenario
  leaks on any backend and no reference probe drifts.
- **Size.** vcraft and zig-maturin build the smallest wheels; PyO3's is the same order.
  vcraft's clean release build is the fastest.

## Known limits

### vcraft

- **V's array lowering.** `count_primes` and `make_range` sit ~1.1–1.2× PyO3 because
  `array.get` is a non-inline bounds-checked call behind `for x in arr` and `arr[i]`,
  `@[direct_array_access]` is not honored by `for in`, and the scalar `<<` fast path added
  in V's `#29736` does not fire for a local slice. It is in V's C codegen, not vcraft: the
  runtime's own cost — the call, the arguments, class access, boxing — is at or ahead of
  PyO3. Written up for the V project in [`V_UPSTREAM.md`](V_UPSTREAM.md).
- **The byte loop.** `checksum` over `bytes` is ~3× PyO3: the V loop reads through the
  non-inline `array.get`, whose `panic` branch keeps gcc from vectorizing the byte-widening
  sum, where LLVM emits a single `psadbw` for Rust's identical loop. Also in V; see
  [`V_UPSTREAM.md`](V_UPSTREAM.md).

### zig-maturin

- A `str` is truncated at an embedded NUL and accepted where `bytes` is meant; an unknown
  keyword argument is ignored; only exact `bytes` reaches a `[]const u8` parameter; an
  integer too large raises `TypeError` instead of `OverflowError`. All are found by the
  correctness matrix. Upstream.

### PyO3

Nothing to note in this benchmark.

## Workarounds in the benchmark code

So the three projects compile with the same semantics:

- **zig-maturin:** `build.zig` forwards the Python include and `make_range` uses
  `zm.PyList_SetItem`. Both are commented in the source.
- **vcraft:** none.
