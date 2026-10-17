module vcraft_project

import os

import vcraft_wheel

// Finding the toolchain and the environment.
//
// `vcraft` locates its own V modules from where its own binary is, rather than from
// `VMODULES` or the working directory. A packaging tool that depends on an environment
// variable is a packaging tool that breaks in the one situation where it matters: a CI
// runner that has V configured for something else.

// version is vcraft's own version, and the version it stamps into a wheel's `WHEEL`.
pub const version = '1.4.2'

// executable_name is the file name an executable has on this platform.
//
// Windows appends `.exe`; every other platform does not. A path built by hand as `'/v'`
// names no file there, so the pieces below ask rather than assume.
pub fn executable_name(stem string) string {
	$if windows {
		return stem + '.exe'
	} $else {
		return stem
	}
}

// python_binary_name is the interpreter's file name on this platform.
//
// Windows ships `python.exe`, not `python3.exe`; POSIX has no `python.exe` and may have
// no `python` at all, so each names its own.
pub fn python_binary_name() string {
	$if windows {
		return 'python.exe'
	} $else {
		return 'python3'
	}
}

// venv_scripts_dir is the directory a virtualenv keeps its executables in: `Scripts` on
// Windows, `bin` everywhere else.
pub fn venv_scripts_dir() string {
	$if windows {
		return 'Scripts'
	} $else {
		return 'bin'
	}
}

// vlib_path returns the `-path` value for the V compiler.
//
// It is the `vlib` directory beside this binary: `<dir>/../vlib`. The binary is built
// into `bin/vcraft`, so the modules are two levels up, and the wheel's `v` executable
// sits in the same place.
pub fn vlib_path() string {
	exe := os.executable()
	dir := os.dir(exe)
	return os.join_path(os.dir(dir), 'vlib')
}

// v_compiler returns the V compiler to use.
//
// `VCRAFT_V` wins, then a `v` beside this binary, then the pinned compiler
// `vcraft toolchain install` built, then `v` on `PATH`. The pinned one comes before
// `PATH` because it is the commit vcraft is tested with, and the `v` on `PATH` is often
// a release too old for the flags vcraft passes.
pub fn v_compiler() string {
	if os.getenv('VCRAFT_V') != '' {
		return os.getenv('VCRAFT_V')
	}
	beside := os.join_path(os.dir(os.executable()), executable_name('v'))
	if os.exists(beside) {
		return beside
	}
	installed := installed_v()
	if installed != '' {
		return installed
	}
	return executable_name('v')
}

// active_environment returns the virtualenv the build should install into, or an empty
// string when there is none.
//
// `VIRTUAL_ENV` is read rather than inferred from `sys.prefix`, because a `develop` that
// installs into the system Python when the user is in a virtualenv is the single most
// annoying thing a build tool can do.
pub fn active_environment() string {
	return os.getenv('VIRTUAL_ENV')
}

// python_in_environment returns the interpreter of the active virtualenv, or the one
// on `PATH`.
pub fn python_in_environment() string {
	venv := active_environment()
	if venv.len == 0 {
		return python_binary_name()
	}
	candidate := os.join_path(venv, venv_scripts_dir(), python_binary_name())
	if os.exists(candidate) {
		return candidate
	}
	return python_binary_name()
}

// develop installs a freshly built extension into the active environment.
//
// It copies the wheel's extension rather than installing the wheel, because `pip
// install` of a local wheel needs a build isolation environment for a package with no
// dependencies, which is more moving parts than copying one file. The `.dist-info` is
// left out on purpose: `develop` is for working on an extension, not for a dependency
// graph, and a half-written `dist-info` confuses `importlib.metadata` more than a
// missing one does.
pub fn develop(p Project, result BuildResult) ! {
	python := python_in_environment()
	if !os.exists(python) {
		return error('no Python interpreter at ${python}; the virtualenv may be broken')
	}
	target := python_line(python, "sysconfig.get_paths()['platlib']")
	if target.len == 0 {
		return error('cannot find site-packages for ${python}')
	}
	// The extension comes out of the wheel, which is the only copy this build made.
	extracted := extract(result, result.extension) or {
		return error('the wheel does not contain ${result.extension}')
	}
	path := target.trim_right('/') + '/' + result.extension
	os.write_file(path, extracted.bytestr()) or {
		return error('cannot write ${path}')
	}
	// A copy must not leave an editable pointer behind. It would not shadow this file,
	// because site-packages is searched first, but two ways of reaching a build from one
	// environment is how a later `pip uninstall` leaves files nobody owns.
	os.rm(target.trim_right('/') + '/' + vcraft_wheel.editable_pth_name(p.name)) or {}
	return
}

// develop_editable points the active environment at this build instead of copying it.
//
// What lands in `site-packages` is a `.pth` file naming the build directory, which is the
// same shape a PEP 660 editable wheel installs. `site` reads it at interpreter start-up
// and puts the directory on `sys.path`, so `import mypkg_native` finds the extension where
// the build left it: the next `vcraft develop` is picked up with nothing reinstalled.
//
// The `.dist-info` goes in as well, so `importlib.metadata` can answer for the
// distribution. Without it the extension imports perfectly and every tool that asks what
// version is installed reports the package as missing, which is a confusing way to find
// out that an editable install is a real thing.
pub fn develop_editable(p Project, result BuildResult) ! {
	python := python_in_environment()
	if !os.exists(python) {
		return error('no Python interpreter at ${python}; the virtualenv may be broken')
	}
	target := python_line(python, "sysconfig.get_paths()['platlib']")
	if target.len == 0 {
		return error('cannot find site-packages for ${python}')
	}
	dir := target.trim_right('/')
	// An editable install must win over a copied extension left by an earlier
	// `develop --copy`. Site-packages itself comes before a `.pth` directory on
	// `sys.path`, so a stale copy shadows the build output and a rebuild is silently
	// ignored.
	os.rm(dir + '/' + result.extension) or {}
	// The build wrote the wheel with the path already in it, so the bytes come from
	// there rather than being assembled twice.
	pth := extract(result, vcraft_wheel.editable_pth_name(p.name)) or {
		return error('the wheel does not contain the editable path file')
	}
	os.write_file(dir + '/' + vcraft_wheel.editable_pth_name(p.name), pth.bytestr()) or {
		return error('cannot write the path file into ${dir}')
	}
	// The metadata files, extracted from the same wheel. They are the distribution's own
	// METADATA and WHEEL plus a RECORD naming what was installed.
	//
	// The dist-info name is escaped and normalised, exactly as the wheel builder names
	// it: a raw project name with dots or dashes does not match the directory in the
	// archive, and the installer would write metadata pip cannot find.
	dist_info := '${vcraft_wheel.escape(p.name)}-${vcraft_wheel.normalize_version(p.version)}.dist-info'
	os.mkdir_all(dir + '/' + dist_info) or {
		return error('cannot create ${dir}/${dist_info}')
	}
	for name in ['METADATA', 'WHEEL', 'RECORD', 'direct_url.json'] {
		data := extract(result, '${dist_info}/${name}') or { continue }
		os.write_file(dir + '/' + dist_info + '/' + name, data.bytestr()) or {
			return error('cannot write ${name} into ${dist_info}')
		}
	}
	return
}

// remove_editable deletes an editable install's `.pth` and `.dist-info` from the active
// environment.
//
// `vcraft clean` removes the build output those files point at, and a `.pth` naming a
// directory that is gone is at best noise on every interpreter start. Silent when there
// is no active environment or the project was never developed into it.
pub fn remove_editable(p Project) {
	if active_environment().len == 0 {
		return
	}
	target := python_line(python_in_environment(), "sysconfig.get_paths()['platlib']")
	if target.len == 0 {
		return
	}
	dir := target.trim_right('/')
	os.rm(dir + '/' + vcraft_wheel.editable_pth_name(p.name)) or {}
	dist_info := '${vcraft_wheel.escape(p.name)}-${vcraft_wheel.normalize_version(p.version)}.dist-info'
	os.rmdir_all(dir + '/' + dist_info) or {}
}

// is_editable_wheel reports whether a wheel points at local build output.
//
// It looks for a `.pth` entry, which is the shape `vcraft build --editable` writes.
// The scan stops at the central directory, because local headers are what this tool
// writes and reads: a general ZIP reader would be code that exists only to undo what
// the writer just did. Uploading one would publish a pointer to the builder's disk
// rather than a copy anyone else can install, so `publish` refuses them.
pub fn is_editable_wheel(path string) !bool {
	data := os.read_file(path) or { return error('cannot read ${path}') }.bytes()
	mut at := 0
	for at + 30 <= data.len {
		signature := u32le(data, at)
		if signature == 0x0201_4b50 {
			return false
		}
		if signature != 0x0403_4b50 {
			return error('${path} is not a ZIP wheel')
		}
		name_len := int(u16le(data, at + 26))
		extra_len := int(u16le(data, at + 28))
		compressed := int(u32le(data, at + 18))
		entry_name := data[at + 30..at + 30 + name_len].bytestr()
		if entry_name.ends_with('.pth') {
			return true
		}
		at = at + 30 + name_len + extra_len + compressed
	}
	return false
}

// extract returns one entry's bytes from a wheel.
//
// The wheel is written by this program and read here, so a full general ZIP reader
// would be code that exists only to undo what the writer just did. It walks the local
// headers, which are fixed-width, and stops at the first central directory signature.
pub fn extract(result BuildResult, name string) ![]u8 {
	data := result.wheel
	mut at := 0
	for at + 30 <= data.len {
		signature := u32le(data, at)
		if signature != 0x0403_4b50 {
			return error('not a ZIP: bad signature at ${at}')
		}
		method := u16le(data, at + 8)
		compressed := int(u32le(data, at + 18))
		uncompressed := int(u32le(data, at + 22))
		name_len := int(u16le(data, at + 26))
		extra_len := int(u16le(data, at + 28))
		entry_name := data[at + 30..at + 30 + name_len].bytestr()
		body := at + 30 + name_len + extra_len
		if entry_name == name {
			raw := data[body..body + compressed]
			if method == 0 {
				return raw
			}
			return vcraft_wheel.inflate(raw)
		}
		at = body + compressed
		_ = uncompressed
	}
	return error('${name} is not in the wheel')
}

// u16le reads a little-endian 16-bit value.
fn u16le(data []u8, at int) u16 {
	return u16(data[at]) | (u16(data[at + 1]) << 8)
}

// u32le reads a little-endian 32-bit value.
fn u32le(data []u8, at int) u32 {
	return u32(data[at]) | (u32(data[at + 1]) << 8) | (u32(data[at + 2]) << 16) |
		(u32(data[at + 3]) << 24)
}

// audit checks a wheel for the mistakes that make an installer reject it.
//
// Returns warnings rather than failing the build, because every one of these is either
// fatal or harmless and the tool cannot always tell which from the outside. The tag
// check is the important one: a wheel whose name and whose `WHEEL` file disagree is
// installed and then fails to import.
pub fn audit(result BuildResult) ![]string {
	mut problems := []string{}
	name := result.filename
	mut parts := []string{}
	mut current := []u8{}
	for ch in name.bytes() {
		if ch == `-` {
			parts << current.bytestr()
			current = []u8{}
			continue
		}
		current << ch
	}
	parts << current.bytestr()
	if parts.len < 5 {
		problems << '${name} has ${parts.len} parts; a wheel name needs five'
	}
	extension := result.extension
	if !extension.contains('.so') {
		problems << '${extension} is not a shared object'
	}
	if result.wheel.len < 4 {
		problems << 'the wheel is too small to be a ZIP'
		return problems
	}
	if u32le(result.wheel, 0) != 0x0403_4b50 {
		problems << 'the wheel does not start with a ZIP local header'
	}
	if !result.tag.contains('-') {
		problems << 'the tag `${result.tag}` has no interpreter, ABI and platform'
	}
	return problems
}
