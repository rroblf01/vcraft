# Changelog

All notable changes to vcraft are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Until 1.0, minor releases may change the
annotation vocabulary, the `vcraft.toml` keys and the CLI.

## [Unreleased]

Work towards 1.0.0; see [ROADMAP.md](ROADMAP.md).

### Renamed (the old names keep working throughout 1.x, with a warning)

- **`@[vc_gil]` is now `@[vc_nogil]`**: it releases the GIL, which the old name read
  as the opposite of.
- **`@[vc_methods]` is now `@[vc_method]`**: it goes on one method at a time.
- **Build settings moved into a `[build]` table** in `vcraft.toml` (`minimum-version`,
  `abi3`, `free-threading`, `strip`, `embed-pyc`, `gc-free-space-divisor`). As
  top-level keys they had to precede every table, and written after `[package]` they
  were silently ignored; the same keys found under `[package]` are now reported.
- **Classifiers are written `classifiers = [...]`** in `[package]`; `[[classifier]]`
  tables are still read.

The public surface and the deprecation policy are written down under *Stability* in
the README.

### Added

- **Keyword arguments and defaults.** Every parameter can be passed by name, in any
  order; a `?T` parameter may be left out and arrives as `none`; and
  `@[vc_defaults: 'step=1, label="item"']` gives other bool, integer, float and string
  parameters defaults. Errors match Python's (missing, repeated, unknown and surplus
  arguments), signatures and stubs show the defaults, and a fully positional call
  costs what it did before. The README used to say keywords were supported; now they
  are.
- **Optional, dict, tuple and fixed-array conversions.** `?T` of a scalar or string
  maps to `T | None` both ways; `map[string]T` to a `dict` with `str` keys; a
  multi-value result `(A, B)` to a `tuple`; and `[N]T` takes any sequence of exactly
  N items and returns a `list`. Stubs name the precise types (`int | None`,
  `dict[str, int]`, `tuple[int, str]`). Other composites stay a diagnostic.
- **`vcraft toolchain install`** builds the V compiler vcraft is tested with into
  `~/.cache/vcraft` (or `$VCRAFT_HOME`), and vcraft finds it there by itself;
  `vcraft toolchain` reports which compiler is used and whether it is the pinned
  commit. `vcraft build` without any V now says how to get one. Building V takes a
  few minutes and about 6 GB of memory at its peak.

### Fixed

- **Cross-compiling to x86_64 from an aarch64 machine produced a mislabelled wheel.**
  vcraft named a cross compiler for aarch64 targets but none for `linux-x86_64-gnu`, so
  from an aarch64 host the build used the host's own `cc`, compiled an aarch64
  extension and tagged it x86_64. It now uses `x86_64-linux-gnu-gcc`, and refuses to
  build when that is missing.
- **A misspelt annotation was silently ignored.** The check for unknown annotations
  looked for a `vc.` prefix, which none has, so `@[vc_fnn]` left its function out of
  the module without a word. It is now an error naming the annotation.
- **The compilers vcraft runs inherited its VEXE.** A binary V compiles sets
  VEXE to the compiler that built it, and V locates its own vlib and thirdparty
  through VEXE: a pip-installed vcraft pointed the user's V at the release build's
  compiler path, which does not exist on their machine. vcraft now clears it.
- **Calling an extension from any thread but the importing one crashed Python.**
  V's garbage collector only knew the thread that imported the module, so the first
  collection triggered from another thread aborted the process with
  `Collecting from unknown thread`. A single worker thread, a `ThreadPoolExecutor`,
  `asyncio.to_thread` or a threaded web server was enough. With the GIL released
  (`@[vc_gil]`) or on free-threaded CPython the collector also neither stopped those
  threads nor scanned their stacks. Every function in the generated glue now
  registers the calling thread with the collector on its first call (one
  thread-local check afterwards), and the thread is unregistered when it exits.
  **Rebuild your extensions** to pick this up.
- **Narrow scalar parameters did not compile.** A function or method taking `i8`,
  `i16`, `i32`, `u8`, `u16`, `u32` or `f32` was accepted by the generator, which then
  wrote glue the V compiler rejected. They now read through range-checked
  conversions: an out-of-range value raises OverflowError.
- **Narrow class fields were written with the wrong width.** Assigning to an `f32`
  field stored the low bytes of a double (`2.0` read back as `0.0`), and an `i8` or
  `u8` field silently truncated out-of-range values. They now convert to their own
  width and raise OverflowError when the value does not fit.
- **An allocation V refused surfaced as RuntimeError.** V reports it with a panic;
  the glue now raises MemoryError for it, like any failed allocation in CPython.
- **Extensions exported more than their init function on musl.** V's own
  `backtrace`, `backtrace_symbols` and `backtrace_symbols_fd` reached the dynamic
  symbol table, where another library in the process could bind to them. Linux builds
  now link with a version script that exports only `PyInit_<module>`, on glibc and
  musl alike.
- **The README promised conversions that did not exist.** `map[string]V`, `?T`,
  enums, fixed arrays, plain structs, V function types and `&T` in plain functions
  are rejected by the generator; the type table now says so, `rune` is documented
  as the `int` code point it is, and every row is exercised by the CLI suite.

### Changed

- **Actions run on Node 24**, which GitHub is moving every action to: checkout v5,
  setup-python v6, cache v5, upload-artifact v6, download-artifact v7,
  build-push-action v7, setup-buildx-action v4, login-action v4, action-gh-release v3,
  in this repository's workflows, the action and the workflow `vcraft generate-ci`
  writes. The action keys its V cache on the runner image, not just its OS.
- **`SECURITY.md`** says how to report a vulnerability and how to verify a download;
  **`MIGRATING.md`** walks a 0.x project to 1.0.
- **V pinned to `36be926`** (vc snapshot `6851aaf`), from `0137eb5`. Every suite
  passes with it; it also stops V picking tcc implicitly on macOS 27. CI, the release,
  the action, both images and `vcraft toolchain install` move together; the musl CI
  job keeps the 0.2.0 image, and its older V, until the images are re-released.
- **README examples are built in CI** (`tests/docs/test_readme.py`). The
  `raise_custom` example called a helper the README never defined; it is complete now.
- **Sanitizer runs in CI**: the runtime, codegen and fuzz suites also run against
  extensions built with AddressSanitizer and UndefinedBehaviorSanitizer
  (`scripts/run-sanitized.sh`).
- **Fuzzed conversions run in CI**: `tests/fuzz/test_fuzz.py` sends seeded hostile
  arguments through every reader and fails on a crash or an unexpected exception.
- **Leak checks run in CI**: a new suite, `tests/memory/test_leaks.py`, fails on
  leaked Python objects, unbounded memory growth or drifting reference counts.
- **macOS builds run on `macos-26`**: the vcraft release and the workflows
  `vcraft generate-ci` writes moved off `macos-14`, which GitHub has deprecated.
  Wheels still target macOS 11.0. Regenerate your workflow with
  `vcraft generate-ci`.
- **The benchmark has a Linux run** and documents the threading crash and its fix
  (`benchmark/README.md`).

## [0.2.0] - 2026-10-07

Faster string and bytes arguments, complete PyPI pages for vcraft and for the
projects it builds, and a fix that let new projects be published at all.

### Added

- **PyPI project pages for your packages**: `readme` in `[package]` (default
  `README.md`, which `vcraft new` writes) becomes the long description PyPI shows,
  typed from its extension so Markdown renders as Markdown. `keywords` and a `[urls]`
  table (`Source = "https://..."`) fill in the sidebar. Wheels and sdists carry all
  three.
- **`vcraft --version`** and `-V`, alongside `vcraft version`.
- **A real PyPI page for vcraft itself**: the README as description, licence,
  project links, keywords and classifiers. Repository links in the README point at
  the release on GitHub so they resolve from pypi.org.

### Changed

- **Borrowed `str` sequences**: a `[]string` argument aliases each item's UTF-8
  buffer instead of copying it, so a 10k-item list costs no per-item
  allocation. The slice must not outlive the call, the same documented contract
  as `[]u8`; safe against mutation because `str` is immutable. Scalar `str`
  parameters still copy.
- **Cheaper `bytes` arguments**: the exact-`bytes` branch of
  `bytes_arg` reads the buffer and length with one C call into locals instead
  of through `bytes_of`, whose 8-byte result struct V allocated per call. Small
  `bytes` calls match PyO3 call-for-call.
- **The scaffolded README reads as a project page**: installation and usage first,
  development instructions last, since it is now what PyPI shows.

### Fixed

- **New projects could not be uploaded to PyPI**: `vcraft new` declared the
  classifier `Programming Language :: V`, which PyPI does not know, and PyPI rejects
  an upload with any unknown classifier. New projects use
  `Programming Language :: Other` and `Implementation :: CPython`. Existing projects
  should replace the `Programming Language :: V` entry in their `vcraft.toml`.

### Upgrading

Replace `text = "Programming Language :: V"` in `vcraft.toml` with
`text = "Programming Language :: Other"`. Workflows written by
`vcraft generate-ci` name the 0.2.0 images: regenerate them with
`vcraft generate-ci` after upgrading.

## [0.1.0] - 2026-10-07

The first release. vcraft builds native CPython extensions from V source and
packages them as wheels, with no Rust, C++ or zlib involved.

### Supported platforms

- CPython 3.11, 3.12, 3.13 and 3.14, plus free-threaded 3.13t and 3.14t. CI tests
  every one of them on Linux x86_64 and macOS arm64.
- Linux wheels for manylinux and musllinux, x86_64 and aarch64, built in the
  published container images. macOS wheels are arm64 and target macOS 11.0 or
  newer.
- Windows is not supported. `vcraft build` and the action refuse it explicitly.
- Building needs a V compiler built from source at the commit pinned in `docker/`.
  The V 0.5.2 release is too old for the flags vcraft passes.

### Added

- **Runtime (`vlib/vcraft`)**: CPython bindings written in V, covering module
  construction, argument parsing for `METH_FASTCALL` and keyword arguments, type
  marshalling, and translation of errors and panics into Python exceptions.
- **Code generator**: turns `@[vc_fn]`, `@[vc_class]`, `@[vc_methods]`,
  `@[vc_field]`, `@[vc_property]` and the other annotations into CPython glue written
  in V. It also writes a `.pyi` stub with signatures and docstrings.
- **Classes**: instances, read/write fields, methods, properties, `__repr__`,
  `__eq__`, `__ne__` and `__hash__`.
  - Inheritance between V classes with `@[vc_base]`.
  - Cycle collection for reference fields with `@[vc_ref]`.
- **Errors**: `!T` results become Python exceptions. `raise_domain` raises a specific
  built-in exception, and `@[vc_error]` maps custom V error types to their own
  exception classes.
- **Zero-copy buffers**: `[]u8` parameters alias any object that supports the buffer
  protocol instead of copying it.
- **GIL and iterators**: `@[vc_gil]` releases the GIL around a call, and
  `@[vc_iter]`/`@[vc_next]` implement the iterator protocol.
- **Wheel writer**: writes DEFLATE, the ZIP container, `METADATA`, `WHEEL`, `RECORD`
  with SHA-256, compatibility tags and PEP 427 file names, all from scratch.
- **Source distributions**.
- **PEP 517 and PEP 660 build backend**: `pip install .`, `pip install <sdist>` and
  `pip install -e .` all work.
- **abi3 builds**: a single stable-ABI wheel covers every CPython from its floor
  upwards. The lowest floor is 3.11.
- **Free-threaded builds**: the build checks that the interpreter really is
  free-threaded, and the module declares itself GIL-free.
- **CLI**: `vcraft new`, `build`, `develop` (editable by default, or `--copy`),
  `sdist`, `publish`, `info`, `generate-ci`, `clean` and `version`.
- **Cross-compilation planning**: `--target` accepts canonical names and Rust-style
  triples. Also adds `--manylinux`/`--musllinux` policies, `--cc`, `--cflags` and
  `--ldflags`, and `--dry-run`.
- **`vcraft generate-ci`**: writes a GitHub Actions workflow with one cell per
  supported CPython from the project's `minimum-version` up. An abi3 project gets one
  cell per platform, and a free-threaded project gets 3.13t and 3.14t cells. Each
  cell installs and imports its wheel in the image or interpreter it was built for.
- **`vcraft-action`**: a composite GitHub Action that builds on the runner or inside
  an image. It caches the V compiler between runs.
- **Container images**: manylinux and musllinux images with V and vcraft
  preinstalled.
- **Returning lists and objects**: functions and methods can return `[]T`
  (boxed into a Python list), `vcraft.PyObj` (its reference is handed to the
  caller) and `voidptr` (borrowed, increfed for the caller).
- **`i64` throughout**: class fields, method parameters and sequence parameters
  accept `i64` as well as `int` (with this V compiler, `int` is already 64 bits).
- **Narrow sequence parameters**: `[]i8`, `[]i16`, `[]i32`, `[]isize`, `[]rune`,
  `[]u16`, `[]u32`, `[]usize`, `[]f32` and `[]bool` convert with the same
  TypeError/OverflowError behaviour as scalar parameters. A sequence element
  with no reader is a diagnostic with file, line and column instead of a
  compile error in the generated glue.
- **Collector tuning**: `gc-free-space-divisor` in `vcraft.toml` sets Boehm's heap
  growth divisor (default 2: roughly half a MiB less stays resident after large
  workloads than with V's own 1, for a few percent of allocation-heavy
  throughput; set 1 to favour speed).
- **Distribution of vcraft itself**: `pip install vcraft` installs the tool on
  Python 3.11 or newer, as a platform wheel for Linux x86_64 (`manylinux_2_28`)
  or macOS arm64 (macOS 11.0+).

### Changed

- **Methods work in place**: methods, accessors and slots operate on the
  instance's state block through a pointer, as PyO3 works through its cell,
  instead of copying the struct in and out per call. As in PyO3, a method that
  fails halfway keeps the fields it already wrote.
- **Cheaper calls**: each trampoline checks arity with a single comparison, reads
  an exact `int` argument with one type check in C, and keeps one `_setjmp`
  panic guard per call (about 5 ns) so a V panic becomes a Python exception
  instead of killing the interpreter.
- **One-pass conversions**: `[]int`, `[]i64` and `[]f64` arguments are filled in
  a single C pass, and returned lists of those element types are built in a
  single C pass with `PyList_SET_ITEM`.
- **No-view fast path for exact `bytes`**: a `[]u8` argument that is exactly
  `bytes` aliases the object directly instead of allocating, acquiring and
  releasing a buffer view. Anything else bytes-like still goes through the
  view, which pins the exporter for the call.
- **Smaller per-call state**: the `state_at` chain is only published when the
  project calls `vcraft.state_at`.
- **Faster imports on macOS**: vcraft starts Boehm before V with only the
  module's own `__DATA` registered as roots, instead of scanning every loaded
  image. Import falls from about 3.5 ms to about 0.6 ms and the memory kept
  after two million calls from about 14 MiB to about 1 MiB. Linux builds do the
  same with the module's own writable segments (not yet measured there). See
  `benchmark/README.md` for the full before/after tables.

### Fixed

- **Leaked list items**: `PyObj.item` on lists and tuples borrows instead of
  returning a new reference the caller treated as borrowed, so the items of a
  sequence passed on every call are freed again.
- **Leaked results**: a raw result takes its reference instead of handing Python
  a pointer nobody owned, which used to crash the interpreter on exit.
- **Method diagnostics**: an unsupported parameter or return type on a
  `@[vc_methods]` method is reported with file, line and column instead of
  failing later as a compile error in the generated glue.
- **Lost C-level conversion errors**: when a CPython conversion set an exception
  while reading an argument, the runtime consumed it for its own message and
  the call failed with `SystemError: ... returned NULL without an exception
  set`. The original exception (e.g. OverflowError for a negative `u64`) now
  reaches the caller.
- **`u64` results**: a function returning an unsigned width never compiled; the
  result local starts as `u64(0)`.
- **Dead `bytes_of`**: `from_py_bytes`'s helper called
  `PyBytes_AsStringAndSize` with two arguments instead of three, which never
  compiled wherever V kept it. It now passes the buffer and length out-pointers
  and reports failure with a null pointer.
- **Abandoned buffer backing**: `buffer_bytes` allocated a `[]u8` of the
  argument's length and then overwrote its `data` with the exporter's pointer,
  so every `[]u8` call left a GC block of the argument's size behind for the
  collector. The slice header is now built from an empty literal.
- **`--dry-run` hid flags**: a release dry run printed the compiler invocation
  before `-prod` and the project root were added to it, so the shown command
  was not the one a real build runs. The plan now renders the full command.
- **Linux builds failed to compile**: the collector pre-initialiser uses
  `struct dl_phdr_info`, which glibc only declares with `_GNU_SOURCE`.
  `vcraft build` now passes `-D_GNU_SOURCE` for Linux targets, and
  `vlib/vcraft/cpython.c.v` carries `#flag linux -D_GNU_SOURCE` so the example
  script and manual `v` builds get it too. A `#define` in the header itself
  comes too late, because the generated translation unit has already included
  system headers by then.

### Build safeguards

`vcraft build` refuses these combinations before compiling, instead of producing a
wheel that fails later:

- an interpreter older than CPython 3.11;
- an `abi3` floor below 3.11, or above the interpreter running the build;
- `abi3` combined with `free-threading`, because free-threaded CPython has no stable
  ABI;
- `free-threading` on CPython older than 3.13;
- a free-threaded tag on a GIL interpreter, or a GIL tag on a free-threaded one.

On macOS the build sets `MACOSX_DEPLOYMENT_TARGET` to the version in the wheel's
platform tag, so the binary loads on every macOS the tag claims. If you set the
variable yourself, the tag follows your value. A `universal2` interpreter tag
becomes the single architecture that was actually compiled.

[Unreleased]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.2.0...HEAD
[0.2.0]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.1.0...vcraft/v0.2.0
[0.1.0]: https://github.com/rroblf01/vcraft/releases/tag/vcraft/v0.1.0
