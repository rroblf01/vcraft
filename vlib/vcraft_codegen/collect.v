module vcraft_codegen

// Walking a parsed project and turning the annotated declarations into the model.

import os
import v.astquery
import v.flat
import v.token

// collect_file adds everything the generator acts on in one file to `p`.
//
// The file is parsed once. `astquery.parse` re-reads and re-parses from disk, so
// calling it per declaration would turn a build into a quadratic number of parses.
pub fn collect_file(path string, mut p Project) {
	lines := read_lines(path)
	ast := astquery.parse(path)
	for decl in astquery.declarations(ast) {
		match decl.kind {
			// A `vc_eq` or `vc_hash` function is a free function, not a method: V allows
			// one receiver per method and a comparison needs both operands. The dispatch
			// tries the operators before the ordinary function path, so a `counter_eq`
			// is not also exported as a callable taking two pointers.
			.fn {
				// `continue`, not `return`: a `return` here leaves the whole loop over the
				// declarations, so the first `@[vc_eq]` in a file stops every declaration
				// after it from being seen -- including the class, whose operators then
				// cannot be resolved because it was never collected.
				if collect_operator(path, lines, ast, decl, mut p) {
					continue
				}
				collect_fn(path, lines, ast, decl, mut p)
			}
			.method { collect_method(path, lines, ast, decl, mut p) }
			.struct { collect_struct(path, lines, ast, decl, mut p) }
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
		'vcraft_generated__method_${decl.receiver.to_lower()}_${decl.name}'
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
	mut f := build_func(decl, ast, block, false)
	f.origin = path
	f.line = decl.line
	f.column = decl.column
	validate(mut p, path, decl, f)
	p.funcs << f
}

// collect_operator records a `vc_eq` or `vc_hash` function and reports whether it took
// ownership of the declaration.
//
// It returns true when the annotation was one of the two, whether or not the name
// matched a class: in the no-match case a diagnostic has been raised, and the
// declaration must not then also be exported as an ordinary function.
fn collect_operator(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) bool {
	block := read_above(lines, decl.line)
	is_eq := attr_eq in block.attrs
	is_hash := attr_hash in block.attrs
	if !is_eq && !is_hash {
		return false
	}
	// The owner is looked up when the function is seen, but a class declared later in
	// the file is not in `p.classes` yet. `link_classes` fills in anything that was
	// still unmatched, which is why `eq_fn` can be empty here and correct there.
	owner := find_eq_owner(decl.name, p.classes)
	if owner < 0 {
		p.operators << Operator{
			name:   decl.name
			line:   decl.line
			column: decl.column
			origin: path
			kind:   if is_eq { 'eq' } else { 'hash' }
		}
		return true
	}
	if find_fn_node(ast, decl.name) == none {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return true
	}
	if is_eq {
		if p.classes[owner].eq_fn.len > 0 {
			report(mut p, path, decl,
				'error: a class may have only one @[vc_eq]; `${p.classes[owner].eq_fn}` is already the equality')
			return true
		}
		p.classes[owner].eq_fn = decl.name
		return true
	}
	if p.classes[owner].hash_name.len > 0 {
		report(mut p, path, decl,
			'error: a class may have only one @[vc_hash]; `${p.classes[owner].hash_name}` is already the hash')
		return true
	}
	p.classes[owner].hash_name = decl.name
	return true
}

// link_operators attaches the operators collected before their class was seen.
//
// A function annotated `@[vc_eq]` is free, so it is dispatched from the `.fn` arm and the
// class it belongs to may not have been collected yet -- a file that declares the struct
// after the operators, or a second file sorted after this one. Resolving it here, once
// every class is known, is what makes the order of the file irrelevant.
fn link_operators(mut p Project) {
	for o in p.operators {
		owner := find_eq_owner(o.name, p.classes)
		if owner < 0 {
			report(mut p, o.origin, astquery.Declaration{
				name: o.name
				line: o.line
				column: o.column
			}, 'error: `${o.name}` is annotated @[vc_${o.kind}] but its name does not start with its class in snake case, so the class it belongs to cannot be told')
			continue
		}
		if o.kind == 'eq' {
			p.classes[owner].eq_fn = o.name
		} else {
			p.classes[owner].hash_name = o.name
		}
	}
	p.operators = []Operator{}
}

// find_eq_owner returns the index of the class a `vc_eq` or `vc_hash` function belongs
// to, matched by the `class_` prefix V's own snake-casing produces.
//
// The name is the only link there is. An operator cannot be a method because V allows one
// receiver, so it is a free function, and a free function has nothing tying it to a class
// except its name.
fn find_eq_owner(fname string, classes []Class) int {
	for i, c in classes {
		if fname.starts_with(c.name.to_lower() + '_') {
			return i
		}
	}
	return -1
}

fn collect_method(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) {
	block := read_above(lines, decl.line)
	// `@[vc_eq]` and `@[vc_hash]` stand in for `@[vc_methods]` on the two slots they
	// fill. They are separate annotations rather than modifiers because the receiver
	// signature is different -- two receivers for eq, an integer result for hash -- and
	// a user who writes `@[vc_methods] @[vc_eq]` would get a method *and* an operator.
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
	mut m := build_func(decl, ast, block, true)
	m.property = attr_property in block.attrs
	if attr_static in block.attrs {
		report(mut p, path, decl,
			'error: `@[vc_static] ${decl.name}` is not supported yet; a static method still needs a receiver in V')
		return
	}
	// The flag is set before the method is appended. V copies a struct on assignment, so
	// a field set afterwards is set on the local and the list keeps a copy without it --
	// which reads as "the annotation was ignored" rather than as a lost assignment.
	p.classes[target].methods << m
}


fn collect_struct(path string, lines []string, ast &flat.FlatAst, decl astquery.Declaration,
	mut p Project) {
	block := read_above(lines, decl.line)
	if attr_class !in block.attrs {
		return
	}
	if class_index(p, decl.name) >= 0 {
		report(mut p, path, decl, 'error: `@[vc_class] ${decl.name}` is declared twice')
		return
	}
	key := decl.name.to_lower()
	mut c := Class{
		name:      decl.name
		doc:       block.doc
		qualified: '${p.module}.${decl.name}'
		ctor:      'vcraft_generated__new_${key}'
		size_fn:   'vcraft_generated__sizeof_${key}'
		ctype:     'g_vc_type_${key}'
		dealloc:   'vcraft_generated__dealloc_${key}'
		repr:      'vcraft_generated__repr_${key}'
		richcompare: 'vcraft_generated__richcompare_${key}'
		hash_fn:     'vcraft_generated__hash_${key}'
		key:       key
	}
	c.fields = collect_fields(path, lines, ast, decl.name, mut p)
	p.classes << c
}

// collect_fields reads the `@[vc_field]` fields of a class.
//
// A field's annotation is written on the field's own line, so it is read from there
// rather than from the line above, and its type comes from the tree.
fn collect_fields(path string, lines []string, ast &flat.FlatAst, struct_name string,
	mut p Project) []Field {
	mut out := []Field{}
	id := find_struct_node(ast, struct_name) or { return out }
	node := ast.node(id)
	// A `pub` field reaches the tree as two nodes: one whose value is `pub` and
	// whose type is the field name, and one holding only the type. Anything else is
	// a plain field whose value is the name.
	// A `pub` or `mut` field reaches the tree as a marker node followed by a node
	// holding only the type; a plain field is one node with the name in `value` and
	// the type in `typ`. Rather than guess which shape a field has, accept both and
	// keep only pairs whose name looks like an identifier.
	mut pending := ''
	for child in ast.children_of(node) {
		c := ast.node(child)
		if c.kind != .field_decl {
			continue
		}
		if c.value == 'pub' || c.value == 'mut' {
			// The documented shape: the marker carries the name in `typ`.
			if c.typ != c.value && is_identifier(c.typ) {
				pending = c.typ
			}
			continue
		}
		if c.value == '' {
			// A type-only node completes the pending name.
			if pending != '' && c.typ != '' {
				out << Field{
					name:   pending
					v_type: c.typ
				}
				pending = ''
			}
			continue
		}
		if is_identifier(c.value) && c.typ != '' {
			out << Field{
				name:   c.value
				v_type: c.typ
			}
			pending = ''
		}
	}
	// Only the annotated ones are exposed, and only scalars are safe to hold in
	// CPython-owned memory.
	mut exposed := []Field{}
	for _, original in out {
		mut f := original
		block := read_inline(lines, field_line(ast, f.name))
		if attr_field !in block.attrs {
			continue
		}
		f.doc = block.doc
		if !f.is_scalar() {
			report(mut p, path, astquery.Declaration{
				name:       f.name
				type_name:  f.v_type
				line:       field_line(ast, f.name)
				column:     1
			}, 'error: `@[vc_field] ${struct_name}.${f.name}` has type `${f.v_type}`, which cannot be stored in a Python object: only bool, the integer and float types are safe. Expose it through a method instead')
			continue
		}
		exposed << f
	}
	return exposed
}

// is_identifier reports whether a name could be a V declaration name, which is how
// a field name is told apart from the `pub` and `mut` markers.
fn is_identifier(text string) bool {
	if text.len == 0 {
		return false
	}
	first := text[0]
	if !(first == `_` || (first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`)) {
		return false
	}
	for i in 1 .. text.len {
		ch := text[i]
		if !(ch == `_` || (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) ||
			(ch >= `0` && ch <= `9`)) {
			return false
		}
	}
	return true
}

// field_line is the 1-based line of a field, used to look its annotation up.
fn field_line(ast &flat.FlatAst, name string) int {
	for raw in ast.file_node_ids {
		if line := find_field_line(ast, flat.NodeId(raw), name) {
			return line
		}
	}
	return 1
}

fn find_field_line(ast &flat.FlatAst, id flat.NodeId, name string) ?int {
	node := ast.node(id)
	if node.kind == .field_decl && (node.value == name || node.typ == name) {
		return ast.source_position(node.pos) or { token.Position{} }.line
	}
	for child in ast.children_of(node) {
		if line := find_field_line(ast, child, name) {
			return line
		}
	}
	return none
}

// find_struct_node locates a struct declaration so its fields can be read.
fn find_struct_node(ast &flat.FlatAst, wanted string) ?flat.NodeId {
	for raw in ast.file_node_ids {
		if found := find_struct_in(ast, flat.NodeId(raw), wanted) {
			return found
		}
	}
	return none
}

fn find_struct_in(ast &flat.FlatAst, id flat.NodeId, wanted string) ?flat.NodeId {
	node := ast.node(id)
	if node.kind == .struct_decl && node.value == wanted {
		return id
	}
	for child in ast.children_of(node) {
		if found := find_struct_in(ast, child, wanted) {
			return found
		}
	}
	return none
}

// link_classes resolves the `new_*` function of each class and gives the class
// methods their flags.
//
// A class with no `new_*` is usable from V but cannot be instantiated from Python,
// which is allowed rather than reported: not every class needs to be constructible.
fn link_classes(mut p Project) {
	// First, because a constructor is found by scanning `p.funcs` and the operators are
	// not in it: they are free functions, dropped from the exported set the moment they
	// were seen.
	link_operators(mut p)
	mut ctors := []string{}
	for i, c in p.classes {
		// V spells a constructor `new_TypeName` in snake case, so the lookup
		// ignores case rather than guessing at a second naming convention.
		wanted := 'new_${c.name}'.to_lower()
		for f in p.funcs {
			if f.name.to_lower() == wanted {
				p.classes[i].ctor_fn = f.name
				ctors << f.name
				if f.params.len > 0 {
					p.diagnostics << Diagnostic{
						file:    f.origin
						line:    f.line
						column:  f.column
						message: 'error: constructor `${f.name}` takes ${f.params.len} argument(s); a class constructor must take none, because it runs in `tp_new` before Python has set anything up'
					}
				}
			}
		}
	}
	if ctors.len == 0 {
		return
	}
	// A `new_X` function is the class's `tp_new`, not a module-level callable. It
	// returns `&X`, which has no marshalling rule of its own, so it is dropped from
	// the exported set along with any diagnostic raised for its signature.
	p.funcs = p.funcs.filter(it.name !in ctors)
	mut kept := []Diagnostic{}
	for d in p.diagnostics {
		mut skip := false
		for ctor in ctors {
			if d.message.contains('`' + ctor + '`') {
				skip = true
			}
		}
		if !skip {
			kept << d
		}
	}
	p.diagnostics = kept
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
