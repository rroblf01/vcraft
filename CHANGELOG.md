# Changelog

All notable changes to vcraft are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Until 1.0, minor releases may change the
annotation vocabulary, the `vcraft.toml` keys and the CLI.

## [0.1.0] - Unreleased

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
  `vcraft build` now passes `-D_GNU_SOURCE` for Linux targets; a `#define` in
  the header itself comes too late, because the generated translation unit has
  already included system headers by then.

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

[0.1.0]: https://github.com/rroblf01/vcraft/releases/tag/vcraft/v0.1.0
