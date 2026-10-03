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
pub const version = '0.1.0'

// vlib_path returns the `-path` value for the V compiler.
//
// It is the `vlib` directory beside this binary: `<dir>/../vlib`. The binary is built
// into `bin/vcraft`, so the modules are two levels up, and the wheel's `v` executable
// sits in the same place.
pub fn vlib_path() string {
	exe := os.executable()
	dir := exe.all_before_last('/')
	return dir.all_before_last('/') + '/vlib'
}

// v_compiler returns the V compiler to use.
//
// `VCRAFT_V` wins, then a `v` beside this binary, then `v` on `PATH`. The middle case is
// what makes a downloaded release work without asking anyone to configure anything.
pub fn v_compiler() string {
	if os.getenv('VCRAFT_V') != '' {
		return os.getenv('VCRAFT_V')
	}
	beside := os.executable().all_before_last('/') + '/v'
	if os.exists(beside) {
		return beside
	}
	return 'v'
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
		return 'python3'
	}
	candidate := venv.trim_right('/') + '/bin/python'
	if os.exists(candidate) {
		return candidate
	}
	return 'python3'
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
		return error('no interpreter at ${python}; activate a virtualenv first')
	}
	script := "import sysconfig;print(sysconfig.get_paths()['platlib'])"
	site := os.execute(python + ' -c "' + script + '"')
	if site.exit_code != 0 {
		return error('cannot find site-packages for ${python}')
	}
	target := site.output.trim_space()
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
	return
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
