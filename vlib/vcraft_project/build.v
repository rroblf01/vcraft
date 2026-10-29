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
	// editable builds a wheel that points at this build's output rather than carrying a
	// copy of the extension, so a rebuild is picked up without reinstalling.
	editable bool
	// interpreter is the Python to build against, or empty for the running one.
	interpreter string
	// platform overrides the platform tag, for cross builds.
	platform string
	// target selects a cross-compilation target, e.g. `linux-aarch64-gnu`. Empty means
	// the host, which is what every build before this flag did.
	target string
	// manylinux claims a manylinux policy, e.g. `2_17`, for a Linux gnu target.
	manylinux string
	// musllinux claims a musllinux policy, e.g. `1_2`, for a Linux musl target.
	musllinux string
	// cc overrides the C compiler V invokes. Needed for a cross target whose toolchain
	// V does not know, e.g. a wrapper around `zig cc`.
	cc string
	// cflags are passed to the C compiler after vcraft's own flags.
	cflags string
	// ldflags are passed to the C compiler after every other C option.
	ldflags string
	// dry_run prints the resolved build plan and writes nothing. It is how a target is
	// verified without its toolchain: planning is pure, compiling is not.
	dry_run bool
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

// python_line runs a one-line Python expression and returns the value it prints.
//
// `os.exec` merges stderr into stdout (V's capture redirects both to one pipe), so a
// stray warning from the interpreter -- a stale editable `.pth` naming a removed build
// directory, a startup hook, a sitecustomize -- would otherwise be read as the answer.
// The value is printed behind a tag and the tag is what is searched for, so noise on
// stderr cannot be mistaken for it.
//
// Single quotes inside the expression, because the whole `-c` script is wrapped in
// double quotes for the shell: a nested `"` ends the shell argument early and the
// interpreter sees a truncated program, which it reports as a syntax error rather than
// as the quoting mistake it is.
fn python_line(python string, expression string) string {
	// The common modules are imported up front so an expression can use them: this is a
	// single expression, not a program, so it cannot carry its own import.
	script := "import sys,sysconfig,os;print('__vcraft__' + str(${expression}))"
	out := os.exec([python, '-c', script])
	if out.exit_code != 0 {
		return ''
	}
	for line in out.output.split_into_lines() {
		if line.starts_with('__vcraft__') {
			return line['__vcraft__'.len..].trim_space()
		}
	}
	return ''
}

// interpreter_version returns `major.minor` for a Python executable.
pub fn interpreter_version(python string) string {
	return python_line(python, "str(sys.version_info[0])+'.'+str(sys.version_info[1])")
}

// interpreter_is_free_threaded reports whether an interpreter has no global interpreter
// lock.
//
// `sys._is_gil_enabled` does not answer it. It reports the *current* state of the
// interpreter, which a GIL build also reports as enabled, so using it means a GIL
// interpreter is never detected. The build flag is the honest answer: it is set at
// compile time and does not change while the process runs.
pub fn interpreter_is_free_threaded(python string) bool {
	return python_line(python, "sysconfig.get_config_var('Py_GIL_DISABLED') or 0") == '1'
}

// extension_suffix returns the suffix CPython expects for an extension, including the
// ABI tag. Read from the interpreter rather than hard-coded, because `cpython-314` on
// one build and `cpython-313` on another is the difference between a wheel that
// installs and one that is ignored.
pub fn extension_suffix(python string) string {
	value := python_line(python, "sysconfig.get_config_var('EXT_SUFFIX') or '.so'")
	return if value.len == 0 { '.so' } else { value }
}

// include_dir returns the directory holding Python.h.
pub fn include_dir(python string) string {
	return python_line(python, "sysconfig.get_paths()['include']")
}

// platform_tag returns the platform tag for the running interpreter.
//
// It comes from `sysconfig.get_platform()`, which is what the interpreter itself calls
// its platform. Deriving it from `os.getenv('OS')` and the machine's architecture is
// how a wheel ends up tagged `linux_x86_64` instead of `manylinux_2_17_x86_64`, and pip
// then refuses it with "not a supported wheel on this platform".
pub fn platform_tag(python string) string {
	value := python_line(python, "sysconfig.get_platform().replace('-', '_').replace('.', '_')")
	return if value.len == 0 { 'linux_x86_64' } else { value }
}

// abi_tag returns the ABI tag for an interpreter version.
//
// A free-threaded build is `cp313t`, a GIL build `cp313`, and an abi3 build is `cp37`
// or whatever the stable ABI floor is. Getting this wrong produces a wheel that pip
// installs and then refuses to import, because the interpreter checks the tag against
// itself before loading anything.
pub fn abi_tag(version string, free_threading bool, abi3 string) string {
	clean := version.replace('.', '')
	// `abi3` with `free-threading` is refused by `check_versions` before this runs;
	// should it get here anyway, the stable ABI floor is the tag it builds.
	if abi3.len > 0 {
		return 'cp${abi3.replace('.', '')}'
	}
	if free_threading {
		return 'cp${clean}t'
	}
	return 'cp${clean}'
}

// macos_platform makes a macOS platform tag describe the binary that is actually
// built, and returns the deployment target that keeps it true. Other tags come back
// unchanged with no deployment target.
//
// `universal2` is replaced by the architecture compiled, because one build makes one
// architecture and a fat-binary tag on a thin binary installs where it cannot run. An
// arm64 tag below 11.0 is raised to 11.0, the first macOS on Apple silicon.
pub fn macos_platform(tag string, machine string) (string, string) {
	if !tag.starts_with('macosx_') {
		return tag, ''
	}
	parts := tag.split('_')
	if parts.len < 4 || !parts[1].is_int() || !parts[2].is_int() {
		return tag, ''
	}
	mut major := parts[1].int()
	mut minor := parts[2].int()
	mut arch := parts[3..].join('_')
	if arch in ['universal2', 'universal', 'intel', 'fat', 'fat3', 'fat64'] {
		arch = if machine in ['arm64', 'aarch64'] { 'arm64' } else { 'x86_64' }
	}
	if arch == 'arm64' && major < 11 {
		major = 11
		minor = 0
	}
	return 'macosx_${major}_${minor}_${arch}', '${major}.${minor}'
}

// macos_retarget rewrites a macOS tag's version, e.g. to `13.0` from a deployment
// target the caller set.
pub fn macos_retarget(tag string, deployment string) string {
	parts := tag.split('_')
	nums := deployment.split('.')
	if parts.len < 4 || nums.len == 0 || !nums[0].is_int() {
		return tag
	}
	minor := if nums.len > 1 && nums[1].is_int() { nums[1] } else { '0' }
	return 'macosx_${nums[0]}_${minor}_' + parts[3..].join('_')
}

// export_script is a GNU ld version script exporting only the module's init function.
pub fn export_script(module string) string {
	return '{\n\tglobal: PyInit_${module};\n\tlocal: *;\n};\n'
}

// windows_import_library returns the linker flags that resolve the CPython symbols a
// native Windows extension leaves undefined, and that keep the extension free of the C
// compiler's own runtime.
//
// A PE DLL cannot carry unresolved imports the way an ELF or Mach-O image can: the
// loader binds every import by name against a module already in the process, so the
// linker has to resolve each `Py*` call against the interpreter's import library before
// the image is written. It lives in `<base_prefix>/libs`, named after the DLL: a full-API
// build links `python3XX.lib`, and any abi3 build links the stable ABI's `python3.lib`.
//
// V's Windows C compiler is MinGW gcc, which otherwise links its own runtime as separate
// DLLs (`libwinpthread-1.dll` and friends) that live in the compiler's bin directory,
// off the loader's path when a user imports the wheel. `-static` folds that runtime into
// the extension. The import library is named by full path rather than `-l`, so `-static`
// cannot send the linker looking for a static libpython that does not exist; the import
// of `python3XX.dll` itself stays dynamic.
//
// Skipped for a cross target: a Linux interpreter's `sysconfig` describes no Windows
// import library, so a cross build passes one through `--ldflags` instead.
fn windows_import_library(python string, abi3 string) string {
	mut name := 'python3'
	if abi3.len == 0 {
		raw := python_line(python, "sysconfig.get_config_var('LDLIBRARY') or ''")
		mut base := raw.all_after_last('/').all_after_last('\\')
		if base.ends_with('.dll') {
			base = base[..base.len - 4]
		}
		if base.starts_with('lib') {
			base = base[3..]
		}
		if base.len > 0 {
			name = base
		}
	}
	dir := python_line(python, "sysconfig.get_config_var('LIBDIR') or os.path.join(sys.base_prefix, 'libs')")
	if dir.len > 0 {
		return '-static ${dir}/${name}.lib'
	}
	return '-l${name}'
}

// extension_ldflags returns the linker flags for an extension on `target_os`.
//
// An extension leaves every `Py*` symbol undefined for the interpreter that loads it to
// resolve. ELF linkers allow that in a shared object by default; Apple's linker refuses
// it, so on macOS every build fails at the link with each CPython symbol listed as
// missing. `-undefined dynamic_lookup` is what CPython's own `LDSHARED` uses there.
pub fn extension_ldflags(target_os string, extra string) string {
	mut flags := []string{}
	if target_os == 'macos' {
		flags << '-undefined dynamic_lookup'
	}
	if target_os == 'windows' {
		// GNU ld stamps a PE image's header with the link time, so two builds of the
		// same source differ byte for byte and a wheel cannot be shown reproducible.
		// Zeroing it is what every reproducible MinGW build does.
		flags << '-Wl,--no-insert-timestamp'
	}
	if extra.len > 0 {
		flags << extra
	}
	return flags.join(' ')
}

// limited_api_defines returns the C defines that select the stable ABI.
//
// Without `Py_LIMITED_API` an abi3 wheel compiles against the full headers and then
// claims an ABI it was not built for: it installs, and the first call into a struct
// CPython is allowed to move between versions reads at the wrong offset.
//
// The value is the hex version the floor asks for, `0x030D0000` for 3.13. CPython's own
// headers use it to hide the concrete object structs behind the limited API, which is
// why the runtime already reaches for accessors when it sees this define.
pub fn limited_api_defines(abi3 string) string {
	if abi3.len == 0 {
		return ''
	}
	mut parts := abi3.split('.')
	if parts.len < 2 {
		return ''
	}
	major := parts[0]
	minor := parts[1].int()
	// The stable ABI only ever gained members, so a build against an older floor still
	// loads on a newer interpreter. `Py_LIMITED_API_COMPAT` is what lets the headers keep
	// the older spelling of a member that was later extended.
	// The floor as two hex digits: `Py_LIMITED_API` is a hex version, so 3.12 is
	// `0x030c0000` and not `0x03120000`. Decimal here compiles, links, and then fails
	// to import on every interpreter older than 3.14, because the headers read a floor
	// of 3.18 and use the function form of `Py_TYPE`, which only 3.14 exports.
	hex_minor := if minor < 16 { '0' + minor.hex() } else { minor.hex() }
	return '-DPy_LIMITED_API=0x0${major}${hex_minor}0000'
}

// interpreter_suffix returns the extension suffix for a build.
//
// The concrete suffix carries the interpreter's own tag:
// `.cpython-314-x86_64-linux-gnu.so`. An abi3 build is loaded through the stable ABI
// machinery instead, so its file name has to say `abi3`. Keeping the concrete suffix is
// the mistake that produces a wheel pip installs and then treats as built for one
// specific interpreter, which throws away the entire reason for building against the
// stable ABI.
pub fn interpreter_suffix(python string, abi3 string) string {
	if abi3.len > 0 {
		// Windows names an abi3 extension like any other, `.pyd`: the loader's suffix
		// list has no `.abi3` entry there and would not import one.
		$if windows {
			return '.pyd'
		}
		return '.abi3.so'
	}
	return extension_suffix(python)
}

// limited_define returns the define that reaches vcraft's own C file.
//
// The `Py_LIMITED_API` flag covers CPython's headers, but `vlib/vcraft/c/shim.c` is
// compiled by the same command yet guarded by its own macro. Without this define the
// shim compiles its full-API branches against limited-API headers and every accessor
// that reads a struct field fails to compile.
pub fn limited_define(abi3 string) string {
	if abi3.len == 0 {
		return ''
	}
	return '-Dvcraft_limited_api'
}

// oldest_python is the oldest CPython vcraft builds for. 3.10 is out because the
// runtime's buffer support needs `PyBuffer_*`, which only joined the stable ABI in 3.11.
pub const oldest_python = '3.11'

// free_threading_floor is the first CPython with a free-threaded build.
pub const free_threading_floor = '3.13'

// supported_pythons are the CPython versions vcraft is tested against, oldest first.
// The generated CI matrix builds one wheel per entry from a project's floor upwards.
pub const supported_pythons = ['3.11', '3.12', '3.13', '3.14', '3.15']

// version_key turns `3.12` into a number that orders correctly: 312 sorts after 311 and
// before 313, where comparing the strings puts `3.9` after `3.12`. Malformed input is
// 0, which every check below treats as too old.
pub fn version_key(version string) int {
	parts := version.split('.')
	if parts.len < 2 || !parts[0].is_int() || !parts[1].is_int() {
		return 0
	}
	return parts[0].int() * 100 + parts[1].int()
}

// check_versions refuses the combinations that compile and then fail somewhere else:
// on the installer, at import, or only on the interpreters nobody tried.
pub fn check_versions(interpreter string, abi3 string, free_threading bool) ! {
	if version_key(interpreter) < version_key(oldest_python) {
		return error('CPython ${interpreter} is not supported; vcraft needs ${oldest_python} or newer')
	}
	if abi3.len > 0 {
		if version_key(abi3) == 0 {
			return error('abi3 `${abi3}` is not a version; write it as `3.12`')
		}
		if version_key(abi3) < version_key(oldest_python) {
			return error('abi3 `${abi3}` is below the oldest supported CPython, ${oldest_python}')
		}
		// Older headers do not describe a newer stable ABI: the build compiles against
		// what 3.11 offers and the tag promises what 3.12 offers.
		if version_key(abi3) > version_key(interpreter) {
			return error('abi3 `${abi3}` is newer than the interpreter building it (${interpreter}); build with ${abi3} or newer')
		}
		// CPython has no stable ABI for free-threaded interpreters, and its headers
		// refuse `Py_LIMITED_API` with `Py_GIL_DISABLED`.
		if free_threading {
			return error('abi3 and free-threading cannot be combined: free-threaded CPython has no stable ABI')
		}
	}
	if free_threading && version_key(interpreter) < version_key(free_threading_floor) {
		return error('free-threading needs CPython ${free_threading_floor} or newer, not ${interpreter}')
	}
}

// build compiles the project and writes a wheel.
pub fn build(p Project, opt BuildOptions) !BuildResult {
	python := if opt.interpreter.len > 0 { opt.interpreter } else { python_binary_name() }
	interp_version := interpreter_version(python)
	if interp_version.len == 0 {
		return error('cannot run ${python}; is it on PATH?')
	}
	check_versions(interp_version, p.abi3, p.free_threading)!
	// The target is resolved before anything else, because every error it can report is
	// cheaper than compiling: an unknown name, a policy on the wrong libc, and a
	// `--platform` that disagrees with the target all fail here.
	// An explicit target, or a policy which implies this machine's own. Everything below
	// keys off this rather than off `opt.target` alone, so `--musllinux 1_2` on a
	// musllinux host takes the same path as `--target linux-x86_64-musl` would.
	explicit := opt.target.len > 0 || opt.manylinux.len > 0 || opt.musllinux.len > 0
	mut target := default_target()
	if opt.target.len > 0 {
		target = parse_target(opt.target)!
		target = target.with_policy(opt.manylinux, opt.musllinux)!
	} else if opt.manylinux.len > 0 || opt.musllinux.len > 0 {
		// A policy without a target means this machine: on a musllinux image
		// `--musllinux 1_2` builds natively, and on a manylinux image `--manylinux`
		// claims the policy the image was made for. Refused when the host cannot
		// satisfy it, e.g. a musl policy on a glibc machine.
		target = target.with_policy(opt.manylinux, opt.musllinux)!
	}
	// The free-threaded build is whatever interpreter the caller named, and this is
	// the check: a GIL interpreter produces a `cp314t`-tagged wheel full of GIL code,
	// which the installer accepts and the free-threaded runtime then refuses to load.
	// Asking the interpreter is the only reliable answer, because the tag suffix
	// depends on how it was configured rather than on its version.
	//
	// Skipped for a cross target, where the interpreter that answers cannot be the one
	// the wheel runs on. A foreign interpreter cannot execute here, so there is nothing
	// to ask; the flags are trusted instead.
	if target.is_host() {
		if p.free_threading && !interpreter_is_free_threaded(python) {
			return error('free-threading is set but ${python} is not a free-threaded build; pass --interpreter for one')
		}
		if !p.free_threading && interpreter_is_free_threaded(python) {
			return error('${python} is a free-threaded build; set free-threading in vcraft.toml or pass --free-threading')
		}
	}
	suffix := if explicit {
		target.extension_suffix(interp_version, p.abi3, p.free_threading)
	} else {
		interpreter_suffix(python, p.abi3)
	}
	include := include_dir(python)
	if include.len == 0 {
		return error('cannot find Python.h for ${python}')
	}
	claimed_platform := if opt.platform.len > 0 {
		// An explicit tag that disagrees with an explicit target is a wheel that lies
		// about what it contains, so it is refused rather than warned about.
		if explicit && opt.platform != target.platform_tag {
			return error('--platform `${opt.platform}` does not match --target `${opt.target}`, which implies `${target.platform_tag}`')
		}
		opt.platform
	} else if explicit {
		target.platform_tag
	} else {
		platform_tag(python)
	}
	// On macOS the tag's version is a promise about the oldest system the binary loads
	// on, and only `MACOSX_DEPLOYMENT_TARGET` makes the compiler keep it: without it the
	// binary requires the build machine's own macOS, and pip installs it on older ones
	// where it then fails to load. A deployment target the caller already set wins, and
	// the tag follows it instead.
	mut tag_platform, deployment := macos_platform(claimed_platform, os.uname().machine)
	if deployment.len > 0 {
		chosen := os.getenv('MACOSX_DEPLOYMENT_TARGET')
		if chosen.len > 0 {
			tag_platform, _ = macos_platform(macos_retarget(tag_platform, chosen), os.uname().machine)
		} else {
			os.setenv('MACOSX_DEPLOYMENT_TARGET', deployment, true)
		}
	}
	// `interp_version` arrives as `3.14` and the tag wants `314`: the interpreter tag has no
	// separator between major and minor. A tag of `cp3.14-cp314-...` is not a tag pip
	// knows, and it rejects the wheel with "no matching distribution".
	numeric := interp_version.replace('.', '')
	// An abi3 tag names the *floor*, not the interpreter that built it: PEP 425 spells
	// it `cp<floor>-abi3-<platform>`. Building 3.14 against the 3.12 stable ABI produces
	// `cp312-abi3-...`, and writing `cp314-cp312-...` instead makes every installer
	// reject the wheel with "no wheels with a matching Python version tag" — including
	// on the very interpreter that built it.
	tag := if p.abi3.len > 0 {
		'cp${p.abi3.replace('.', '')}-abi3-${tag_platform}'
	} else {
		'cp${numeric}-${abi_tag(interp_version, p.free_threading, p.abi3)}-${tag_platform}'
	}
	limited := limited_api_defines(p.abi3)

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
	// The backend is rewritten on every build so that it always describes the binary
	// doing the building. A checked-in copy is a copy of whichever version generated it.
	write_backend(opt.root) or { return error('cannot write the build backend') }

	// Every argument is quoted individually. `-path` takes `dir|@vlib`, and an
	// unquoted `@` is a shell word the shell tries to run: the error is "not found"
	// pointing at a directory that does exist.
	// `-new-compiler` and the two variables stop V from answering a C error by
	// downloading its 0.5.2 release and retrying with it: that retry hides the real
	// diagnostic behind an unrelated parse error in the generated glue, and on a CI
	// runner it costs a download and a compiler build on every failure.
	// `scripts/vcraft-v.sh` does the same for this repository's own builds.
	for name in ['V_MACOS_V3_NO_FALLBACK', 'V_C_ERROR_BUG_REPORT_DISABLED'] {
		if os.getenv(name).len == 0 {
			os.setenv(name, '1', true)
		}
	}
	// The collector's heap growth is a `-D` define for the C compiler rather than a
	// `-d` one for V: the only reader is the C pre-initialiser, and V's `$if`
	// cannot see a `-cflags` define while the C preprocessor can.
	gc_define := if p.gc_free_space_divisor != 2 {
		'-DVCRAFT_GC_DIVISOR=${p.gc_free_space_divisor}'
	} else {
		''
	}
	// glibc only declares `struct dl_phdr_info` and `dl_iterate_phdr` with
	// `_GNU_SOURCE`, which the collector pre-initialiser needs for its Linux
	// root walk. It has to arrive as a command-line define: by the time that
	// header is included, the translation unit has already pulled in system
	// headers and glibc has frozen its feature set, so a `#define` there comes
	// too late. Accepted harmlessly by musl, which needs no such gate.
	gnu_define := if target.os == 'linux' {
		'-D_GNU_SOURCE'
	} else {
		''
	}
	// The manifest's flags come first and the CLI's after, so `--cflags` adds to what the
	// project already asks for rather than replacing it.
	extra_cflags := (p.cflags + ' ' + opt.cflags).trim_space()
	mut link_extra := (p.ldflags + ' ' + opt.ldflags).trim_space()
	mut args := [
		opt.v,
		'-new-compiler',
		'-enable-globals',
		'-shared',
		'-o',
		output,
		'-path',
		'${opt.v_path}|@vlib',
		'-cflags',
		('-I${include} ' + limited + ' ' + limited_define(p.abi3) + ' ' + gc_define + ' ' + gnu_define + ' ' + extra_cflags).trim_space(),
	]
	if target.os == 'linux' {
		// Export only the init function. V's `-fvisibility=hidden` already hides most of
		// the runtime, but not everything: on musl V defines its own `backtrace`,
		// `backtrace_symbols` and `backtrace_symbols_fd`, and they ended up in the
		// dynamic symbol table, where another library in the process could bind to
		// them. A version script hides every symbol but `PyInit_<module>` whatever
		// the libc or the V version does.
		// Absolute: V runs the linker from its own working directory, where a path
		// relative to the project does not resolve.
		script := absolute(compiled + '/' + p.module + '.exports')
		os.write_file(script, export_script(p.module)) or {
			return error('cannot write ${script}')
		}
		link_extra = ('-Wl,--version-script=' + script + ' ' + link_extra).trim_space()
	}
	if target.os == 'windows' && target.is_host() {
		// A PE DLL cannot leave `Py*` undefined the way an ELF or Mach-O image does:
		// the loader resolves imports by name against a module already in the process,
		// so the linker has to bind every CPython call against the interpreter's import
		// library before the image is written. It ships in `<base_prefix>/libs`, beside
		// the DLL. A cross build reaches no Windows interpreter from here, so it has to
		// pass the import library through `--ldflags`.
		import_lib := windows_import_library(python, p.abi3)
		if import_lib.len > 0 {
			link_extra = (import_lib + ' ' + link_extra).trim_space()
		}
	}
	// `--strip` / `[build] strip`: strip in the linker rather than with a `strip` binary
	// after the fact, so the flag is part of the build command (`--dry-run` shows it) and
	// no extra tool has to be on PATH. The symbol table goes; the dynamic symbol table
	// stays, so `PyInit_` is still exported and the interpreter still loads the module.
	if p.strip {
		strip_flag := if target.os == 'macos' { '-Wl,-x' } else { '-Wl,-s' }
		link_extra = (strip_flag + ' ' + link_extra).trim_space()
	}
	ldflags := extension_ldflags(target.os, link_extra)
	if ldflags.len > 0 {
		args << '-ldflags'
		args << ldflags
	}
	if explicit {
		// An explicit target is spelled out even when it matches the host, so `--dry-run`
		// shows what the defaults resolve to and a build log says what was built.
		args << '-os'
		args << target.v_os()
		if target.v_arch().len > 0 {
			args << '-arch'
			args << target.v_arch()
		}
		if target.libc_flag().len > 0 {
			args << target.libc_flag()
		}
	}
	cc := if opt.cc.len > 0 { opt.cc } else { target.default_cc() }
	if cc.len > 0 {
		args << '-cc'
		args << cc
	}
	// The rest of the command is toolchain-independent, so it is assembled before
	// the dry-run return: `--dry-run` must show the command as it would run,
	// including `-prod` and the project root. Only the toolchain check and the
	// compilation itself stay after the return.
	// vcraft's own C code has to be told which API it is compiling against. Under
	// `Py_LIMITED_API` CPython hides the concrete object structs behind the stable ABI,
	// so the runtime reaches for its accessors instead of reading a struct field, and
	// that switch is a `-d` define rather than a `cflags` one.
	if limited.len > 0 {
		args << '-d'
		args << 'vcraft_limited_api'
	}
	// The object header is 16 bytes with the GIL and 32 without it, so the V mirrors
	// of CPython's structs have a free-threaded shape selected the same way. Keyed
	// off the project flag rather than the interpreter, because a cross build cannot
	// ask a foreign interpreter anything; the flag and the interpreter are checked
	// against each other above whenever the interpreter can run here.
	if p.free_threading {
		args << '-d'
		args << 'vcraft_free_threaded'
	}
	if opt.release {
		args << '-prod'
	}
	args << opt.root.trim_right('/')
	if opt.dry_run {
		// Before the toolchain check: planning is pure and has to work where the
		// compiler does not exist, which is the whole point of verifying a target
		// without its toolchain.
		println(describe_plan(p, opt, target, tag, suffix, output, args))
		return BuildResult{
			wheel:     []
			filename:  ''
			path:      ''
			extension: p.module + suffix
			tag:       ''
			python:    interp_version
		}
	}
	if cc.len > 0 {
		// Before compiling, because a missing cross compiler otherwise fails after V has
		// generated all of the C, and the error names a file in a temporary directory
		// rather than the compiler that is not installed.
		if !cc_exists(cc) {
			return error('target `${target.name}` needs a C compiler named `${cc}`, which is not on PATH; pass --cc for the one to use')
		}
	} else if !target.is_host() {
		return error('target `${target.name}` is not this machine; pass --cc for the cross compiler to use')
	}
	// V names the shared object itself when the `-o` does not already carry the
	// platform's own suffix: macOS appends `.dylib` and MinGW/llvm-mingw append `.dll`,
	// so `x.cpython-311-darwin.so` is written as `x.cpython-311-darwin.so.dylib` and
	// `x.cp314-win_amd64.pyd` as `x.cp314-win_amd64.pyd.dll`. CPython only imports its
	// EXT_SUFFIX, so the suffixed file is moved back after the build. Both names are
	// cleared first, so a leftover from an earlier build can never be read as this one.
	suffixed := if target.os == 'windows' { output + '.dll' } else { output + '.dylib' }
	for stale in [output, suffixed] {
		if os.exists(stale) {
			os.rm(stale) or { return error('cannot remove ${stale}') }
		}
	}
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('the V compiler failed:\n${result.output}')
	}
	if !os.exists(output) && os.exists(suffixed) {
		os.mv(suffixed, output) or { return error('cannot move ${suffixed} to ${output}') }
	}
	binary := os.read_file(output) or { return error('cannot read ${output}') }

	// Hand-written Python travels with a wheel from the project's `python/` directory.
	// That is where generated stubs live and where a shim belongs, so it is the one
	// place worth looking. An editable wheel does not copy it: the wheel's `.pth` points
	// at the source tree, so a change is picked up without reinstalling.
	python_root := os.join_path(opt.root, 'python')
	mut extras := []vcraft_wheel.ExtraFile{}
	mut editable_paths := []string{}
	if opt.editable {
		editable_paths << absolute(compiled)
		if os.exists(python_root) {
			editable_paths << absolute(python_root)
		}
	} else if os.exists(python_root) {
		for name in python_files(python_root) {
			source_path := python_root.trim_right('/') + '/' + name
			source := os.read_file(source_path) or {
				return error('cannot read ${source_path}')
			}
			if shipped_as_source(name) || !p.embed_pyc {
				extras << vcraft_wheel.ExtraFile{
					name: name
					data: source.bytes()
				}
				continue
			}
			compiled_pyc := compile_pyc(python, python_root, name) or { return err }
			extras << vcraft_wheel.ExtraFile{
				name: pyc_name(name)
				data: compiled_pyc
			}
		}
	}

	// The licence text travels in the wheel so it is distributed with the code, under
	// the `.dist-info/licenses/` directory PEP 639 puts it in. The `License:` metadata
	// field is a separate, human-readable label.
	if license_path := find_license_file(opt.root) {
		data := os.read_file(license_path) or { return error('cannot read ${license_path}') }
		dist_info := '${vcraft_wheel.escape(p.name)}-${vcraft_wheel.normalize_version(p.version)}.dist-info'
		extras << vcraft_wheel.ExtraFile{
			name: dist_info + '/licenses/' + license_path.all_after_last('/')
			data: data.bytes()
		}
	}

	long, long_type := p.long_description(opt.root)
	mut wheel := vcraft_wheel.build(vcraft_wheel.BuildInput{
		distribution:    p.name
		version:         p.version
		module:          p.module
		extension:       p.module + suffix
		binary:          binary.bytes()
		extras:          extras
		editable_paths:  editable_paths
		direct_url:      if opt.editable { direct_url_json(absolute(opt.root)) } else { '' }
		tags:            [tag]
		summary:         p.description
		description:     long
		description_content_type: long_type
		license:         p.license
		authors:         p.authors
		maintainers:     p.maintainers
		keywords:        p.keywords
		project_urls:    p.urls
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
		python:    interp_version
	}
}

// cc_exists reports whether a C compiler is available.
//
// The first word is the executable and the rest are its arguments, which is how a
// wrapper like `zig cc` is spelled. Only the executable has to exist; the arguments
// are the wrapper's own business.
fn cc_exists(cc string) bool {
	fields := cc.split(' ')
	if fields.len == 0 || fields[0].len == 0 {
		return false
	}
	if fields[0].contains('/') {
		return os.exists(fields[0])
	}
	return os.find_abs_path_of_executable(fields[0]) or { '' } != ''
}

// describe_plan renders what a build would do, for `--dry-run`.
//
// The whole point is that planning is pure: it names the target, the tag, the extension
// and the compiler invocation without touching the toolchain, so a target whose
// compiler is not installed can still be verified this far.
fn describe_plan(p Project, opt BuildOptions, target CrossTarget, tag string, suffix string, output string, args []string) string {
	mut out := target.describe()
	out += 'tag              ${tag}\n'
	deployment := os.getenv('MACOSX_DEPLOYMENT_TARGET')
	if tag.contains('-macosx_') && deployment.len > 0 {
		out += 'deployment       MACOSX_DEPLOYMENT_TARGET=${deployment}\n'
	}
	out += 'extension        ${p.module + suffix}\n'
	out += 'output           ${output}\n'
	// The command is shown shell-quoted so it can be pasted into a shell, even though it
	// is run through `os.exec` with the arguments as a list.
	out += 'command          ${args.map(shell_quote(it)).join(' ')}\n'
	return out
}

// absolute makes a path absolute, which the `.pth` of an editable install needs.
//
// `site` reads a `.pth` line as a directory to put on `sys.path`, and a relative one is
// resolved against whatever the process's working directory happens to be when the
// import happens -- which is not the project directory.
fn absolute(path string) string {
	if os.is_abs_path(path) {
		return path
	}
	// `.`, the project root `vcraft build` uses, resolves to the working directory rather
	// than to `working-directory/.`, so the paths written into editable metadata do not
	// carry a trailing dot.
	if path == '.' {
		return os.getwd()
	}
	cwd := os.getwd()
	return cwd.trim_right('/') + '/' + path
}

// direct_url_json identifies the editable source tree in PEP 610 form.
//
// The URL is what makes `pip show -f` and installers treat the wheel as a pointer to a
// checkout rather than as a copy. Backslashes become forward slashes and quotes are
// percent-encoded, because a JSON string with a raw quote is not JSON and a Windows path
// is not a URL.
fn direct_url_json(root string) string {
	url := root.replace('\\', '/').replace('"', '%22')
	return '{"dir_info":{"editable":true},"url":"file://' + url + '"}\n'
}

// python_files lists the Python files under a project's Python directory, relative to
// it: `.py` modules, `.pyi` stubs and the `py.typed` marker.
//
// `.pyi` and `py.typed` ship as they are: a type checker reads them, an interpreter
// ignores them, and there is nothing to compile. A `.py` under `embed-pyc` becomes a
// `.pyc` instead. Sorted, because a wheel whose contents move between builds is a wheel
// nobody can reproduce.
fn python_files(dir string) []string {
	mut out := []string{}
	collect_files_with_suffixes(dir, '', mut out, ['.py', '.pyi', 'py.typed'])
	out.sort()
	return out
}

// shipped_as_source reports whether a Python-tree file is copied verbatim rather than
// compiled when `embed-pyc` is set. Stubs and the `py.typed` marker are metadata, not
// modules.
fn shipped_as_source(name string) bool {
	return name.ends_with('.pyi') || name.ends_with('py.typed')
}

fn collect_files_with_suffixes(dir string, prefix string, mut out []string, suffixes []string) {
	mut entries := os.ls(dir) or { return }
	entries.sort()
	for entry in entries {
		path := dir.trim_right('/') + '/' + entry
		rel := if prefix.len == 0 { entry } else { prefix + '/' + entry }
		if os.is_dir(path) {
			collect_files_with_suffixes(path, rel, mut out, suffixes)
			continue
		}
		for suffix in suffixes {
			if entry.ends_with(suffix) {
				out << rel
				break
			}
		}
	}
}

// pyc_name is where a source file's compiled form goes in a sourceless wheel.
//
// `foo.py` becomes `foo.pyc` beside it, and not `__pycache__/foo.cpython-314.pyc`. The
// cached form is keyed to the interpreter that wrote it and is only importable when the
// source is there to validate it; a `.pyc` at the top level is imported directly, which
// is what a distribution without sources needs.
fn pyc_name(name string) string {
	return name[..name.len - 3] + '.pyc'
}

// compile_pyc compiles one `.py` to a `.pyc` and returns the bytes.
//
// Through the interpreter rather than by writing the bytecode format here: the header
// carries a magic number that changes with every CPython release, and the marshalled
// code below it is a stack of opcodes whose format is not documented at all. Getting
// either wrong produces a file CPython rejects with "bad magic number", which says
// nothing about which of the two was wrong.
//
// Unchecked-hash invalidation, because the source will not be there to check against. The
// default records the source's mtime and size, and CPython then recompiles the module --
// from a source that was never shipped -- on first import, once per interpreter start.
fn compile_pyc(python string, dir string, name string) ![]u8 {
	target := dir.trim_right('/') + '/' + pyc_name(name)
	script := "import py_compile,sys;" +
		"py_compile.compile(sys.argv[1],cfile=sys.argv[2],doraise=True," +
		'invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)'
	source := dir.trim_right('/') + '/' + name
	result := os.exec([python, '-c', script, source, target])
	if result.exit_code != 0 {
		return error('cannot compile ${name}: ${result.output}')
	}
	data := os.read_file(target) or { return error('cannot read ${target}') }
	os.rm(target) or {}
	return data.bytes()
}

// find_license_file returns the first conventional licence file at the project root, or
// none. The names are the ones PyPI, setuptools and the metadata spec recognise.
fn find_license_file(root string) ?string {
	for name in ['LICENSE', 'LICENSE.txt', 'LICENSE.md', 'LICENSE.rst', 'COPYING',
		'COPYING.txt'] {
		path := root.trim_right('/') + '/' + name
		if os.exists(path) {
			return path
		}
	}
	return none
}

// shell_quote renders a command argument for display.
//
// Single quotes, so that a path with a space, a `|` or a `$` in it survives. The build
// itself runs commands through `os.exec` with the arguments as a list, where no quoting
// is needed; this is only for the `--dry-run` plan, which prints a command to paste.
pub fn shell_quote(text string) string {
	return "'" + text.replace("'", "'\\''") + "'"
}
