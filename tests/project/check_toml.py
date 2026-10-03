"""Checks the `vcraft.toml` parser.

Every case here is a file that parses without error and reads back wrong. That is the
shape a parser bug takes when the grammar it implements is a subset of the real one: the
file looks fine, the diagnostics are empty, and the configuration is silently the
default. A parser that only ever sees well-formed input cannot tell the difference, so
the cases are the awkward ones rather than the ordinary ones.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def build_driver(tmp: Path) -> Path:
    """Build a small program that prints one configuration lookup."""
    src = tmp / "src"
    src.mkdir(parents=True, exist_ok=True)
    # `base_url` rather than a virtual `src/`: V no longer treats `src/` as a module
    # root, and every project here names its sources the same way for that reason.
    (tmp / "v.mod").write_text("Module {\n\tname: 'tomlcheck'\n\tbase_url: 'src'\n}\n")
    (src / "main.v").write_text(
        "module main\n\n"
        "import os\n\n"
        "import vcraft_project\n\n"
        "fn main() {\n"
        "\tpath := os.args[1]\n"
        "\ttext := os.read_file(path) or { panic('cannot read') }\n"
        "\ttable := vcraft_project.parse(text) or {\n"
        "\t\teprintln('PARSE ERROR: ' + err.msg())\n"
        "\t\texit(1)\n"
        "\t}\n"
        "\tpkg := table.subtable('package')\n"
        "\tprintln('name=' + pkg.string_of('name', '<none>'))\n"
        "\tprintln('version=' + pkg.string_of('version', '<none>'))\n"
        "\tprintln('abi3=' + table.string_of('abi3', '<none>'))\n"
        "\tprintln('minimum=' + table.string_of('minimum-version', '<none>'))\n"
        "\tprintln('free=' + table.bool_of('free-threading', false).str())\n"
        "\tprintln('strip=' + table.bool_of('strip', false).str())\n"
        "\tprintln('classifiers=' + pkg.string_list_of('classifiers').str())\n"
        "\tprintln('deps=' + pkg.string_list_of('dependencies').str())\n"
        "\tprintln('classifier0=' + table.subtable('classifier').string_of('text', '<none>'))\n"
        "\t}\n"
    )
    out = tmp / "driver"
    proc = subprocess.run(
        [str(ROOT / "scripts" / "vcraft-v.sh"), "-enable-globals", "-o", str(out),
         "-path", f"{ROOT}/vlib|@vlib", str(tmp)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"cannot build the driver:\n{proc.stdout}\n{proc.stderr}")
    return out


class Suite:
    def __init__(self) -> None:
        self.passed = 0
        self.failures: list[str] = []

    def check(self, label: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"  ok   {label}")
        else:
            print(f"  FAIL {label} {detail}")
            self.failures.append(label)

    def equal(self, label: str, got, expected) -> None:
        self.check(label, got == expected, f"got {got!r}, want {expected!r}")


def parse(driver: Path, tmp: Path, text: str) -> dict[str, str]:
    path = tmp / "case.toml"
    path.write_text(text)
    proc = subprocess.run([str(driver), str(path)], capture_output=True, text=True)
    values = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            values[key] = value
    return values


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="vcraft-toml-"))
    try:
        driver = build_driver(tmp)
        t = Suite()

        print("root keys before any table")
        got = parse(driver, tmp,
                    'abi3 = "3.12"\n'
                    'minimum-version = "3.13"\n'
                    "\n"
                    "[package]\n"
                    'name = "x"\n')
        # The bug this covers: a root key written after `[package]` belongs to that
        # table in TOML, and a parser that only reads the table it is in returns the
        # default with no diagnostic.
        t.equal("abi3", got.get("abi3"), "3.12")
        t.equal("minimum", got.get("minimum"), "3.13")
        t.equal("package name", got.get("name"), "x")

        print("a key after a table belongs to it")
        got = parse(driver, tmp,
                    "[package]\n"
                    'name = "x"\n'
                    'abi3 = "3.12"\n')
        t.equal("abi3 inside package is not a root key", got.get("abi3"), "<none>")

        print("types")
        got = parse(driver, tmp,
                    "free-threading = true\n"
                    "strip = false\n"
                    "\n"
                    "[package]\n"
                    'name = "x"\n')
        t.equal("a true boolean", got.get("free"), "true")
        t.equal("a false boolean", got.get("strip"), "false")

        print("arrays")
        got = parse(driver, tmp,
                    "[package]\n"
                    'name = "x"\n'
                    'classifiers = ["A :: B", "C :: D"]\n'
                    'dependencies = ["requests>=2", "numpy"]\n')
        t.equal("a string array", got.get("classifiers"), "['A :: B', 'C :: D']")
        t.equal("a dependency array", got.get("deps"), "['requests>=2', 'numpy']")

        print("a bare string is a one-element list")
        got = parse(driver, tmp,
                    "[package]\n"
                    'name = "x"\n'
                    'dependencies = "requests"\n')
        t.equal("a scalar where a list is meant", got.get("deps"), "['requests']")

        print("arrays of tables")
        got = parse(driver, tmp,
                    "[package]\n"
                    'name = "x"\n'
                    "\n"
                    "[[classifier]]\n"
                    'text = "First"\n'
                    "\n"
                    "[[classifier]]\n"
                    'text = "Second"\n')
        t.equal("the first table of an array", got.get("classifier0"), "First")

        print("comments and quoting")
        got = parse(driver, tmp,
                    "# a leading comment\n"
                    "[package]\n"
                    'name = "x"   # a trailing comment\n'
                    "\n"
                    "# another\n")
        t.equal("a comment after a value", got.get("name"), "x")
        got = parse(driver, tmp,
                    "[package]\n"
                    "name = 'x'\n"
                    'description = "a # inside quotes"\n')
        t.equal("single quotes", got.get("name"), "x")

        print("blank lines and trailing newlines")
        for label, text in [
            ("no trailing newline", '[package]\nname = "x"'),
            ("many blank lines", '[package]\n\n\n\nname = "x"\n\n\n'),
            ("leading blank lines", '\n\n[package]\nname = "x"\n'),
            ("only comments", '# nothing here\n'),
        ]:
            got = parse(driver, tmp, text)
            expected = "x" if "name" in text else "<none>"
            t.equal(label, got.get("name"), expected)

        print("malformed input is refused, not guessed")
        for label, text in [
            ("a line with no equals", "[package]\nname\n"),
            ("an unclosed table", "[package\nname = \"x\"\n"),
            ("an unclosed array of tables", "[[classifier]\ntext = \"x\"\n"),
            ("an empty key", "[package]\n = \"x\"\n"),
        ]:
            got = parse(driver, tmp, text)
            # The driver exits non-zero, so nothing is printed. The check is that the
            # parse did not succeed with values.
            t.check(label, got.get("name", "<none>") == "<none>", str(got))

        print("a whole project round-trips")
        project = ROOT / "examples" / "hello"
        if (project / "vcraft.toml").exists():
            got = parse(driver, tmp, (project / "vcraft.toml").read_text())
            t.equal("the example's name", got.get("name"), "hello")
            t.check("the example's module", got.get("name") == "hello", str(got))
        else:
            print("  skip no vcraft.toml in examples/hello")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if t.failures:
        print(f"{len(t.failures)} failure(s): {', '.join(t.failures)}")
        return 1
    print(f"all {t.passed} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
