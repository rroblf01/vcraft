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
		return os.getenv('VCRAFT_HOME')
	}
	if os.getenv('XDG_CACHE_HOME') != '' {
		return os.join_path(os.getenv('XDG_CACHE_HOME'), 'vcraft')
	}
	return os.join_path(os.home_dir(), '.cache', 'vcraft')
}

// toolchain_dir is the checkout the pinned compiler is built in.
pub fn toolchain_dir() string {
	return toolchain_root() + '/v-' + v_commit[..12]
}

// installed_v returns the pinned compiler if `vcraft toolchain install` built it, or ''.
pub fn installed_v() string {
	candidate := os.join_path(toolchain_dir(), executable_name('v'))
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
// (on stderr, which `os.exec` merges) before it.
pub fn v_reported_commit(v string) string {
	out := os.exec([v, 'version'])
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

// host_os is the operating system this build runs on. A compile-time `$if` through
// `default_target`, because nothing at runtime reliably describes the host.
fn host_os() string {
	return default_target().os
}

// toolchain_tools lists the programs `vcraft toolchain install` needs on PATH.
//
// POSIX builds V with its `make`; Windows drives the same build through the checkout's
// own `makev.bat`, which ships with the sources, so only `git` has to be present there.
pub fn toolchain_tools() []string {
	if host_os() == 'windows' {
		return ['git']
	}
	return ['git', 'make']
}

// fetch_tcc_command fetches V's bundled TCC, the fast C compiler V reaches for by
// default. Optional everywhere: without it V falls back to the system C compiler. On
// POSIX the Makefile knows where TCC lives; on Windows there is no make, so the same
// repository `makev.bat` would clone is cloned here.
fn fetch_tcc_command(dir string) []string {
	if host_os() == 'windows' {
		// Windows is amd64 only for now, so the 64-bit branch of `makev.bat` is the one
		// to match.
		return ['git', 'clone', '--filter=blob:none', '-q', '--branch',
			'thirdparty-windows-amd64', 'https://github.com/vlang/tccbin', os.join_path(dir,
			'thirdparty', 'tcc')]
	}
	return ['make', '-C', dir, 'fresh_tcc']
}

// toolchain_build_command builds the pinned V inside dir.
//
// On POSIX `local=1` keeps the Makefile off the network and `VEXE=./v` keeps the compiler
// it writes inside the checkout. On Windows `makev.bat` does the same build; `--local`
// stops it re-syncing the `vc` and TCC checkouts already in place, and it changes into
// its own directory, so the full path is enough to run it from anywhere.
fn toolchain_build_command(dir string, jobs int) []string {
	if host_os() == 'windows' {
		return ['cmd', '/c', os.join_path(dir, 'makev.bat'), '--local']
	}
	return ['make', '-C', dir, 'local=1', '-j${jobs}', 'VEXE=./v']
}

// prebuilt_base is where `release-v.yml` publishes the pinned V, one archive per platform,
// under the release tagged `v/<commit>`.
pub const prebuilt_base = 'https://github.com/rroblf01/vcraft/releases/download'

// prebuilt_asset names the archive for this host, or '' when none is published: the
// archives are built on glibc runners, so a musl host builds from source.
pub fn prebuilt_asset() string {
	t := default_target()
	return match true {
		t.os == 'linux' && t.arch == 'x86_64' && t.libc == 'gnu' { 'linux-x86_64' }
		t.os == 'linux' && t.arch == 'aarch64' && t.libc == 'gnu' { 'linux-aarch64' }
		t.os == 'macos' && t.arch == 'aarch64' { 'macos-arm64' }
		t.os == 'macos' && t.arch == 'x86_64' { 'macos-x86_64' }
		t.os == 'windows' { 'win-amd64' }
		else { '' }
	}
}

// prebuilt_url is the archive's address for this host, or ''. `VCRAFT_V_ARCHIVE_URL`
// replaces it, for a mirror on a network that cannot reach GitHub (any URL curl takes,
// `file://` included).
pub fn prebuilt_url() string {
	if os.getenv('VCRAFT_V_ARCHIVE_URL') != '' {
		return os.getenv('VCRAFT_V_ARCHIVE_URL')
	}
	asset := prebuilt_asset()
	if asset == '' {
		return ''
	}
	return '${prebuilt_base}/v/${v_commit}/v-${v_commit}-${asset}.tar.gz'
}

// install_prebuilt downloads and unpacks the published V for this host into `dir`: a
// download of seconds where the source build takes minutes. `curl` fetches it, or the
// Python on PATH when there is no curl, and `tar` unpacks it; the result has to report
// the pinned commit, or it is removed and the call fails.
fn install_prebuilt(dir string) ! {
	url := prebuilt_url()
	if url == '' {
		return error('no prebuilt V is published for this platform')
	}
	if os.find_abs_path_of_executable('tar') or { '' } == '' {
		return error('`tar` is needed to unpack the prebuilt V')
	}
	archive := dir + '.tar.gz'
	os.mkdir_all(os.dir(dir)) or { return error('cannot create ${os.dir(dir)}') }
	mut fetch := []string{}
	if os.find_abs_path_of_executable('curl') or { '' } != '' {
		fetch = ['curl', '-fsSL', '--retry', '2', '-o', archive, url]
	} else {
		python := os.find_abs_path_of_executable(executable_name('python3')) or {
			os.find_abs_path_of_executable(executable_name('python')) or {
				return error('`curl` or Python is needed to download the prebuilt V')
			}
		}
		fetch = [python, '-c', 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])',
			url, archive]
	}
	println('+ download ${url}')
	if os.system_args(fetch) != 0 {
		os.rm(archive) or {}
		return error('the download failed')
	}
	if os.exists(dir) {
		os.rmdir_all(dir) or { return error('cannot clear ${dir}: ${err.msg()}') }
	}
	os.mkdir_all(dir) or { return error('cannot create ${dir}') }
	// The archive is named relative to its own directory: GNU tar (Git for Windows' is
	// often first on PATH) reads `C:\...` as `host:path` and tries a remote archive.
	// `--force-local` would say the same, but Windows' own bsdtar refuses that flag.
	here := os.getwd()
	os.chdir(os.dir(archive)) or { return error('cannot enter ${os.dir(archive)}') }
	unpacked := os.system_args(['tar', '-xzf', os.file_name(archive), '-C', dir])
	os.chdir(here) or {}
	os.rm(archive) or {}
	built_v := os.join_path(dir, executable_name('v'))
	if unpacked != 0 || !v_matches_pin(built_v) {
		// Say why, so a fallback to the five-minute source build is never silent: the
		// unpack status and what the unpacked compiler answered (or that it would not run).
		reason := if unpacked != 0 {
			'tar exited with ${unpacked}'
		} else {
			answer := os.exec([built_v, 'version'])
			'`v version` exited with ${answer.exit_code} and said: ${answer.output.trim_space().limit(300)}'
		}
		os.rmdir_all(dir) or {}
		return error('the prebuilt archive did not unpack to V ${v_commit[..7]} (${reason})')
	}
	println('installed the prebuilt V ${v_commit[..7]} in ${dir}')
}

// install_toolchain builds the pinned V into `toolchain_dir()`, printing what it runs.
//
// git and a build tool -- `make` on POSIX, the checkout's own `makev.bat` on Windows --
// are what it needs; the C compiler is fetched with the sources. A checkout left by an
// interrupted run is removed first, because a half-built V is worse than none. The C
// bootstrap sources are deleted afterwards, as CI does: they are only read while
// building the compiler, and they are most of its size.
//
// With `prebuilt` it first downloads the archive `release-v.yml` publishes for this host
// and falls back to the source build only when there is none or the download fails.
pub fn install_toolchain(jobs int, prebuilt bool) ! {
	dir := toolchain_dir()
	if installed_v() != '' && v_matches_pin(installed_v()) {
		println('V ${v_commit[..7]} is already installed in ${dir}')
		return
	}
	if prebuilt {
		install_prebuilt(dir) or {
			eprintln('note: ${err.msg()}; building V from source instead')
			install_into(dir, jobs) or {
				os.rmdir_all(dir) or {}
				return err
			}
			return
		}
		return
	}
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
	for tool in toolchain_tools() {
		if os.find_abs_path_of_executable(tool) or { '' } == '' {
			return error('`${tool}` is needed to build V; install it and run this again')
		}
	}
	if os.exists(dir) {
		os.rmdir_all(dir) or { return error('cannot clear ${dir}: ${err.msg()}') }
	}
	os.mkdir_all(dir) or { return error('cannot create ${dir}') }
	fetch := [
		['git', '-C', dir, 'init', '-q'],
		['git', '-C', dir, 'remote', 'add', 'origin', 'https://github.com/vlang/v.git'],
		['git', '-C', dir, 'fetch', '-q', '--depth', '1', 'origin', v_commit],
		['git', '-C', dir, 'checkout', '-q', 'FETCH_HEAD'],
		['git', 'clone', '-q', 'https://github.com/vlang/vc.git', dir + '/vc'],
		['git', '-C', dir + '/vc', 'checkout', '-q', vc_commit],
	]
	for step in fetch {
		println('+ ${step.join(' ')}')
		if os.system_args(step) != 0 {
			return error('`${step.join(' ')}` failed; nothing was installed')
		}
	}
	// V's own fast compiler for non-release builds, fetched before V is built as CI
	// does. Optional: without it V compiles with the system's cc, more slowly.
	tcc := fetch_tcc_command(dir)
	println('+ ${tcc.join(' ')}')
	if os.system_args(tcc) != 0 {
		eprintln('warning: tcc could not be fetched; V will use the system C compiler')
	}
	// VEXE pinned to the checkout's own `./v`: the build writes the compiler it makes to
	// $VEXE, and an inherited one is somebody else's compiler.
	os.unsetenv('VEXE')
	built_v := os.join_path(dir, executable_name('v'))
	build := toolchain_build_command(dir, jobs)
	println('+ ${build.join(' ')}')
	if os.system_args(build) != 0 {
		// The build's last step runs a script for V's own CI after the compiler is built:
		// the Makefile's on POSIX, `makev.bat`'s on Windows. On musl that step fails to
		// link at the pinned commit (the cached `builtin` object exports `backtrace`,
		// which calls a function that is static in another object). A compiler that
		// reports the pin is complete.
		if !v_matches_pin(built_v) {
			return error('`${build.join(' ')}` failed; nothing was installed')
		}
		eprintln('warning: `${build.join(' ')}` failed after building V; the compiler itself works')
	}
	os.rmdir_all(os.join_path(dir, 'vc')) or {}
	if !v_matches_pin(built_v) {
		reported := os.exec([built_v, 'version']).output.trim_space()
		return error('the compiler built in ${dir} does not report commit ${v_commit[..7]}; `v version` said: ${reported}')
	}
	println('installed V ${v_commit[..7]} in ${dir}')
}
