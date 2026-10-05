# vcraft-action

Build a Python extension written in V, as a GitHub Action. It mirrors
`maturin-action`: it downloads pinned `vcraft` and V releases and runs any
`vcraft` command, and it can do it inside a manylinux container.

```yaml
- uses: rroblf01/vcraft/actions/vcraft-action@v1
  with:
    vcraft-version: v0.1.0
    v-version: '0.5.2'
    args: build --release
```

For a manylinux wheel, run the whole job in the published image instead and skip
the installs: the image already carries both.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/rroblf01/vcraft-manylinux:0.1.0
    steps:
      - uses: actions/checkout@v4
      - run: vcraft build --target linux-x86_64-gnu --manylinux 2_28
```

## Inputs

| Input               | Default        | Meaning                                    |
| ------------------- | -------------- | ------------------------------------------ |
| `vcraft-version`    | `v0.1.0`       | The vcraft release to download             |
| `v-version`         | `0.5.2`        | The V compiler release to download         |
| `args`              | `build --release` | The vcraft command to run               |
| `working-directory` | `.`            | The project directory to run vcraft in     |

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
