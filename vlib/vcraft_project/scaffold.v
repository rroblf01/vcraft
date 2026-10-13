module vcraft_project

import os

// Writing a new project.
//
// The scaffold is a fixed set of files rather than a template engine. A template engine
// would need its own parser and its own escaping rules to write four files that never
// vary, and the thing it would be escaping is a file this program also has to read back.

// scaffold_file is one file the scaffold writes.
pub struct ScaffoldFile {
pub mut:
	path    string
	content string
}

// scaffold returns the files that make up a new project.
//
// The layout is the one `examples/hello` uses: `v.mod` at the root naming the V module,
// the V source under `src/`, and no generated file checked in. The glue is written by
// `vcraft build` on every run, so a scaffold that shipped one would ship a file that
// goes stale the moment a function is added.
pub fn scaffold(p Project) []ScaffoldFile {
	mut files := []ScaffoldFile{}
	files << ScaffoldFile{
		path:    'vcraft.toml'
		content: p.render()
	}
	files << ScaffoldFile{
		path: 'v.mod'
		content: 'Module {\n\tname: "${p.module}"\n\tbase_url: "src"\n' +
			'\trequires: ["vcraft"]\n}\n'
	}
	files << ScaffoldFile{
		path:    'src/${p.module}.v'
		content: example_source(p)
	}
	files << ScaffoldFile{
		path:    'main.py'
		content: demo_main(p)
	}
	files << ScaffoldFile{
		path:    'tests/test_${p.name}.py'
		content: example_test(p)
	}
	files << ScaffoldFile{
		path:    'tests/__init__.py'
		content: ''
	}
	files << ScaffoldFile{
		path:    'README.md'
		content: readme(p)
	}
	files << ScaffoldFile{
		path:    '.gitignore'
		content: '/build/\n/dist/\n/.vcraft/\n/src/_vcraft_generated.v\n*.so\n__pycache__/\n*.pyc\n.pytest_cache/\n'
	}
	// The PEP 517 backend, so that `pip install .` works from a fresh checkout without
	// the project having to know anything about it.
	files << ScaffoldFile{
		path:    'pyproject.toml'
		content: pyproject_toml()
	}
	files << ScaffoldFile{
		path:    backend_py()
		content: backend_source()
	}
	return files
}

// example_source is the V file a new project starts with.
//
// It exercises one function of each kind, so that a first build produces something
// importable and the annotations are all visible in one place rather than discovered
// one at a time from the documentation.
fn example_source(p Project) string {
	mut out := 'module ${p.module}\n\nimport vcraft\n\n'
	out += '// greet returns a greeting for `name`.\n'
	out += '//\n'
	out += '// The doc comment becomes the Python `__doc__`, so it is worth writing.\n'
	out += '@[vc_fn]\n'
	out += 'pub fn greet(name string) string {\n'
	// The `\${name}` is V's own interpolation and belongs to the generated source, not
	// to this string, so it is escaped here and unescaped by the V lexer.
	out += "\treturn 'Hello, \${name}!'\n"
	out += '}\n\n'
	out += '// add returns the sum of two integers.\n'
	out += '@[vc_fn]\n'
	out += 'pub fn add(a int, b int) int {\n'
	out += '\treturn a + b\n'
	out += '}\n\n'
	out += '// parse_int reads a decimal integer, refusing anything else.\n'
	out += '//\n'
	out += '// The exceptions are the ones Python\'s own int() raises, which is the point of\n'
	out += '// raise_domain: a bare error() would make all three a RuntimeError and an\n'
	out += '// `except ValueError` around this call would stop matching.\n'
	out += '@[vc_fn]\n'
	out += 'pub fn parse_int(text string) !int {\n'
	out += '\tmut value := 0\n'
	out += '\tmut seen := false\n'
	out += '\tfor ch in text {\n'
	out += '\t\tif ch < `0` || ch > `9` {\n'
	out += "\t\t\treturn vcraft.raise_domain(.value_error, 'invalid literal for int()')\n"
	out += '\t\t}\n'
	out += '\t\tseen = true\n'
	out += '\t\tvalue = value * 10 + int(ch - `0`)\n'
	out += '\t}\n'
	out += '\tif !seen {\n'
	out += "\t\treturn vcraft.raise_domain(.value_error, 'invalid literal for int()')\n"
	out += '\t}\n'
	out += '\treturn value\n'
	out += '}\n\n'
	out += '// Counter is a class. Fields are scalars and become read/write attributes;\n'
	out += '// methods become methods; a property becomes a read-only attribute.\n'
	out += '//\n'
	out += '// Fields must be scalars. A V string held in a Python object is a pointer V\'s\n'
	out += '// collector cannot see, because it does not scan memory CPython allocated.\n'
	out += '@[vc_class]\n'
	out += 'pub struct Counter {\n'
	out += 'mut:\n'
	out += '\t@[vc_field] value int\n'
	out += '\t@[vc_field] step int\n'
	out += '}\n\n'
	out += '// new_counter is the constructor. It takes no arguments; an instance is made by\n'
	out += '// calling the type, and `Counter(1)` is a TypeError.\n'
	out += '//\n'
	out += '//\n'
	out += '// `@[vc_fn]` is what makes the generator see this as a constructor. Without the\n'
	out += '// annotation it is an ordinary private helper, `link_classes` never finds it, and\n'
	out += '// the instances come out holding whatever the allocator left behind. The\n'
	out += '// generator then removes it from the exported set, because a `new_*` is the\n'
	out += '// type\'s `tp_new` rather than something Python can call.\n'
	out += '@[vc_fn]\n'
	out += 'pub fn new_counter() &Counter {\n'
	out += '\treturn &Counter{ step: 1 }\n'
	out += '}\n\n'
	out += '// increment adds step to value and returns the new total.\n'
	out += '@[vc_method]\n'
	out += 'pub fn (mut c Counter) increment() int {\n'
	out += '\tc.value += c.step\n'
	out += '\treturn c.value\n'
	out += '}\n\n'
	out += '// is_zero reports whether the value is still zero.\n'
	out += '@[vc_method]\n'
	out += '@[vc_property]\n'
	out += 'pub fn (c &Counter) is_zero() bool {\n'
	out += '\treturn c.value == 0\n'
	out += '}\n'
	return out
}

// demo_main is the runnable example a new project starts with.
//
// It lives at the project root rather than under `python/`, so it is not packaged into
// the wheel: it is the first thing to run after `vcraft develop`, a way to see the
// extension work without writing any Python first.
fn demo_main(p Project) string {
	mut out := '"""Run this after `vcraft develop` to see the extension in action."""\n\n'
	out += 'from __future__ import annotations\n\n'
	out += 'import ${p.module} as m\n\n\n'
	out += 'def main() -> None:\n'
	out += '\tprint(m.greet("world"))\n'
	out += '\tprint(m.add(2, 3))\n'
	out += '\tcounter = m.Counter()\n'
	out += '\tprint(counter.increment())\n'
	out += '\ttry:\n'
	out += '\t\tm.parse_int("not a number")\n'
	out += '\texcept ValueError as exc:\n'
	out += '\t\tprint(f"parse_int: {exc}")\n\n\n'
	out += 'if __name__ == "__main__":\n'
	out += '\tmain()\n'
	return out
}

// example_test is the test a new project starts with.
//
// `unittest` from the standard library rather than pytest, so `python -m unittest` runs
// it with no dependency to install; pytest discovers and runs it unchanged.
fn example_test(p Project) string {
	mut out := '"""Tests for the scaffolded extension."""\n\n'
	out += 'import unittest\n\n'
	out += 'import ${p.module} as m\n\n\n'
	out += 'class TestScaffold(unittest.TestCase):\n'
	out += '\tdef test_greet(self) -> None:\n'
	out += '\t\tself.assertEqual(m.greet("world"), "Hello, world!")\n\n'
	out += '\tdef test_add(self) -> None:\n'
	out += '\t\tself.assertEqual(m.add(2, 3), 5)\n\n'
	out += '\tdef test_counter(self) -> None:\n'
	out += '\t\tcounter = m.Counter()\n'
	out += '\t\tself.assertEqual(counter.increment(), 1)\n\n'
	out += '\tdef test_parse_int_rejects(self) -> None:\n'
	out += '\t\twith self.assertRaises(ValueError):\n'
	out += '\t\t\tm.parse_int("not a number")\n\n\n'
	out += 'if __name__ == "__main__":\n'
	out += '\tunittest.main()\n'
	return out
}

// readme is the README a new project starts with.
fn readme(p Project) string {
	// This file is the project's PyPI page as well as its repository front page, so it
	// opens with what a user needs, installing and using the package, and leaves the
	// build instructions for the end.
	mut out := '# ${p.name}\n\n'
	out += '${p.description}\n\n'
	out += '## Installation\n\n'
	out += '```console\n'
	out += '$ pip install ${p.name}\n'
	out += '```\n\n'
	out += '## Usage\n\n'
	out += '```python\n'
	out += '>>> import ${p.module} as m\n'
	out += ">>> m.greet('world')\n"
	out += "'Hello, world!'\n"
	out += '>>> m.add(2, 3)\n'
	out += '5\n'
	out += '>>> c = m.Counter()\n'
	out += '>>> c.increment()\n'
	out += '1\n'
	out += '```\n\n'
	out += '## Development\n\n'
	out += 'Written in [V](https://vlang.io) and built with [vcraft](https://github.com/rroblf01/vcraft).\n\n'
	out += '```console\n'
	out += '$ python -m venv .venv && source .venv/bin/activate\n'
	out += '$ vcraft develop          # build and install into the active virtualenv\n'
	out += '$ python main.py          # run the example, which imports the extension\n'
	out += '$ python -m unittest      # run the tests under tests/\n'
	out += '$ vcraft build --release  # write a wheel into dist/\n'
	out += '```\n'
	return out
}

// write_scaffold writes the files, creating directories as needed.
//
// Existing files are never overwritten. A `vcraft new` in a directory that already has
// a `v.mod` should say so rather than replace a working project's manifest.
pub fn write_scaffold(root string, p Project) ![]string {
	mut written := []string{}
	for f in scaffold(p) {
		target := root.trim_right('/') + '/' + f.path
		dir := target.all_before_last('/')
		if dir != '' && !os.exists(dir) {
			os.mkdir_all(dir) or {
				return error('cannot create ${dir}')
			}
		}
		if os.exists(target) {
			return error('${target} already exists; nothing was written')
		}
		os.write_file(target, f.content) or {
			return error('cannot write ${target}')
		}
		written << target
	}
	return written
}
