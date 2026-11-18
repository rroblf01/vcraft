"""Import V source files directly.

    import vcraft_tool.auto      # installs the import hook
    import fastmath             # compiles fastmath.v next to the caller, then imports it

The first import of a `.v` file builds it with vcraft into a cache keyed by its source,
the interpreter and the vcraft version; later imports load the cached extension, and an
edit rebuilds it. No project, `vcraft.toml` or wheel is involved: the file is the module.

The file is the whole V module. Its `module` line, when it has one, must name the module
being imported; without one it is added. Anything a `@[vc_*]` annotation exports is
there after the import, exactly as in a built project.

`vcraft_tool.auto.build(source, name)` is the same build for source held in a string,
which is what the Jupyter magic uses.
"""

from __future__ import annotations

import hashlib
import importlib.abc
import importlib.machinery
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path

from vcraft_tool._locate import vcraft_binary  # noqa: F401  (part of this module's API)

_MODULE_LINE = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", re.M)


def cache_root() -> Path:
    """Where built modules are kept: `$VCRAFT_HOME/auto`, else the user cache."""
    if os.environ.get("VCRAFT_HOME"):
        base = Path(os.environ["VCRAFT_HOME"])
    elif os.environ.get("XDG_CACHE_HOME"):
        base = Path(os.environ["XDG_CACHE_HOME"]) / "vcraft"
    else:
        base = Path.home() / ".cache" / "vcraft"
    return base / "auto"


def _with_module_line(source: str, name: str) -> str:
    found = _MODULE_LINE.search(source)
    if found is None:
        return f"module {name}\n\n{source}"
    if found.group(1) != name:
        raise ImportError(
            f"{name}.v declares `module {found.group(1)}`; importing it as `{name}` "
            f"needs `module {name}`"
        )
    return source


def _relocate_errors(output: str, name: str, origin: str, shift: int) -> str:
    """Point compiler messages at the user's file instead of the cache's copy.

    The build compiles `src/<name>.v` inside the cache, which may start with a `module`
    line the user's file does not have; locations are rewritten to the original path and
    its own line numbers.
    """
    # Either separator: the compiler names the file as it was given, `.\src\x.v` on Windows.
    pattern = re.compile(rf"(?:\.[/\\])?src[/\\]{re.escape(name)}\.v:(\d+):")
    return pattern.sub(lambda m: f"{origin}:{max(int(m.group(1)) - shift, 1)}:", output)


def build(source: str, name: str, release: bool = True, origin: str | None = None) -> Path:
    """Build V `source` as the extension module `name` and return the built file.

    Cached: the same source for the same interpreter and vcraft builds once. `origin`
    names the file the source came from, so a compile error points there.
    """
    if not name.isidentifier():
        raise ImportError(f"`{name}` is not a valid module name")
    text = _with_module_line(source, name)
    binary = vcraft_binary()
    version = subprocess.run([binary, "version"], capture_output=True, text=True).stdout.strip()
    key = hashlib.sha256(
        "\0".join([text, sys.version, sysconfig.get_platform(), version, str(release)]).encode()
    ).hexdigest()[:20]
    project = cache_root() / f"{name}-{key}"
    suffixes = importlib.machinery.EXTENSION_SUFFIXES
    built = [p for p in project.glob(f"dist/build/{name}*") if any(str(p).endswith(s) for s in suffixes)]
    if built:
        return built[0]
    (project / "src").mkdir(parents=True, exist_ok=True)
    (project / "vcraft.toml").write_text(
        f'[package]\nname = "{name}"\nversion = "0.0.0"\nmodule = "{name}"\n'
        f'description = "built by vcraft_tool.auto"\n'
    )
    (project / "v.mod").write_text(
        f"Module {{\n\tname: \"{name}\"\n\tbase_url: \"src\"\n\trequires: [\"vcraft\"]\n}}\n"
    )
    (project / "src" / f"{name}.v").write_text(text)
    command = [binary, "build", "--interpreter", sys.executable, "--skip-audit"]
    if release:
        command.append("--release")
    proc = subprocess.run(command, cwd=project, capture_output=True, text=True)
    if proc.returncode != 0:
        shutil.rmtree(project, ignore_errors=True)
        shift = text.count("\n") - source.count("\n")
        message = (proc.stderr or proc.stdout).strip()
        if origin:
            message = _relocate_errors(message, name, origin, shift)
        # Only the lines about the user's code: the compiler also prints notices about
        # vcraft's own runtime, which say nothing about this file.
        relevant = [line for line in message.splitlines() if "vcraft_tool/vlib" not in line]
        raise ImportError(f"vcraft could not build `{name}`:\n" + "\n".join(relevant))
    built = [p for p in project.glob(f"dist/build/{name}*") if any(str(p).endswith(s) for s in suffixes)]
    if not built:
        raise ImportError(f"vcraft built `{name}` but no extension module was written")
    return built[0]


def load(path: Path, name: str):
    """Import the extension module `name` from `path`."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class VFinder(importlib.abc.MetaPathFinder):
    """Finds `<name>.v` on the search path and builds it into an extension module."""

    def find_spec(self, fullname, path=None, target=None):
        last = fullname.rpartition(".")[2]
        for entry in (path if path is not None else sys.path):
            candidate = Path(entry or ".") / f"{last}.v"
            if candidate.is_file():
                built = build(candidate.read_text(), last, origin=str(candidate))
                return importlib.util.spec_from_file_location(fullname, built)
        return None


def install() -> None:
    """Put the finder first on `sys.meta_path`, once."""
    if not any(isinstance(f, VFinder) for f in sys.meta_path):
        sys.meta_path.insert(0, VFinder())


install()
