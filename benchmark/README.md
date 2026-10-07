# Benchmark: PyO3 vs vcraft vs zig-maturin

Three independent projects implementing **the same thirteen functions with the same
semantics**, one per tool, plus a pure-Python reference:

| directory | tool | language | module |
|---|---|---|---|
| [`pyo3/`](pyo3) | PyO3 0.29 + maturin 1.15 | Rust 1.98 | `bench_pyo3` |
| [`vcraft/`](vcraft) | vcraft (this repo) | V `0137eb5` | `bench_vcraft_native` |
| [`zig-maturin/`](zig-maturin) | [zig-maturin](https://github.com/rroblf01/zig-maturin) 1.0.1 | Zig 0.16 | `bench_zig` |
| [`pure_python.py`](pure_python.py) | — | Python | `pure_python` |

## How to run it

```console
$ ./run.sh            # clean build of all three, install into .venv, benchmark
$ ./run.sh --quick    # fewer repeats, to check the harness
```

It needs `uv`, `cargo`, `zig` 0.16 and a `v` built at the commit pinned in `docker/` on
`PATH`. It installs nothing outside `benchmark/.venv`. `BENCH_PYTHON` picks the interpreter
(3.13 by default, the newest all three support). The full result is written to
[`results.md`](results.md) and [`results.json`](results.json).

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
| `c.value` | attribute read |

- **Speed:** `timeit`, best of 7 repeats, in a dedicated process.
- **Memory:** each scenario runs in a fresh process, **twice in a row**.
  *Peak* is the process's maximum RSS. *Kept* is what stays resident after the first
  batch and `gc.collect()`. *Leak* is what the second batch, identical to the first, adds:
  a heap that has plateaued adds nothing, and a leak does.
- **Import:** 8 processes. The first is reported separately, because macOS verifies each
  freshly installed binary once; the "warm" figure is the median of the rest.
- **Size:** the wheel, the extension as built, and the extension after `strip -x`.
- **Correctness:** expected values, including `2**40`, and that `2**63` raises `OverflowError`.

Each tool compiles in its release mode: `cargo --release` (opt-level 3),
`vcraft build --release` (`v -prod`) and `zig-maturin build --release` (`ReleaseSafe`). All
three keep bounds checks.

## Initial results

macOS 27, Apple Silicon (arm64), CPython 3.13.15. A single machine and a single full
run; the earlier quick run gave the same figures within 5%.

This is the starting picture, before improving vcraft. vcraft's progress is under
[vcraft progress](#vcraft-progress), and the latest full run under
[`results.md`](results.md).

### Size and build

| | PyO3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | **189 KiB** | **186 KiB** |
| extension (`strip -x`) | 414 KiB | **351 KiB** | 400 KiB |
| clean release build¹ | 5.7 s | **2.1 s** | 8.4 s |

¹ Clean project, with warm cargo and zig caches (no downloads).

### Speed (time per call; lower is better)

| workload | PyO3 | vcraft | zig-maturin | Python |
|---|---|---|---|---|
| `add` | **29 ns** | 41 ns | 206 ns | 16 ns |
| `fib(25)` | 121 µs | **118 µs** | 164 µs | 5.20 ms |
| `count_primes(1e6)` | 2.00 ms | 3.76 ms | **1.43 ms** | 42.2 ms |
| `sum_floats(100k)` | **451 µs** | 968 µs | 496 µs | 775 µs |
| `make_range(100k)` | **833 µs** | 1.10 ms | 841 µs | 775 µs |
| `greet` | 60 ns | **39 ns** | 275 ns | 33 ns |
| `Counter()` | 36 ns | **35 ns** | 200 ns | 39 ns |
| `c.increment()` | **19 ns** | 29 ns | 194 ns | 27 ns |

### Memory

| | PyO3 | vcraft | zig-maturin | Python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,088 KiB | **144 KiB** | — |
| `import` (warm) | **0.51 ms** | 3.50 ms | 0.57 ms | — |
| `greet` ×2M: kept / leak | 0 / 0 | 13.8 MiB / 0 | 0 / 0 | 0 / 0 |
| `make_range` ×200: kept / leak | 0 / 0 | **790 MiB / 772 MiB** | 0 / 0 | 0 / 0 |
| `count_primes(10M)` ×5: kept / leak | 0 / 0 | 14.7 MiB / 0 | 0 / 0 | 0 / 0 |
| `Counter()` ×1M: kept / leak | 0 / 0 | 12.9 MiB / 0.9 MiB | 0 / 0 | 0 / 0 |

### Correctness

All correct except one case: with `add(2**63, 0)`, zig-maturin raises
`TypeError: expected int, got int` instead of `OverflowError`.

## Conclusions

**Speed: all three generate comparable native code.** On `fib`, the difference between
PyO3 and vcraft is noise, and Zig trails somewhat, probably because of `ReleaseSafe`. The
real differences are at the boundary with Python: the cost of each call and of conversions.
There PyO3 is the most consistent. vcraft is at 1.4–1.5× on simple calls and is best at
`greet` and object construction. zig-maturin pays 5–10× per call today, for one concrete
cause fixed with a one-liner (see below).

**Size: a practical tie.** Between 186 and 221 KiB per wheel. Not a criterion to choose by.

**RAM: PyO3 and zig-maturin are indistinguishable from pure Python. vcraft is not.**
- The Boehm GC adds about 1 MiB at import and leaves a 13–15 MiB heap it never returns
  to the system. It plateaus; it is not a leak.
- There is a real leak: **vcraft today has no way to return a list without losing
  memory** (see below). In `make_range`, every call loses the whole list.

**Is vcraft worth it?** The code V generates is as fast as Rust's. With the allocation
outside the GC, `count_primes` drops to 1.34 ms, better than the other two. Plus the build
is the fastest and the binary the smallest. But today **it is not on par with PyO3**:
it lacks basic pieces, like returning lists, and the GC costs RAM and speed on large
allocations. The foundation is worth it; the points below are what separate it from
PyO3, and almost all of them are bounded.

**zig-maturin** is very close to PyO3 in everything except per-call cost, and that has a
verified fix.

**PyO3** is the reference: the most consistent and with no failures in this benchmark. In
exchange, it has the heaviest build of the two with their own toolchain and a somewhat
larger wheel.

## What to improve

### vcraft

By priority. Each point is reproduced in this benchmark.

1. ✅ *Fixed in step 1.* **Returning `[]T` does not compile.** The emitter generates `vcraft.to_py_list(result)` with one
   argument, and the runtime declares `to_py_list[T](items, box)` with two
   (`vlib/vcraft_codegen/emit.v`, `boxed_expr`).
2. ✅ *Fixed in step 1.* **The alternatives for returning a list fail too.** Returning `vcraft.PyObj` or
   `PyObj` kills the generator with SIGBUS (exit 138), with no diagnostics. A
   `voidptr` under `@[vc_fn]` generates `result.ptr` over a pointer and does not compile.
3. ✅ *Solved in step 1: a `vcraft.PyObj` result hands over its reference.*
   **`@[vc_raw]` cannot return a new object without leaking it.** The glue treats the
   result as borrowed and does `borrow(result).new_ref()`. Together with points 1 and 2,
   returning a list means losing memory; that is what `make_range` measures.
4. ✅ *Fixed in step 1.* **An `i64` field in a class does not compile.** The generated getter and `__repr__` call
   `to_py_int` and `repr_int`, which only accept `int`. With this V, `int` is already 64 bits, so
   accepting both types is enough.
5. ✅ *Fixed in step 4.* **`sum_floats` is slower than pure Python**, 2.1× behind PyO3:
   `from_py_f64_seq_arg` does `obj.item(k)` and per-element checks, and appends to
   the result with `<<` on a GC array. Reading the list with `PySequence_Fast` and
   `PyFloat_AsDouble` over the items directly is the usual thing.
6. ✅ *Done in step 1, with no measurable effect.* **`to_py_list` builds the list with
   `PyList_New(0)` and `PyList_Append`.** Reserving it at its size is what PyO3 and
   pyo3zig do, but the difference in `make_range` is in point 7.
7. ✅ *Fixed in step 6 (import and memory); the diagnosis was wrong.* **GC
   cost.** Import was 3.5 ms vs 0.5 ms, with a minimum 13–15 MiB heap. Plus,
   large allocations ran 2.8× slower than with `calloc` (3.76 vs 1.34 ms in
   `count_primes`). The 3 ms and 13 MiB came from Boehm scanning every image in
   the process (step 6). The `calloc` part was not the GC: the experiment used a raw
   pointer, which skips the per-element calls V compiles `a[i] = x` into (step 5).
8. **Pending, in V:** V's new compiler turns every `<<` and every `a[i] = x` into
   a call with a one-element `memcpy`, and `@[direct_array_access]` does not avoid it on
   writes. That is what stands between vcraft and PyO3 in `count_primes` and `make_range`.
   Minimal repro (V `0137eb5`, `v -new-compiler -o out.c`):
   `fill(mut a []i64) { for i in 0 .. n { a[i] = i } }` generates per element
   `{ Array* _a0 = a; int _i0 = i; array__set(_a0, _i0, &(i64[]){i}); }`, identical
   with `@[direct_array_access]`; `a << x` generates `array_push(a, &x)`, with its
   checks and `copy_element_to` per element. The definitions are in the
   generated C itself (`array__set` bounds-checks and does a `vmemcpy` of
   `element_size`; `array__push` checks, reserves and does `copy_element_to`).
   Measured in `count_primes(1e6)`: half the samples land in
   `memmove`/`memcpy`, and the same sieve over a `malloc`'d buffer with direct
   stores drops to 1.7 ms (V `0137eb5`, macOS arm64), ahead of PyO3
   (2.02 ms). In `make_range(100k)` the split is the same in reverse: building
   the `[]i64` with `<<` costs 208 µs vs 13 µs with direct stores, and the
   C conversion is already on par with `list(range(100k))` (790 vs
   783 µs); the profile shows two thirds in `PyLong_FromLongLong` (one alloc per
   element, unavoidable) and one third in `array__push`. With no detours in user
   code there is no fix inside vcraft: V does the lowering.
   Reported to vlang/v; the issue text is in the chat history.
   Compiler note: measured thoroughly, no flag avoids it. V already compiles
   the extension with `-O3`; neither explicit `-O3` via `--cflags` (bit-identical
   binary: V emits it anyway), nor `-flto`, nor `-fwrapv` folds
   the `memcpy` in the large TU (verified by compiling the generated C by hand and
   by disassembler). In a small TU it does fold, and only with the full
   executable recipe (`-O3 -flto` leaves it ~2×); without LTO or in a large TU,
   the per-element `memcpy` stays. So `vcraft build` forces nothing:
   there is no lever.
9. ✅ *Measured after step 6, offered as the `gc-free-space-divisor` option and
   the default since (2).* `GC_set_free_space_divisor(1)`, the value V
   sets, grows the heap before collecting. With 2, on this machine: kept drops
   from 1.0 to 0.5 MiB after `greet` ×2M, from 1.1 to 0.3 in `make_range`
   and from 1.3 to 1.0 in `sum_floats`; import RSS does not change (1,120 KiB).
   It costs `sum_floats` 129 → 135 µs (+5%), `fib` +1.6%, and nothing measurable in
   the rest (`add` 22 → 23 ns is noise). Divisors 3 and 4 measured later:
   only `sum_floats` kept drops further (0.6 → 0.3 → 0.1 MiB); `greet` (0.5) and
   `make_range` (1.2) do not move, nor does speed. The floor is set by heap
   granularity, not the divisor: 2 stays. `GC_FORCE_UNMAP_ON_GCOLLECT=1`
   does not move kept by a single KiB either.

### zig-maturin

1. **`setjmp` per call** (`pyo3zig_capi.c`). On macOS, `setjmp` saves the signal mask
   with a syscall on every entry. Switching to `_setjmp`/`_longjmp`
   (or `sigsetjmp(env, 0)`), verified in a copy: `add` goes from 206 to **31 ns**,
   `increment` from 194 to **22 ns** and `greet` from 275 to 98 ns.
2. **`METH_VARARGS` instead of `METH_FASTCALL`.** It builds a tuple per call; PyO3 and vcraft
   use `FASTCALL`. Not measured separately.
3. **The `build.zig` that `scaffold` generates does not forward `-Dpython-include` to the dependency.**
   The dependency then falls back to `python3-config`, which does not exist in a uv venv, and the
   build aborts. Fixed in [`zig-maturin/build.zig`](zig-maturin/build.zig).
4. **Integer overflow:** it should raise `OverflowError`, not
   `TypeError: expected int, got int`.
5. **`pz` does not re-export `PyList_SetItem`**: the low-level
   `zig-maturin` module must be imported to build a list with no copies.
6. Without `--release`, `zig-maturin build` compiles in `Debug`. Worth keeping in mind when
   comparing.

### PyO3

Nothing to note in this benchmark.

## Workarounds in the benchmark code

So the three projects compile with the same semantics:
- **zig-maturin:** `build.zig` forwards the Python include (point 3) and `make_range` uses
  `zm.PyList_SetItem` (point 5). Both are commented in the source.
- **vcraft:** none since step 1. Before, `make_range` used `@[vc_raw]` (points 1–3,
  which is why it leaked) and `Counter.value` was `int` (point 4).

## vcraft progress

vcraft's figures after each step, with the full benchmark. PyO3 stays stable
across runs on large workloads (±3%: `count_primes`,
`sum_floats`, `make_range` moved +0.5%, +0.3% and +1.0% between the last two
full measurements); at nanosecond scale there is more noise
(PyO3's `greet`: 60 → 54 ns, −10%) and in warm import too
(+7% PyO3, +10% zig). Differences below 5% on small cells are not
real movement. The reference column is the initial table.

| step | `add` | `increment` | `sum_floats` | `make_range` | `count_primes` | `make_range` leak |
|---|---|---|---|---|---|---|
| PyO3 (reference) | 29 ns | 19 ns | 451 µs | 833 µs | 2.00 ms | 0 |
| initial | 41 ns | 29 ns | 968 µs | 1.10 ms | 3.76 ms | 772 MiB |
| 1. returning lists and objects | 40 ns | 29 ns | 970 µs | 1.09 ms | 3.76 ms | **0** |
| 2. fixed per-call cost | **22 ns** | 29 ns | 942 µs | 1.10 ms | 3.77 ms | 0 |
| 3. methods on the pointer | 23 ns | **16 ns** | 961 µs | 1.10 ms | 3.78 ms | 0 |
| 4. reading sequences | 22 ns | 16 ns | **153 µs** | 1.10 ms | 3.78 ms | 0 |
| 5. numeric lists in C | 22 ns | 16 ns | 152 µs | 1.03 ms | 3.77 ms | 0 |
| 6. GC roots (macOS) | 22 ns | 16 ns | **133 µs** | **988 µs** | 3.70 ms | 0 |
| verification after diagnostics, divisor, readers and Linux roots | 23 ns | 16 ns | 135 µs | 1.00 ms | 3.73 ms | 0 |
| divisor 2 by default + `bytes` with no view | 23 ns | 16 ns | 131 µs | 1.00 ms | 3.77 ms | 0 |

vcraft memory and import per step (PyO3: 0.50 ms import, 304 KiB, 0 kept):

| step | `import` | `import` RSS | kept after `greet` ×2M | `greet` ×2M peak |
|---|---|---|---|---|
| initial | 3.50 ms | 1,088 KiB | 13.8 MiB | 41.8 MiB |
| 6. GC roots (macOS) | **0.61 ms** | 1,120 KiB | **1.0 MiB** | **29.0 MiB** |
| verification after diagnostics, divisor, readers and Linux roots | 0.63 ms | 1,104 KiB | 1.0 MiB | 29.2 MiB |
| divisor 2 by default + `bytes` with no view | 0.62 ms | 1,136 KiB | **0.5 MiB** | 28.5 MiB |

**Step 1** (points 1–4 and 6). `[]T`, `vcraft.PyObj` and `voidptr` can now be returned, and
`i64` fields compile. The leak is gone: what is left after `make_range` is 18.5 MiB of
GC heap, which plateaus. Reserving the list at its size does not change the time: what
is expensive in `make_range` is first building the 800 KB `[]i64` in the GC, the same cost as
in `count_primes` (point 7).

**Step 2.** Each function's glue checked arity with two calls, and after each one
queried `PyErr_Occurred`. Now it is a single `nargs` comparison, and the
error message is only built on failure. Plus, an exact `int` that fits in
64 bits is read with a single C type check; before it was two `PyType_IsSubtype`
(one to reject `bool`, one to accept `int`) plus another error query. `add` goes
from 40 to **22 ns**, ahead of PyO3 (29 ns). Measured by parts in a copy of the glue: arity
contributed about 6 ns, integer reading about 10, and the panic guard
(`recover()`, one `_setjmp` per call) about 5. The guard stays: without it, a
V `panic` kills the interpreter. `increment` does not change because a method copies the
instance state in and out on every call; that is the next step.

**Step 3.** Methods, accessors and slots work on the instance's state block
through a pointer, like PyO3 through its cell, instead of copying the whole struct
before and after each call. Plus, the state chain each trampoline publishes
for `vcraft.state_at` (one `PyMem_Malloc` allocation and two copies per call) is only
emitted if some file in the module calls `state_at`. `increment` goes from 29 to **16 ns**,
ahead of PyO3 (19 ns). Trade-off, the same as in PyO3: a method that
`panic`s halfway keeps what it already wrote.

**Step 4.** Measuring turned up a leak the benchmark could not see: `PyObj.item` used
`PySequence_GetItem`, which returns a new reference, and its caller treated it
as borrowed. Every element read from a list passed as `[]T` kept one reference
too many, so the elements of a temporary list were never freed. Now
`item` uses `PyList_GetItem`/`PyTuple_GetItem`, and the benchmark has a scenario that passes
a fresh list on every call to catch it. Plus, `[]int`, `[]i64` and `[]f64`
convert in C, in a single pass, the elements that are exact `int` or `float`;
the rest takes the general path. `sum_floats` goes from 961 to **153 µs**, three times
faster than PyO3 (451 µs).

**Step 5.** A list returned from `[]i64`, `[]int` or `[]f64` is built in C in a
single pass, with `PyList_SET_ITEM`, instead of calling one function per element.
`make_range` drops from 1.10 to 1.03 ms; the conversion already costs the same as
`list(range(n))`. Profiling surfaced the real cause of what is left, and **it corrects
point 7**: it is not the GC. V's new compiler turns every `<<` and every
`a[i] = x` assignment into a function call that copies one element with `memcpy`, and
`@[direct_array_access]` only removes the check on reads. That is what separates
`count_primes` and `make_range` from PyO3, and it is in V, not in vcraft.

**Step 6.** On macOS, Boehm registered the writable data of **every**
image in the process as roots (about 400 in a normal Python), with one callback per
image. That cost about 3 ms of every import and made every collection walk
all those libraries' data, so their pages counted in the RSS. Now
vcraft starts the GC before V, without that registration, and hand-registers only the
module's `__DATA` segment, where V keeps its globals. Import goes from 3.5 to
**0.61 ms**, and memory kept after two million calls from 13.8 to **1.0 MiB**: what
looked like GC heap was system-library pages. Code that allocates
a lot also runs faster (`sum_floats` 153 → 133 µs; a loop that only concatenates
strings, 1.8×). Linux is unchanged: there Boehm registers libraries differently and I have
not measured it. Of the import that is left (0.63 vs 0.54 ms warm), `PyInit`
is not to blame: with the image preloaded it is 118 vs 230 µs; the rest is
Boehm startup, once per process. And import RSS (1,136 vs
304 KiB) does not yield to GC tuning either: neither `GC_MARKERS=1` nor
`GC_INITIAL_HEAP_SIZE=64k` moves it one KiB. Per `vmmap`, about 400 KiB is the
`.so` itself mapped (`__TEXT` 240 KiB resident + `__DATA`/`__LINKEDIT`); the
rest is runtime startup. There is no lever here: the extension is already the
smallest of the three after `strip` (351 vs 414 and 400 KiB). The definitive
test: an empty vcraft module keeps 1,104 of the 1,136 KiB — the nine
functions and the type only add ~30 KiB. Of those 1,104, `vmmap` attributes ~640
KiB to Boehm heap faulted at startup (the collector's internal structures, not
live data: the initial-heap knob does not move it either) and ~350 KiB to its own
mapping. Structural floor.

### State after step 6

vcraft beats PyO3 in `add` (22 vs 29 ns), `fib`, `sum_floats` (133 vs
451 µs), `greet` (34 vs 60 ns), `Counter()` and `increment` (16 vs 19 ns), and in
wheel size and build time. It loses in `count_primes` (3.70 vs 2.02 ms) and in
`make_range` (988 vs 829 µs), because of how V compiles array writes.
On memory it stays above: about 800 KiB more at import (the initial heap and the
GC structures) and around 1–2 MiB kept after large workloads.

### New workloads: `checksum` and `expect_positive`

Two paths the seven workloads did not touch: the buffer protocol (`bytes` with no
copy) and an exception round trip per call.

- `checksum(100k bytes)`: PyO3 1.7 µs, vcraft 4.8 µs, zig 25.7 µs. Adding it
  surfaced a real bug: `buffer_bytes` allocated a `[]u8` of the argument's size
  and then overwrote its `data` with the exporter's pointer,
  abandoning one GC block per call (the profile showed 26% in
  `GC_collect_or_expand`). Fixed by building the header from an empty literal;
  the `checksum(new 100kB) x500` memory scenario sits at 0.0
  kept and 0.0 leak on all three. After that, exact `bytes` no longer goes through
  the view (`vpy_is_exact_bytes` + direct alias; the profile goes from ~7% of
  samples in `GetBuffer`/`Release`/`PyMem_Calloc` to zero): at 100k the number does
  not move (4.8 µs, the loop rules) and at 256 B barely (125 vs 83 ns; the
  view was ~9 ns of those 42). Of what is left, the bulk is the loop: a sum with
  `u64(b)` widening vs Rust's SIMD, plus boxing the result.
- `expect_positive(-1)` under `try`: vcraft 93 ns, ahead of PyO3
  (112 ns), Python (124 ns) and zig (277 ns).
- On correctness, all three pass the three new checks. zig-maturin
  still fails `add 2**63` with `TypeError` instead of `OverflowError`.
- Note on `make_range` kept: it swings between 1.1 and 2.5 MiB across builds
  (measured 1.1, 1.8, 1.9 and 2.5 with leak always 0.0), even without the
  new functions. It is heap slack with divisor 1, not a leak and not a
  regression from any particular change.

### Second wave: `echo_bytes`, `join_strings`, `c.add`, `c.value`

Four boundaries the earlier workloads did not cover: a `bytes` return, a `str`
sequence, a method with an argument, and an attribute read.

- `echo_bytes(100k bytes)`: vcraft 1.5 µs, ahead of zig (1.7), Python (1.6) and
  PyO3 (4.2). The way in borrows in all three (the exact-`bytes` fast path on
  vcraft's side); the way out copies once everywhere. The memory scenario
  `echo_bytes(new 100kB) x500` sits at 0.0 kept and 0.0 leak on all four.
  (Purity note: `bytes(data)` and `data + b""` in pure Python return the same
  object, so the reference uses `bytes(memoryview(data))` — exactly one copy.)
- `join_strings(10k strs)`: zig 127 µs, vcraft 173, PyO3 204. The one boundary
  where zig leads by structure: `pz` borrows each item via `PyUnicode_AsUTF8`
  and only the join allocates, while vcraft copies every item into a V string
  (one GC allocation plus copy per item, 10k of them) and PyO3 builds a
  `Vec<String>`. A borrow-based `str` sequence reader would close most of it;
  the `join_strings(new 1k strs) x500` scenario (vcraft kept 0.8 MiB, leak 0.0)
  already guards that path against item leaks.
- `c.add(1)`: vcraft 22 ns, ahead of PyO3 (28 ns) and zig (204 ns — methods go
  through `METH_VARARGS` there, tuple included).
- `c.value`: vcraft and zig tie at 15 ns, PyO3 at 21.
- Correctness: all four pass the five new checks everywhere.
