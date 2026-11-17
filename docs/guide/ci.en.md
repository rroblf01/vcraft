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

Pushing a `v*` tag runs the matrix, builds an sdist, and then the `publish` job uploads
the wheels and the sdist to PyPI with
[trusted publishing](https://docs.pypi.org/trusted-publishers/): the job gets an OIDC
token from GitHub (`permissions: id-token: write`) and PyPI exchanges it for a
short-lived credential, so no API token or secret is stored anywhere. The rest of the
workflow is read-only (`contents: read`).

One-time setup, on PyPI's side: in the project's *Publishing* settings (or as a pending
publisher before the first release) add a GitHub publisher with your repository, the
workflow `build.yml` and the environment `pypi`. Create the `pypi` environment in the
repository settings, and add required reviewers there if a release should wait for an
approval. Then:

```console
$ git tag v0.1.0 && git push origin v0.1.0
```

## Running the tool's own suites

The vcraft repository tests every claim in this documentation. If you are contributing,
the suites are in `tests/` (see `AGENTS.md`).
