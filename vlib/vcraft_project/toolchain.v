module vcraft_project

import os

// The V compiler vcraft is built and tested with.
//
// No V release is new enough: 0.5.2 rejects flags vcraft passes. So vcraft pins a
// commit, and `vcraft toolchain install` builds exactly that commit into a cache of its
// own, instead of asking every user to follow a list of git and make commands. The same
// pins appear in CI, the images and the action; the CLI suite checks they agree.

// v_commit is the V commit vcraft builds and tests with.
pub const v_commit = '36be92642c49a8fe9213ea4b96c6bf56b67b668c'

// vc_commit is the matching snapshot of `vlang/vc`, the C bootstrap V builds from. A newer
// snapshot enforces checker rules the pinned V sources predate.
pub const vc_commit = '6851aaf3f9e696b30b26e406f16095b0002acaab'

// toolchain_root is where installed compilers live: `$VCRAFT_HOME`, else
// `$XDG_CACHE_HOME/vcraft`, else `~/.cache/vcraft`.
pub fn toolchain_root() string {
	if os.getenv('VCRAFT_HOME') != '' {
		return os.getenv('VCRAFT_HOME').trim_right('/')
	}
	if os.getenv('XDG_CACHE_HOME') != '' {
		return os.getenv('XDG_CACHE_HOME').trim_right('/') + '/vcraft'
	}
	return os.home_dir().trim_right('/') + '/.cache/vcraft'
}

// toolchain_dir is the checkout the pinned compiler is built in.
pub fn toolchain_dir() string {
	return toolchain_root() + '/v-' + v_commit[..12]
}

// installed_v returns the pinned compiler if `vcraft toolchain install` built it, or ''.
pub fn installed_v() string {
	candidate := toolchain_dir() + '/v'
	if os.is_executable(candidate) {
		return candidate
	}
	return ''
}

// v_matches_pin reports whether a compiler is the pinned commit, by asking it: `v version`
// prints `V 0.5.2 36be926`, the short hash of the commit it was built from.
pub fn v_matches_pin(v string) bool {
	return v_reported_commit(v).len >= 7 && v_commit.starts_with(v_reported_commit(v))
}

// v_reported_commit is the short hash `v version` prints, or ''. The version line is
// looked for among all output lines: a freshly built V can print notes or warnings
// (on stderr, which `os.execute` merges) before it.
pub fn v_reported_commit(v string) string {
	out := os.execute(shell_quote(v) + ' version')
	if out.exit_code != 0 {
		return ''
	}
	for line in out.output.split_into_lines() {
		fields := line.trim_space().split(' ')
		if fields.len >= 3 && fields[0] == 'V' {
			return fields[2]
		}
	}
	return ''
}

// install_toolchain builds the pinned V into `toolchain_dir()`, printing what it runs.
//
// git, make and a C compiler are what it needs; it downloads nothing else. A checkout
// left by an interrupted run is removed first, because a half-built V is worse than none.
// The C bootstrap sources are deleted afterwards, as CI does: they are only read while
// building the compiler, and they are most of its size.
pub fn install_toolchain(jobs int) ! {
	dir := toolchain_dir()
	install_into(dir, jobs) or {
		// A half-built checkout is gigabytes of nothing usable: remove it, so the
		// "nothing was installed" in the error is true.
		os.rmdir_all(dir) or {}
		return err
	}
}

fn install_into(dir string, jobs int) ! {
	if installed_v() != '' && v_matches_pin(installed_v()) {
		println('V ${v_commit[..7]} is already installed in ${dir}')
		return
	}
	for tool in ['git', 'make'] {
		if os.execute('command -v ${tool}').exit_code != 0 {
			return error('`${tool}` is needed to build V; install it and run this again')
		}
	}
	if os.exists(dir) {
		os.rmdir_all(dir) or { return error('cannot clear ${dir}: ${err.msg()}') }
	}
	os.mkdir_all(dir) or { return error('cannot create ${dir}') }
	q := shell_quote(dir)
	fetch := [
		'git -C ${q} init -q',
		'git -C ${q} remote add origin https://github.com/vlang/v.git',
		'git -C ${q} fetch -q --depth 1 origin ${v_commit}',
		'git -C ${q} checkout -q FETCH_HEAD',
		'git clone -q https://github.com/vlang/vc.git ${shell_quote(dir + '/vc')}',
		'git -C ${shell_quote(dir + '/vc')} checkout -q ${vc_commit}',
	]
	for step in fetch {
		println('+ ${step}')
		if os.system(step) != 0 {
			return error('`${step}` failed; nothing was installed')
		}
	}
	// V's own fast compiler for non-release builds, fetched before V is built as CI
	// does. Optional: without it V compiles with the system's cc, more slowly.
	println('+ make -C ${q} fresh_tcc')
	if os.system('make -C ${q} fresh_tcc') != 0 {
		eprintln('warning: tcc could not be fetched; V will use the system C compiler')
	}
	// VEXE pinned to the checkout's own `./v`: V's Makefile writes the compiler it builds
	// to $VEXE, and an inherited one is somebody else's compiler.
	os.unsetenv('VEXE')
	build := 'make -C ${q} local=1 -j${jobs} VEXE=./v'
	println('+ ${build}')
	if os.system(build) != 0 {
		// The Makefile's last step compiles and runs a script for V's own CI after the
		// compiler is built, and on musl that step fails to link at the pinned commit
		// (the cached `builtin` object exports `backtrace`, which calls a function that
		// is static in another object). A compiler that reports the pin is complete.
		if !v_matches_pin(dir + '/v') {
			return error('`${build}` failed; nothing was installed')
		}
		eprintln('warning: `${build}` failed after building V; the compiler itself works')
	}
	os.rmdir_all(dir + '/vc') or {}
	if !v_matches_pin(dir + '/v') {
		reported := os.execute(shell_quote(dir + '/v') + ' version').output.trim_space()
		return error('the compiler built in ${dir} does not report commit ${v_commit[..7]}; `v version` said: ${reported}')
	}
	println('installed V ${v_commit[..7]} in ${dir}')
}
