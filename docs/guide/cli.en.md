# The command line

```console
$ vcraft --help
```

| Command | What it does |
| --- | --- |
| `vcraft new <name>` | Scaffolds a project: manifest, V source, demo, test, README |
| `vcraft build` | Runs the generator, compiles the extension and writes a wheel |
| `vcraft develop` | Builds and installs into the active virtualenv, editable by default |
| `vcraft info` | Prints what a build would resolve: module, suffix, tag, toolchain |
| `vcraft clean` | Removes `dist/` and the editable build output |
| `vcraft generate-ci` | Writes a GitHub Actions workflow that builds and checks the wheels |
| `vcraft publish` | Uploads the built wheels (refuses an editable build) |
| `vcraft toolchain` | Reports the V compiler vcraft uses and whether it is the pinned one |
| `vcraft toolchain install` | Builds the pinned V into vcraft's own cache |
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
| `--interpreter <path>` | `build`, `info` | The interpreter to build against |
| `--out-dir <dir>` | `build` | Where the wheel is written |
| `--dry-run` | `build`, `develop` | Print the plan without running it |

`vcraft info` is pure planning: it names the OS, architecture, tag and compiler without
touching a toolchain, so it works everywhere, including for a target whose compiler is not
installed.

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
