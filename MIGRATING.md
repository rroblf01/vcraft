# Migrating from 0.x to 1.0

1.0 renames a few things and fixes behaviour that 0.x got wrong. Everything renamed
still works throughout 1.x and prints a warning saying what to write instead, so a
project builds unchanged; the steps below make the warnings go away and pick up the
fixes.

## 1. Install the toolchain

```console
$ pip install --upgrade vcraft
$ vcraft toolchain install      # the V compiler 1.0 is tested with, into vcraft's cache
```

1.0 pins a newer V commit. If you built V by hand for 0.x, `vcraft toolchain` tells you
whether it is the one 1.0 expects.

## 2. Rename two annotations

| 0.x | 1.0 |
|---|---|
| `@[vc_gil]` | `@[vc_nogil]` |
| `@[vc_methods]` | `@[vc_method]` |

Annotation spellings are now checked: a misspelt one, which 0.x ignored and so left
its function out of the module, is now an error.

## 3. Move build settings into `[build]`

```toml
# 0.x                              # 1.0
minimum-version = "3.11"           [package]
abi3 = "3.11"                      name = "my-extension"
                                   # ...
[package]                          classifiers = ["Programming Language :: Other"]
name = "my-extension"
# ...                              [build]
                                   minimum-version = "3.11"
[[classifier]]                     abi3 = "3.11"
text = "Programming Language :: V"
```

- `minimum-version`, `abi3`, `free-threading`, `strip`, `embed-pyc` and
  `gc-free-space-divisor` go in `[build]`.
- Classifiers become `classifiers = [...]` in `[package]`.
- Replace `Programming Language :: V` with `Programming Language :: Other`: PyPI does
  not know the former and rejects the whole upload (fixed in 0.2.0 for new projects).

## 4. Regenerate the CI workflow

```console
$ vcraft generate-ci
```

The 1.0 workflow builds macOS wheels on `macos-26`, uses actions that run on Node 24,
and names the 1.0 images.

## 5. Rebuild and republish your extensions

Extensions built with 0.x crash when called from any thread other than the one that
imported them (`Collecting from unknown thread`), which includes thread pools,
`asyncio.to_thread` and threaded web servers. The glue 1.0 generates registers every
calling thread with V's garbage collector, so rebuilding is what fixes it; nothing in
your V code changes.

## New in 1.0, nothing to change

- Every parameter can be passed by keyword; `?T` parameters are optional, and
  `@[vc_defaults: 'step=1']` gives defaults to others.
- `?T`, `map[string]T`, multi-value results (as tuples) and `[N]T` convert.
- `vcraft toolchain install`, `vcraft --version`, and a PyPI project page from your
  `README.md`.

The full list is in [CHANGELOG.md](CHANGELOG.md).
