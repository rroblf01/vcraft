module vcraft_project

import os

// What a project says about itself.
//
// A `v.mod` names the V module and nothing else, which is the minimum V needs and not
// enough to build a wheel: a wheel needs a distribution name, a version, and an
// interpreter, and none of those belong to the V module. They live in `vcraft.toml`,
// a file of this project instead, so that adding a key never means teaching V's
// manifest a new field.
//
//	[package]
//	name = "hello"
//	version = "0.1.0"
//	module = "hello_native"
//	description = "Greets people from V."
//	license = "MIT"
//	requires-python = ">=3.11"
//	classifiers = ["Programming Language :: Other"]
//
//	[build]
//	minimum-version = "3.11"

// Project is a parsed `vcraft.toml`.
pub struct Project {
pub mut:
	// name is the distribution name, which becomes the wheel's file name and the
	// `.dist-info` directory.
	name string
	// version is the distribution version.
	version string
	// module is the importable name of the extension, which is also the V module name.
	module string
	// description is the one-line summary in METADATA.
	description string
	// license is the licence identifier or name.
	license string
	// requires_python is the `Requires-Python` field.
	requires_python string
	// readme is the file, relative to the project root, whose text becomes the long
	// description PyPI shows on the project page. Missing is not an error: the
	// one-line description is used instead.
	readme string
	// keywords go into METADATA as `Keywords`.
	keywords []string
	// urls are `Project-URL` entries, `Label, https://...`, from the `[urls]` table.
	urls []string
	// minimum_version is the oldest CPython this builds against. It picks the ABI
	// tag, and it is separate from `requires_python` because one says what the code
	// needs to run and the other says what it was compiled for.
	minimum_version string
	// classifiers go into METADATA verbatim.
	classifiers []string
	// dependencies are `Requires-Dist` entries.
	dependencies []string
	// abi3, when set, builds against the stable ABI from that version on.
	abi3 string
	// free_threading builds a free-threaded extension.
	free_threading bool
	// strip removes symbols from the extension.
	strip bool
	// gc_free_space_divisor tunes Boehm's heap growth: the collector runs once the
	// live data exceeds the heap divided by this. The default is 2, which keeps
	// roughly half a MiB less resident after large workloads than V's own 1, for
	// a few percent of allocation-heavy throughput (measured on macOS arm64,
	// CPython 3.13; see benchmark/README.md). Set 1 to favour speed instead.
	gc_free_space_divisor int
	// embed_pyc ships the project's Python files compiled rather than as source.
	//
	// A sourceless distribution: the wheel carries `foo.pyc` where a source install would
	// carry `foo.py`, and CPython imports that directly. It is smaller, and it keeps the
	// wheel's contents from being the one thing in it a reader can read.
	embed_pyc bool
}

// default_project returns what `vcraft new` writes.
pub fn default_project(name string) Project {
	return Project{
		name:            name
		version:         '0.1.0'
		module:          '${name}_native'
		description:     'A Python extension written in V.'
		license:         'MIT'
		requires_python: '>=3.11'
		readme:          'README.md'
		minimum_version: '3.11'
		gc_free_space_divisor: 2
		// Trove classifiers PyPI accepts. There is no `Programming Language :: V`, and
		// PyPI refuses the whole upload over one unknown classifier, so V projects say
		// `Other`, the classifier PyPI keeps for languages it does not list.
		classifiers: ['Programming Language :: Other', 'Programming Language :: Python :: 3',
			'Programming Language :: Python :: Implementation :: CPython']
	}
}

// load reads a project's `vcraft.toml`.
//
// The defaults are filled in first and then overridden, so a project that says nothing
// about a field still builds. That matters for `vcraft develop`: refusing to run
// because a description is missing would be a worse experience than a wheel with an
// empty Summary.
pub fn load(root string) !Project {
	path := root.trim_right('/') + '/vcraft.toml'
	text := os.read_file(path) or {
		return error('no ${path}; run `vcraft new` to create a project')
	}
	table := parse(text)!
	pkg := table.subtable('package')
	mut p := default_project(pkg.string_of('name', 'unnamed'))
	p.name = pkg.string_of('name', p.name)
	p.version = pkg.string_of('version', p.version)
	p.module = pkg.string_of('module', p.module)
	p.description = pkg.string_of('description', p.description)
	p.license = pkg.string_of('license', p.license)
	p.requires_python = pkg.string_of('requires-python', p.requires_python)
	mut classifiers := pkg.string_list_of('classifiers')
	// `[[classifier]]` entries are the same thing written the long way. They were what
	// `vcraft new` wrote before 1.0, so they are still read, with a warning.
	legacy := table.table_list_of('classifier')
	if legacy.len > 0 {
		eprintln('warning: vcraft.toml: write classifiers as `classifiers = [...]` in [package]; `[[classifier]]` goes in vcraft 2.0')
	}
	for t in legacy {
		label := t.string_of('text', '')
		if label != '' {
			classifiers << label
		}
	}
	p.classifiers = classifiers
	p.dependencies = pkg.string_list_of('dependencies')
	p.readme = pkg.string_of('readme', p.readme)
	p.keywords = pkg.string_list_of('keywords')
	// `[urls]` maps a label to an address, as in PEP 621's `[project.urls]`, and each
	// becomes one `Project-URL`. Read in file order so the page lists them as written.
	for e in table.subtable('urls').entries {
		if e.value.kind == .string && e.value.text.len > 0 {
			p.urls << '${e.name}, ${e.value.text}'
		}
	}
	// Build settings live in `[build]`. Before 1.0 they were root-level keys, which had
	// to precede every table: written after `[package]`, TOML makes them keys of that
	// table, and they were silently ignored. Root-level keys are still read throughout
	// 1.x, with a warning; the same keys under `[package]` get one too, since that is
	// where the old layout's mistake put them.
	build := table.subtable('build')
	mut settings := Table{}
	for key in build_keys {
		if v := build.get(key) {
			settings.entries << Entry{
				name:  key
				value: v
			}
		} else if v := table.get(key) {
			settings.entries << Entry{
				name:  key
				value: v
			}
			eprintln('warning: vcraft.toml: move `${key}` into a [build] table; top-level build keys go in vcraft 2.0')
		}
		if _ := pkg.get(key) {
			eprintln('warning: vcraft.toml: `${key}` under [package] is ignored; it belongs in [build]')
		}
	}
	p.minimum_version = settings.string_of('minimum-version', p.minimum_version)
	p.abi3 = settings.string_of('abi3', '')
	p.free_threading = settings.bool_of('free-threading', false)
	p.strip = settings.bool_of('strip', false)
	p.embed_pyc = settings.bool_of('embed-pyc', false)
	p.gc_free_space_divisor = settings.int_of('gc-free-space-divisor', 2)
	if p.gc_free_space_divisor < 1 {
		return error('gc-free-space-divisor is ${p.gc_free_space_divisor}; it must be 1 or more (2 is the default, 1 favours speed over memory)')
	}
	return p
}

// render writes a project's `vcraft.toml`.
//
// Round-trips through the same parser `load` uses, so a file this writes is one `load`
// can read. Quoted throughout rather than relying on bare words, because a description
// with a comma in it is not a bare word and a classifier with a `::` looks like one.
// build_keys are the settings read from `[build]`.
pub const build_keys = ['minimum-version', 'abi3', 'free-threading', 'strip', 'embed-pyc',
	'gc-free-space-divisor']

pub fn (p Project) render() string {
	mut out := '[package]\n'
	out += 'name = ${quote(p.name)}\n'
	out += 'version = ${quote(p.version)}\n'
	out += 'module = ${quote(p.module)}\n'
	out += 'description = ${quote(p.description)}\n'
	out += 'license = ${quote(p.license)}\n'
	out += 'requires-python = ${quote(p.requires_python)}\n'
	if p.readme.len > 0 {
		out += 'readme = ${quote(p.readme)}\n'
	}
	if p.keywords.len > 0 {
		out += 'keywords = [' + p.keywords.map(quote(it)).join(', ') + ']\n'
	}
	if p.classifiers.len > 0 {
		out += 'classifiers = [' + p.classifiers.map(quote(it)).join(', ') + ']\n'
	}
	if p.dependencies.len > 0 {
		out += 'dependencies = [' + p.dependencies.map(quote(it)).join(', ') + ']\n'
	}
	out += '\n[build]\n'
	out += 'minimum-version = ${quote(p.minimum_version)}\n'
	if p.abi3.len > 0 {
		out += 'abi3 = ${quote(p.abi3)}\n'
	}
	if p.free_threading {
		out += 'free-threading = true\n'
	}
	if p.embed_pyc {
		out += 'embed-pyc = true\n'
	}
	if p.strip {
		out += 'strip = true\n'
	}
	if p.gc_free_space_divisor != 2 {
		out += 'gc-free-space-divisor = ${p.gc_free_space_divisor}\n'
	}
	if p.urls.len > 0 {
		out += '\n[urls]\n'
		for u in p.urls {
			label := u.all_before(', ')
			out += '${label} = ${quote(u.all_after(', '))}\n'
		}
	}
	return out
}

// long_description returns the text PyPI shows on the project page and its MIME type.
//
// The `readme` file when it exists, typed by its extension, so a Markdown README renders
// as Markdown rather than as its source. Otherwise the one-line description as plain
// text, which is what a project without a README had before.
pub fn (p Project) long_description(root string) (string, string) {
	if p.readme.len > 0 {
		path := root.trim_right('/') + '/' + p.readme
		if text := os.read_file(path) {
			lower := p.readme.to_lower()
			kind := if lower.ends_with('.md') || lower.ends_with('.markdown') {
				'text/markdown'
			} else if lower.ends_with('.rst') {
				'text/x-rst'
			} else {
				'text/plain'
			}
			return text, kind
		}
	}
	return p.description, ''
}
