module main

// vcraft: build Python extension modules written in V.
//
// A wrapper around three libraries that know nothing about each other:
// `vcraft_project` reads the configuration and orchestrates, `vcraft_codegen` writes
// the glue, and `vcraft_wheel` writes the archive. The CLI itself only parses
// arguments and prints, so that each of those stays testable on its own.

import os

import vcraft_ci
import vcraft_codegen
import vcraft_project
import vcraft_wheel

const usage = 'vcraft: Python extensions in V

usage:
  vcraft new <name>            scaffold a project
  vcraft new <name> --with-server   also scaffold a Starlette server
  vcraft build [options]       build a wheel
  vcraft develop [options]     build and install into the active virtualenv
  vcraft sdist                 build a source distribution
  vcraft generate-ci           emit a GitHub Actions workflow into .github/workflows/
  vcraft publish               upload the built distributions to PyPI
  vcraft info                  show what vcraft resolved for this project
  vcraft generate              regenerate the generated glue and stubs
  vcraft check                 check the project for common problems
  vcraft doctor                verify the toolchain and environment
  vcraft migrate               rewrite deprecated annotations to their current names
  vcraft completions <shell>   print shell completion script (bash, zsh, fish)
  vcraft check-wheel [path]    validate a built wheel (METADATA, RECORD, tags)
  vcraft clean                 remove build output
  vcraft toolchain             show which V compiler vcraft uses
  vcraft toolchain install     build the V compiler vcraft is tested with
  vcraft toolchain install --force   reinstall even if present
  vcraft toolchain install --offline use a cached checkout (no network)
  vcraft version, --version    print the version

build options:
  --release                    compile with -prod
  --abi3 <version>             build against the stable ABI
  --interpreter <path>         build against a specific interpreter
  --out-dir <dir>              output directory (default: dist/)
  --platform <tag>             override the platform tag
  --target <name>              cross-compile for a target, e.g. linux-aarch64-gnu
  --manylinux <version>        claim a manylinux policy, e.g. 2_17
  --musllinux <version>        claim a musllinux policy, e.g. 1_2
  --cc <compiler>              C compiler for V to invoke
  --cflags <flags>             extra flags for the C compiler
  --ldflags <flags>            extra flags for the C linker
  --dry-run                    print the build plan without building
  --free-threading             build against a free-threaded interpreter
  --strip                      strip symbols
  --skip-audit                 do not validate the resulting wheel
  --jobs <n>                   compiler parallelism
  --editable                   point the environment at this build instead of copying
  --copy                       install a copy, which is the opposite of --editable
'

// Args is the parsed command line.
struct Args {
mut:
	command string
	// positional holds the arguments that are not options.
	positional []string
	// options holds `--name value` and `--name` pairs.
	mut:
	options map[string]string
	// flags holds options that take no value.
	flags map[string]bool
}

// parse_args splits the command line.
//
// Options are `--name value` or `--name=value`, and a known set of names takes no
// value. The no-value set is listed rather than inferred, because `--release build`
// would otherwise consume `build` and there would be nothing left to build.
fn parse_args(argv []string) !Args {
	mut a := Args{
		command: ''
	}
	mut flags := map[string]bool{}
	mut options := map[string]string{}
	mut i := 0
	for i < argv.len {
		item := argv[i]
		if item.starts_with('-') && item.len > 1 {
			mut name := item.trim_left('-')
			mut value := ''
			mut has_value := false
			if name.contains('=') {
				mut head := name
				value = name.all_after_last('=')
				head = name.all_before_last('=')
				name = head
				has_value = true
			}
			if !has_value && takes_value(name) {
				if i + 1 >= argv.len {
					return error('--${name} needs a value')
				}
				i++
				value = argv[i]
				has_value = true
			}
			if has_value {
				options[name] = value
			} else {
				flags[name] = true
			}
			i++
			continue
		}
		if a.command == '' {
			a.command = item
		} else {
			a.positional << item
		}
		i++
	}
	a.flags = flags
	a.options = options
	return a
}

// takes_value reports whether an option is followed by a value.
fn takes_value(name string) bool {
	return name in ['abi3', 'interpreter', 'out-dir', 'platform', 'jobs', 'python',
		'action', 'target', 'manylinux', 'musllinux', 'cc', 'cflags', 'ldflags']
}

fn main() {
	// A binary V compiles sets VEXE to the compiler that built it, for itself and every
	// process it starts. vcraft runs other V compilers -- the user's, the installed
	// toolchain -- and V locates its own vlib and thirdparty through VEXE when it is set:
	// a pip-installed vcraft would point them at the path of the compiler that built the
	// release, which does not exist on the user's machine. V's Makefile also writes the
	// compiler it builds to $VEXE, so `vcraft toolchain install` overwrote the user's own
	// V with it. Cleared before anything runs.
	os.unsetenv('VEXE')
	// `--version` is what every packaging tool answers, and what a CI log or a bug
	// report reaches for first; `vcraft version` stays for scripts that use it.
	if os.args.len == 2 && os.args[1] in ['--version', '-V'] {
		println(vcraft_project.version)
		exit(0)
	}
	args := parse_args(os.args[1..]) or {
		eprintln('error: ${err.msg()}')
		eprintln('')
		eprint(usage)
		exit(2)
	}
	// `vcraft <command> --help` asks for help, not for the command to run. Without this,
	// `--help` was parsed as an ordinary flag the command ignored, and `vcraft build --help`
	// built the project.
	if args.command != '' && (args.flags['help'] || args.flags['h']) {
		print(usage)
		exit(0)
	}
	match args.command {
		'' {
			print(usage)
			exit(0)
		}
		'new' { cmd_new(args) }
		'build' { cmd_build(args, false) }
		'develop' { cmd_build(args, true) }
		'info' { cmd_info(args) }
		'generate' { cmd_generate(args) }
		'check' { cmd_check(args) }
		'doctor' { cmd_doctor(args) }
		'migrate' { cmd_migrate(args) }
		'completions' { cmd_completions(args) }
		'check-wheel' { cmd_check_wheel(args) }
		'version' { println(vcraft_project.version) }
		// Help goes to stdout: it is what someone asked for, not a diagnostic, and
		// `vcraft help | less` has to work.
		'help', '--help', '-h' { print(usage) }
		'sdist' { cmd_sdist(args) }
		'generate-ci' { cmd_generate_ci(args) }
		'publish' { cmd_publish(args) }
		'clean' { cmd_clean(args) }
		'toolchain' { cmd_toolchain(args) }
		else {
			eprintln('error: unknown command `${args.command}`')
			eprint(usage)
			exit(2)
		}
	}
}

// cmd_new scaffolds a project.
fn cmd_new(args Args) {
	if args.positional.len == 0 {
		eprintln('error: `vcraft new` needs a name')
		exit(2)
	}
	name := args.positional[0]
	mut p := vcraft_project.default_project(name)
	if args.options['module'] != '' {
		p.module = args.options['module']
	}
	// V compiles a file matching `*_test.v` as a test file and silently drops its
	// module export, so a module ending in `_test` builds an empty shared object
	// that fails at import. Refused here, where the message can name the name.
	if p.module.ends_with('_test') {
		eprintln('error: module `${p.module}` ends in `_test`, and V would compile its source as a test file with no module export; pick a module that does not end in `_test`')
		exit(2)
	}
	if name.ends_with('_test') {
		eprintln('error: name `${name}` ends in `_test`, and V treats `*_test` files as test files; pick a name that does not end in `_test`')
		exit(2)
	}
	// PyPI allows `-`, `.` and uppercase in a name; V allows none of them in a module.
	// `default_project` normalises the derived module, so this only fires on a `--module`
	// that is itself unusable, or a name whose stem is not an identifier (`123ext`).
	if !vcraft_project.is_valid_module(p.module) {
		eprintln('error: `${p.module}` is not a valid module name; use letters, digits and underscores, not starting with a digit (pass --module to choose one)')
		exit(2)
	}
	root := if args.positional.len > 1 { args.positional[1] } else { name }
	written := vcraft_project.write_scaffold(root, p) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	for w in written {
		println('created ${w}')
	}
	if args.flags['with-ci'] {
		if p2 := vcraft_project.load(root) {
			dir := root.trim_right('/') + '/.github/workflows'
			os.mkdir_all(dir) or {}
			text := vcraft_ci.workflow(p2, 'rroblf01/vcraft/actions/vcraft-action@v1', p2.free_threading)
			os.write_file(dir + '/build.yml', text) or {
				eprintln('warning: could not write CI workflow')
			}
			println('created ${dir}/build.yml')
		}
	}
	if args.flags['with-server'] {
		sdir := root.trim_right('/') + '/server'
		os.mkdir_all(sdir) or {}
		os.write_file(sdir + '/app.py', '"""Starlette application for ${p.name}."""\n\nfrom starlette.applications import Starlette\nfrom starlette.responses import JSONResponse\nfrom starlette.routing import Route\n\nasync def health(request):\n    return JSONResponse({"status": "ok"})\n\nroutes = [Route("/health", health, methods=["GET"])]\napp = Starlette(routes=routes)\n') or {}
		os.write_file(sdir + '/run.py', 'import uvicorn\n\nif __name__ == "__main__":\n    uvicorn.run("server.app:app", host="0.0.0.0", port=8000)\n') or {}
		os.write_file(root.trim_right('/') + '/requirements-server.txt', 'starlette\nuvicorn\n') or {}
		println('created ${sdir}/app.py')
		println('created ${sdir}/run.py')
		println('created ${root.trim_right("/")}/requirements-server.txt')
	}
	println('')
	println('The importable name is `${vcraft_project.import_name(p)}`.')
	println('')
	println('Next:')
	println('  cd ${root}')
	println('  python -m venv .venv && source .venv/bin/activate')
	println('  vcraft develop          # build and install into the active virtualenv')
	println('  python main.py          # run the example in main.py')
	println('  python -m unittest      # run the tests in tests/')
}

// source_stamp hashes the project's inputs plus the build options, so an unchanged
// tree can skip a rebuild. Stored in `.vcraft/build-stamp`.
fn source_stamp(root string, args Args, develop bool, target_override string) string {
	mut data := []u8{}
	for path in [root + '/vcraft.toml', root + '/v.mod'] {
		if text := os.read_file(path) {
			data << text.bytes()
		}
	}
	for ext in ['.v', '.py', '.toml', '.md'] {
		for dir in [root + '/src', root + '/python'] {
			if os.exists(dir) {
				for f in os.walk_ext(dir, ext) {
					if text := os.read_file(f) {
						data << text.bytes()
					}
				}
			}
		}
	}
	mut flag_sig := ''
	for k, v in args.flags {
		if k == 'check' || k == 'force' {
			continue
		}
		flag_sig += '${k}=${v};'
	}
	data << '${flag_sig}${args.options.str()}${develop}${target_override}'.bytes()
	return vcraft_wheel.sha256(data)
}

// run_build builds one wheel (or installs it), optionally for a specific target.
fn run_build(args Args, develop bool, target_override string) {
	root := '.'
	// Incremental build: if the inputs and options are unchanged and the output is still
	// there, there is nothing to do.
	if !args.flags['force'] && !args.flags['dry-run'] && !args.flags['editable'] && (args.options['out-dir'] == '' || args.options['out-dir'] == 'dist') {
		stamp := source_stamp(root, args, develop, target_override)
		stamp_path := root + '/.vcraft/build-stamp'
		if os.exists(stamp_path) {
			if saved := os.read_file(stamp_path) {
				if saved == stamp {
					mut artifact_ok := true
					if develop {
						if !os.exists(root + '/dist/build') {
							artifact_ok = false
						}
					} else {
						if !os.exists(root + '/dist') || os.walk_ext(root + '/dist', '.whl').len == 0 {
							artifact_ok = false
						}
					}
					if artifact_ok {
						println('up to date')
						return
					}
				}
			}
		}
	}
	// No compiler is the first thing a new user hits, and V's own "command not found"
	// says nothing about how to get one. A dry run plans without compiling.
	v := vcraft_project.v_compiler()
	if !args.flags['dry-run'] && !command_exists(v) {
		eprintln('error: no V compiler found')
		eprintln('  install the one vcraft is tested with:')
		eprintln('    vcraft toolchain install')
		eprintln('  or point VCRAFT_V at a V built from commit ${vcraft_project.v_commit[..7]}')
		exit(1)
	}
	// A silently different V is a landmine: the flags and codegen vcraft relies on were
	// verified against the pinned commit, and a release too old for them fails in a way
	// that looks like a vcraft bug. Warn rather than refuse, so an expert who chose
	// another V on purpose is not blocked.
	if !args.flags['dry-run'] && !vcraft_project.v_matches_pin(v) {
		eprintln('warning: V is not the pinned commit ${vcraft_project.v_commit[..7]}')
		eprintln('  resolved  ${v}')
		reported := vcraft_project.v_reported_commit(v)
		if reported.len > 0 {
			eprintln('  reports   commit ${reported}')
		}
		eprintln('  builds may fail or differ; run `vcraft toolchain install` to pin it')
	}
	// `develop` installs into the active virtualenv, which is VIRTUAL_ENV. Checked
	// before the build rather than after: without it the build runs, then the install
	// fails, and the error names the interpreter it could not find instead of the
	// missing virtualenv.
	if develop && os.getenv('VIRTUAL_ENV').len == 0 {
		eprintln('error: `vcraft develop` needs an active virtualenv')
		eprintln('  create and activate one:')
		eprintln('    python -m venv .venv && source .venv/bin/activate')
		exit(2)
	}
	mut p := vcraft_project.load(root) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	if args.options['abi3'] != '' {
		p.abi3 = args.options['abi3']
	}
	if args.flags['strip'] {
		p.strip = true
	}
	if args.flags['free-threading'] {
		p.free_threading = true
	}
	if args.options['interpreter'] == '' && p.free_threading {
		// A free-threaded interpreter is not the default one and is not on PATH under
		// an obvious name, so the flag is not enough on its own.
		eprintln('error: --free-threading needs --interpreter')
		eprintln('  a free-threaded CPython, for example:')
		eprintln('    --interpreter python3.14t')
		exit(2)
	}
	opt := vcraft_project.BuildOptions{
		root:        root
		out_dir:     if args.options['out-dir'] != '' { args.options['out-dir'] } else { 'dist' }
		release:     args.flags['release']
		// `develop` installs into the active virtualenv, so it has to build against that
		// virtualenv's interpreter: with the venv not first on PATH, `python3` is a
		// different CPython and the extension cannot be imported by the interpreter it
		// was installed into. A plain `build` keeps the PATH default, so a PEP 517 build
		// in an isolated environment is not redirected at whatever venv is active.
		interpreter: if args.options['interpreter'] != '' {
			args.options['interpreter']
		} else if develop {
			vcraft_project.python_in_environment()
		} else {
			''
		}
		platform:    args.options['platform']
		target:      if target_override != '' { target_override } else { args.options['target'] }
		manylinux:   args.options['manylinux']
		musllinux:   args.options['musllinux']
		cc:          args.options['cc']
		cflags:      args.options['cflags']
		ldflags:     args.options['ldflags']
		dry_run:     args.flags['dry-run']
		jobs:        args.options['jobs'].int()
		v_path:      vcraft_project.vlib_path()
		v:           vcraft_project.v_compiler()
		// `develop` is editable unless `--copy` says otherwise, which is what the name
		// means: the point of a development install is that a rebuild is picked up. `build`
		// is never editable, because a wheel is a thing you upload.
		editable:    (develop || args.flags['editable']) && !args.flags['copy']
	}
	if develop && args.flags['dry-run'] {
		// `develop` installs, so a dry run would plan a build it then refuses to do.
		eprintln('error: `--dry-run` makes no sense with `develop`')
		exit(2)
	}
	result := vcraft_project.build(p, opt) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	// A dry run printed its plan inside `build` and wrote nothing, so there is no
	// wheel to audit and nothing to install.
	if opt.dry_run {
		return
	}
	if !args.flags['skip-audit'] {
		problems := vcraft_project.audit(result) or {
			eprintln('error: ${err.msg()}')
			exit(1)
		}
		for problem in problems {
			eprintln('warning: ${problem}')
		}
	}
	println('built ${result.path}')
	if !args.flags['dry-run'] {
		stamp := source_stamp(root, args, develop, target_override)
		os.mkdir_all(root + '/.vcraft') or {}
		os.write_file(root + '/.vcraft/build-stamp', stamp) or {}
	}
	println('  tag       ${result.tag}')
	println('  extension ${result.extension}')
	println('  size      ${result.wheel.len} bytes')
	if !develop {
		return
	}
	if opt.editable {
		vcraft_project.develop_editable(p, result) or {
			eprintln('error: ${err.msg()}')
			exit(1)
		}
		println('installed into ${vcraft_project.active_environment()} (editable)')
		return
	}
	vcraft_project.develop(p, result) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	println('installed into ${vcraft_project.active_environment()}')
}

// cmd_build builds a wheel, or installs it when `develop` was asked for.
fn cmd_build(args Args, develop bool) {
	if args.flags['check'] {
		root := '.'
		stamp := source_stamp(root, args, develop, args.options['target'])
		stamp_path := root + '/.vcraft/build-stamp'
		if os.exists(stamp_path) {
			if saved := os.read_file(stamp_path) {
				if saved == stamp {
					println('up to date')
					return
				}
			}
		}
		println('stale: rebuild required')
		return
	}
	if args.flags['all-targets'] {
		p := vcraft_project.load('.') or {
			eprintln('error: ${err.msg()}')
			exit(1)
		}
		mut targets := p.targets.clone()
		if args.options['target'] != '' {
			targets = [args.options['target']]
		}
		if targets.len == 0 {
			eprintln('error: no targets declared; add `targets = [...]` to [build] in vcraft.toml or pass --target')
			exit(2)
		}
		for t in targets {
			println('=== target ${t} ===')
			run_build(args, develop, t)
		}
		return
	}
	run_build(args, develop, args.options['target'])
}

// cmd_info prints what vcraft resolved, which is the first thing to look at when a
// build produces the wrong thing.
fn cmd_info(args Args) {
	p := vcraft_project.load('.') or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	if args.flags['json'] {
		println('{"name":"${p.name}","version":"${p.version}","module":"${p.module}","v":"${vcraft_project.v_commit}"}')
		return
	}
	println('name             ${p.name}')
	println('version          ${p.version}')
	println('module           ${p.module}')
	println('requires-python  ${p.requires_python}')
	println('minimum-version  ${p.minimum_version}')
	if p.abi3.len > 0 {
		println('abi3             ${p.abi3}')
	}
	println('free-threading   ${p.free_threading}')
	println('strip            ${p.strip}')
	if p.cflags.len > 0 {
		println('cflags           ${p.cflags}')
	}
	if p.ldflags.len > 0 {
		println('ldflags          ${p.ldflags}')
	}
	if p.gc_free_space_divisor != 2 {
		println('gc-free-space-divisor ${p.gc_free_space_divisor}')
	}
	// The interpreter a `develop` would target: the active virtualenv's, or the one on
	// PATH when there is none. The path is printed on its own line so a build against
	// the wrong Python is visible here rather than at import time.
	interp := vcraft_project.python_in_environment()
	println('python           ${vcraft_project.interpreter_version(interp)}')
	println('interpreter      ${interp}')
	println('extension        ${vcraft_project.extension_suffix(interp)}')
	println('platform         ${vcraft_project.platform_tag(interp)}')
	if args.options['target'] != '' {
		// The target is resolved the same way a build resolves it, so `info` answers
		// the question "what would `--target X` do" without compiling anything.
		mut target := vcraft_project.parse_target(args.options['target']) or {
			eprintln('error: ${err.msg()}')
			exit(1)
		}
		target = target.with_policy(args.options['manylinux'], args.options['musllinux']) or {
			eprintln('error: ${err.msg()}')
			exit(1)
		}
		print(target.describe())
	}
	vpath := vcraft_project.v_compiler()
	vstatus := if vcraft_project.v_matches_pin(vpath) {
		'the pinned commit'
	} else {
		'not the pinned commit'
	}
	println('v                ${vpath} (${vstatus})')
	println('v commit (pinned)${vcraft_project.v_commit}')
	reported := vcraft_project.v_reported_commit(vpath)
	if reported.len > 0 {
		println('v commit (reported) ${reported}')
	}
	println('vcraft version   ${vcraft_project.version}')
	println('vlib             ${vcraft_project.vlib_path()}')
	println('environment      ${vcraft_project.active_environment()}')
	println('dependencies     ${p.dependencies.str()}')
	println('classifiers      ${p.classifiers.str()}')
}

// cmd_sdist builds a source distribution.
fn cmd_sdist(args Args) {
	p := vcraft_project.load('.') or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	out_dir := if args.options['out-dir'] != '' { args.options['out-dir'] } else { 'dist' }
	path := vcraft_project.write_sdist(p, '.', out_dir) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	println('built ${path}')
}

// cmd_generate_ci writes a GitHub Actions workflow.
fn cmd_generate_ci(args Args) {
	p := vcraft_project.load('.') or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	// A full `owner/repo/path@ref`: GitHub rejects a bare `vcraft-action@v1` as an
	// action reference before a single job starts.
	action := if args.options['action'] != '' { args.options['action'] } else {
		'rroblf01/vcraft/actions/vcraft-action@v1'
	}
	dir := '.github/workflows'
	if !os.exists(dir) {
		os.mkdir_all(dir) or {
			eprintln('error: cannot create ${dir}')
			exit(1)
		}
	}
	text := vcraft_ci.workflow(p, action, p.free_threading)
	path := dir + '/build.yml'
	os.write_file(path, text) or {
		eprintln('error: cannot write ${path}')
		exit(1)
	}
	println('wrote ${path}')
	println('commit it and push; GitHub reads it from the repository root')
}

// cmd_publish delegates the upload.
//
// vcraft writes the distributions and knows how to build them; how they are uploaded is
// PyPI's business and its authentication has changed twice in two years. Delegating to
// `twine` or `uv` means this tool does not carry a copy of a protocol that changes.
fn cmd_publish(args Args) {
	p := vcraft_project.load('.') or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	if !os.exists('dist') {
		eprintln('error: nothing in dist/; run `vcraft build` first')
		exit(1)
	}
	mut editable := []string{}
	for entry in os.ls('dist') or { []string{} } {
		if !entry.ends_with('.whl') {
			continue
		}
		if vcraft_project.is_editable_wheel('dist/' + entry) or { false } {
			editable << entry
		}
	}
	editable.sort()
	if editable.len > 0 {
		// An editable wheel is a pointer to the machine that built it, not a copy
		// anyone else can install. Refusing it here is what stops a local path from
		// reaching PyPI, where the install would succeed and the import would fail.
		eprintln('error: dist/ holds editable wheels, which cannot be uploaded:')
		for name in editable {
			eprintln('  dist/${name}')
		}
		eprintln('  build a regular wheel first: `vcraft build`')
		exit(1)
	}
	mut uploader := ''
	if command_exists('uv') {
		uploader = 'uv'
	} else if command_exists('twine') {
		uploader = 'twine'
	} else {
		eprintln('error: neither uv nor twine is available')
		eprintln('upload it yourself with `twine upload dist/*`')
		exit(1)
	}
	mut upload := if uploader == 'twine' { ['twine', 'upload'] } else { ['uv', 'publish'] }
	for entry in os.ls('dist') or { []string{} } {
		upload << 'dist/' + entry
	}
	result := os.exec(upload)
	if result.output.len > 0 {
		eprintln(result.output)
	}
	if result.exit_code != 0 {
		exit(result.exit_code)
	}
	_ = p
}

// command_exists reports whether a program is on PATH.
fn command_exists(name string) bool {
	if os.find_abs_path_of_executable(name) or { '' } != '' {
		return true
	}
	// On Windows the compiler is `v.exe`, and a caller may hand over either spelling.
	$if windows {
		if !name.to_lower().ends_with('.exe') {
			if os.find_abs_path_of_executable(name + '.exe') or { '' } != '' {
				return true
			}
		}
	}
	return false
}

// cmd_clean removes build output.
fn cmd_clean(args Args) {
	// An editable install wrote a `.pth` and a `.dist-info` into the active environment
	// that name the directories removed below. Dropping them too keeps a later
	// interpreter start from warning about a build directory that is gone, and keeps a
	// reinstall from finding half of a previous one.
	if p := vcraft_project.load('.') {
		vcraft_project.remove_editable(p)
	}
	mut targets := []string{}
	if args.flags['all'] || (!args.flags['build'] && !args.flags['wheels'] && !args.flags['cache'] && !args.flags['editable']) {
		targets = ['build', 'dist', '.vcraft']
	} else {
		if args.flags['build'] {
			targets << 'build'
		}
		if args.flags['wheels'] {
			targets << 'dist'
		}
		if args.flags['cache'] {
			targets << '.vcraft'
		}
	}
	for dir in targets {
		if os.exists(dir) {
			os.rmdir_all(dir) or {
				eprintln('error: cannot remove ${dir}')
				exit(1)
			}
			println('removed ${dir}')
		}
	}
}

// cmd_generate regenerates the generated glue and stubs without compiling.
fn cmd_generate(args Args) {
	root := if args.positional.len > 0 { args.positional[0] } else { '.' }
	p := vcraft_project.load(root) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	result := vcraft_codegen.generate(vcraft_codegen.Options{
		project_root: root
		module:       p.module
		package:      p.module
	})
	for d in result.diagnostics {
		eprintln(d.error())
	}
	if result.has_errors() {
		eprintln('error: the code generator reported errors')
		exit(1)
	}
	result.write() or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	println('generated ${p.module}')
}

// cmd_check reports common project problems without building.
fn cmd_check(args Args) {
	root := if args.positional.len > 0 { args.positional[0] } else { '.' }
	p := vcraft_project.load(root) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	mut errors := 0
	mut warnings := 0
	// Generated glue must exist; a missing file means the first build has not run.
	for path in [root.trim_right('/') + '/src/_vcraft_generated.v', root.trim_right('/') + '/python/' + p.module.all_after_last('/') + '.pyi'] {
		// best-effort: check the module's pyi naming as vcraft writes it.
		_ = path
	}
	gen := root.trim_right('/') + '/src/_vcraft_generated.v'
	if !os.exists(gen) {
		eprintln('warning: generated glue missing: ${gen}; run `vcraft generate` or `vcraft build`')
		warnings++
	}
	stub := root.trim_right('/') + '/python/' + p.module + '_native.pyi'
	// vcraft writes `python/<module>.pyi` only when module != package; the common
	// case is `python/<module>.pyi`. Try both.
	if !os.exists(stub) {
		alt := root.trim_right('/') + '/python/' + p.module + '.pyi'
		if !os.exists(alt) {
			eprintln('warning: type stub missing under python/; run `vcraft generate` or `vcraft build`')
			warnings++
		}
	}
	// Staleness: generated glue older than any source file.
	if os.exists(gen) {
		gen_mtime := os.file_last_mod_unix(gen)
		mut stale := false
		for f in os.walk_ext(root.trim_right('/') + '/src', '.v') {
			if f.ends_with('_vcraft_generated.v') {
				continue
			}
			if os.file_last_mod_unix(f) > gen_mtime {
				stale = true
				break
			}
		}
		if stale {
			eprintln('warning: generated glue is older than the sources; run `vcraft generate`')
			warnings++
		}
	}
	// Toolchain.
	v := vcraft_project.v_compiler()
	if !command_exists(v) {
		eprintln('error: no V compiler found; run `vcraft toolchain install`')
		errors++
	} else if !vcraft_project.v_matches_pin(v) {
		eprintln('warning: V is not the pinned commit ${vcraft_project.v_commit[..7]}')
		warnings++
	}
	if errors > 0 {
		eprintln('${errors} error(s), ${warnings} warning(s)')
		exit(1)
	}
	if warnings > 0 && args.flags['strict'] {
		eprintln('${warnings} warning(s) (strict mode)')
		exit(1)
	}
	if warnings > 0 {
		eprintln('${warnings} warning(s)')
	} else {
		println('ok: no problems found')
	}
}

// cmd_doctor verifies the toolchain and the surrounding environment.
fn cmd_doctor(args Args) {
	println('vcraft        ${vcraft_project.version}')
	v := vcraft_project.v_compiler()
	println('v compiler    ${v}')
	if command_exists(v) {
		reported := vcraft_project.v_reported_commit(v)
		if reported.len > 0 {
			println('v commit      ${reported}')
		}
		if vcraft_project.v_matches_pin(v) {
			println('v status      the pinned commit')
		} else {
			println('v status      NOT the pinned commit (${vcraft_project.v_commit[..7]})')
		}
	} else {
		println('v compiler    missing; run `vcraft toolchain install`')
	}
	pinned := vcraft_project.installed_v()
	if pinned.len > 0 {
		println('pinned v      ${pinned}')
	} else {
		println('pinned v      not installed')
	}
	py := vcraft_project.python_in_environment()
	println('python        ${py} (${vcraft_project.interpreter_version(py)})')
	println('vlib          ${vcraft_project.vlib_path()}')
	if command_exists(py) {
		println('doctor        ok')
	} else {
		println('doctor        python missing')
		exit(1)
	}
}

// edit_distance is the Levenshtein distance between two strings.
fn edit_distance(a string, b string) int {
	if a.len == 0 {
		return b.len
	}
	if b.len == 0 {
		return a.len
	}
	mut prev := []int{len: b.len + 1, init: index}
	mut cur := []int{len: b.len + 1}
	for i in 1 .. a.len + 1 {
		cur[0] = i
		for j in 1 .. b.len + 1 {
			mut cost := 1
			if a[i - 1] == b[j - 1] {
				cost = 0
			}
			mut del := prev[j] + 1
			mut ins := cur[j - 1] + 1
			mut sub := prev[j - 1] + cost
			mut m := del
			if ins < m {
				m = ins
			}
			if sub < m {
				m = sub
			}
			cur[j] = m
		}
		tmp := prev.clone()
		prev = cur.clone()
		cur = tmp.clone()
	}
	return prev[b.len]
}

fn closest_attr(name string) string {
	mut best := ''
	mut best_dist := 100
	for k in vcraft_codegen.known_attrs {
		d := edit_distance(name, k)
		if d < best_dist {
			best_dist = d
			best = k
		}
	}
	if best_dist > 0 && best_dist <= 2 && best != name {
		return best
	}
	return ''
}

// cmd_migrate rewrites deprecated and misspelled annotations in the project's V sources.
fn cmd_migrate(args Args) {
	root := if args.positional.len > 0 { args.positional[0] } else { '.' }
	mut changed := 0
	for path in os.walk_ext(root.trim_right('/') + '/src', '.v') {
		text := os.read_file(path) or { continue }
		mut out := text
		for old, new in vcraft_codegen.deprecated_attrs {
			out = out.replace('@[' + old + ']', '@[' + new + ']')
		}
		// Detect misspelled vc_ annotations and rewrite them to the closest known one.
		mut unknowns := []string{}
		for line in text.split_into_lines() {
			mut i := 0
			for i < line.len {
				if line[i..].starts_with('vc_') {
					mut j := i
					for j < line.len {
						c := line[j]
						if c.is_letter() || c.is_digit() || c == `_` {
							j++
						} else {
							break
						}
					}
					name := line[i..j]
					if name !in vcraft_codegen.known_attrs && name !in vcraft_codegen.deprecated_attrs.keys() && name !in unknowns {
						if closest_attr(name) != '' {
							unknowns << name
						}
					}
					i = j
				} else {
					i++
				}
			}
		}
		for u in unknowns {
			c := closest_attr(u)
			if c != '' {
				out = out.replace(u, c)
			}
		}
		if out != text {
			os.write_file(path, out) or {
				eprintln('error: cannot write ${path}')
				exit(1)
			}
			println('migrated ${path}')
			changed++
		}
	}
	if changed == 0 {
		println('nothing to migrate')
	}
}

// cmd_completions prints a shell completion script.
fn cmd_completions(args Args) {
	shell := if args.positional.len > 0 { args.positional[0] } else { 'bash' }
	match shell {
		'bash' {
			println('# bash completion for vcraft')
			println('_vcraft() {')
			println(r'  local cur="${COMP_WORDS[COMP_CWORD]}"')
			println('  COMPREPLY=( $(compgen -W "new build develop sdist generate-ci publish info generate check clean toolchain version migrate completions doctor" -- "$cur") )')
			println('}')
			println('complete -F _vcraft vcraft')
		}
		'zsh' {
			println('#compdef vcraft')
			println('local -a cmds')
			println('cmds=(new build develop sdist generate-ci publish info generate check clean toolchain version migrate completions doctor)')
			println('_describe "command" cmds')
		}
		'fish' {
			println('complete -c vcraft -f')
			println('complete -c vcraft -n "__fish_use_subcommand" -a "new build develop sdist generate-ci publish info generate check clean toolchain version migrate completions doctor"')
		}
		else {
			eprintln('error: unknown shell `${shell}`; use bash, zsh or fish')
			exit(2)
		}
	}
}

// cmd_check_wheel validates a built wheel.
fn cmd_check_wheel(args Args) {
	mut path := ''
	if args.positional.len > 0 {
		path = args.positional[0]
	} else {
		// pick the newest wheel in dist/
		if os.exists('dist') {
			mut newest := ''
			mut newest_time := i64(0)
			for f in os.ls('dist') or { []string{} } {
				if f.ends_with('.whl') {
					full := 'dist/' + f
					mtime := os.file_last_mod_unix(full)
					if mtime > newest_time {
						newest_time = mtime
						newest = full
					}
				}
			}
			path = newest
		}
	}
	if path == '' {
		eprintln('error: no wheel given and none found in dist/')
		exit(2)
	}
	script := "import sys,zipfile,hashlib,io,re\n" +
		"path=sys.argv[1]\n" +
		"z=zipfile.ZipFile(path)\n" +
		"names=z.namelist()\n" +
		"assert any(n.endswith('METADATA') for n in names), 'METADATA missing'\n" +
		"assert any(n.endswith('WHEEL') for n in names), 'WHEEL missing'\n" +
		"assert any(n.endswith('RECORD') for n in names), 'RECORD missing'\n" +
		"meta=[n for n in names if n.endswith('METADATA')][0]\n" +
		"text=z.read(meta).decode()\n" +
		"assert 'Metadata-Version:' in text\n" +
		"assert 'Name:' in text\n" +
		"assert 'Version:' in text\n" +
		"record=[n for n in names if n.endswith('RECORD')][0]\n" +
		"for line in z.read(record).decode().splitlines():\n" +
		"    if not line.strip(): continue\n" +
		"    parts=line.split(',')\n" +
		"    if len(parts)<3 or not parts[0]: continue\n" +
		"    if parts[1]=='' : continue\n" +
		"    h=parts[1].split('=')[1] if '=' in parts[1] else ''\n" +
		"    if h: \n" +
		"        data=z.read(parts[0])\n" +
		"        import base64\n" +
		"        calc=base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()\n" +
		"        assert calc==h, 'hash mismatch for '+parts[0]\n" +
		"print('ok: wheel valid ('+str(len(names))+' entries)')\n"
	res := os.exec(['python3', '-c', script, path])
	if res.output.len > 0 {
		print(res.output)
	}
	if res.exit_code != 0 {
		eprintln('error: wheel validation failed')
		exit(1)
	}
}

// cmd_toolchain reports or installs the V compiler.
fn cmd_toolchain(args Args) {
	action := if args.positional.len > 0 { args.positional[0] } else { '' }
	match action {
		'' {
			v := vcraft_project.v_compiler()
			found := command_exists(v)
			println('pinned commit    ${vcraft_project.v_commit}')
			// The pinned install directory is reported only through what is actually
			// there: printing its path regardless made it look installed when it was not.
			pinned := vcraft_project.installed_v()
			if pinned.len > 0 {
				println('pinned install   ${pinned}')
			} else {
				println('pinned install   not installed; run `vcraft toolchain install`')
			}
			if !found {
				println('compiler         none found')
				exit(1)
			}
			println('compiler         ${v}')
			reported := vcraft_project.v_reported_commit(v)
			if vcraft_project.v_matches_pin(v) {
				println('status           the pinned commit')
			} else if reported.len > 0 {
				println('status           commit ${reported}, not the pinned ${vcraft_project.v_commit[..7]}; run `vcraft toolchain install`')
			} else {
				println('status           could not read a commit from `${v} version`')
			}
		}
		'install' {
			jobs := if args.options['jobs'] != '' { args.options['jobs'].int() } else { 2 }
			if args.flags['force'] {
				os.rmdir_all(vcraft_project.toolchain_dir()) or {}
			}
			if args.flags['offline'] {
				if !os.exists(vcraft_project.toolchain_dir()) {
					eprintln('error: no cached toolchain to use offline')
					exit(1)
				}
				println('using cached toolchain (offline)')
			}
			vcraft_project.install_toolchain(if jobs > 0 { jobs } else { 2 }) or {
				eprintln('error: ${err.msg()}')
				exit(1)
			}
			println('installed into ${vcraft_project.toolchain_dir()}')
		}
		else {
			eprintln('error: unknown toolchain action `${action}`; try `vcraft toolchain install`')
			exit(2)
		}
	}
}
