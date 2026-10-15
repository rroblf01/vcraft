# Changelog

All notable changes to vcraft are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor releases could change the
annotation vocabulary, the `vcraft.toml` keys and the CLI.

## [Unreleased]

## [1.2.0] - 2026-10-14

### Added

- **Persistent native buffers in `@[vc_class]`.** A field annotated `@[vc_buffer]` holds a
  `[]T` of scalars whose backing lives for the object's lifetime, is not copied per call,
  and is freed exactly once at dealloc. State that used to be rebuilt or batched per call
  can now live in V: a stabilizer tableau, a state vector, a scratch workspace. The
  `vcraft.buffer_new_*` helpers allocate the backing, `memoryview(instance)` exposes the
  first buffer of a class with no copy, `vcraft.buffer_resize_*` grows or shrinks it, and a
  resize is refused with `BufferError` while a memoryview is open. A class holding both a
  buffer and a `@[vc_ref]` is collectable and frees both.
- **Constructors that take arguments.** `new_<class>` may declare parameters; `tp_new`
  binds Python's positional and keyword arguments with the same marshalling rules a method
  uses, so `Vector(4)` calls `new_vector(4)` and the signature reaches the `.pyi` stub as
  `__init__`. A subclass runs its base's constructor with no arguments, so an
  argument-taking constructor is allowed only on a class whose base chain is argument-free;
  the generator reports the other case.
- **Capsules.** `vcraft.new_handle(value, destructor)` wraps an arbitrary native pointer in
  a `PyCapsule` and `vcraft.handle_data(capsule)` recovers it, as the escape hatch next to
  `@[vc_raw]` for state that is not a plain slice.
- **`@[vc_static]` and `@[vc_raw]` methods.** A static method is written
  `fn Class.name(...)` with no receiver and becomes a Python `staticmethod`; `@[vc_raw]` is
  now allowed on a method, where the arguments arrive as borrowed `PyObject`s and the
  receiver still works on the instance's state.
- **Complex numbers.** `math.complex.Complex` (or `complex.Complex`) marshals to and from a
  Python `complex`, and a real is accepted where a complex is expected.
- **Authors and maintainers.** `[package] authors` and `maintainers` in `vcraft.toml` reach
  `METADATA`, and a licence file at the project root travels in the wheel and the sdist.
- **Multi-line arrays in `vcraft.toml`.** A `classifiers` or `dependencies` list may span
  several lines instead of one very long one.
- **Element-typed sequence stubs.** Generated stubs type `[]int` as `Sequence[int]` rather
  than `Sequence[Any]`.
- **`ty` configuration** in the scaffold, beside the pyright and mypy hints.

### Changed

- **The state chain no longer allocates per call.** A module that publishes the chain —
  any class with a base whose methods reach it through `vcraft.state_at` — allocated a
  snapshot of it with `PyMem_Malloc` on every trampoline and freed it after. It is now a
  per-thread stack of frames in native thread-local storage, and the accessors are
  inlined, so leaving is a decrement. On the benchmark `Counter`: `c.add` 96 → 77 ns,
  `c.value` 72 → 48, `c.increment` 79 → 63.

### Fixed

- **`pyproject.toml` is merged, not overwritten.** `vcraft build` and `vcraft develop`
  used to replace the whole file with vcraft's template, silently deleting a project's own
  `[project]`, `[dependency-groups]` (PEP 735, so `uv sync --group dev` works) and
  `[tool.*]` tables. A build now rewrites only vcraft's `[build-system]` table and leaves
  every other table, comment and ordering in place; a file that does not exist yet is
  created from the full template.
- **`!void` functions and methods.** A result type of `!` (may fail, returns no value) was
  read as `voidptr`, and the wrapper tried to box a value the function never produced,
  which failed to compile. It is now treated as `void`.
- **Constructor name matching** now accepts the snake-cased spelling of a multi-word class,
  so `TallyBuffer` is built by `new_tally_buffer` as well as `new_tallybuffer`.
- **`PyExc.buffer_error`** added, so a buffer-protocol failure can name `BufferError`.
- **`vcraft develop` builds against the active virtualenv's interpreter.** It installed
  into the virtualenv but compiled with whatever `python3` was first on `PATH`, so the
  extension could be built for one CPython and installed into another.
- **Interpreter probes read past stderr.** The version and platform queries captured
  stdout and stderr together, so a stray warning became the answer and a working
  interpreter was reported as unsupported.
- **The editable pointer is silent and `vcraft clean` removes it.** A `.pth` naming a
  removed build directory no longer warns on every interpreter start, and cleaning drops
  the pointer and its `.dist-info` from the active environment.
- **`vcraft toolchain` reports the compiler it actually resolved** and a build warns when
  it is not the pinned commit, instead of printing a toolchain directory that may not
  exist.

## [1.1.1] - 2026-10-13

### Fixed

- **`vcraft new` normalises the name into a valid module.** A hyphen or an uppercase
  letter — both ordinary in a PyPI name — produced `module my-extension_native` or
  `module MyExt_native`, which V rejects, so the project did not compile. The derived
  module is now lowercased with `-` and `.` turned into `_`, the test file follows it,
  and a name that is not an identifier (a leading digit, a bad `--module`) is refused
  before anything is written.
- **`vcraft new` points type checkers at `python/`.** The generated `pyproject.toml`
  carries `[tool.pyright] extraPaths = ["python"]` and `[tool.mypy] mypy_path =
  "python"`, so `import <name>` is not reported missing by Pylance before the package
  is installed; after `vcraft develop`, the extension's `.pyi` stub sits beside the
  package and the re-export resolves too.
- **`vcraft develop` without an active virtualenv fails before the build**, with the
  command to create and activate one, instead of building first and then reporting "no
  interpreter at python3".

## [1.1.0] - 2026-10-13

### Added

- **A new project ships a runnable demo and a test.** `vcraft new` now writes `main.py`,
  which imports the extension and calls into it, and `tests/test_<name>.py` with
  `unittest` cases, so `python main.py` and `python -m unittest` work right after
  `vcraft develop`. Both travel in the sdist; neither is packaged into the wheel, so the
  demo is for the development loop rather than part of the distribution.
- **A new project is importable under its own name.** `vcraft new` writes a Python
  package `python/<name>/` that re-exports the native module, with a `py.typed` marker,
  so `import <name>` is the public name and a type checker sees the API. The native
  module `<name>_native` stays importable as an implementation detail. Hand-written
  Python under a project's `python/` directory was already packaged; the `py.typed`
  marker now travels with it.

### Fixed

- **The generated type stub ships in the wheel.** It was written to
  `python/<module>/_stubs.pyi`, which is not where a type checker looks for a
  top-level extension module, and the wheel packer dropped every `.pyi`, so an
  installed wheel offered no type information. The stub is now `python/<module>.pyi`
  and travels in the wheel next to the extension.
- **The list-conversion error path no longer leaks.** `type_name()` read a type's
  `__name__` with `PyObject_GetAttrString`, which builds a temporary Python str for the
  attribute key on every call, so a hot failure path that named the offending type — a
  list element that is not a float — lost about 48 bytes per call. It now reads the name
  with `PyType_GetName` and `PyUnicode_AsUTF8AndSize` through the C shim, allocating
  nothing. `sum_floats(['x'])` called 200,000 times went from a 9.2 MiB leak to 0,
  measured by the benchmark's error-path memory scenario.

### Changed

- **`vcraft new` prints the importable module and the first commands.** It names the
  extension module (which differs from the distribution name), shows the virtualenv
  step, and points at `python main.py` and `python -m unittest`. The README's quick
  start, "How it works" diagram and generated-layout section now match the files that
  are actually written.
- **The benchmark probes edge cases, reference retention and error paths.** The
  correctness matrix now covers integer limits and overflow, an embedded NUL and a
  non-BMP code point in a `str`, empty and negative sizes, wrong-typed arguments and
  every buffer-like object; a `sys.getrefcount` probe checks that no borrowed argument
  is retained; and the memory scenarios include calls that raise on every iteration. A
  case that aborts its process is re-run on its own instead of losing the run. The new
  probes found a leak in vcraft's list-conversion error path (~48 bytes per call) and
  three zig-maturin deviations (embedded-NUL truncation, a `str` read as bytes, and
  `OverflowError` reported as `TypeError`).
- **The benchmark covers keyword arguments and defaults.** A `describe` workload with
  two defaults and an optional parameter is exercised positionally, by keyword, mixed,
  and with missing, unknown and surplus arguments. It surfaced a zig-maturin bug: an
  unknown keyword is silently ignored instead of raising `TypeError`.
- **The benchmark covers optional values, maps, tuples and fixed-size arrays.** New
  workloads exercise `?T` in and out (`maybe_double`), a `dict` result built from a
  `list[str]` (`histogram`), a multi-value tuple result (`minmax`) and a `[N]T` in and
  out (`reverse3`), with the empty, wrong-type and wrong-length cases alongside. A
  plain dict expected value and a per-backend expectation table are now distinct
  (`PerBackend`), so `histogram` can be checked against a dict.
- **The benchmark covers the class surface.** Counter grows a read-only property, value
  equality and a hash; a `Countdown` class is its own iterator, with the exhaustion path
  checked against `StopIteration`; and a `BoundedCounter` exercises single inheritance,
  including an inherited field, an inherited method, `isinstance` both ways and the
  refusal path. All four backends pass.
- **The benchmark measures thread scaling.** An `lcg` workload — a serial integer loop
  with no vectorisation and no allocation — runs from 1 to 8 threads on each backend.
  It releases the GIL through PyO3's `detach`, Zig's `allowThreads` and vcraft's
  `@[vc_nogil]`, and the table reports the parallel speedup. All three scale on this
  12-core machine (vcraft 6.5×, zig-maturin 7.6×, PyO3 5.4× at eight threads), so
  thread registration and GIL release hold; the pure-Python reference, which cannot
  release the GIL, is not measured.
- **Python 3.15 support.** CPython 3.15.0 joined `supported_pythons`, the CI matrix, the
  wheel classifiers and the matrix `vcraft generate-ci` writes; the free-threaded list
  adds 3.15t. The GIL build needed no runtime changes — the slot ids, the layout check
  and the conversions already match 3.15's headers. The free-threaded build did: 3.15's
  `PyModuleDef_Init` rejects a definition whose head does not carry
  `_Py_STATICALLY_ALLOCATED_FLAG`, which only `PyModuleDef_HEAD_INIT` sets, so the
  module definition's head is now copied from a static one before its fields are filled
  in. The full suite passes on 3.15, and a free-threaded 3.15t wheel imports with the
  GIL disabled.
- **Small cleanups.** A local variable shadowing the module `version` constant was
  renamed, removing a V compiler warning. The benchmark's Performance note no longer
  counts "thirteen" workloads, its stale "Threads: what this benchmark did not measure"
  section now points at the thread-scaling table, and the roadmap's threaded-workloads
  item is checked off.
- **No deprecated process APIs.** Every `os.execute`/`os.system` call was replaced with
  `os.exec`/`os.system_args` (an argument array, no shell), removing the 23 V compiler
  deprecation warnings. `command -v` now uses `os.find_abs_path_of_executable`, the
  interpreter probes pass their script as one argument instead of building a quoted
  shell string, and `vcraft publish` passes the files in `dist/` as arguments. The
  `--dry-run` plan still prints the compiler command shell-quoted, so it can be pasted.

## [1.0.0] - 2026-10-09

The first stable release: from here on the annotation vocabulary, the `vcraft.toml`
keys and the CLI change only with a deprecation period. Upgrading from 0.x is
described in [MIGRATING.md](MIGRATING.md).

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
  few minutes and about 6 GB of memory at its peak. On musl (Alpine), where the last
  step of V's Makefile fails to link at the pinned commit after the compiler is
  built, a compiler that reports the pin is accepted with a warning; the musllinux
  image does the same.

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

[Unreleased]: https://github.com/rroblf01/vcraft/compare/vcraft/v1.0.0...HEAD
[1.0.0]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.2.0...vcraft/v1.0.0
[0.2.0]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.1.0...vcraft/v0.2.0
[0.1.0]: https://github.com/rroblf01/vcraft/releases/tag/vcraft/v0.1.0
