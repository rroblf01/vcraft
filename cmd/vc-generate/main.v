module main

// A throwaway driver for the code generator, used while the CLI does not exist
// yet. Phase 2's test suite runs it.
//
//	vcraft-generate <project-root> <module> <package>

import os
import vcraft_codegen

fn main() {
	mut args := os.args[1..]
	if args.len < 3 {
		eprintln('usage: vc-generate <project-root> <module> <package>')
		exit(2)
	}
	opt := vcraft_codegen.Options{
		project_root: args[0]
		module:       args[1]
		package:      args[2]
	}
	result := vcraft_codegen.generate(opt)
	for d in result.diagnostics {
		eprintln(d.error())
	}
	if result.has_errors() {
		exit(1)
	}
	result.write() or {
		eprintln('error: ${err}')
		exit(1)
	}
	println('wrote ${result.glue_path}')
	println('wrote ${result.stub_path}')
}
