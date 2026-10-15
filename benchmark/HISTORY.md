# Benchmark history

The measured log behind [`README.md`](README.md): the initial macOS run, the vcraft work in steps, and the later Linux runs, oldest first. The current results are in [`results-linux.md`](results-linux.md) (Linux) and [`results.md`](results.md) (macOS, older).

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
  samples in `GetBuffer`/`Release`/`PyMem_Calloc` to zero) and the exact-`bytes`
  branch reads buffer and length with one C call into locals instead of a
  multi-return helper (whose 8-byte result struct V allocated per call): at
  256 B vcraft now ties PyO3 call-for-call (83 vs 83 ns, was 125 vs 83). At
  100k the number does not move (4.8 µs), and the profile puts ~100% of samples
  in the loop itself — which *is* vectorized (NEON `tbl`/`uaddw`), but clang
  lowers the widening sum to nibble-split sequences, ~2.8x more instructions
  than the single `uaddlv` LLVM emits for Rust's identical loop. Backend code
  quality again, same class as the array-write lowering: no in-repo fix that
  keeps the three spellings comparable.
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

### Edge cases, references and error paths

Three probes the earlier waves did not have: a correctness matrix of edge cases, a
`sys.getrefcount` check on every borrowed argument, and a memory scenario that raises on
every call. Full figures in [`results.md`](results.md).

- **A vcraft leak on the list-conversion error path, since fixed.** `sum_floats(['x'])`,
  called 200,000 times, used to leave about **9.6 MiB** resident and a second identical
  batch added the same again — roughly 48 bytes lost per call, 0 for the other three
  backends. The cause was a per-call temporary in `type_name()`; the scenario now
  reports a 0 leak (see the vcraft fix list below).
- **`make_range(-1)` matches nothing.** `list(range(-1))` is `[]`, PyO3 returns `[]`,
  Zig fails inside CPython with a `listobject.c` SystemError, and vcraft raises
  `RuntimeError: panic in V code: negative .cap:-1`. The V panic guard contains it — the
  interpreter survives — but no backend here returns the reference's empty list.
- **zig-maturin truncates a `str` at an embedded NUL**: `greet('a\x00b')` returns
  `'Hello, a!'`, and it reads a `str` as bytes: `checksum('ab')` returns 195 instead of
  raising `TypeError`.
- **Only exact `bytes` is a buffer to PyO3 and Zig.** PyO3's `&[u8]` and Zig's
  `[]const u8` reject `bytearray`, `memoryview` and `array.array`; the reference and
  vcraft accept all of them through the buffer protocol.
- **No reference leaks anywhere.** Every borrowed argument's count is unchanged after
  2,000 calls in all four backends.

### Keywords, rich types, classes and threads

The keyword/default, optional, map, tuple and fixed-array workloads, the class surface
(property, equality, hash, iteration, inheritance) and the thread-scaling table went in
on all four backends.

- **zig-maturin ignores an unknown keyword argument.** `describe(3, nope=1)` returns
  `'item: 3'`; the other three raise `TypeError`.
- **vcraft, PyO3 and the reference agree on every keyword, optional, map, tuple,
  fixed-array and class case**, including the empty, wrong-type and wrong-length
  branches: `Counter() == Counter()` and `len({Counter(), Counter()}) == 1`, a
  `Countdown` that ends in `StopIteration`, and a `BoundedCounter` whose inherited
  field, inherited method and `isinstance` in both directions all behave. The
  `make_range(-1)` panic below stays vcraft's only divergence in the matrix.
- **All three release the GIL and scale.** On a 12-core machine with eight threads:
  vcraft 6.5×, zig-maturin 7.6×, PyO3 5.4×. Thread registration and `@[vc_nogil]` hold.

## Linux run

Linux x86_64 (AMD Ryzen 5 3600, glibc 2.44), CPython 3.13.13, vcraft 0.2.0. The first
run off macOS; full figures in [`results-linux.md`](results-linux.md).

| workload | PyO3 | vcraft | zig-maturin | Python |
|---|---|---|---|---|
| `add` | 73 ns | **65 ns** | 87 ns | 37 ns |
| `fib(25)` | 202.6 µs | **107.2 µs** | 323.2 µs | 9.41 ms |
| `count_primes(1e6)` | 1.95 ms | 2.37 ms | **1.89 ms** | 96.80 ms |
| `sum_floats(100k)` | 889.0 µs | **231.4 µs** | 1.13 ms | 1.53 ms |
| `greet` | 138 ns | **129 ns** | 224 ns | 75 ns |
| `checksum(100kB)` | **13.6 µs** | 41.9 µs | 39.4 µs | 2.17 ms |
| `join_strings(10k)` | 536.3 µs | 304.7 µs | **292.8 µs** | 72.2 µs |
| `c.add(1)` | 65 ns | **62 ns** | 87 ns | 63 ns |

The shape holds from macOS: vcraft leads on call overhead, recursion and
`list[float]` conversion, PyO3 on the byte loop, and pure Python still wins
`join_strings` because `str.join` never leaves C. Import costs vcraft 684 KiB of RSS
here, against 648 KiB for PyO3, rather than the 3.7× gap measured on macOS.

## Threads

Every workload above runs on the thread that imported the module; the *Thread scaling*
table near the end measures how each backend behaves when it does not. Before 1.0 it did
not, and the failure was silent until it aborted: run on any other thread, vcraft 0.2.0
crashed, because the V collector only knew the importing thread and the first collection
triggered from another one aborted the process with `Collecting from unknown thread`.
One worker thread was enough; so was a
`ThreadPoolExecutor`, a threaded web server, or `asyncio.to_thread`. With the GIL
released (`@[vc_nogil]`) or on free-threaded CPython it was worse in principle: the
collector neither stopped those threads nor scanned their stacks.

vcraft 1.0 registers each thread with the collector the first time it enters the
extension and unregisters it when the thread exits. Measured on the same Linux machine
with `bench_vcraft_native`, 200,000 `greet`/`join_strings`/`make_range` calls per thread:

| threads | 0.2.0 | with the fix |
|---|---|---|
| 1 worker | aborts | 0.2 s |
| 8 | aborts | 1.9 s |
| 16 | aborts | 3.7 s |
| `ThreadPoolExecutor(4)`, 500k `greet` | aborts | completes |

On free-threaded 3.14t with the GIL disabled, eight threads allocating in a
`@[vc_nogil]` function in parallel and a thousand short-lived threads all complete with
correct results. The CLI suite and the free-threaded CI job now cover these cases.

## vcraft 1.0 on Linux

The same machine and interpreter as the Linux run above, after the 1.0 work; full
figures in [`results-linux.md`](results-linux.md), which this run replaced.

| workload | vcraft 0.2.0 | vcraft 1.0 | PyO3 | Python |
|---|---|---|---|---|
| `add` | 65 ns | 73 ns | 72 ns | 35 ns |
| `fib(25)` | 107.2 µs | 102.4 µs | 205.5 µs | 9.28 ms |
| `greet` | 129 ns | 114 ns | 135 ns | 78 ns |
| `make_range(100k)` | 2.75 ms | 2.31 ms | 2.18 ms | 2.22 ms |
| `Counter()` | 93 ns | 103 ns | 90 ns | 79 ns |
| `c.add(1)` | 62 ns | 66 ns | 68 ns | 63 ns |

What moved, and why:

- **Thread registration costs nothing measurable.** Every call now checks a
  thread-local flag before anything else (see *Threads* above); a build with the check
  removed measured the same, and so did one compiled with the previous V pin.
- **Keyword arguments cost about 5 ns on a call with parameters.** Functions are now
  registered as `METH_FASTCALL | METH_KEYWORDS`, whose CPython dispatcher does slightly
  more than plain `METH_FASTCALL`. It is the convention PyO3 always uses, and `add` now
  sits with PyO3's.
- **A per-call allocation, found by bisecting this table, is gone.** The first version
  of keyword binding declared its slot array on every call and took its address, which
  V answers by moving the array to the collector's heap. The slots are now created only
  when a call uses keywords or leaves a parameter out; `Counter()` went from 112 ns back
  to 103 ns.
- The rest is within run-to-run noise, which is about ±10% for one run on this
  machine.

## vcraft 1.2.0 on Linux (first run)

The same machine as the Linux run above (AMD Ryzen 5 3600, 12 threads), CPython
3.13.16. This was the first 1.2.0 run; [`results-linux.md`](results-linux.md) is the
current one, which also includes the buffer/complex/static workloads and the
allocation-free state chain below.

This is the first run that includes the whole benchmark: the edge-case matrix, the
reference probes and the class surface. That matters for the method rows. The
benchmark's `BoundedCounter` inherits, and its generated `bump` reads the base through
`vcraft.state_at(1)`, so the module publishes the state chain on **every** trampoline —
one `PyMem_Malloc` and two chain copies per call (step 3 above). The earlier macOS and
1.0 Linux runs predate the class surface and did not pay it. So the method and
attribute rows are higher here than in those tables, and PyO3, which has no such
per-call cost, is ahead on them:

| workload | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| `add` | 72 ns | 70 ns | 89 ns | 36 ns |
| `fib(25)` | 222.1 µs | 108.9 µs | 383.5 µs | 9.11 ms |
| `greet` | 136 ns | 115 ns | 221 ns | 69 ns |
| `Counter()` | 102 ns | 105 ns | 75 ns | 93 ns |
| `c.increment()` | 47 ns | 82 ns | 60 ns | 55 ns |
| `c.add(1)` | 67 ns | 101 ns | 74 ns | 54 ns |
| `c.value` | 47 ns | 72 ns | 32 ns | 12 ns |
| `c.is_zero` | 35 ns | 70 ns | 47 ns | 37 ns |

vcraft still leads the boundaries the benchmark was built around: `fib` (2.0× over
PyO3), `sum_floats` (238 vs 849 µs), `greet`, `minmax` (652 vs 1,102 µs) and
`histogram` (569 vs 797 µs). It trails PyO3 on `checksum` (40.1 vs 13.4 µs, the same
byte-loop lowering noted above) and on `count_primes` and `make_range`, which are V's
array-write lowering rather than vcraft's. Thread scaling is unchanged: vcraft 6.2× on
eight threads, against PyO3 5.6× and zig-maturin 6.3×. Memory stays at the same floor —
868 KiB added at import and a 0.5 MiB round-off on `make_range`'s heap — with no leak
on any scenario and no leaked reference on any probe.

The method-call cost is worth a look before 1.3: the chain is published for a class
with no base too, and a module that never calls `state_at` pays nothing, but one
subclass turns it on for every trampoline in the file. Scoping the publish to the
classes that can observe it — one with a base, or a method whose body mentions
`state_at` — would take it off the common paths.

## vcraft 1.3.0 on Linux

Same machine, CPython 3.13.16. The state now lives inside the object instead of in a
separate `PyObject_Malloc` block behind a pointer, so a fresh instance pays one
allocation instead of two and a method reaches its state without following a pointer;
the per-trampoline "no state" branch is gone too. A class whose constructor failed also
stops leaking its object (a `tp_new` fix, not a speed one).

The clean signal is construction, where the extra allocation was paid every call and the
machine's noise cancels between the two backends:

| workload | 1.2.0 | 1.3.0 |
|---|---|---|
| `Counter()` | 106 ns | 92 ns |
| `Vector(1000)` | 306 ns | 310 ns |

PyO3's `Counter()` held at 94 → 96 ns across the two runs, so vcraft's −13% is the change,
not the machine; a controlled A/B over the class surface (many repeats, one process) put
construction at ~13% and attribute and method access at ~5–8% (`c.value`, `c.increment`,
`c.set_step`, a subclass property). The benchmark's nanosecond rows cannot resolve that
5–8% against its own ±10% run-to-run jitter — PyO3's `c.value` moved 46 → 48 ns and
`c.increment` 55 → 58 ns between the two runs, same code — so those rows move either way
here and are not evidence. The larger workloads (`fib`, `sum_floats`, `checksum`,
`count_primes`) do not touch class state at all and are unchanged within noise.

The 1.2.0 section's worry — the chain published on every trampoline of a file with a
subclass — is unchanged by this: 1.3.0 removed the extra object allocation and the
null-state branch, not the chain. Scoping the publish to the classes that can observe it
is still open.

Memory stays at the same floor: ~760 KiB added at import and no leak on any scenario.
Boehm's retained heap is as before and as noisy as before — `count_primes(10M)` kept
19.6 MiB in the 1.2.0 run and 28.9 MiB here (PyO3 and pure Python hold at 9.5 MiB) with a
0.5 MiB second-batch round-off, `GC_set_force_unmap_on_gcollect` and the free-space
divisor measured against it and neither moves it. It plateaus, never leaks.


## Call-path allocations (still 1.3.0)

Four per-call costs in the glue, none of them a change in what crosses the boundary:

- **The parameter-name and optional arrays were literals in `tp_new`.** Every
  `Class(...)` built `[]string{...}` and `[]bool{...}` with `new_array_from_c_array`.
  They are now module-level globals, the same ones a function trampoline already used.
- **The argument slots were a heap slice.** `mut bound := []voidptr{len: n}` asked the
  collector for a block on every construction. It is now a fixed array on the stack
  (`unsafe { [n]voidptr{} }` → `void* bound[n]`), so a positional construction allocates
  nothing for the slots.
- **A base-less `newstate` zeroed and copied the state twice.** `mut state := T{};
  state = *ctor()` is now `return *ctor()`.
- **`set_error` copied the message into a C string.** A V string has no terminator, so
  `PyErr_SetString` needed one built first: a malloc, a copy, a free and a `strlen` inside
  CPython, per exception. The message now goes across as a pointer and a length
  (`PyUnicode_FromStringAndSize` + `PyErr_SetObject`).
- **`tp_iternext` checked for a pending exception twice**, once in the `!T` branch and
  again in the shared tail.

A controlled A/B, many repeats in one process on the same machine:

| row | before | after | PyO3 |
|---|---|---|---|
| `Vector(1)` | 202 ns | **154 ns** | 140 ns |
| `Vector(1000)` | 296 ns | **278 ns** | 233 ns |
| `list(Countdown())` | 464 ns | **428 ns** | 370 ns |
| `expect_positive(err)` | 285 ns | **224 ns** | 237 ns |

`expect_positive` is now ahead of PyO3; the benchmark's `Vector(1000)` moves 1.23× → 1.17×
and `list(Countdown())` 1.27× → 1.19× (both ratios vcraft/PyO3, from the full run). The
nanosecond rows carry the benchmark's ±10% jitter, so only the controlled figures above
are the evidence.

What is left on `checksum` (~3×), `count_primes` and `make_range` (~1.1–1.2×) is V's C
codegen — `array.get` is a non-inline bounds-checked call, `for x in arr` ignores
`@[direct_array_access]`, the scalar `<<` fast path does not fire for a local slice, and
the byte-widening sum is not vectorized. It is written up for the V project in
[`V_UPSTREAM.md`](V_UPSTREAM.md); `@[direct_array_access]` on `count_primes` alone takes
it from 2.34 ms to 1.75 ms, ahead of PyO3's 1.96 ms.
