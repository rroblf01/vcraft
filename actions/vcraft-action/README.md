# vcraft-action

Build a Python extension written in V, as a GitHub Action. It mirrors
`maturin-action`: it installs a pinned `vcraft` release from PyPI, builds the V
compiler from a pinned source commit (no V release is newer than the flags
vcraft passes), and runs any `vcraft` command. It can also do it inside a
manylinux container, in which case nothing is installed at all.

Prerequisites are a Python with pip -- `actions/setup-python` -- and, for
container builds, Docker on the runner.

```yaml
- uses: rroblf01/vcraft/actions/vcraft-action@v1
  with:
    vcraft-version: v0.2.0
    args: build --release
```

For a manylinux wheel, run the whole job in the published image instead and skip
the installs: the image already carries both.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/rroblf01/vcraft-manylinux:0.2.0
    steps:
      - uses: actions/checkout@v4
      - run: vcraft build --target linux-x86_64-gnu --manylinux 2_28
```

## Inputs

| Input               | Default           | Meaning                                 |
| ------------------- | ----------------- | --------------------------------------- |
| `vcraft-version`    | `v0.2.0`          | The vcraft release to install from PyPI |
| `args`              | `build --release` | The vcraft command to run               |
| `container`         | `''`              | An image to build inside instead        |
| `working-directory` | `.`               | The project directory to run vcraft in  |

## Supported runners

Linux and macOS (arm64). The vcraft release is downloaded per runner OS, and
the V compiler is built from a pinned source commit on both: no V release is
newer than the flags vcraft passes, so a release binary is not an option yet.
When V cuts a newer release this goes back to downloading it; until then the
source build adds several minutes, and the `container` input skips the installs
entirely.

Windows runners are refused with a clear error: vcraft quotes its compiler
arguments for a POSIX shell and has never compiled there.

## Releases

The action is versioned by tag on this repository, independently of the images.
`v1` moves with every release and `v1.0` with every patch release, so `uses:
...@v1` tracks the action while `...@v1.0.0` pins it:

```console
$ git tag -a v1.0.0 -m "vcraft-action v1.0.0"
$ git tag -fa v1 -m "vcraft-action v1"
$ git tag -fa v1.0 -m "vcraft-action v1.0"
$ git push origin v1.0.0 v1.0 v1
```

The release workflow in `.github/workflows/release-action.yml` moves the floating
tags whenever a `vcraft-action/v*` tag is pushed, so the only manual step is
pushing the version tag.
