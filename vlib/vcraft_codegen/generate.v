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
	// The enum and struct registries are module state consulted by `lookup`, so they are
	// cleared before a project is scanned.
	reset_type_registry()
	src := os.join_path(opt.project_root, opt.src_dir)
	// Enums and plain structs first, so a signature that names one declared in a file that
	// sorts later still resolves when the signature is validated.
	register_types(src, mut p)
	collect_dir(src, mut p)
	for path in v_files_under(src) {
		file_lines := read_lines(path)
		report_unknown_attrs(file_lines, path, mut p)
		report_c_int_widths(file_lines, path, mut p)
	}
	link_classes(mut p)

	return Generated{
		glue_path:    os.join_path(src, '_vcraft_generated.v')
		glue:         locate_panics(skip_recover_on_return(enter_collector(emit_glue(p))), p,
			opt.project_root)
		stub_path:    os.join_path(opt.project_root, opt.stubs_dir, opt.package + '.pyi')
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
	// The stub is written as `<package>.pyi` next to where the extension is packaged,
	// which is how a type checker finds it for a top-level extension module. The
	// `python/` directory a fresh project does not have is created here, so the first
	// `vcraft build` fails on the project rather than on a missing directory.
	ensure_dir_of(g.stub_path)
	os.write_file(g.glue_path, g.glue)!
	os.write_file(g.stub_path, g.stub)!
}

// ensure_dir_of creates the directory a path lives in, if it is missing.
fn ensure_dir_of(path string) {
	dir := os.dir(path)
	if dir == '' || dir == '.' || os.exists(dir) {
		return
	}
	os.mkdir_all(dir) or { return }
}

// skip_recover_on_return keeps the panic guard's `recover()` off the normal return path.
//
// A trampoline guards its call with `defer { if message := recover() { ... } }`. V runs
// a deferred block on every exit, not only when a panic lands there, so a call that
// returned normally still paid `recover()`: a function call and a thread-local lookup
// to learn that no panic is in flight. That was a measurable share of a short call.
//
// The rewrite gives the guard a local flag that every normal return clears first:
//
//	mut vc_live := true
//	defer {
//		if vc_live {
//			if message := recover() { ... }
//		}
//	}
//	...
//	vc_ret0 := <the returned expression>
//	vc_live = false
//	return vc_ret0
//
// The order is what makes it sound. The returned expression is evaluated *before* the
// flag is cleared, so a panic anywhere in the function's V code, the return expression
// included, reaches the landing pad with the flag still set and recovers exactly as
// before. And the flag is written only after the last V code ran: C leaves a local that
// was modified between `setjmp` and `longjmp` indeterminate, but a panic never follows
// the write, so the landing pad only ever reads the value `setjmp` saw. An expression
// that cannot panic (`unsafe { nil }`, a literal, a plain name) skips the temporary.
//
// Done over the finished text, like `enter_collector`, so every emitter's guard gets it.
// A function whose guard is followed by no `return` (it falls off the end) is left
// untouched rather than given a flag nothing clears.
fn skip_recover_on_return(glue string) string {
	lines := glue.split_into_lines()
	mut out := []string{cap: lines.len + lines.len / 4}
	mut i := 0
	for i < lines.len {
		if !lines[i].starts_with('fn ') {
			out << lines[i]
			i++
			continue
		}
		mut end := i + 1
		for end < lines.len && lines[end] != '}' {
			end++
		}
		if end >= lines.len {
			out << lines[i..]
			break
		}
		out << rewrite_guarded_fn(lines[i..end + 1])
		i = end + 1
	}
	return out.join('\n') + '\n'
}

// rewrite_guarded_fn applies `skip_recover_on_return` to one function, given its lines
// from the `fn` line to the closing brace.
fn rewrite_guarded_fn(lines []string) []string {
	mut guard := -1
	for k in 0 .. lines.len - 1 {
		if lines[k] == '\tdefer {' && lines[k + 1] == '\t\tif message := recover() {' {
			guard = k
			break
		}
	}
	if guard < 0 {
		return lines
	}
	mut guard_end := guard + 1
	for guard_end < lines.len && lines[guard_end] != '\t}' {
		guard_end++
	}
	if guard_end >= lines.len {
		return lines
	}
	mut out := []string{cap: lines.len + 16}
	out << lines[..guard]
	out << '\tmut vc_live := true'
	out << '\tdefer {'
	out << '\t\tif vc_live {'
	for k in guard + 1 .. guard_end {
		out << '\t' + lines[k]
	}
	out << '\t\t}'
	out << '\t}'
	mut rewritten := 0
	// The indentation of an anonymous function opened inside the body, whose own
	// `return` statements belong to it and must not touch the trampoline's flag.
	mut closure_indent := -1
	for k in guard_end + 1 .. lines.len {
		line := lines[k]
		indent := leading_tabs(line)
		body := line[indent..]
		if closure_indent >= 0 {
			if indent == closure_indent && body.starts_with('}') {
				closure_indent = -1
			}
			out << line
			continue
		}
		if body.ends_with('{') && opens_closure(body) {
			closure_indent = indent
			out << line
			continue
		}
		if body != 'return' && !body.starts_with('return ') {
			out << line
			continue
		}
		tabs := line[..indent]
		expr := body['return'.len..].trim_space()
		if expr == '' || cannot_panic(expr) {
			out << tabs + 'vc_live = false'
			out << line
		} else {
			name := 'vc_ret${rewritten}'
			out << tabs + '${name} := ${expr}'
			out << tabs + 'vc_live = false'
			out << tabs + 'return ${name}'
		}
		rewritten++
	}
	if rewritten == 0 {
		return lines
	}
	return out
}

// leading_tabs counts the tabs that indent a line of the generated glue.
fn leading_tabs(line string) int {
	mut n := 0
	for n < line.len && line[n] == `\t` {
		n++
	}
	return n
}

// opens_closure reports whether a line that ends in `{` opens an anonymous function.
fn opens_closure(body string) bool {
	return body.contains('fn (') || body.contains('fn [')
}

// cannot_panic reports whether a returned expression runs no V code: the null pointer,
// a numeric or boolean literal, or a plain local.
fn cannot_panic(expr string) bool {
	if expr == 'unsafe { nil }' || expr == 'true' || expr == 'false' {
		return true
	}
	mut digits := expr
	if digits.starts_with('-') {
		digits = digits[1..]
	}
	if digits.len > 0 && digits.bytes().all(it.is_digit()) {
		return true
	}
	return expr.len > 0 && (expr[0].is_letter() || expr[0] == `_`)
		&& expr.bytes().all(it.is_letter() || it.is_digit() || it == `_`)
}

// locate_panics makes each trampoline report where its V function lives when it turns
// a panic into an exception: `vcraft.raise_panic(message)` becomes
// `vcraft.raise_panic_at(message, 'src/lib.v', 42, 'parse')`, which adds a traceback frame
// for that line. Done over the finished text, like `enter_collector`, so every emitter's
// guard gets it; a trampoline the map does not know keeps the plain call.
fn locate_panics(glue string, p Project, root string) string {
	mut where := map[string]string{}
	for f in p.funcs {
		panic_location(mut where, f, root)
	}
	for c in p.classes {
		for m in c.methods {
			panic_location(mut where, m, root)
			// `tp_iter` and `tp_iternext` are named after the class, not the method.
			if m.is_iter || m.is_next {
				mut slot := m
				slot.trampoline = if m.is_iter { c.iter_fn } else { c.next_fn }
				panic_location(mut where, slot, root)
			}
		}
		if c.ctor_fn.len > 0 {
			panic_location(mut where, Func{
				name:       c.ctor_fn
				trampoline: 'vcraft_generated__new_${c.key}'
				origin:     c.ctor_origin
				line:       c.ctor_line
			}, root)
		}
	}
	mut out := []string{cap: glue.len / 32}
	mut current := ''
	for line in glue.split_into_lines() {
		if line.starts_with('fn ') {
			current = line[3..].all_before('(')
		}
		if line.ends_with('vcraft.raise_panic(message)') {
			if loc := where[current] {
				out << line.replace('vcraft.raise_panic(message)', 'vcraft.raise_panic_at(message, ${loc})')
				continue
			}
		}
		out << line
	}
	return out.join('\n') + '\n'
}

// panic_location records where `f` is declared, keyed by its trampoline, in the form
// `raise_panic_at` takes: the file relative to the project, the line and the name.
fn panic_location(mut where map[string]string, f Func, root string) {
	if f.trampoline.len == 0 || f.origin.len == 0 || f.line < 1 {
		return
	}
	mut file := f.origin
	prefix := root.trim_right('/') + '/'
	if file.starts_with(prefix) {
		file = file[prefix.len..]
	}
	if file.starts_with('./') {
		file = file[2..]
	}
	name := if f.name.len > 0 { f.name } else { f.py_name }
	where[f.trampoline] = "'${file}', ${f.line}, '${name}'"
}

// enter_collector starts every function in the glue by registering the calling thread
// with V's collector.
//
// Every one of them is an entry point Python can reach from any thread: functions,
// methods, accessors, `__repr__`, iteration, `tp_dealloc` and `tp_traverse` alike, and
// a function added to the emitter later is one more. Done here, over the finished
// text, rather than in each emitter, so a new kind of trampoline cannot forget it.
// The call is one thread-local load after a thread's first.
fn enter_collector(glue string) string {
	mut out := []string{cap: glue.len / 32}
	for line in glue.split_into_lines() {
		out << line
		if line.starts_with('fn vcraft_generated__') && line.ends_with('{') {
			out << '\tvcraft.gc_enter()'
		}
	}
	return out.join('\n') + '\n'
}
