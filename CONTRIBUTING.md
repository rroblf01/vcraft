# Contributing to vcraft

Thanks for helping. vcraft is CPython bindings, a code generator and a wheel builder in
one repository; this page is the short way in. The details every change runs into are in
[AGENTS.md](AGENTS.md) (written for people and coding agents alike) and in each module's
README under `vlib/`.

## Setting up

You need Python 3.11 or newer, `git`, `make` and a C compiler. Build the V compiler vcraft
pins, then vcraft itself:

```console
$ pip install vcraft && vcraft toolchain install   # or build V at the commit in ci.yml
$ ./scripts/build-vcraft.sh                       # bin/vcraft from this checkout
```

**Never run `v` directly**: use `scripts/vcraft-v.sh`, which bounds memory and stops V from
answering a C error by rebuilding itself.

## Running the tests

Each suite is a plain Python script that builds what it needs; run the ones your change
touches, and all of them before a release:

```console
$ python3 tests/codegen/test_codegen.py    # the generator, through examples/hello
$ python3 tests/runtime/test_runtime.py    # the CPython runtime
$ python3 tests/cli/test_cli.py            # the CLI, in fresh virtualenvs
$ python3 tests/memory/test_leaks.py       # reference and memory leaks
```

The full list, in CI order, is in AGENTS.md. A behaviour change comes with a check in the
suite that covers it; a new annotation usually means a function in
`examples/hello/src/hello_native.v` and its checks in `tests/codegen/test_codegen.py`.

## What a change includes

- **Docs in both languages.** `docs/` is English and Spanish; a page changed in one needs
  its twin (`python3 scripts/check-docs-i18n.py`). README code blocks are compiled by
  `tests/docs/test_readme.py`.
- **A CHANGELOG entry** under `[Unreleased]`, saying what changed for a user.
- **MIGRATING.md** when anything a project relies on behaves differently.
- **Generated files regenerated, never edited**: `scripts/gen-runtime-docs.py` after a
  public runtime function changes, `scripts/update-ci-templates.py` after the workflow
  generator does.
- **Performance claims measured** with `benchmark/ab.py`, which interleaves builds; a
  single run cannot tell 5% apart.

Commit messages are in English and describe why, not only what.

## Proposing something bigger

Read [DECISIONS.md](DECISIONS.md) first: some obvious-looking additions were weighed and
set aside, with the reason. Then open an issue with the proposal template, so the design
can be agreed before the code is written.

## Reporting a vulnerability

Privately, as [SECURITY.md](SECURITY.md) describes, never in a public issue.
