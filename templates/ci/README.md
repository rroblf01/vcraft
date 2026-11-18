# CI workflow templates

The GitHub Actions workflows `vcraft new --with-ci` and `vcraft generate-ci` write, kept
here as text so they can be read, reviewed and copied without running vcraft. They are
generated for a project named `mypkg` (module `mypkg_native`):

| File | When `vcraft.toml` says | Matrix |
| --- | --- | --- |
| [`build.yml`](build.yml) | nothing special | one wheel per CPython 3.11–3.15 for manylinux x86_64 and aarch64, macOS arm64 and Windows (20 cells) |
| [`build-abi3.yml`](build-abi3.yml) | `abi3 = "3.11"` in `[build]` | one stable-ABI wheel per platform, musllinux included (6 cells) |
| [`build-free-threading.yml`](build-free-threading.yml) | `free-threading = true` in `[build]` | 3.13t, 3.14t and 3.15t for manylinux x86_64, macOS arm64 and Windows (9 cells) |

Each builds and import-checks every wheel, builds an sdist, and on a `v*` tag publishes
both to PyPI through trusted publishing (see the CI guide for the one-time PyPI setup).

To use one, run `vcraft generate-ci` in your project, which writes the same file with
your names and your vcraft version. Copying one of these by hand works too: save it as
`.github/workflows/build.yml` and replace `mypkg_native` with your module.

They are regenerated, never edited: `python3 scripts/update-ci-templates.py` rewrites
them from `bin/vcraft`, and the CLI suite fails when they no longer match what the
generator writes.
