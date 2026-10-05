module main

// vcraft: build Python extension modules written in V.
//
// A wrapper around three libraries that know nothing about each other:
// `vcraft_project` reads the configuration and orchestrates, `vcraft_codegen` writes
// the glue, and `vcraft_wheel` writes the archive. The CLI itself only parses
// arguments and prints, so that each of those stays testable on its own.

import os

import vcraft_ci
import vcraft_project

const usage = 'vcraft: Python extensions in V

usage:
  vcraft new <name>            scaffold a project
  vcraft build [options]       build a wheel
  vcraft develop [options]     build and install into the active virtualenv
  vcraft sdist                 build a source distribution
  vcraft generate-ci           emit a GitHub Actions workflow into .github/workflows/
  vcraft publish               upload the built distributions to PyPI
  vcraft info                  show what vcraft resolved for this project
  vcraft version               print the version

build options:
  --release                    compile with -prod
  --abi3 <version>             build against the stable ABI
  --interpreter <path>         build against a specific interpreter
  --out-dir <dir>              output directory (default: dist/)
  --platform <tag>             override the platform tag
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
		'action']
}

fn main() {
	args := parse_args(os.args[1..]) or {
		eprintln('error: ${err.msg()}')
		eprintln('')
		eprint(usage)
		exit(2)
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
		'version' { println(vcraft_project.version) }
		// Help goes to stdout: it is what someone asked for, not a diagnostic, and
		// `vcraft help | less` has to work.
		'help', '--help', '-h' { print(usage) }
		'sdist' { cmd_sdist(args) }
		'generate-ci' { cmd_generate_ci(args) }
		'publish' { cmd_publish(args) }
		'clean' { cmd_clean(args) }
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
	root := if args.positional.len > 1 { args.positional[1] } else { name }
	written := vcraft_project.write_scaffold(root, p) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	for w in written {
		println('created ${w}')
	}
	println('')
	println('Next:')
	println('  cd ${root}')
	println('  vcraft develop')
}

// cmd_build builds a wheel, or installs it when `develop` was asked for.
fn cmd_build(args Args, develop bool) {
	root := '.'
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
		interpreter: args.options['interpreter']
		platform:    args.options['platform']
		jobs:        args.options['jobs'].int()
		v_path:      vcraft_project.vlib_path()
		v:           vcraft_project.v_compiler()
		// `develop` is editable unless `--copy` says otherwise, which is what the name
		// means: the point of a development install is that a rebuild is picked up. `build`
		// is never editable, because a wheel is a thing you upload.
		editable:    (develop || args.flags['editable']) && !args.flags['copy']
	}
	result := vcraft_project.build(p, opt) or {
		eprintln('error: ${err.msg()}')
		exit(1)
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

// cmd_info prints what vcraft resolved, which is the first thing to look at when a
// build produces the wrong thing.
fn cmd_info(args Args) {
	p := vcraft_project.load('.') or {
		eprintln('error: ${err.msg()}')
		exit(1)
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
	println('python           ${vcraft_project.interpreter_version("python3")}')
	println('extension        ${vcraft_project.extension_suffix("python3")}')
	println('platform         ${vcraft_project.platform_tag("python3")}')
	println('v                ${vcraft_project.v_compiler()}')
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
	action := if args.options['action'] != '' { args.options['action'] } else {
		'vcraft-action@v1'
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
	if os.exists('uv') || command_exists('uv') {
		uploader = 'uv'
	} else if command_exists('twine') {
		uploader = 'twine'
	} else {
		eprintln('error: neither uv nor twine is available')
		eprintln('upload it yourself with `twine upload dist/*`')
		exit(1)
	}
	mut result := os.execute('uv publish dist/*')
	if uploader == 'twine' {
		result = os.execute('twine upload dist/*')
	}
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
	return os.execute('command -v ' + name).exit_code == 0
}

// cmd_clean removes build output.
fn cmd_clean(args Args) {
	for dir in ['build', 'dist', '.vcraft'] {
		if os.exists(dir) {
			os.rmdir_all(dir) or {
				eprintln('error: cannot remove ${dir}')
				exit(1)
			}
			println('removed ${dir}')
		}
	}
}
