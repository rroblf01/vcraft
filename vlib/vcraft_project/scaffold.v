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
	// The Python package that re-exports the native module, so `import <name>` is the
	// public name and the native module stays an implementation detail. The build
	// already packages anything under `python/`, so the scaffold only has to write the
	// two files. Skipped when the distribution and the module share a name, where the
	// package would shadow the extension it imports.
	if python_package(p) != p.module {
		files << ScaffoldFile{
			path:    'python/${python_package(p)}/__init__.py'
			content: python_init(p)
		}
		files << ScaffoldFile{
			path:    'python/${python_package(p)}/py.typed'
			content: ''
		}
	}
	files << ScaffoldFile{
		path:    'main.py'
		content: demo_main(p)
	}
	files << ScaffoldFile{
		path:    'tests/test_${python_package(p)}.py'
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
		// Only the generated stub is ignored, not every `.pyi`: a project may keep a
		// hand-written top-level stub under `python/`.
		content: '/build/\n/dist/\n/.vcraft/\n/.venv/\n/src/_vcraft_generated.v\npython/${p.module}.pyi\n*.so\n__pycache__/\n*.pyc\n.pytest_cache/\n'
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

// python_package is the importable package name for a project.
//
// A distribution name is not a Python identifier when it carries a hyphen or a dot
// (`my-ext` is a valid PyPI name and not a valid module), so those become underscores.
fn python_package(p Project) string {
	return module_name(p.name)
}

// import_name is the name a user imports: the re-export package when the scaffold
// writes one, the native module otherwise. `vcraft new` prints it.
pub fn import_name(p Project) string {
	pkg := python_package(p)
	if pkg != p.module {
		return pkg
	}
	return p.module
}

// python_init is the package `__init__.py`, which re-exports the native module.
//
// `import *` brings the exported functions and classes into the package namespace, so
// `import <name>` exposes the same API as the extension without a second list to keep
// in step with the V sources.
fn python_init(p Project) string {
	mut out := '"""${p.name}: ${p.description}\n\n'
	out += 'The native code lives in the extension module `${p.module}`; this package\n'
	out += 're-exports it so that `import ${python_package(p)}` is the only name to remember.\n'
	out += '"""\n\n'
	out += 'from ${p.module} import *  # noqa: F401,F403\n'
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
	out += 'import ${import_name(p)} as m\n\n\n'
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
	out += 'import ${import_name(p)} as m\n\n\n'
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
	out += '>>> import ${import_name(p)} as m\n'
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
		target := os.join_path(root, f.path)
		dir := os.dir(target)
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

// InitPlan is what `vcraft init` found in an existing Python project and will write.
pub struct InitPlan {
pub mut:
	project Project
	// package is the existing Python package the extension is added to, '' when none
	// was found.
	package string
	// files are the new files; none of them exists yet.
	files []ScaffoldFile
	// pyproject is the merged `pyproject.toml`, and replaced_backend the backend its old
	// `[build-system]` named ('' when it had none).
	pyproject        string
	replaced_backend string
	// gitignore is the `.gitignore` with vcraft's lines appended.
	gitignore string
}

// plan_init looks at an existing Python project and plans what `vcraft init` adds.
//
// The project's name comes from `[project].name` in `pyproject.toml`, else from
// `name_override`, else from the directory. Its Python stays where it is: a `python/`
// tree is vcraft's default, a `src/<package>` or a flat `<package>/` layout is recorded
// as `python-source` and `python-packages` in `[build]`, so the wheel ships that package
// beside the extension and nothing else from the directory. The V source goes in `src/`
// either way; V compiles only the `.v` files there.
pub fn plan_init(root string, name_override string, module_override string) !InitPlan {
	if os.exists(os.join_path(root, 'vcraft.toml')) {
		return error('${os.join_path(root, 'vcraft.toml')} already exists; this is already a vcraft project')
	}
	pyproject_path := os.join_path(root, 'pyproject.toml')
	existing := os.read_file(pyproject_path) or { '' }
	mut name := name_override
	mut backend := ''
	if existing.len > 0 {
		if name.len == 0 && existing.contains('[project]') {
			table := parse(pyproject_section(existing)) or { Table{} }
			name = table.subtable('project').string_of('name', '')
		}
		backend = pyproject_backend(existing)
	}
	if name.len == 0 {
		name = os.file_name(os.real_path(root))
	}
	mut p := default_project(name)
	if module_override.len > 0 {
		p.module = module_override
	}
	if !is_valid_module(p.module) || p.module.ends_with('_test') {
		return error('`${p.module}` cannot be the native module name; pass --module with letters, digits and underscores, not ending in `_test`')
	}
	pkg := module_name(name)
	mut found := ''
	if os.is_dir(os.join_path(root, 'python')) {
		p.python_source = 'python'
	} else if os.exists(os.join_path(root, 'src', pkg, '__init__.py')) {
		p.python_source = 'src'
		found = pkg
	} else if os.exists(os.join_path(root, pkg, '__init__.py')) {
		p.python_source = '.'
		found = pkg
	} else if candidate := package_under(os.join_path(root, 'src')) {
		p.python_source = 'src'
		found = candidate
	} else if candidate := package_under(root) {
		p.python_source = '.'
		found = candidate
	}
	if found.len > 0 {
		p.python_packages = [found]
		if found == p.module {
			return error('the Python package and the native module are both `${found}`; pass --module to name the extension')
		}
	}
	if !os.exists(os.join_path(root, 'README.md')) {
		p.readme = ''
	}
	// The metadata `[project]` already states is copied, so the two files agree.
	apply_pyproject(mut p, root, Table{})
	mut plan := InitPlan{
		project:          p
		package:          found
		replaced_backend: backend
	}
	plan.files << ScaffoldFile{
		path:    'vcraft.toml'
		content: p.render()
	}
	plan.files << ScaffoldFile{
		path:    'v.mod'
		content: 'Module {\n\tname: "${p.module}"\n\tbase_url: "src"\n\trequires: ["vcraft"]\n}\n'
	}
	plan.files << ScaffoldFile{
		path:    'src/${p.module}.v'
		content: example_source(p)
	}
	plan.files << ScaffoldFile{
		path:    backend_py()
		content: backend_source()
	}
	for f in plan.files {
		if os.exists(os.join_path(root, f.path)) {
			return error('${os.join_path(root, f.path)} already exists; nothing was written')
		}
	}
	plan.pyproject = if existing.len > 0 { merge_pyproject(existing) } else { pyproject_toml() }
	mut ignore := os.read_file(os.join_path(root, '.gitignore')) or { '' }
	mut lines := ignore.split_into_lines()
	for line in ['/build/', '/dist/', '/.vcraft/', '/src/_vcraft_generated.v',
		(if p.python_source == '.' { '/' } else { '/' + p.python_source + '/' }) + p.module + '.pyi',
		'*.so'] {
		if line !in lines {
			if ignore.len > 0 && !ignore.ends_with('\n') {
				ignore += '\n'
			}
			ignore += line + '\n'
			lines << line
		}
	}
	plan.gitignore = ignore
	return plan
}

// package_under is the one Python package directly under `dir`, skipping the
// directories that hold tests, docs, build output or an environment.
fn package_under(dir string) ?string {
	mut entries := os.ls(dir) or { return none }
	entries.sort()
	for entry in entries {
		if entry.starts_with('.') || entry.starts_with('_')
			|| entry in ['tests', 'test', 'docs', 'build', 'dist', 'venv', 'examples', 'benchmarks'] {
			continue
		}
		if os.exists(os.join_path(dir, entry, '__init__.py')) {
			return entry
		}
	}
	return none
}

// pyproject_backend is the `build-backend` an existing `pyproject.toml` names.
fn pyproject_backend(text string) string {
	mut inside := false
	for line in text.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('[') {
			inside = t == '[build-system]'
			continue
		}
		if inside && t.starts_with('build-backend') {
			return t.all_after('=').trim_space().trim('"\'')
		}
	}
	return ''
}

// write_init writes a plan made by `plan_init` and returns the paths it touched.
pub fn write_init(root string, plan InitPlan) ![]string {
	mut written := []string{}
	for f in plan.files {
		target := os.join_path(root, f.path)
		dir := os.dir(target)
		if dir != '' && !os.exists(dir) {
			os.mkdir_all(dir) or { return error('cannot create ${dir}') }
		}
		os.write_file(target, f.content) or { return error('cannot write ${target}') }
		written << target
	}
	for name, content in {
		'pyproject.toml': plan.pyproject
		'.gitignore':     plan.gitignore
	} {
		target := os.join_path(root, name)
		os.write_file(target, content) or { return error('cannot write ${target}') }
		written << target
	}
	return written
}

// devcontainer_json is `.devcontainer/devcontainer.json`, written by `vcraft new
// --devcontainer` and `vcraft init --devcontainer`: opening the repository in GitHub
// Codespaces or a VS Code dev container gives a ready environment with no local install.
//
// The image is the Dev Containers Python one. On creation a virtualenv is made in the
// workspace, vcraft is installed into it with the V compiler it pins (a prebuilt download
// where one is published), and the project is built and installed editable, so the first
// thing the person sees is a working `import`. The virtualenv is put first on `PATH` and
// named in `VIRTUAL_ENV` for every terminal, which is what `vcraft develop` looks for.
pub fn devcontainer_json(p Project) string {
	return '{
  "name": "${p.name} (vcraft)",
  "image": "mcr.microsoft.com/devcontainers/python:3.13",
  "remoteEnv": {
    "VIRTUAL_ENV": "\${containerWorkspaceFolder}/.venv",
    "PATH": "\${containerWorkspaceFolder}/.venv/bin:\${containerEnv:PATH}"
  },
  "postCreateCommand": "python -m venv .venv && .venv/bin/pip install -q vcraft && .venv/bin/vcraft toolchain install && VIRTUAL_ENV=\$PWD/.venv .venv/bin/vcraft develop",
  "customizations": {
    "vscode": {
      "extensions": ["ms-python.python", "vlanguage.vscode-vlang"],
      "settings": {"python.defaultInterpreterPath": ".venv/bin/python"}
    }
  }
}
'
}

// write_devcontainer writes `.devcontainer/devcontainer.json` under `root`, refusing to
// replace one that exists.
pub fn write_devcontainer(root string, p Project) !string {
	dir := os.join_path(root, '.devcontainer')
	target := os.join_path(dir, 'devcontainer.json')
	if os.exists(target) {
		return error('${target} already exists; it was left as it is')
	}
	os.mkdir_all(dir) or { return error('cannot create ${dir}') }
	os.write_file(target, devcontainer_json(p)) or { return error('cannot write ${target}') }
	return target
}
