# Roadmap to 1.0.0

1.0.0 is the next release. It promises stability: from 1.0 on, the annotation
vocabulary, the `vcraft.toml` keys and the CLI change only with a deprecation
period, and every claim in the documentation is backed by a test.

Each item lands on `main` with its tests and a changelog entry under
`[Unreleased]`. Items are checked off here as they land.

## Correctness first

- [x] **Threads.** Extensions can be called from any thread: every generated entry
      point registers the calling thread with V's collector, and unregisters it on
      exit. Covered by the CLI suite and the free-threaded CI job.
- [x] **The documentation only promises what works.** The type table listed
      conversions the generator rejected (`map`, `?T`, enums, fixed arrays, structs,
      function types, `&T`); they are now listed as not supported yet. Narrow scalar
      parameters (`i8`…`u32`, `f32`) generated glue that did not compile, and narrow
      class fields were written with the wrong width; both fixed.
- [x] **Type table tests.** Every row of the type table is built and round-tripped in
      the CLI suite, with its range checks.
- [ ] **README example tests.** Every code example in the README compiled and run in
      CI.
- [x] **Leak checks in CI.** `tests/memory/test_leaks.py` runs fifteen scenarios
      (strings, lists, bytes, views, errors, owned and borrowed objects, instances,
      cycles, iteration, short-lived threads) twice in a fresh process and fails if
      the second batch keeps Python objects or grows the peak RSS, and checks that
      borrowed arguments keep their reference count.
- [ ] **Sanitizers.** A CI job builds the runtime and an example with ASan and UBSan
      and runs the runtime and codegen suites under them.
- [x] **Fuzzed conversions.** `tests/fuzz/test_fuzz.py` sends seeded random and
      hostile values (huge ints, NaN, surrogates, NULs, non-contiguous views, bad
      `__index__`/`__float__`, failing sequences, missing and surplus arguments)
      through every function, method and attribute of the example: no crash, only
      expected exceptions.

- [x] **Allocation failure raises MemoryError.** An allocation V refuses is a panic,
      which the glue now raises as MemoryError instead of RuntimeError. Out of reach:
      an allocation the system grants and then cannot back is the OOM killer's, as
      for pure Python; and under an address-space limit (`RLIMIT_AS`) Boehm's own
      marker can fault before V sees the failure.

## Platforms

- [x] **macOS runners on `macos-26`**, off the deprecated `macos-14`.
- [ ] **Python 3.15**, as soon as the final release is out (rc1 today): added to
      `supported_pythons`, CI, the generated matrix and the classifiers.
- [ ] **Linux aarch64 and musllinux tested per commit**, not only built: the suites run
      on `ubuntu-24.04-arm` and inside the musllinux image.
- [ ] **V without building it.** A prebuilt V at the pinned commit for each supported
      platform, installable from PyPI (as `ziglang` ships Zig) or by
      `vcraft toolchain install`, so `pip install vcraft` is enough to start.
- [ ] **Windows: decided.** Either supported, with a CI job, or documented as out of
      scope for 1.x with the reasons.

## Feature parity with PyO3

- [ ] **Types:** `map[string]V` ↔ `dict`, `?T` ↔ `T | None`, enums, tuples, fixed
      arrays, plain structs, and class instances (`&T`) in plain functions.
- [ ] **Arguments:** keyword arguments and defaults for every signature.
- [ ] **Callbacks:** calling a Python callable from V.
- [ ] **Class protocols:** `__len__`, `__getitem__`, `__contains__`, ordering
      comparisons, numeric operators, `classmethod`, module-level constants.
- [ ] **Buffer export:** returning memory as a `memoryview` without a copy.
- [ ] **Subinterpreters:** multi-phase initialisation (PEP 489) for every build, not
      only abi3.

## Performance

- [ ] **Threaded workloads in the benchmark:** GIL-released throughput against PyO3's
      `allow_threads`, and the collector's pause with many threads.
- [ ] **Byte loops:** `checksum` is 3× PyO3; report the array lowering to V upstream
      and work around it in the runtime where possible.

## Stability and release

- [ ] **API freeze:** annotations, `vcraft.toml` keys and CLI reviewed, renamed where
      needed, and frozen, with a written deprecation policy.
- [ ] **Documentation site:** a user guide and a reference split out of the README,
      with every example executed in CI.
- [ ] **A real V release:** depend on a published V newer than 0.5.2 once one exists,
      instead of a pinned commit.
- [ ] **Security:** `SECURITY.md`, and PyPI attestations checked.
- [ ] **A real project** published to PyPI with vcraft, as the reference example.
