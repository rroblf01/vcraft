# Benchmark: PyO3 vs vcraft vs zig-maturin vs pybind11

Four independent projects implementing the same workloads with the same semantics, one
per tool, plus a pure-Python reference:

| directory | tool | language | module |
|---|---|---|---|
| [`pyo3/`](pyo3) | PyO3 0.29 + maturin 1.15 | Rust | `bench_pyo3` |
| [`vcraft/`](vcraft) | vcraft (this repo) | V | `bench_vcraft_native` |
| [`zig-maturin/`](zig-maturin) | [zig-maturin](https://github.com/rroblf01/zig-maturin) 1.0.1 | Zig 0.16 | `bench_zig` |
| [`pybind11/`](pybind11) | pybind11 3.1.0 + setuptools | C++17 | `bench_pybind11` |
| [`pure_python.py`](pure_python.py) | — | Python | `pure_python` |

## How to run it

```console
$ ./run.sh            # clean build of all four, install into .venv, benchmark
$ ./run.sh --quick    # fewer repeats, to check the harness
```

It needs `uv`, `cargo` and a `v` built at the commit pinned in `docker/` on `PATH`; `zig`
0.16 and a C++17 compiler (`c++`, for pybind11) are optional, and a backend whose
toolchain is missing is left out of the run with a warning. It installs nothing outside `benchmark/.venv`. `BENCH_PYTHON` picks the interpreter
(3.13 by default, the newest all of them support).

### Comparing two builds of vcraft

`run.sh` measures each backend once, one after the other, so a machine that changes state
in between (load, frequency scaling) moves its numbers by more than most optimisations do.
To tell whether a change to vcraft helped, [`ab.py`](ab.py) runs the same workloads for
several variants in turn, round after round, and keeps each variant's best figure:

```console
$ python ab.py pyo3=venv-a/bin/python:bench_pyo3 \
               base=venv-a/bin/python:bench_vcraft_native \
               new=venv-b/bin/python:bench_vcraft_native \
               --rounds 5 [--only 'Counter()' ...] [--import-runs 20] [--memory]
```

Each variant is `label=python:module`, so a variant is an interpreter with one build of
the module installed. The table gives every variant's time and two ratios: the last
variant against the first, and the last two against each other. Two identical builds
come out within about 5% of each other on short calls and about 10% on the long loops,
which is the floor below which a difference means nothing.

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
`vcraft build --release` (`v -prod`), `zig-maturin build --release` (`ReleaseSafe`) and
pybind11's setuptools helper with `-O3 -DNDEBUG`. The first three keep bounds checks; the
C++ indexes `std::vector` with `operator[]`, as idiomatic C++ does, which has none.

## Results

The current run is [`results-linux.md`](results-linux.md): Linux x86_64 (AMD Ryzen 5
3600), CPython 3.13, vcraft 1.8.0, V 36be926, PyO3 0.29, pybind11 3.1.0 (GCC 16). zig-maturin
is not in it: the machine has zig 0.17, which zig-maturin 1.0.1 does not build with; its
last figures are in the 1.3.0 run in [HISTORY.md](HISTORY.md). Time per call, lower is
better:

| workload | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|
| `add` | 73 ns | 62 ns | 79 ns | 36 ns |
| `fib(25)` | 221.3 µs | 106.2 µs | 112.0 µs | 9.07 ms |
| `count_primes(1e6)` | 1.99 ms | 2.12 ms | 2.31 ms | 94.44 ms |
| `sum_floats(100k)` | 842.1 µs | 228.8 µs | 840.9 µs | 1.58 ms |
| `make_range(100k)` | 2.25 ms | 2.28 ms | 2.98 ms | 2.15 ms |
| `greet` | 135 ns | 111 ns | 125 ns | 71 ns |
| `describe(3)` | 168 ns | 125 ns | 225 ns | 159 ns |
| `histogram(10k)` | 686.2 µs | 582.2 µs | 378.9 µs | 618.5 µs |
| `checksum(100kB)` | 13.7 µs | 12.6 µs | 12.8 µs | 2.19 ms |
| `join_strings(10k)` | 466.3 µs | 256.4 µs | 279.0 µs | 71.0 µs |
| `expect_positive(err)` | 217 ns | 212 ns | 3.1 µs | 223 ns |
| `Counter()` | 96 ns | 62 ns | 249 ns | 103 ns |
| `c.add(1)` | 65 ns | 54 ns | 155 ns | 53 ns |
| `c.value` | 46 ns | 33 ns | 107 ns | 12 ns |
| `list(Countdown())` | 337 ns | 239 ns | 4.3 µs | 584 ns |
| `Vector(1000)` | 226 ns | 217 ns | 397 ns | 2.3 µs |
| `complex_scale(1+2j, 3)` | 93 ns | 82 ns | 97 ns | 61 ns |

What the numbers say:

- **Compute is a draw between the compilers.** `fib` runs in 106 µs (V through gcc) and
  112 µs (C++ through gcc) against PyO3's 221 µs; the sieve and the buffer sums are
  within 15% of each other everywhere.
- **The boundary is where they differ.** vcraft is fastest on 21 of the 26 workloads,
  PyO3 on `count_primes` and `make_range` (and level on `v.total()` and the static
  method). pybind11 is fastest on `histogram` (its
  `unordered_map` to `dict`) and close on strings and bytes, but every call into a class
  costs it 2.5–6× more (`c.value` 107 ns, `c == c` 144 ns), and raising an exception
  (`expect_positive`, the `StopIteration` that ends `Countdown`) costs about 3–4 µs,
  14–18× the others: pybind11 throws a C++ exception and translates it.
- **Memory.** PyO3 and pybind11 stay near pure Python; vcraft keeps its Boehm heap
  (`count_primes` leaves 28.8 MiB against PyO3's 9.5, `make_range` 4.7 against 0.9), all
  plateauing, not leaking. Import adds 864 KiB with PyO3, 1,008 KiB with vcraft and
  2,672 KiB with pybind11 (which also imports slowest, 1.35 ms). No scenario leaks on any
  backend and no reference probe drifts.
- **Size.** pybind11 builds the smallest wheel (155 KiB, against 279 and 293); PyO3
  builds fastest from clean (9.1 s, pybind11 10.2, vcraft 14.1).
- **Correctness.** vcraft panics on `make_range(-1)` (the benchmark's V code makes a
  slice with a negative capacity); pybind11's two differences are under Known limits.

## Known limits

### vcraft

- **V's array lowering.** `count_primes` and `make_range` sit ~1.0–1.1× PyO3 because
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

### pybind11

- An integer that does not fit `int64_t` raises `TypeError` ("incompatible function
  arguments") instead of `OverflowError`: pybind11 reports any failed conversion as a
  mismatch of the whole signature.
- A `std::string` parameter accepts `bytes` as well as `str`, so `greet(b'x')` returns
  `'Hello, x!'` instead of raising. Both are found by the correctness matrix and are
  pybind11's documented behaviour, not the benchmark's code.

## Workarounds in the benchmark code

So the four projects compile with the same semantics:

- **zig-maturin:** `build.zig` forwards the Python include and `make_range` uses
  `zm.PyList_SetItem`. Both are commented in the source.
- **vcraft:** none.
- **pybind11:** none. `Vector` exports its buffer as doubles (format `d`) rather than
  bytes, so the memoryview case accepts either format.
