module vcraft_codegen

// The entry point: read a project, return the files to write.

import os

// Options describes what to generate and where.
pub struct Options {
pub:
	// project_root is the directory holding v.mod.
	project_root string
	// src_dir is where the user's V sources live, relative to the project root.
	// The generated v.mod uses `base_url` to point at it, because V no longer
	// treats `src/` as a module root by itself.
	src_dir string = 'src'
	// module is the V module the glue is compiled into, which is the user's own.
	module string
	// package is the Python package name, and therefore what `PyInit_` is named.
	package string
	// stubs_dir is where the `.pyi` goes, relative to the project root.
	stubs_dir string = 'python'
}

// Generated is the result of a run.
pub struct Generated {
pub:
	glue_path string
	glue      string
	stub_path string
	stub      string
	// diagnostics carries everything the scan found, whether or not generation
	// succeeded, so the caller can print them all at once.
	diagnostics []Diagnostic
}

// has_errors reports whether any diagnostic is fatal.
pub fn (g Generated) has_errors() bool {
	return g.diagnostics.any(it.message.starts_with('error'))
}

// generate scans the project and renders the glue and the stub. It writes nothing.
pub fn generate(opt Options) Generated {
	mut p := Project{
		module:  opt.module
		package: opt.package
	}
	src := os.join_path(opt.project_root, opt.src_dir)
	collect_dir(src, mut p)
	for path in v_files_under(src) {
		report_unknown_attrs(read_lines(path), path, mut p)
	}
	link_classes(mut p)

	return Generated{
		glue_path:    os.join_path(src, '_vcraft_generated.v')
		glue:         emit_glue(p)
		stub_path:    os.join_path(opt.project_root, opt.stubs_dir, opt.package, '_stubs.pyi')
		stub:         emit_stubs(p)
		diagnostics: p.diagnostics
	}
}

// The exported functions are already in a stable order: `collect_dir` walks the
// files sorted, and `astquery.declarations` returns them in source order. Nothing
// here reorders them, so the generated diff means something.

// write renders the files to disk.
//
// The glue is written unconditionally rather than only when it changed: V's
// compiler hashes its inputs itself, so an unchanged file costs nothing and a
// changed one can never be missed.
pub fn (g Generated) write() ! {
	os.write_file(g.glue_path, g.glue)!
	os.write_file(g.stub_path, g.stub)!
}
