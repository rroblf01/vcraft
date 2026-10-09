# Roadmap to 1.0.0

1.0.0 is the next release. It promises stability: from 1.0 on, the annotation
vocabulary, the `vcraft.toml` keys and the CLI change only with a deprecation
period, and every claim in the documentation is backed by a test.

So the line between 1.0 and 1.x is drawn by what cannot change after the promise: the
public surface, and the conversions and calling conventions it fixes. Features that
only add to it can arrive in 1.1, 1.2... without breaking anyone.

Each item lands with its tests and a changelog entry under `[Unreleased]`, and is
checked off here when it does.

## Required for 1.0

### Surface to freeze

- [x] **API review and freeze.** `@[vc_gil]` became `@[vc_nogil]`, `@[vc_methods]`
      became `@[vc_method]`, build settings moved into `[build]`, classifiers became
      `classifiers = [...]`; the old forms warn until 2.0. Policy: README, *Stability*.
- [x] **Keyword arguments and defaults** for every function and method: any
      parameter by name, `?T` optional, `@[vc_defaults]` for the rest.
- [x] **`?T`, `map[string]T`, multi-value results and `[N]T`** of scalars and
      strings, as parameters and results (a tuple only as a result).
- [ ] **Migration guide** from 0.2: the classifier, regenerating the CI workflow, and
      rebuilding extensions for the thread fix.

### Correctness

- [x] **Threads.** Extensions can be called from any thread: every generated entry
      point registers the calling thread with V's collector, and unregisters it on
      exit. Covered by the CLI suite and the free-threaded CI job.
- [x] **The documentation only promises what works**, and every row of the type table
      is built and round-tripped in the CLI suite.
- [x] **README examples** are built in CI (`tests/docs/test_readme.py`).
- [x] **Leak checks in CI** (`tests/memory/test_leaks.py`).
- [x] **Sanitizers in CI** (`scripts/run-sanitized.sh`, ASan and UBSan).
- [x] **Fuzzed conversions in CI** (`tests/fuzz/test_fuzz.py`).
- [x] **Allocation failure raises MemoryError.** Out of reach: an allocation the
      system grants and cannot back is the OOM killer's, as for pure Python.
- [x] **Only `PyInit_<module>` is exported** from Linux extensions, on glibc and musl.

### Platforms and toolchain

- [x] **macOS runners on `macos-26`**, off the deprecated `macos-14`.
- [ ] **Linux aarch64 and musl green in CI.** The cells exist (`ubuntu-24.04-arm`,
      and the suites inside the musllinux image); checked off once a run is green.
- [ ] **Python 3.15**, if its final release comes out before 1.0: into
      `supported_pythons`, the CI matrix proper, the generated matrix and the
      classifiers. CI already runs it as a non-blocking prerelease cell.
- [x] **V in one command.** `vcraft toolchain install`; V pinned to `36be926`.
- [x] **Windows: decided.** Out of scope for 1.x; see [After 1.0](#after-10).

### Release hygiene

- [ ] **Actions off Node 20**, which GitHub is retiring: checkout, setup-python,
      cache, upload/download-artifact and the docker actions moved to their current
      majors.
- [ ] **The action's V cache keyed per runner image**, so a compiler built on one
      macOS image is never restored on another.
- [ ] **`SECURITY.md`**, and PyPI attestations checked on the published files.
- [ ] **Benchmark re-run** with thread registration in every call, to confirm its cost
      is negligible.
- [ ] **Images re-released** for 1.0 with the new V pin, and the musl CI job moved to
      them.

## In 1.x

Additions that do not change anything 1.0 promises.

- [ ] **More types:** enums, plain structs, maps with non-string keys, nested
      composites, and class instances (`&T`) in plain functions.
- [ ] **Callbacks:** calling a Python callable from V.
- [ ] **Class protocols:** `__len__`, `__getitem__`, `__contains__`, ordering
      comparisons, numeric operators, `classmethod`, module-level constants.
- [ ] **Buffer export:** returning memory as a `memoryview` without a copy.
- [ ] **Subinterpreters:** multi-phase initialisation (PEP 489) for every build.
- [ ] **V without building it:** a prebuilt V for each supported platform (as
      `ziglang` ships Zig on PyPI), so not even the five-minute build is needed.
- [ ] **Threaded workloads in the benchmark**, against PyO3's `allow_threads`.
- [ ] **Byte loops:** `checksum` is 3× PyO3; report the array lowering to V upstream
      and work around it in the runtime where possible.
- [ ] **Documentation site:** a user guide and a reference split out of the README.
- [ ] **A real project** published to PyPI with vcraft, as the reference example.

## Outside our control

- **A real V release.** vcraft pins a V commit because no release is new enough;
  once V publishes one newer than 0.5.2, vcraft depends on it instead. Not a 1.0
  blocker: `vcraft toolchain install` already hides the pin from users.

## After 1.0

Decided against for 1.x, written down so the decision can be revisited with its reasons.

- **Windows.** vcraft quotes every compiler argument for a POSIX shell, its build
  scripts are bash, the action refuses Windows runners, and no Windows wheel has ever
  been built. Supporting it means a cmd/PowerShell-safe build driver, MSVC or MinGW
  with V, `.pyd` naming and a CI job, which would delay 1.0 considerably. Until then
  the README and `vcraft build` say plainly that Windows is not supported.
