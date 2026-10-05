module vcraft_project

import os

// Cross-compilation targets.
//
// A target names an operating system, an architecture and, on Linux, a C library. It is
// the one place a wheel's platform tag comes from when the build is not for the machine
// it runs on: `--platform` overrides the tag for a build that is still native, while
// `--target` also selects the V `-os`/`-arch` flags, the C compiler, and the suffix of
// the extension.
//
// The canonical form is `<os>-<arch>-<libc>`, with Rust-style triples accepted as
// aliases. `host` and `native` mean this machine, which is what a build without
// `--target` has always done.

// CrossTarget is one resolved `--target`.
pub struct CrossTarget {
pub mut:
	// name is the canonical name, e.g. `linux-aarch64-gnu`.
	name string
	// os is `linux`, `macos` or `windows`.
	os string
	// arch is the wheel architecture: `x86_64`, `aarch64` or `amd64`. Always the
	// architecture actually built -- never `universal2`, which needs two of them.
	arch string
	// libc is `gnu`, `musl`, or empty where there is no choice to make.
	libc string
	// policy is the Linux distribution policy, e.g. `manylinux_2_17`. Empty means no
	// policy is claimed and the tag stays `linux_<arch>`.
	policy string
	// platform_tag is the wheel platform tag this target implies.
	platform_tag string
}

// parse_target resolves a `--target` value.
//
// Unknown names are refused rather than guessed at, because a guessed target produces a
// wheel whose tag names a platform the binary was not built for, and pip installs it
// happily on that platform before anything fails.
pub fn parse_target(name string) !CrossTarget {
	clean := name.trim_space().to_lower()
	if clean == '' || clean == 'host' || clean == 'native' {
		return default_target()
	}
	mut os_ := ''
	mut arch := ''
	mut libc := ''
	match clean {
		'linux-x86_64-gnu', 'manylinux-x86_64', 'x86_64-unknown-linux-gnu' {
			os_ = 'linux'
			arch = 'x86_64'
			libc = 'gnu'
		}
		'linux-aarch64-gnu', 'manylinux-aarch64', 'aarch64-unknown-linux-gnu' {
			os_ = 'linux'
			arch = 'aarch64'
			libc = 'gnu'
		}
		'linux-x86_64-musl', 'musllinux-x86_64', 'x86_64-unknown-linux-musl' {
			os_ = 'linux'
			arch = 'x86_64'
			libc = 'musl'
		}
		'linux-aarch64-musl', 'musllinux-aarch64', 'aarch64-unknown-linux-musl' {
			os_ = 'linux'
			arch = 'aarch64'
			libc = 'musl'
		}
		// No `universal2`: a fat binary needs two architectures linked together and
		// this builds one, so tagging one architecture's output `universal2` would
		// be the same lie as a guessed platform tag. macos-arm64 and macos-x86_64
		// name what is actually built.
		'macos-arm64', 'aarch64-apple-darwin' {
			os_ = 'macos'
			arch = 'arm64'
		}
		'macos-x86_64', 'x86_64-apple-darwin' {
			os_ = 'macos'
			arch = 'x86_64'
		}
		'windows-amd64', 'x86_64-pc-windows-msvc' {
			os_ = 'windows'
			arch = 'amd64'
		}
		else {
			return error('unknown target `${name}`; see `vcraft build --help` for the list')
		}
	}
	mut tag := CrossTarget{
		name: clean
		os:   os_
		arch: arch
		libc: libc
	}
	tag.platform_tag = tag.default_platform_tag()
	return tag
}

// default_platform_tag is the platform tag with no distribution policy claimed.
//
// `linux_<arch>` rather than `manylinux_*`: claiming manylinux is a statement about the
// libc the binary was linked against, and a build that has not verified that must not
// make it. A policy arrives through `--manylinux` or `--musllinux`, explicitly.
pub fn (t CrossTarget) default_platform_tag() string {
	if t.os == 'linux' {
		return 'linux_' + t.arch
	}
	if t.os == 'macos' {
		return 'macosx_11_0_' + t.arch
	}
	return 'win_' + t.arch
}

// default_target describes the machine this build runs on.
//
// Compile-time `$if`, because that is the only thing that cannot lie about the host: an
// environment variable can be exported wrongly, and `uname -m` reports the kernel rather
// than the toolchain. The libc comes from `host_libc` below rather than an assumption,
// because assuming glibc is how a musl build gets a gnu tag.
pub fn default_target() CrossTarget {
	mut os_ := 'linux'
	$if macos {
		os_ = 'macos'
	}
	$if windows {
		os_ = 'windows'
	}
	mut arch := 'x86_64'
	$if arm64 {
		arch = 'aarch64'
	}
	// The host's own architecture, not `universal2`: one build makes one
	// architecture's binary, and the tag says which.
	$if windows {
		arch = 'amd64'
	}
	mut libc := ''
	if os_ == 'linux' {
		libc = host_libc()
	}
	mut host := CrossTarget{
		name: 'host'
		os:   os_
		arch: arch
		libc: libc
	}
	host.platform_tag = host.default_platform_tag()
	return host
}

// host_libc reports the C library of this machine: `musl` on a musl host, `gnu`
// otherwise.
//
// By asking `ldd`, which on musl is the dynamic loader itself and prints its own name,
// rather than by reading release files whose format is a per-distribution sprawl. Only
// the output is read, not the exit code: musl's `ldd --version` prints its name and
// then exits 1 with a usage message, so requiring success would report gnu on the one
// host this exists to detect.
fn host_libc() string {
	out := os.execute('ldd --version')
	if out.output.contains('musl') {
		return 'musl'
	}
	return 'gnu'
}

// with_policy returns the target with a Linux distribution policy applied.
//
// `manylinux` needs a version like `2_17` and `musllinux` one like `1_2`. A policy on a
// non-Linux target, or `manylinux` on a musl target, is refused: the tag it would produce
// names a platform the binary cannot satisfy.
pub fn (t CrossTarget) with_policy(manylinux string, musllinux string) !CrossTarget {
	if manylinux.len == 0 && musllinux.len == 0 {
		return t
	}
	if manylinux.len > 0 && musllinux.len > 0 {
		return error('`--manylinux` and `--musllinux` cannot both be set')
	}
	if t.os != 'linux' {
		return error('a Linux distribution policy needs a Linux target, not `${t.name}`')
	}
	mut out := t
	if manylinux.len > 0 {
		if t.libc != 'gnu' {
			return error('`--manylinux` needs a gnu target, not `${t.name}`')
		}
		out.policy = 'manylinux_' + manylinux
		out.platform_tag = 'manylinux_' + manylinux + '_' + t.arch
	} else {
		if t.libc != 'musl' {
			return error('`--musllinux` needs a musl target, not `${t.name}`')
		}
		out.policy = 'musllinux_' + musllinux
		out.platform_tag = 'musllinux_' + musllinux + '_' + t.arch
	}
	return out
}

// is_host reports whether the target is this machine.
pub fn (t CrossTarget) is_host() bool {
	host := default_target()
	return t.os == host.os && t.arch == host.arch && t.libc == host.libc
}

// v_os is the `-os` value V compiles this target with.
pub fn (t CrossTarget) v_os() string {
	return t.os
}

// v_arch is the `-arch` value V compiles this target with, or empty when V needs none.
//
// V selects the architecture from the compiler for the targets it supports natively, and
// an explicit `-arch` for those is how a build ends up compiling the host's sysroot for
// the wrong machine. So this is empty except where V documents the flag: Arm macOS,
// where the compiler default cannot be trusted.
pub fn (t CrossTarget) v_arch() string {
	if t.os == 'macos' && t.arch == 'arm64' {
		return 'arm64'
	}
	return ''
}

// default_cc is the C compiler V should invoke for this target.
//
// Empty for the host, where V's own default is right. Anything else names a
// cross compiler that has to exist, and the build checks that before compiling rather
// than after generating a gigabyte of C.
pub fn (t CrossTarget) default_cc() string {
	if t.is_host() {
		return ''
	}
	if t.os == 'linux' && t.arch == 'aarch64' && t.libc == 'gnu' {
		return 'aarch64-linux-gnu-gcc'
	}
	if t.os == 'linux' && t.arch == 'x86_64' && t.libc == 'musl' {
		return 'x86_64-linux-musl-gcc'
	}
	if t.os == 'linux' && t.arch == 'aarch64' && t.libc == 'musl' {
		return 'aarch64-linux-musl-gcc'
	}
	if t.os == 'windows' {
		return 'x86_64-w64-mingw32-gcc'
	}
	if t.os == 'macos' {
		return 'clang'
	}
	return ''
}

// libc_flag is the `-glibc` or `-musl` V flag for a Linux target.
//
// Explicit rather than inferred, because V's inference reads the host: on a glibc host
// building for musl it would otherwise select `$if glibc` branches for a musl binary.
pub fn (t CrossTarget) libc_flag() string {
	if t.os != 'linux' {
		return ''
	}
	if t.libc == 'musl' {
		return '-musl'
	}
	return '-glibc'
}

// extension_platform is the platform part of a CPython extension suffix for this target,
// e.g. `x86_64-linux-gnu`.
pub fn (t CrossTarget) extension_platform() string {
	if t.os == 'windows' {
		return 'win_' + t.arch
	}
	if t.os == 'macos' {
		return 'darwin'
	}
	if t.libc == 'musl' {
		return t.arch + '-linux-musl'
	}
	return t.arch + '-linux-gnu'
}

// extension_suffix is the file suffix of the compiled extension for this target.
//
// `.pyd` on Windows, `.so` everywhere else. CPython loads a `.so` on macOS regardless
// of architecture, so there is no per-arch suffix to compute there.
pub fn (t CrossTarget) extension_suffix(version string, abi3 string) string {
	if abi3.len > 0 {
		if t.os == 'windows' {
			return '.abi3.pyd'
		}
		return '.abi3.so'
	}
	numeric := version.replace('.', '')
	if t.os == 'windows' {
		return '.cp${numeric}-win_${t.arch}.pyd'
	}
	if t.os == 'macos' {
		return '.cpython-${numeric}-darwin.so'
	}
	return '.cpython-${numeric}-${t.extension_platform()}.so'
}

// describe renders the resolved target for `--dry-run` and `info`.
pub fn (t CrossTarget) describe() string {
	mut out := 'target           ${t.name}\n'
	out += 'target-os        ${t.os}\n'
	out += 'target-arch      ${t.arch}\n'
	if t.libc.len > 0 {
		out += 'target-libc      ${t.libc}\n'
	}
	if t.policy.len > 0 {
		out += 'target-policy    ${t.policy}\n'
	}
	out += 'platform-tag     ${t.platform_tag}\n'
	return out
}
