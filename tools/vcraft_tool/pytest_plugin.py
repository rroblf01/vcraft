"""A pytest plugin that rebuilds the extension before the tests import it.

Installed with vcraft and inactive until asked for, so it never changes a test run that
did not opt in:

    pytest --vcraft-develop

or, for every run of a project, in `pyproject.toml`:

    [tool.pytest.ini_options]
    vcraft_develop = true

It runs `vcraft develop` in the project that holds the nearest `vcraft.toml` above the
rootdir before collection, so the tests always import the current V code. The build is
incremental: an unchanged tree costs a hash of the sources. A failed build stops the run
with the compiler's output instead of testing a stale extension.
"""

from __future__ import annotations

import importlib
import os
import site
import subprocess
import sys
import sysconfig
from pathlib import Path

import pytest


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("vcraft")
    group.addoption("--vcraft-develop", action="store_true", default=False,
                    help="run `vcraft develop` before collecting the tests")
    parser.addini("vcraft_develop", type="bool", default=False,
                  help="run `vcraft develop` before collecting the tests")


def _project_root(start: Path) -> Path | None:
    for directory in (start, *start.parents):
        if (directory / "vcraft.toml").is_file():
            return directory
    return None


def pytest_configure(config: pytest.Config) -> None:
    if not (config.getoption("vcraft_develop") or config.getini("vcraft_develop")):
        return
    root = _project_root(Path(config.rootpath))
    if root is None:
        raise pytest.UsageError("--vcraft-develop: no vcraft.toml at or above the rootdir")
    # Not from vcraft_tool.auto: importing that installs its .v import hook.
    from vcraft_tool._locate import vcraft_binary

    # `vcraft develop` installs into VIRTUAL_ENV. That is the environment of the
    # interpreter running these tests, which need not be the activated one: `.venv/bin/pytest`
    # runs from a virtualenv nobody activated.
    env = dict(os.environ)
    if sys.prefix != sys.base_prefix:
        env["VIRTUAL_ENV"] = sys.prefix
    proc = subprocess.run([vcraft_binary(), "develop"], cwd=root, env=env,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise pytest.UsageError(
            f"vcraft develop failed in {root}:\n{(proc.stderr or proc.stdout).strip()}")
    # A first `develop` writes `.pth` files, which Python reads only at start-up: without
    # this, the run that installed the project could not import it. `addsitedir` reads them
    # now and skips the directories already on sys.path.
    site.addsitedir(sysconfig.get_paths()["platlib"])
    importlib.invalidate_caches()
