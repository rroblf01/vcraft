# Configuration

Packaging configuration lives in `vcraft.toml` at the project root. `vcraft new` writes
one. `pyproject.toml` is the only other file vcraft touches, and it is **merged, not
replaced**: a build rewrites just the `[build-system]` table and leaves every other table
alone, so a project's own `[project]`, `[dependency-groups]` (PEP 735, so
`uv sync --group dev` works) and `[tool.*]` config survive `vcraft build` and
`vcraft develop`.

```toml
[package]
name = "my-extension"
version = "0.1.0"
module = "my_extension"
description = "A Python extension written in V."
license = "MIT"
requires-python = ">=3.11"
readme = "README.md"         # the PyPI project page, rendered as Markdown
keywords = ["fast", "parsing"]
classifiers = ["Programming Language :: Other", "Programming Language :: Python :: 3"]
dependencies = []

[build]
minimum-version = "3.11"     # oldest CPython the CI matrix builds a wheel for
abi3 = "3.11"                # optional: one stable-ABI wheel for 3.11 and newer
free-threading = false       # true: build for a free-threaded CPython (3.13t+)
strip = false
embed-pyc = false
gc-free-space-divisor = 2    # Boehm heap growth: 1 favours speed, 2 memory

[urls]
Source = "https://github.com/me/my-extension"
Issues = "https://github.com/me/my-extension/issues"
```

## `[build]`

| Key | Default | Meaning |
| --- | --- | --- |
| `minimum-version` | `"3.11"` | Oldest CPython `vcraft generate-ci` builds a wheel for |
| `abi3` | unset | Stable-ABI floor for a single portable wheel, `3.11` or newer |
| `free-threading` | `false` | Build for a free-threaded interpreter and declare it GIL-free |
| `strip` | `false` | Strip the extension |
| `embed-pyc` | `false` | Ship sourceless `.pyc` files instead of the project's `.py` |
| `gc-free-space-divisor` | `2` | Boehm heap growth divisor; `1` trades memory for speed |

## `[package]` and `[urls]`

`readme` names the file PyPI shows as the project page (`.md` is rendered as Markdown,
`.rst` as reStructuredText); `vcraft new` writes a `README.md` and points at it.
Classifiers must be ones PyPI knows: V has none of its own, so use
`Programming Language :: Other`. Each entry of `[urls]` becomes a link in the PyPI sidebar.

## Refused combinations

`vcraft build` refuses the combinations that would compile and then fail later: an
interpreter older than 3.11, an `abi3` floor below 3.11 or above the interpreter building
it, `abi3` together with `free-threading` (free-threaded CPython has no stable ABI), and
`free-threading` on anything older than 3.13.

## Older spellings

Before 1.0 the build keys were top-level keys and classifiers were `[[classifier]]`
tables; both are still read throughout 1.x, with a warning saying what to change.
