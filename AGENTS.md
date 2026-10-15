# AGENTS.md

Agent guidance for this repo. The executable sources of truth are `scripts/` and
`.github/workflows/ci.yml`; per-module detail is in `vlib/*/README.md`. `CLAUDE.md` is
git-ignored and local-only, so it may not be in your checkout.

## What this is

vcraft is to the V language what PyO3 + maturin is to Rust: CPython bindings written in
V, a code generator that turns `@[vc_*]` annotations into extension glue, and a CLI that
compiles the project with `v -shared` and writes the wheel itself. Currently at 1.2.0
(see `CHANGELOG.md`). No Rust, C++ or zlib in the pipeline.

`bin/`, `build/`, `**/_vcraft_generated.v` and `python/*.pyi` are generated and
git-ignored — never hand-edit them; regenerate with `scripts/build-vcraft.sh` or a suite.

## Invoking the V compiler

**Never call `v` directly.** Always go through `scripts/vcraft-v.sh`. A bare `v` answers
a failed C compile by bootstrapping the whole V compiler from source (GiB and minutes,
easy to trigger by accident). The wrapper passes `-new-compiler -no-parallel`, bounds
`VJOBS`, and runs under `systemd-run` with a 4 GiB ceiling (`VCRAFT_NO_MEMORY_LIMIT=1`
skips it, `VCRAFT_MEMORY_MAX` overrides).

V must be built from source at the commit pinned in `.github/workflows/ci.yml`
(`V_COMMIT`/`VC_COMMIT`); no V release is new enough (0.5.2 rejects `-new-compiler`).
The same pins appear in `docker/*`, `actions/vcraft-action/action.yml` and
`release-vcraft.yml` — keep them in sync. Modules are resolved with `-path
"$root/vlib|@vlib"`; `VMODULES` is never touched.

## Build and test

Each suite is a standalone, stdlib-only Python script (not pytest) that builds its own
prerequisites. Running a script runs that whole area — **there is no per-test filter**.
Each prints `ok`/`FAIL`, most through a local `Suite` helper copied into the file. CI order:

```
python3 tests/project/check_toml.py     # vcraft.toml parser (builds its own V driver)
python3 tests/packaging/test_pack.py    # scripts/pack-vcraft-wheel.py
python3 tests/wheel/test_wheel.py       # wheel writer
python3 tests/runtime/test_runtime.py   # CPython runtime
python3 tests/codegen/test_codegen.py   # code generator, end to end
python3 tests/memory/test_leaks.py      # each scenario twice per process; fails on growth
python3 tests/fuzz/test_fuzz.py [rounds] [calls-per-round]
python3 tests/docs/test_readme.py       # builds every ```v block of README.md (see markers)
python3 tests/cli/test_cli.py           # builds bin/vcraft, uses fresh venvs
```

Other scripts:

- `./scripts/build-vcraft.sh` builds the CLI into `bin/vcraft`.
- `./scripts/build-example.sh [example] [module]` runs the generator then compiles. It
  rebuilds `build/vc-generate` every time on purpose: a stale generator silently emits an
  empty module instead of erroring.
- `scripts/run-sanitized.sh <cmd>` builds ASan/UBSan (Linux only). Bound it with a cgroup
  (`systemd-run --user --scope -p MemoryMax=…`), **not** `RLIMIT_AS`: ASan reserves TBs.
- `./scripts/check-slot-ids.sh` checks the hard-coded `Py_tp_*` slot ids in
  `vlib/vcraft/cpython.c.v` against the installed CPython headers (the codegen suite runs
  it too).
- `scripts/build-probe.sh`, `build-runtime-tests.sh` and `build-wheel-test.sh` each
  compile one artifact (the Gate 0 probe, the runtime test module, the example wheel) and
  are called by the suites; prefer running the suite over these directly.

## Test environment quirks

- Suites and build scripts use whichever `python3` is first on `PATH`. To test another
  CPython, put a wrapper script named `python3` first on PATH; do **not** use a symlink
  (venvs made from a symlinked uv Python cannot find their stdlib).
- Free-threaded CI imports with `PYTHON_GIL=0 -W error::RuntimeWarning`; a missing
  `Py_mod_gil` declaration surfaces as an error that way.
- `tests/cli/test_cli.py` uses PyYAML to lint this repo's workflows and action and
  **skips** those checks when it is not installed.
- `tests/docs/test_readme.py` compiles every ```v block in `README.md`; put
  `<!-- readme-test: continue -->` or `<!-- readme-test: skip -->` on the line before a
  block to join it to the previous one or exclude it.
- Supported CPython is 3.11–3.15 plus 3.13t/3.14t/3.15t. Keep `supported_pythons` /
  `oldest_python` (`vlib/vcraft_project/build.v`), the `ci.yml` matrix, `Requires-Python`
  in `scripts/pack-vcraft-wheel.py` and `version` (`vlib/vcraft_project/env.v`) in step.
- CI also runs the suites on musl inside the published `vcraft-musllinux` image, under
  ASan/UBSan, and against a free-threaded interpreter. `MUSL_IMAGE` in `ci.yml` must name
  a **published** image: push the `images/v<version>` tag (which `release-images.yml`
  checks against `version` in `env.v`) before bumping `MUSL_IMAGE`, or the musl job fails
  with "manifest unknown" until the image exists. Then, in order, `vcraft/v<version>`
  (PyPI and the GitHub release), and `vcraft-action/v<version>` (which moves the action's
  floating tags and whose default version must already point at the vcraft release).

## Architecture

Layered modules under `vlib/`; each has a README with the easy-to-get-wrong details.

- `vlib/vcraft` — runtime linked into every extension: CPython bindings (`cpython.c.v`),
  C accessors (`c/shim.{c,h}`), conversions, classes, buffers, iterators, errors, panic
  guard, GIL. The API is stateless free functions; argument helpers take an explicit index.
- `vlib/vcraft_codegen` — parses V sources with `v.astquery` and emits
  `src/_vcraft_generated.v` (git-ignored) and `python/<package>.pyi`. The `@[...]`
  attribute block is read from the **source text** because V's parse tree drops attributes.
  `cmd/vc-generate` is a thin driver.
- `vlib/vcraft_wheel` — writes wheels and sdists from scratch: fixed-Huffman DEFLATE, ZIP,
  tar, SHA-256, CRC32, METADATA/WHEEL/RECORD, tags. No zlib.
- `vlib/vcraft_project` — `vcraft.toml` parser (a deliberately limited TOML subset),
  scaffolding, build and cross-compile planning, the PEP 517/660 backend.
- `vlib/vcraft_ci` — the workflow written by `vcraft generate-ci`.
- `cmd/vcraft` — the CLI; at runtime it locates `vlib` relative to its own binary.

`benchmark/` is a separate PyO3-vs-vcraft-vs-zig-maturin comparison; `./benchmark/run.sh`
needs `uv`, `cargo`, `zig` 0.16 and a pinned `v` on PATH, and installs only into
`benchmark/.venv`.

## V compiler constraints (silent breakage)

Full write-up in `vlib/vcraft/README.md`. Worth knowing when editing the runtime or
generator:

1. A module that binds CPython **must** `#include <Python.h>`: V emits no `fn C.`
   prototypes, so gcc assumes an `int` return, truncates `PyObject *`, and the module
   segfaults.
2. A `.c.v` file only exports its declarations to the module named on its own `module` line.
3. CPython data symbols (`PyExc_*`, `PY_VERSION_HEX`) need C accessors in `c/shim.c`.
4. Generic functions called across modules get no forward declaration and fail to compile
   (hence the panic guard is inlined per trampoline).
5. A `mut` receiver method on a struct from another module generates C that passes the
   struct by value (hence no reader/cursor object; helpers take explicit indices).
6. A file or module named `*_test` is compiled as a V test and its export is silently dropped.
7. The object header is 16 bytes with the GIL, 32 free-threaded, so struct mirrors come in
   two shapes and are checked at import (`check_layout`). `$if` in struct-field position is
   silently ignored, so the shapes are whole structs under a top-level `$if`.
