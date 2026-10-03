module vcraft_project

import os

import vcraft_codegen
import vcraft_wheel

// Running the compiler and packaging the result.
//
// This is where a project stops being source and becomes a wheel. Nothing here knows
// about the annotation vocabulary or about CPython: the code generator has already
// written the glue, and all that is left is to compile it, find the `.so`, and wrap it.

// BuildOptions is what `vcraft build` was asked for.
pub struct BuildOptions {
pub mut:
	// root is the project directory.
	root string
	// out_dir is where the wheel goes.
	out_dir string
	// release compiles with `-prod`.
	release bool
	// interpreter is the Python to build against, or empty for the running one.
	interpreter string
	// platform overrides the platform tag, for cross builds.
	platform string
	// jobs is the parallelism, or 0 for the wrapper's default.
	jobs int
	// v_path is the directory holding vcraft's V modules, passed to `v -path`.
	v_path string
	// v is the V compiler binary.
	v string
}

// BuildResult is what a build produced.
pub struct BuildResult {
pub mut:
	// wheel is the bytes written.
	wheel []u8
	// filename is the wheel's name, without a directory.
	filename string
	// path is where it was written.
	path string
	// extension is the compiled extension's name.
	extension string
	// tag is the compatibility tag the wheel carries.
	tag string
	// python is the interpreter version the build targeted.
	python string
}

// interpreter_version returns `major.minor` for a Python executable.
pub fn interpreter_version(python string) string {
	// Single quotes inside the `-c` script, because the whole script is wrapped in
	// double quotes for the shell. A nested `"` ends the shell argument early and the
	// interpreter sees a truncated program, which it reports as an error rather than as
	// the quoting mistake it is.
	script := "import sys;print(str(sys.version_info[0])+'.'+str(sys.version_info[1]))"
	out := os.execute(python + ' -c "' + script + '"')
	if out.exit_code != 0 {
		return ''
	}
	return out.output.trim_space()
}

// extension_suffix returns the suffix CPython expects for an extension, including the
// ABI tag. Read from the interpreter rather than hard-coded, because `cpython-314` on
// one build and `cpython-313` on another is the difference between a wheel that
// installs and one that is ignored.
pub fn extension_suffix(python string) string {
	script := "import sysconfig;print(sysconfig.get_config_var('EXT_SUFFIX') or '.so')"
	out := os.execute(python + ' -c "' + script + '"')
	if out.exit_code != 0 {
		return '.so'
	}
	return out.output.trim_space()
}

// include_dir returns the directory holding Python.h.
pub fn include_dir(python string) string {
	script := "import sysconfig;print(sysconfig.get_paths()['include'])"
	out := os.execute(python + ' -c "' + script + '"')
	if out.exit_code != 0 {
		return ''
	}
	return out.output.trim_space()
}

// platform_tag returns the platform tag for the running interpreter.
//
// It comes from `sysconfig.get_platform()`, which is what the interpreter itself calls
// its platform. Deriving it from `os.getenv('OS')` and the machine's architecture is
// how a wheel ends up tagged `linux_x86_64` instead of `manylinux_2_17_x86_64`, and pip
// then refuses it with "not a supported wheel on this platform".
pub fn platform_tag(python string) string {
	script := "import sysconfig;print(sysconfig.get_platform().replace('-', '_').replace('.', '_'))"
	out := os.execute(python + ' -c "' + script + '"')
	if out.exit_code != 0 {
		return 'linux_x86_64'
	}
	return out.output.trim_space()
}

// abi_tag returns the ABI tag for an interpreter version.
//
// A free-threaded build is `cp313t`, a GIL build `cp313`. Getting this wrong produces a
// wheel that pip installs and then refuses to import, because the interpreter checks
// the tag against itself before loading anything.
pub fn abi_tag(version string, free_threading bool) string {
	clean := version.replace('.', '')
	if free_threading {
		return 'cp${clean}t'
	}
	return 'cp${clean}'
}

// build compiles the project and writes a wheel.
pub fn build(p Project, opt BuildOptions) !BuildResult {
	python := if opt.interpreter.len > 0 { opt.interpreter } else { 'python3' }
	version := interpreter_version(python)
	if version.len == 0 {
		return error('cannot run ${python}; is it on PATH?')
	}
	suffix := extension_suffix(python)
	include := include_dir(python)
	if include.len == 0 {
		return error('cannot find Python.h for ${python}')
	}
	tag_platform := if opt.platform.len > 0 { opt.platform } else {
		platform_tag(python)
	}
	// `version` arrives as `3.14` and the tag wants `314`: the interpreter tag has no
	// separator between major and minor. A tag of `cp3.14-cp314-...` is not a tag pip
	// knows, and it rejects the wheel with "no matching distribution".
	numeric := version.replace('.', '')
	tag := 'cp${numeric}-${abi_tag(version, p.free_threading)}-${tag_platform}'

	mut compiled := opt.out_dir.trim_right('/') + '/build'
	if !os.exists(compiled) {
		os.mkdir_all(compiled) or { return error('cannot create ${compiled}') }
	}
	output := compiled + '/' + p.module + suffix

	// The glue is regenerated on every build, so a build never depends on a checked-in
	// copy that a source change has made stale.
	// `package` is what `PyInit_` is named, and for a single extension module that is
	// the module name, not the distribution name. Passing the distribution produces a
	// shared object that exports `PyInit_<distribution>`, which the interpreter loads
	// happily and then reports as "does not define module export function" the moment
	// anything imports it.
	generate_result := vcraft_codegen.generate(vcraft_codegen.Options{
		project_root: opt.root
		module:       p.module
		package:      p.module
	})
	for d in generate_result.diagnostics {
		eprintln(d.error())
	}
	if generate_result.has_errors() {
		return error('the code generator reported errors')
	}
	generate_result.write() or { return error('cannot write the generated glue') }

	// Every argument is quoted individually. `-path` takes `dir|@vlib`, and an
	// unquoted `@` is a shell word the shell tries to run: the error is "not found"
	// pointing at a directory that does exist.
	mut args := [
		shell_quote(opt.v),
		'-enable-globals',
		'-shared',
		'-o',
		shell_quote(output),
		'-path',
		shell_quote('${opt.v_path}|@vlib'),
		'-cflags',
		shell_quote('-I${include}'),
	]
	if opt.release {
		args << '-prod'
	}
	args << shell_quote(opt.root.trim_right('/'))
	result := os.execute(args.join(' '))
	if result.exit_code != 0 {
		return error('the V compiler failed:\n${result.output}')
	}
	binary := os.read_file(output) or { return error('cannot read ${output}') }

	mut wheel := vcraft_wheel.build(vcraft_wheel.BuildInput{
		distribution:    p.name
		version:         p.version
		module:          p.module
		extension:       p.module + suffix
		binary:          binary.bytes()
		tags:            [tag]
		summary:         p.description
		description:     p.description
		license:         p.license
		requires_python: p.requires_python
		classifiers:     p.classifiers
		requires_dist:   p.dependencies
	})!
	filename := vcraft_wheel.wheel_filename(p.name, p.version, [tag])
	if !os.exists(opt.out_dir) {
		os.mkdir_all(opt.out_dir) or { return error('cannot create ${opt.out_dir}') }
	}
	path := opt.out_dir.trim_right('/') + '/' + filename
	os.write_file(path, wheel.bytestr()) or { return error('cannot write ${path}') }

	return BuildResult{
		wheel:     wheel
		filename:  filename
		path:      path
		extension: p.module + suffix
		tag:       tag
		python:    version
	}
}

// shell_quote renders a shell argument safely.
//
// Single quotes, so that a path with a space, a `|` or a `$` in it survives. The build
// invokes a compiler through the shell rather than through `execve`, because V's `-cflags`
// takes several values at once and passing them as a list is not supported.
pub fn shell_quote(text string) string {
	return "'" + text.replace("'", "'\\''") + "'"
}
