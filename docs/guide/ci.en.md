# Continuous integration

`vcraft generate-ci` writes a GitHub Actions workflow that builds a wheel per supported
Python and platform, installs and imports each one, and is ready to publish to PyPI.

```console
$ vcraft generate-ci
wrote .github/workflows/build.yml
```

The matrix comes from the manifest. Without `abi3`, one wheel per interpreter; with
`abi3 = "3.11"`, one wheel per platform that covers every CPython from the floor up. Free
threading adds `3.13t`, `3.14t` and `3.15t` cells.

## What the workflow does

- Builds inside the published `vcraft-manylinux` / `vcraft-musllinux` images, so a Linux
  wheel carries the right libc policy.
- Runs aarch64 cells on arm runners.
- Tags macOS with the architecture actually built (`macosx-arm64`).
- Installs and imports each wheel before it is uploaded, so a wheel that builds but does
  not load fails the run.
- Uses the [vcraft action](https://github.com/rroblf01/vcraft/tree/main/actions/vcraft-action)
  to install the toolchain and build.

## Publishing from CI

The generated workflow is ready to publish. Add a token (a `PYPI_API_TOKEN` secret or
trusted publishing) and the release step uploads the wheels the matrix produced.

## Running the tool's own suites

The vcraft repository tests every claim in this documentation. If you are contributing,
the suites are in `tests/` (see `AGENTS.md`).
