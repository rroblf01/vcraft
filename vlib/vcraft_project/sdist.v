module vcraft_project

import os

import vcraft_wheel

// A source distribution.
//
// An sdist is a tar.gz holding the project's sources and a `PKG-INFO`, which is the
// same metadata as a wheel's `METADATA` with two extra fields. It is what a build
// frontend fetches when it has to build from source, so `pip install <sdist>` is the
// check that matters: it is the one path that exercises the whole toolchain through
// PEP 517 rather than through a wheel that already exists.

// sdist_file is one file the archive holds.
struct SdistFile {
mut:
	path    string
	content []u8
}

// sdist builds the archive and returns its bytes.
pub fn sdist(p Project, root string) ![]u8 {
	mut tar := vcraft_wheel.new_tar()
	tar.add_directory(base_name(p))
	// `pyproject.toml` and the backend have to be in the sdist as well as the sources.
	// An sdist that omits them is a source tree with no way to build: pip untars it,
	// reads `pyproject.toml`, and finds nothing, so the install fails before any of the
	// V sources are looked at.
	for name in ['v.mod', 'vcraft.toml', 'pyproject.toml', backend_py(), 'README.md',
		'src/' + p.module + '.v'] {
		path := root.trim_right('/') + '/' + name
		if !os.exists(path) {
			continue
		}
		data := os.read_file(path) or { return error('cannot read ${path}') }
		tar.add_file('${base_name(p)}/' + name, data.bytes()) or { return err }
	}
	tar.add_file('${base_name(p)}/PKG-INFO', pkg_info(p).bytes()) or { return err }
	// Project Python travels as source: the wheel builder compiles it when `embed-pyc`
	// is set, so an sdist that omits it builds a wheel without the helpers. Type stubs
	// travel as well, because they are the interface a type checker reads.
	python_root := root.trim_right('/') + '/python'
	if os.exists(python_root) {
		for name in python_sources(python_root) {
			path := python_root + '/' + name
			data := os.read_file(path) or { return error('cannot read ${path}') }
			tar.add_file('${base_name(p)}/python/' + name, data.bytes()) or { return err }
		}
	}
	// Gzipped, because that is what the `.tar.gz` in the file name promises and what
	// pip's sdist handling expects. A stored tar under that name is rejected by the
	// first read.
	return vcraft_wheel.gzip(tar.bytes())
}

// base_name is the directory the archive unpacks into, which is `name-version`.
fn base_name(p Project) string {
	return vcraft_wheel.escape(p.name) + '-' + vcraft_wheel.normalize_version(p.version)
}

// pkg_info renders the sdist's `PKG-INFO`.
//
// The wheel's `METADATA` plus `Metadata-Version` and nothing else is not enough: an
// sdist's `PKG-INFO` is read by the build frontend before the package's own metadata
// exists, so a field that only a wheel can supply has to be absent rather than wrong.
fn pkg_info(p Project) string {
	mut out := vcraft_wheel.render_metadata(vcraft_wheel.MetaData{
		name:            p.name
		version:         p.version
		summary:         p.description
		description:     p.description
		license:         p.license
		requires_python: p.requires_python
		classifiers:     p.classifiers
	})
	return out
}

// write_sdist builds the archive and writes it into `out_dir`.
pub fn write_sdist(p Project, root string, out_dir string) !string {
	bytes := sdist(p, root)!
	name := '${vcraft_wheel.escape(p.name)}-${vcraft_wheel.normalize_version(p.version)}.tar.gz'
	if !os.exists(out_dir) {
		os.mkdir_all(out_dir) or { return error('cannot create ${out_dir}') }
	}
	path := out_dir.trim_right('/') + '/' + name
	os.write_file(path, bytes.bytestr()) or { return error('cannot write ${path}') }
	return path
}
