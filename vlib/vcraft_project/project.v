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
//	requires-python = ">=3.12"
//
//	minimum-version = "3.12"
//
//	[[classifiers]]
//	text = "Programming Language :: V"

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
}

// default_project returns what `vcraft new` writes.
pub fn default_project(name string) Project {
	return Project{
		name:            name
		version:         '0.1.0'
		module:          '${name}_native'
		description:     'A Python extension written in V.'
		license:         'MIT'
		requires_python: '>=3.12'
		minimum_version: '3.12'
		classifiers: ['Programming Language :: V', 'Programming Language :: Python :: 3']
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
	// `[[classifier]]` entries are the same thing written the long way, and a project
	// that uses the long form should not have to also use the short one.
	for t in table.table_list_of('classifier') {
		label := t.string_of('text', '')
		if label != '' {
			classifiers << label
		}
	}
	p.classifiers = classifiers
	p.dependencies = pkg.string_list_of('dependencies')
	p.minimum_version = table.string_of('minimum-version', p.minimum_version)
	p.abi3 = table.string_of('abi3', '')
	p.free_threading = table.bool_of('free-threading', false)
	p.strip = table.bool_of('strip', false)
	return p
}

// render writes a project's `vcraft.toml`.
//
// Round-trips through the same parser `load` uses, so a file this writes is one `load`
// can read. Quoted throughout rather than relying on bare words, because a description
// with a comma in it is not a bare word and a classifier with a `::` looks like one.
pub fn (p Project) render() string {
	mut out := '[package]\n'
	out += 'name = ${quote(p.name)}\n'
	out += 'version = ${quote(p.version)}\n'
	out += 'module = ${quote(p.module)}\n'
	out += 'description = ${quote(p.description)}\n'
	out += 'license = ${quote(p.license)}\n'
	out += 'requires-python = ${quote(p.requires_python)}\n'
	if p.dependencies.len > 0 {
		out += 'dependencies = ['
		for i, d in p.dependencies {
			if i > 0 {
				out += ', '
			}
			out += quote(d)
		}
		out += ']\n'
	}
	out += '\n'
	out += 'minimum-version = ${quote(p.minimum_version)}\n'
	if p.abi3.len > 0 {
		out += 'abi3 = ${quote(p.abi3)}\n'
	}
	if p.free_threading {
		out += 'free-threading = true\n'
	}
	if p.strip {
		out += 'strip = true\n'
	}
	out += '\n'
	for c in p.classifiers {
		out += '[[classifier]]\n'
		out += 'text = ${quote(c)}\n\n'
	}
	return out
}
