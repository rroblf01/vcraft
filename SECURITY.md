# Security policy

## Supported versions

Security fixes go into the latest minor release of the current major version. From
1.0 on that means the newest 1.x; older minors are not patched, since a minor release
never breaks the public surface (see *Stability* in the README) and upgrading within
1.x is the supported path.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub's
[security advisories](https://github.com/rroblf01/vcraft/security/advisories/new) for
this repository, with:

- what an attacker can do, and under which conditions;
- the vcraft version, the platform, and the CPython version;
- a minimal V project or Python snippet that reproduces it, if you have one.

You should get an acknowledgement within a week. Once a fix is ready it is released,
the advisory is published, and the changelog names the issue.

Things in scope include memory safety in the runtime (`vlib/vcraft`) or the generated
glue (a crash, a use-after-free, an out-of-bounds read reachable from Python), the
wheels and sdists vcraft writes, the build backend, and the release pipeline.

## Verifying what you install

vcraft's wheels are published to PyPI from GitHub Actions with trusted publishing, and
each file carries a PyPI provenance attestation tying it to the workflow run and the
commit that built it. PyPI shows it on each file's page, and it can be fetched from
`https://pypi.org/integrity/vcraft/<version>/<file>/provenance`.

The container images and the GitHub Action are built and released from this repository
by the workflows in `.github/workflows`; nothing is published from a developer machine.
