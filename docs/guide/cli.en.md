# The command line

```console
$ vcraft --help
```

| Command | What it does |
| --- | --- |
| `vcraft new <name>` | Scaffolds a project: manifest, V source, demo, test, README |
| `vcraft init [dir]` | Adds vcraft to an existing Python project (see below) |
| `vcraft build` | Runs the generator, compiles the extension and writes a wheel |
| `vcraft develop` | Builds and installs into the active virtualenv, editable by default |
| `vcraft develop --watch` | The same, then again on every change to a V, C or manifest file (`--interval <ms>`, default 500) |
| `vcraft info` | Prints what a build would resolve: module, suffix, tag, toolchain |
| `vcraft clean` | Removes `dist/` and the editable build output |
| `vcraft generate-ci` | Writes a GitHub Actions workflow that builds and checks the wheels |
| `vcraft publish` | Uploads the built wheels (refuses an editable build) |
| `vcraft toolchain` | Reports the V compiler vcraft uses and whether it is the pinned one |
| `vcraft toolchain install` | Installs the pinned V into vcraft's own cache: the prebuilt archive where one is published, a source build otherwise (`--from-source` forces it) |
| `vcraft version` / `--version` | Prints the version |

## Common flags

| Flag | Applies to | Effect |
| --- | --- | --- |
| `--release` | `build` | Optimized build (`-prod`) |
| `--target <name>` | `build`, `info` | Cross target: `linux-x86_64-gnu`, `windows-amd64`, … |
| `--platform <tag>` | `build` | Overrides the wheel platform tag; must agree with `--target` |
| `--manylinux <ver>` / `--musllinux <ver>` | `build` | Claims a Linux distribution policy |
| `--abi3 <version>` | `build` | One stable-ABI wheel for `version` and newer |
| `--free-threading` | `build` | Build against the free-threaded ABI |
| `--interpreter <path>` | `build`, `info` | The interpreter to build against; `a,b,c` builds one wheel each |
| `--find-interpreter` | `build` | One wheel for every supported CPython on `PATH` |
| `--debug` | `build`, `develop` | `-g`: V line numbers in gdb and crash reports |
| `--sanitize` | `build`, `develop` | ASan and UBSan; prints how to run Python with the runtime preloaded |
| `--out-dir <dir>` | `build` | Where the wheel is written |
| `--dry-run` | `build`, `develop` | Print the plan without running it |
| `--pgo <script.py>` | `build`, `develop` | Profile-guided build with gcc (see below) |

`vcraft info` is pure planning: it names the OS, architecture, tag and compiler without
touching a toolchain, so it works everywhere, including for a target whose compiler is not
installed.

## Profile-guided builds: `--pgo`

```console
$ vcraft build --pgo bench_my_ext.py
pgo 1/3: instrumented build
pgo 2/3: training with bench_my_ext.py
pgo 3/3: optimized build
```

The extension is built once instrumented, the script runs against it (with the project's
Python tree importable) and records which branches and calls are hot, and the real build
is then optimized for that profile. Code the script never ran is still optimized for
speed (`-fprofile-partial-training`). It needs gcc as the C compiler and trains on this
machine with one interpreter, so it does not combine with `--target` or several
interpreters.

It is a trade, so measure with your own workload. On the benchmark it made 22 of 26
workloads 4-31% faster (`join_strings` 0.69x, `describe(3)` 0.74x, `add` 0.88x), but a
tight loop that writes an array element by element can lose: the prime sieve ran 1.64x
slower and the recursive `fib` 1.17x. Train with calls that resemble production, at
production sizes.

## An existing Python project: `vcraft init`

```console
$ cd mylib            # pyproject.toml, src/mylib/__init__.py, tests/...
$ vcraft init
$ vcraft develop --watch
```

`init` writes `vcraft.toml`, `v.mod`, `src/<name>_native.v` and `vcraft_build.py`, and
never overwrites one that exists. In `pyproject.toml` it replaces `[build-system]` only,
naming the backend it replaced; `[project]` stays the source of the metadata. It finds the
Python package under `python/`, `src/<pkg>` or a flat `<pkg>/` and records the last two
as `python-source` and `python-packages`, so the wheel carries that package, the
extension and its stub, and not the tests or scripts beside them. `--name` and
`--module` override the derived names.

`develop --watch` keeps running: each change rebuilds and reinstalls, so the next
`import` in a new process sees it. A failed build is printed and the watch continues.
Python files of an editable install need no rebuild.

## Examples

```console
$ vcraft build --release
$ vcraft build --target linux-aarch64-gnu --manylinux 2_17
$ vcraft build --abi3 3.11
$ vcraft build --interpreter /opt/python/cp312-cp312/bin/python
$ vcraft info --target windows-amd64
```

See [Wheels](wheels.md) for tags and policies, and [Continuous integration](ci.md) for
`generate-ci`.
