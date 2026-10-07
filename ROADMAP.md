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
- [ ] **The documentation only promises what works.** The type table in the README
      lists conversions the generator rejects (`map[string]V`, `?T`, enums, and
      possibly V function types, `[N]T` and structs). Correct it now, then implement
      the missing ones below.
- [ ] **Documentation tests.** Every row of the type table and every example in the
      README is compiled and run in CI, so the two cannot drift apart again.
- [ ] **Leak checks in CI.** The benchmark's memory scenarios (fresh objects per call,
      run twice) become a test that fails when the second batch keeps memory.
- [ ] **Sanitizers.** A CI job builds the runtime and an example with ASan and UBSan
      and runs the runtime and codegen suites under them.
- [ ] **Fuzzed conversions.** Random ints, floats, strings, bytes and sequences,
      including invalid ones, through every argument reader: no crash, the right
      exception.

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

- [ ] **Types:** `map[string]V` ↔ `dict`, `?T` ↔ `T | None`, enums, tuples.
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
