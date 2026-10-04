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
			// A `@[vc_error]` struct is collected before the class path, which would
			// otherwise reject it for not being annotated `@[vc_class]`.
			.struct {
				if !collect_error_type(path, lines, ast, decl, mut p) {
					collect_struct(path, lines, ast, decl, mut p)
				}
			}
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

// link_bases resolves each class's `@[vc_base]` to the index of the class it names,
// reporting the three ways it can be wrong.
//
// Resolved here rather than at collection for the same reason the operators are: a base
// may be declared later in the file, or in a file that sorts after this one.
fn link_bases(mut p Project) {
	for i, c in p.classes {
		if c.base.len == 0 {
			continue
		}
		owner := class_index(p, c.base)
		if owner < 0 {
			report(mut p, c.origin, astquery.Declaration{
				name: c.name
				line: c.line
				column: c.column
			}, 'error: `${c.name}` inherits `${c.base}`, which is not a class in this project')
			continue
		}
		if owner == i {
			report(mut p, c.origin, astquery.Declaration{
				name: c.name
				line: c.line
				column: c.column
			}, 'error: `${c.name}` cannot inherit from itself')
			continue
		}
		if creates_cycle(p, i, owner) {
			report(mut p, c.origin, astquery.Declaration{
				name: c.name
				line: c.line
				column: c.column
			}, 'error: the inheritance chain through `${c.base}` is a cycle; Python cannot create the type and would fail at import with no message about which class')
			continue
		}
		p.classes[i].base_index = owner
	}
	check_chain_depth(mut p)
	// The list is reordered before anything reads it, so `base_index` is recomputed after
	// the sort rather than carried through it.
	sort_classes(mut p)
	// Filled in a second pass, because a subclass's state needs its base's fields and
	// the base may itself have one. A chain is flattened from the root down, so the
	// layout is the same whatever order the classes were declared in.
	for i in 0 .. p.classes.len {
		p.classes[i].state_fields = flatten_fields(mut p, i)
	}
}

// max_state_chain is the number of generations the runtime can publish.
//
// Duplicated from `vcraft.state_chain_max` rather than imported: `vcraft` binds to
// CPython, and importing it into the generator would pull `Python.h` into a build that has
// no include path for it. The two have to agree, and this is the place to change if the
// runtime's array grows.
const max_state_chain = 8

// check_chain_depth reports a chain deeper than the runtime can publish.
//
// The runtime holds one pointer per generation, in a fixed array, so a chain past its
// length has nowhere to put the top of it. Reported here rather than silently truncated:
// a truncated chain compiles, imports, and then hands a method a nil where it expected an
// ancestor, which is a segfault at some later line with nothing to connect it to this.
fn check_chain_depth(mut p Project) {
	for i, c in p.classes {
		mut depth := 0
		for base := c.base_index; base >= 0; base = p.classes[base].base_index {
			depth++
			if depth > max_state_chain {
				report(mut p, c.origin, astquery.Declaration{
					name: c.name
					line: c.line
					column: c.column
				}, 'error: `${c.name}` inherits ${depth} levels deep; vcraft can publish at most ${max_state_chain}')
				p.classes[i].base_index = -1
				break
			}
		}
	}
}

// link_refs checks that every `@[vc_ref(Name)]` names a class, and drops the field when it
// does not.
//
// Deferred to here for the same reason `link_bases` is: the target may be declared later
// in the file or in a file that sorts after this one, so resolving it while collecting
// would report a forward reference as an error.
//
// A field whose target is missing is dropped rather than left as an unchecked reference.
// Leaving it would compile, and the setter would accept anything, which is a mistake with
// no message rather than one with a diagnostic.
fn link_refs(mut p Project) {
	for i, c in p.classes {
		mut kept := []Field{}
		for f in c.fields {
			if f.ref_target.len > 0 && class_index(p, f.ref_target) < 0 {
				report(mut p, c.origin, astquery.Declaration{
					name:      c.name
					type_name: f.v_type
					line:      field_line_of(p, i, f.name)
					column:    1
				}, 'error: `@[vc_ref(${f.ref_target})] ${c.name}.${f.name}` names `${f.ref_target}`, which is not a class in this project')
				continue
			}
			kept << f
		}
		p.classes[i].fields = kept
	}
}

// field_line_of finds the line a class's field is declared on, for a diagnostic raised
// after the collection pass has moved on.
fn field_line_of(p Project, class_index int, field string) int {
	for line, text in read_lines(p.classes[class_index].origin) {
		if text.trim_space().starts_with(field + ' ') {
			return line + 1
		}
	}
	return p.classes[class_index].line
}

// sort_classes puts every class after the one it inherits.
//
// Not an optimisation but a requirement, and of two separate things:
//
//   - V needs a function declared before the one that calls it. A subclass's generated
//     state constructor calls its base's, and a base's type must already exist when the
//     subclass's `Py_tp_bases` tuple names it.
//   - CPython refuses a type whose base is not ready, and with `Py_tp_bases` it fails at
//     import with a message that names no class of ours.
//
// A declaration order of subclass-first is perfectly ordinary V, so the generator has to
// cope with it rather than report it.
//
// The sort is stable: classes that do not depend on each other keep the order they were
// written in, so a generated file reads in the author's order where it can.
fn sort_classes(mut p Project) {
	mut sorted := []Class{}
	// The index each class had before the sort, carried alongside it. Remapping the old
	// indices is what keeps `link_bases`' decisions intact: a class whose base was
	// rejected has no `base_index` to remap, and resolving the name again here would
	// hand back the very base that was just reported as impossible -- and then walk the
	// chain into itself.
	mut origin := []int{}
	mut done := []bool{}
	size := p.classes.len
	for _ in 0 .. size {
		done << false
	}
	mut placed := 0
	for placed < size {
		mut moved := false
		for i in 0 .. size {
			if done[i] {
				continue
			}
			// A class is ready once its base has been placed. A base that could not be
			// resolved, and so has no `base_index`, is ready by default: the diagnostic
			// has already been reported and the class is left as a root.
			if p.classes[i].base_index >= 0 && !done[p.classes[i].base_index] {
				continue
			}
			sorted << p.classes[i]
			origin << i
			done[i] = true
			placed++
			moved = true
		}
		if !moved {
			// Only a cycle can get here, and `link_bases` has already reported it. The
			// rest is appended in declaration order so the generator produces something
			// the V compiler can complain about rather than looping.
			for i in 0 .. size {
				if !done[i] {
					sorted << p.classes[i]
					origin << i
					done[i] = true
				}
			}
		}
	}
	mut remap := []int{}
	for _ in 0 .. size {
		remap << -1
	}
	for i, old in origin {
		remap[old] = i
	}
	p.classes = sorted
	for i in 0 .. p.classes.len {
		old_base := p.classes[i].base_index
		if old_base < 0 {
			continue
		}
		p.classes[i].base_index = remap[old_base]
	}
}

// flatten_fields returns the fields of the class at `index` and of everything above it,
// each carrying the member path that reaches it inside that class's state block.
//
// The path is what a generated renderer needs: `state.value` for a field of the class
// itself when it has no base, `state.self.limit` for one of its own when it does, and
// `state.base.value` for one it inherited. A chain accumulates `base.self.` per
// generation, because the state of a class with a base holds the base's whole state
// followed by its own struct.
//
// Base fields come first so a repr reads in inheritance order, and so the declared order
// of a subclass does not push the fields it inherited to the end.
fn flatten_fields(mut p Project, index int) []Field {
	if p.classes[index].base_index >= 0 {
		mut out := []Field{}
		for mut f in flatten_fields(mut p, p.classes[index].base_index) {
			// The base's own paths are relative to the base's state block, which is the
			// first field of this one.
			f.path = 'base.' + f.path
			out << f
		}
		for mut f in p.classes[index].fields {
			f.path = 'self.' + f.name
			out << f
		}
		return out
	}
	mut out := []Field{}
	for mut f in p.classes[index].fields {
		f.path = f.name
		out << f
	}
	return out
}

// creates_cycle reports whether following `base_index` from `start` comes back to it.
fn creates_cycle(p Project, start int, initial int) bool {
	mut at := initial
	for _ in 0 .. p.classes.len {
		if at == start {
			return true
		}
		next := p.classes[at].base_index
		if next < 0 {
			return false
		}
		at = next
	}
	// A chain longer than the number of classes cannot be acyclic.
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
	// `@[vc_base(Name)]` names the class this one inherits. The argument is a name and
	// not a flag, so the scan keeps arguments as well as annotation names.
	mut base := ''
	if attr_base in block.attrs {
		base = block.args[attr_base]
		if base.len == 0 {
			report(mut p, path, decl,
				'error: `@[vc_base]` needs the name of the class to inherit, as in `@[vc_base(Base)]`')
			return
		}
	}
	mut c := Class{
		name:      decl.name
		doc:       block.doc
		base:      base
		origin:    path
		line:      decl.line
		column:    decl.column
		qualified: '${p.module}.${decl.name}'
		ctor:      'vcraft_generated__new_${key}'
		size_fn:   'vcraft_generated__sizeof_${key}'
		newstate_fn: 'vcraft_generated__newstate_${key}'
		ctype:     'g_vc_type_${key}'
		dealloc:   'vcraft_generated__dealloc_${key}'
		repr:      'vcraft_generated__repr_${key}'
		richcompare: 'vcraft_generated__richcompare_${key}'
		hash_fn:     'vcraft_generated__hash_${key}'
		key:       key
	}
	c.fields = collect_fields(path, lines, ast, decl.name, mut p, false)
	p.classes << c
}

// find_method_of_struct reports whether a struct declares a method of that name.
//
// The receiver is part of the method node's value, so a `msg` on some other struct in the
// same file would otherwise satisfy the check.
fn find_method_of_struct(ast &flat.FlatAst, struct_name string, method string) bool {
	for raw in ast.file_node_ids {
		if method_in_struct(ast, flat.NodeId(raw), struct_name, method) {
			return true
		}
	}
	return false
}

fn method_in_struct(ast &flat.FlatAst, id flat.NodeId, struct_name string, method string) bool {
	node := ast.node(id)
	if node.kind == .fn_decl {
		receiver, name := split_receiver(node.value)
		if name == method && receiver == struct_name {
			return true
		}
	}
	for child in ast.children_of(node) {
		if method_in_struct(ast, child, struct_name, method) {
			return true
		}
	}
	return false
}

// split_receiver splits a method node's `Receiver.name` into its two parts. A free
// function has no receiver and comes back with an empty one.
fn split_receiver(value string) (string, string) {
	if dot := value.last_index('.') {
		return value[..dot], value[dot + 1..]
	}
	return '', value
}

// collect_fields reads the `@[vc_field]` fields of a class.
//
// A field's annotation is written on the field's own line, so it is read from there
// rather than from the line above, and its type comes from the tree.
//
// `every_field` returns the struct's fields as declared, with no annotation filter and no
// scalar check. The class path wants the exposed ones; the `@[vc_error]` path wants to know
// which field could hold an exception class, and that is a question about the declaration
// rather than about what is exposed. Reading them through one walker keeps the two field
// shapes -- `pub` marker plus type node, or a plain node with both -- handled once.
fn collect_fields(path string, lines []string, ast &flat.FlatAst, struct_name string,
	mut p Project, every_field bool) []Field {
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
	// Only the annotated ones are exposed, and only scalars and references are safe to
	// hold in CPython-owned memory.
	mut exposed := []Field{}
	for _, original in out {
		mut f := original
		if every_field {
			exposed << f
			continue
		}
		block := read_inline(lines, field_line(ast, f.name))
		if attr_field !in block.attrs && attr_ref !in block.attrs {
			continue
		}
		f.doc = block.doc
		if attr_ref in block.attrs {
			f.ref = true
			f.ref_target = block.args[attr_ref]
			if !f.is_pyobj() {
				report(mut p, path, astquery.Declaration{
					name:       f.name
					type_name:  f.v_type
					line:       field_line(ast, f.name)
					column:     1
				}, 'error: `@[vc_ref] ${struct_name}.${f.name}` has type `${f.v_type}`, but a reference field must be a `vcraft.PyObj`: it holds a Python object and a reference count, and vcraft keeps that count itself. Declare it as `@[vc_ref] ${f.name} vcraft.PyObj`')
				continue
			}
			// The target is not resolved here. A class may be declared after this one, or
			// in a file that sorts later, so resolving it during collection would reject
			// every forward reference. `link_refs` does it once the whole project is read.
			exposed << f
			continue
		}
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

// collect_error_type collects a struct annotated `@[vc_error]`.
//
// Reports it and returns false when the annotation is on something that cannot be an
// error type, so the caller can try the ordinary paths and produce the diagnostic they
// would have anyway.
fn collect_error_type(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) bool {
	block := read_above(lines, decl.line)
	if attr_error !in block.attrs {
		return false
	}
	key := decl.name.to_lower()
	for existing in p.errors {
		if existing.name == decl.name {
			report(mut p, path, decl, 'error: `@[vc_error] ${decl.name}` is declared twice')
			return true
		}
	}
	// V's error interface is `msg()` and `code()`, and V rejects a `!T` return whose type
	// does not have both. The message here names the two rather than leaving the reader
	// to work it out from V's own error.
	mut has_msg := false
	mut has_code := false
	for method in ['msg', 'code'] {
		if find_method_of_struct(ast, decl.name, method) {
			if method == 'msg' {
				has_msg = true
			} else {
				has_code = true
			}
		}
	}
	if !has_msg {
		report(mut p, path, decl, 'error: `@[vc_error] ${decl.name}` has no `msg()` method, so it cannot be returned from a `!T` function: the error interface V requires is `msg()` and `code()`')
		return true
	}
	if !has_code {
		report(mut p, path, decl, 'error: `@[vc_error] ${decl.name}` has no `code()` method, so it cannot be returned from a `!T` function: the error interface V requires is `msg()` and `code()`. Return a `vcraft.PyExc` value from it to choose the Python exception')
		return true
	}
	// The exception class travels in one `PyObj` field. More than one and there is no way
	// to tell which is the class, so the raiser is not emitted and the type falls back to
	// naming a builtin exception through `code()`.
	mut excs := []string{}
	for field in collect_fields(path, lines, ast, decl.name, mut p, true) {
		if field.is_pyobj() {
			excs << field.name
		}
	}
	if excs.len > 1 {
		report(mut p, path, decl, 'error: `@[vc_error] ${decl.name}` has ${excs.len} `PyObj` fields (${excs.join(', ')}), so which one holds the Python exception is ambiguous. Keep one, or name the exception from `code()` instead')
		return true
	}
	mut exc_field := ''
	if excs.len == 1 {
		exc_field = excs[0]
	}
	p.errors << ErrorType{
		name:      decl.name
		exc_field: exc_field
		doc:       block.doc
		origin:    path
		line:      decl.line
		raiser:    'vcraft_generated__raise_${key}'
	}
	return true
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
	link_bases(mut p)
	link_refs(mut p)
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
