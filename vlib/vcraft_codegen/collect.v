module vcraft_codegen

// Walking a parsed project and turning the annotated declarations into the model.

import os
import v.astquery
import v.flat

// collect_file adds everything the generator acts on in one file to `p`.
//
// The file is parsed once. `astquery.parse` re-reads and re-parses from disk, so
// calling it per declaration would turn a build into a quadratic number of parses.
pub fn collect_file(path string, mut p Project) {
	lines := read_lines(path)
	ast := astquery.parse(path)
	for decl in astquery.declarations(ast) {
		match decl.kind {
			.fn { collect_fn(path, lines, ast, decl, mut p) }
			.method { collect_method(path, lines, ast, decl, mut p) }
			.struct { collect_struct(path, lines, decl, mut p) }
			else {}
		}
	}
}

// collect_dir walks `dir` recursively, skipping anything that is not V source.
pub fn collect_dir(dir string, mut p Project) {
	if !os.is_dir(dir) {
		return
	}
	for path in v_files_under(dir) {
		collect_file(path, mut p)
	}
}

// v_files_under lists the V sources under `dir`, sorted so that generation is
// reproducible.
pub fn v_files_under(dir string) []string {
	mut out := []string{}
	collect_v_files(dir, mut out)
	out.sort()
	return out
}

fn collect_v_files(dir string, mut out []string) {
	mut entries := os.ls(dir) or { return }
	entries.sort()
	for entry in entries {
		path := os.join_path(dir, entry)
		if os.is_dir(path) {
			collect_v_files(path, mut out)
		} else if entry.ends_with('.v') && entry != '_vcraft_generated.v' {
			out << path
		}
	}
}

// find_fn_node locates the fn_decl node for a named function so its parameter list
// can be read from the tree.
fn find_fn_node(ast &flat.FlatAst, wanted string) ?flat.NodeId {
	for raw in ast.file_node_ids {
		if found := find_in(ast, flat.NodeId(raw), wanted) {
			return found
		}
	}
	return none
}

fn find_in(ast &flat.FlatAst, id flat.NodeId, wanted string) ?flat.NodeId {
	node := ast.node(id)
	if node.kind == .fn_decl {
		// A method's node value is `Receiver.name`.
		if node.value == wanted || node.value.ends_with('.' + wanted) {
			return id
		}
	}
	for child in ast.children_of(node) {
		if found := find_in(ast, child, wanted) {
			return found
		}
	}
	return none
}

// params_of reads the declared parameters of a function node, skipping a method
// receiver.
fn params_of(ast &flat.FlatAst, id flat.NodeId, is_method bool) []Param {
	node := ast.node(id)
	mut out := []Param{}
	for child in ast.children_of(node) {
		c := ast.node(child)
		if c.kind != .param {
			continue
		}
		if is_method && out.len == 0 && is_receiver(c.typ) {
			continue
		}
		out << Param{
			name:   c.value
			v_type: c.typ
		}
	}
	return out
}

// is_receiver reports whether a parameter type is a method receiver rather than an
// argument.
fn is_receiver(v_type string) bool {
	return v_type.starts_with('&') || v_type == 'mut'
}

// build_func fills in the parts of a function that come from the tree.
fn build_func(decl astquery.Declaration, ast &flat.FlatAst, block AttrBlock,
	is_method bool) Func {
	mut f := Func{
		name:    decl.name
		doc:     block.doc
		raw:     attr_raw in block.attrs
		nogil:   attr_nogil in block.attrs
		params:  params_of(ast, find_fn_node(ast, decl.name) or {
			flat.empty_node
		}, is_method)
	}
	f.v_ret, f.returns_result = split_result(decl.type_name)
	f.trampoline = if is_method {
		'vcraft_generated__method_${decl.receiver}_${decl.name}'
	} else {
		'vcraft_generated__wrap_${decl.name}'
	}
	return f
}

fn collect_fn(path string, lines []string, ast &flat.FlatAst, decl astquery.Declaration,
	mut p Project) {
	block := read_above(lines, decl.line)
	if attr_fn !in block.attrs && attr_raw !in block.attrs {
		return
	}
	if find_fn_node(ast, decl.name) == none {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return
	}
	f := build_func(decl, ast, block, false)
	validate(mut p, path, decl, f)
	p.funcs << f
}

fn collect_method(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) {
	block := read_above(lines, decl.line)
	if attr_methods !in block.attrs {
		return
	}
	mut target := -1
	for i, c in p.classes {
		if c.name == decl.receiver {
			target = i
			break
		}
	}
	if target < 0 {
		report(mut p, path, decl,
			'error: `${decl.name}` is annotated @[vc_methods] but `${decl.receiver}` is not annotated @[vc_class]')
		return
	}
	if find_fn_node(ast, decl.name) == none {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return
	}
	p.classes[target].methods << build_func(decl, ast, block, true)
}

fn collect_struct(path string, lines []string, decl astquery.Declaration, mut p Project) {
	block := read_above(lines, decl.line)
	if attr_class !in block.attrs {
		return
	}
	if class_index(p, decl.name) >= 0 {
		report(mut p, path, decl, 'error: `@[vc_class] ${decl.name}` is declared twice')
		return
	}
	p.classes << Class{
		name: decl.name
		doc:  block.doc
	}
}

// class_index returns the position of a class by name, or -1.
fn class_index(p Project, name string) int {
	for i, c in p.classes {
		if c.name == name {
			return i
		}
	}
	return -1
}

fn report(mut p Project, path string, decl astquery.Declaration, message string) {
	p.diagnostics << Diagnostic{
		file:    path
		line:    decl.line
		column:  decl.column
		message: message
	}
}

// validate rejects a declaration the generator cannot honour, with a position.
fn validate(mut p Project, path string, decl astquery.Declaration, f Func) {
	for param in f.params {
		if lookup(param.v_type) == .unsupported {
			report(mut p, path, decl,
				'error: cannot expose `${decl.name}`: type `${param.v_type}` of parameter `${param.name}` has no marshalling rule')
			return
		}
	}
	if f.raw {
		return
	}
	if f.v_ret.len > 0 && lookup(f.v_ret) == .unsupported {
		report(mut p, path, decl,
			'error: cannot expose `${decl.name}`: return type `${f.v_ret}` has no marshalling rule')
	}
}

// report_unknown_attrs reports any `vc.` annotation the generator does not know, so
// a typo does not silently drop a declaration from the module.
pub fn report_unknown_attrs(lines []string, path string, mut p Project) {
	for i, line in lines {
		trimmed := line.trim_space()
		if !trimmed.starts_with('@[') {
			continue
		}
		indent := line.len - trimmed.len
		for name in parse_attr_names(line) {
			if name.starts_with('vc.') && name !in known_attrs {
				p.diagnostics << Diagnostic{
					file:    path
					line:    i + 1
					column:  indent + 1
					message: 'error: unknown vcraft annotation `${name}`'
				}
			}
		}
	}
}
