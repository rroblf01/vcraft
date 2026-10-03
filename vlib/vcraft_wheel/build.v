module vcraft_wheel

// Putting a wheel together.
//
// A wheel is a ZIP holding an extension module, the metadata files, and a RECORD of
// every entry's hash. This assembles those in the order the specification expects,
// which is not an arbitrary choice: `RECORD` has to hash the metadata files, so it is
// written last and names itself without a hash.

// BuildInput is everything needed to produce one wheel.
pub struct BuildInput {
pub mut:
	// distribution and version become the file name and the METADATA Name/Version.
	distribution string
	version      string
	// module is the extension's importable name.
	module string
	// extension is the file name of the compiled module inside the wheel.
	extension string
	// binary is the compiled module's bytes.
	binary []u8
	// tags are the compatibility tags, e.g. `cp314-cp314-manylinux_2_17_x86_64`.
	// Several are listed when one wheel serves more than one.
	tags []string
	summary         string
	description     string
	license         string
	requires_python string
	classifiers     []string
	requires_dist   []string
}

// build writes the wheel and returns its bytes.
//
// The file name comes from the tags, and `WHEEL` lists the same ones, so an installer
// comparing them finds them equal. Getting that wrong is the most common way a wheel
// is rejected: pip reads the name, decides the wheel is for this platform, installs
// it, and only then notices `WHEEL` disagrees.
pub fn build(input BuildInput) ![]u8 {
	// The `.dist-info` directory is named after the *distribution*, never after the
	// module. pip checks that the directory starts with the distribution name from the
	// file name and rejects the wheel outright if it does not, which is what happens
	// when an extension called `hello_native` is distributed as `vcraft-demo` and the
	// directory is built from the module.
	mut name := input.distribution
	mut archive := new_archive()

	// The extension goes at the root of the archive, not inside a directory named
	// after it.
	//
	// A directory with no `__init__.py` is a namespace package, and Python resolves one
	// without opening the files inside it: `hello_native/hello_native.so` installs
	// cleanly and then imports as an empty namespace package whose only member is a
	// submodule. The symptom is a module with no attributes and a `__file__` of None,
	// which looks like a build that produced an empty extension.
	archive.add_file(input.extension, input.binary)

	mut metadata := MetaData{
		name:            name
		version:         input.version
		summary:         input.summary
		description:     input.description
		license:         input.license
		requires_python: input.requires_python
		classifiers:     input.classifiers
		requires_dist:   input.requires_dist
	}
	archive.add_file('${escape(name)}-${normalize_version(input.version)}.dist-info/METADATA',
		render_metadata(metadata).bytes())
	archive.add_file('${escape(name)}-${normalize_version(input.version)}.dist-info/WHEEL',
		render_wheel(input.tags.join(','), 'vcraft ${input.version}').bytes())

	// RECORD lists every file with its hash, and lists itself without one, because a
	// file cannot contain its own hash.
	mut dist_info := '${escape(name)}-${normalize_version(input.version)}.dist-info'
	mut record_path := '${dist_info}/RECORD'
	mut record := []u8{}
	for e in archive.entries {
		record << record_row(e.name, e.data, true).bytes()
	}
	record << record_row(record_path, []u8{}, false).bytes()
	archive.add_stored(record_path, record)

	return archive.to_bytes()
}

// wheel_filename returns the file name for a wheel, from the first tag.
pub fn wheel_filename(distribution string, version string, tags []string) string {
	return '${escape(distribution)}-${normalize_version(version)}-${tags[0]}.whl'
}
