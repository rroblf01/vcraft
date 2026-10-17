# Roadmap

vcraft reached 1.0 and kept the promise that came with it: the annotation vocabulary,
the `vcraft.toml` keys and the CLI change only with a deprecation period, and every claim
in the documentation is backed by a test. Every release since (1.1, 1.2, 1.3) has only
added to that surface. This file tracks what is left.

Each item lands with its tests and a changelog entry, and is checked off here when it
does.

## Reaching V's ceiling

vcraft's per-call cost is close to PyO3's; what remains is V's own output, the collector,
and a few things vcraft still owns.

- [x] **Inline instance state.** The state lives inside the object, after the PyObject
      header, so construction pays one allocation instead of two and a method follows no
      pointer. Construction is ~13% faster and method and attribute access ~5–8%.
      Shipped in 1.3.0.
- [x] **A constructor that fails no longer leaks the object.** `tp_new` releases the
      half-built instance when the user's constructor raises or panics. Shipped in 1.3.0.
- [x] **Buffer export.** Returning memory as a `memoryview` without a copy, from a
      function or a method, not only through `memoryview(instance)` on a class. Shipped in
      1.3.0 as `@[vc_memoryview]`.
- [x] **Call-path allocations.** A construction no longer builds the parameter-name and
      optional arrays as literals or puts the argument slots on the collector's heap, a
      base-less `newstate` no longer copies twice, `tp_iternext` checks for a pending
      exception once, and an exception is raised without a NUL-terminated copy of its
      message. `Vector(1000)` 1.23×→1.17× PyO3, `Vector(1)` 1.47×→~1.10×,
      `list(Countdown())` 1.27×→1.19×, `expect_positive(err)` now ahead. Shipped in
      1.3.0.
- [ ] **Byte loops and array lowering.** `checksum` over `bytes` is ~3× PyO3 and
      `count_primes`/`make_range` ~1.1–1.2×: V emits `array.get` (non-inline, bounds-checked)
      for `for x in arr` and `arr[i]`, does not honor `@[direct_array_access]` in `for in`,
      and does not take the scalar `<<` fast path for a local slice, and gcc does not
      vectorize the byte-widening sum. All of it is V's C codegen, not vcraft, and none of
      it is reachable from the runtime. Reported upstream in
      [`benchmark/V_UPSTREAM.md`](benchmark/V_UPSTREAM.md) with the generated C and the
      assembly; `@[direct_array_access]` on `count_primes` alone closes that row.
- [ ] **Boehm retention.** vcraft keeps its collector heap (`count_primes` leaves
      19.6 MiB against PyO3's 9.5), plateauing, never leaking. `gc-free-space-divisor` and
      `GC_set_force_unmap_on_gcollect` were measured in 1.3.0 and do not move it: the
      retained memory is live between batches, or free but not collected because nothing
      allocates after the batch. Structural until V exposes a knob.
- [ ] **Huge pages for native buffers.** A `@[vc_buffer]`'s backing is allocated with
      CPython's allocator, so it is neither page-aligned nor something `madvise` can act
      on. A project simulating a 20-qubit state (a 16 MB `[]f64`) is DRAM/TLB-bound: its
      gate kernels run at ~18 GB/s where a cache-resident run does 25 GB/s, while
      NumPy-based Cirq holds 23 GB/s. Allocating large buffers with `mmap` and
      `madvise(..., MADV_HUGEPAGE)` on Linux -- above a size threshold, with an opt-out and
      a fallback to the current allocator when transparent huge pages are off -- is the
      portable way to close that gap; macOS and Windows have no equivalent. It changes the
      core buffer lifecycle, so it lands only after profiling shows the workload is
      TLB-bound rather than bandwidth-bound.
- [ ] **Runtime SIMD dispatch for hot kernels.** `-march=x86-64-v2` (now reachable through
      `[build] cflags`) raises the cache-resident rate from 25 to 38 GB/s but leaves the
      DRAM-bound case unchanged, and a wheel built with it inherits that CPU floor and
      breaks a `vcraft.toml` shared with arm64. Function multiversioning -- a baseline and
      an AVX2 copy chosen at load with `__builtin_cpu_supports`, as NumPy and OpenBLAS do --
      gives the SIMD speed from a portable wheel. V's codegen does not emit it, so it is a
      C-shim design.

## In 1.x

Additions that do not change anything 1.x promises.

- [x] **Persistent native buffers:** a `@[vc_buffer]` field holds a `[]T` of scalars for
      the object's lifetime, freed at dealloc and exposed through the buffer protocol.
- [x] **Constructors with arguments:** `new_<class>` may take parameters, bound in
      `tp_new` with the same marshalling rules as a method.
- [x] **More types:** enums (a generated `enum.IntEnum`), plain structs (a `dict`), maps
      with non-string keys and nested composites, all as parameters and results. Class
      instances (`&T`) as parameters and results shipped in 1.3.0; the rest ships in 1.4.0.
- [x] **Callbacks:** `vcraft.call`, `call_owned`, `getattr` and `call_method` call a
      Python callable from V. Shipped in 1.3.0.
- [x] **Class protocols:** `@[vc_len]`, `@[vc_getitem]`, `@[vc_contains]`, the ordering
      operators `@[vc_lt]`/`vc_le`/`vc_gt`/`vc_ge`, `@[vc_classmethod]` and
      `@[vc_const]` module constants. Shipped in 1.3.0.
- [ ] **Numeric operators:** `__add__`, `__mul__` and the rest. They do not fit the
      `@[vc_eq]`/`@[vc_lt]` shape and need a design: an operator function takes two state
      pointers, so a mixed operand (`counter * 2`) has no state to hand over, the same
      slot is called with the operands swapped for the reflected case (`2 * counter`), and
      a result that is a *new* instance is not one of the operands, which is exactly what
      an instance-reference result refuses. Not a 1.3.0 item.
- [x] **Buffer export:** returning memory as a `memoryview` without a copy (see above).

- [ ] **V without building it:** a prebuilt V for each supported platform (as
      `ziglang` ships Zig on PyPI), so not even the five-minute build is needed.
- [x] **Threaded workloads in the benchmark**, against PyO3's `allow_threads`: an
      `lcg` loop from 1 to 8 threads, with the GIL released on all three backends.
- [x] **Documentation site:** a guide and a reference in English and Spanish under `docs/`,
      built with MkDocs Material and published to GitHub Pages. The README stays the source
      of truth and keeps every V example tested. Ships in 1.4.0.
- [x] **A real project** published to PyPI with vcraft: [`vqubit`](https://pypi.org/project/vqubit/),
      a dependency-free quantum computing framework whose linear algebra, gate matrices and
      simulators are written in V, shipped as one abi3 wheel per platform. Ships in 1.4.0.

## Platforms and toolchain

- [x] **Windows (`win_amd64`).** `vcraft build` links the `.pyd` against the interpreter's
      own import library with the MinGW runtime folded in statically, the CLI and
      `vcraft toolchain install` (`makev.bat`) work there, the action and
      `vcraft generate-ci` run on `windows-latest`, `release-v` publishes a prebuilt
      Windows V and `release-vcraft` a `win_amd64` wheel, and every suite — including the
      previously POSIX-only packaging, cli, docs and wheel — passes on `windows-latest`.
      Ships in 1.4.0.
- [x] **Linux aarch64 and musl green in CI.** The cells exist (`ubuntu-24.04-arm`, and
      the suites inside the musllinux image); green in CI from 1.4.0.

## Outside our control

- **A real V release.** vcraft pins a V commit because no release is new enough; once V
  publishes one newer than 0.5.2, vcraft depends on it instead. Not a blocker:
  `vcraft toolchain install` already hides the pin from users.

## After 1.x

Decided against for 1.x, written down so the decision can be revisited with its reasons.

- **arm64 Windows and MSVC.** 1.4 brings `win_amd64` linked with the toolchain V ships
  (MinGW-w64). MSVC links differently, and `win_arm64` needs its own import library and
  runner; both wait until the x64 path has real users.
- **Subinterpreters, deferred.** Multi-phase initialisation (PEP 489) is in place for the
  abi3 builds, so the remaining work is the state model, not the entry point. A heap type
  is per-interpreter from CPython 3.12, and the runtime keeps the type objects and the
  state-chain key in process-wide globals because V has no per-interpreter globals. Real
  support means moving that state into per-interpreter storage and proving that Boehm,
  which is process-wide, never lets a V object escape its interpreter -- and it cannot
  make Boehm itself per-interpreter. In the meantime, V code run directly (or in a
  subprocess) already gives stronger parallelism and isolation than a subinterpreter does:
  a subinterpreter only earns its keep for many isolated Python tenants in one process.
  Revisit when that is wanted and the state move looks tractable.
