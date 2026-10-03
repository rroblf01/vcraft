module main

// Builds the wheel the wheel tests check. Run by scripts/build-wheel-test.sh.

import os

import vcraft_wheel

fn main() {
	mut binary_path := ''
	mut out_dir := ''
	mut args := os.args[1..]
	for i in 0 .. args.len {
		if args[i] == '--binary' && i + 1 < args.len {
			binary_path = args[i + 1]
		}
		if args[i] == '--out' && i + 1 < args.len {
			out_dir = args[i + 1]
		}
	}
	if binary_path == '' || out_dir == '' {
		eprintln('usage: build_wheel --binary FILE --out DIR')
		exit(1)
	}
	binary := os.read_file(binary_path) or {
		eprintln('cannot read ${binary_path}')
		exit(1)
	}
	name := os.file_name(binary_path)
	out := vcraft_wheel.build(vcraft_wheel.BuildInput{
		distribution: 'vcraft-demo'
		version:      '0.1.0'
		module:       'hello_native'
		extension:    name
		binary:       binary.bytes()
		tags:         ['cp314-cp314-manylinux_2_17_x86_64']
		summary:      'A demo package built by vcraft'
		license:      'MIT'
		requires_python: '>=3.12'
		classifiers: ['Programming Language :: V', 'Programming Language :: Python :: 3']
	}) or {
		eprintln('build failed: ' + err.msg())
		exit(1)
	}
	wheel := vcraft_wheel.wheel_filename('vcraft-demo', '0.1.0',
		['cp314-cp314-manylinux_2_17_x86_64'])
	target := out_dir.trim_right('/') + '/' + wheel
	os.write_file(target, out.bytestr()) or {
		eprintln('cannot write ${target}')
		exit(1)
	}
	println(target)
}
