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
	// Read from the code, not the comments: a comment that mentions `state_at(0)` (an
	// explanation, say) would otherwise force every class to publish, which is the cost
	// the scoping below exists to avoid.
	for line in lines {
		code := if line.contains('//') { line.all_before('//') } else { line }
		if !p.uses_state_at && code.contains('state_at(') {
			p.uses_state_at = true
		}
		if !p.uses_state_at_zero && code.contains('state_at(0)') {
			p.uses_state_at = true
			p.uses_state_at_zero = true
		}
	}
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
				if collect_static_method(path, lines, ast, decl, mut p) {
					continue
				}
				collect_fn(path, lines, ast, decl, mut p)
			}
			.method { collect_method(path, lines, ast, decl, mut p) }
			.const { collect_const(path, lines, decl, mut p) }
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
// receiver (always the first parameter of a method node, whatever its shape:
// `mut c Counter` arrives as `&Counter`, `c &Counter` the same, `c Counter`
// as `Counter`).
fn params_of(ast &flat.FlatAst, id flat.NodeId, is_method bool) []Param {
	node := ast.node(id)
	mut out := []Param{}
	mut receiver_skipped := false
	for child in ast.children_of(node) {
		c := ast.node(child)
		if c.kind != .param {
			continue
		}
		if is_method && !receiver_skipped {
			receiver_skipped = true
			continue
		}
		out << Param{
			name:   c.value
			v_type: c.typ
		}
	}
	return out
}

// build_func fills in the parts of a function that come from the tree.
fn build_func(decl astquery.Declaration, ast &flat.FlatAst, block AttrBlock,
	is_method bool) Func {
	mut f := Func{
		name:          decl.name
		doc:           block.doc
		raw:           attr_raw in block.attrs
		nogil:         attr_nogil in block.attrs
		export_buffer: attr_memoryview in block.attrs
		params:        params_of(ast, find_fn_node(ast, decl.name) or {
			flat.empty_node
		}, is_method)
	}
	defaults := parse_defaults(block.args[attr_defaults] or { '' })
	for name, value in defaults {
		mut found := false
		for mut param in f.params {
			if param.name == name {
				param.default = value
				found = true
			}
		}
		if !found {
			f.unknown_defaults << name
		}
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
// operator_kind returns the operator annotation on a block, or '' when it carries none.
//
// `@[vc_eq]`, `@[vc_hash]`, `@[vc_lt]`, `@[vc_le]`, `@[vc_gt]` and `@[vc_ge]` all stand
// in for `@[vc_method]` on one slot, and each is a free function taking two receivers
// (or, for hash, one), because V allows one receiver per method.
fn operator_kind(block AttrBlock) string {
	if attr_eq in block.attrs {
		return 'eq'
	}
	if attr_hash in block.attrs {
		return 'hash'
	}
	if attr_lt in block.attrs {
		return 'lt'
	}
	if attr_le in block.attrs {
		return 'le'
	}
	if attr_gt in block.attrs {
		return 'gt'
	}
	if attr_ge in block.attrs {
		return 'ge'
	}
	// Forward before reflected: `vc_rshift` is the right-shift operator and `vc_rrshift`
	// its reflected form, so the plain name has to win.
	for s in numeric_slots {
		if 'vc_' + s.name in block.attrs {
			return s.name
		}
	}
	for s in numeric_slots {
		if s.arity == 2 && 'vc_r' + s.name in block.attrs {
			return 'r' + s.name
		}
	}
	return ''
}

// resolve_numeric maps an operator kind to its table entry and whether it is the
// reflected form. A forward name wins over a reflected one, so `rshift` is the forward
// operator and `rrshift` its reflected form rather than the reverse.
fn resolve_numeric(key string) (NumericSlot, bool) {
	for s in numeric_slots {
		if s.name == key {
			return s, false
		}
	}
	for s in numeric_slots {
		if s.arity == 2 && 'r' + s.name == key {
			return s, true
		}
	}
	return NumericSlot{}, false
}

fn is_numeric_kind(key string) bool {
	for s in numeric_slots {
		if s.name == key || (s.arity == 2 && 'r' + s.name == key) {
			return true
		}
	}
	return false
}

// assign_operator sets the class field an operator kind fills, reporting a second one.
//
// The six operators each have one field, and a class with two `@[vc_eq]` functions has no
// way to choose between them, so the second is a diagnostic rather than a silent
// override.
fn assign_operator(mut p Project, owner int, kind string, name string, path string,
	decl astquery.Declaration) {
	existing := match kind {
		'eq' { p.classes[owner].eq_fn }
		'hash' { p.classes[owner].hash_name }
		'lt' { p.classes[owner].lt_fn }
		'le' { p.classes[owner].le_fn }
		'gt' { p.classes[owner].gt_fn }
		'ge' { p.classes[owner].ge_fn }
		else { '' }
	}
	if existing.len > 0 {
		report(mut p, path, decl,
			'error: a class may have only one @[vc_${kind}]; `${existing}` is already the ${kind} operator')
		return
	}
	match kind {
		'eq' { p.classes[owner].eq_fn = name }
		'hash' { p.classes[owner].hash_name = name }
		'lt' { p.classes[owner].lt_fn = name }
		'le' { p.classes[owner].le_fn = name }
		'gt' { p.classes[owner].gt_fn = name }
		'ge' { p.classes[owner].ge_fn = name }
		else {}
	}
}

// assign_numeric validates a numeric operator against its class and records it.
//
// The shape is the whole contract, so it is checked here rather than left to generated C
// that would not compile: the first parameter is the instance, the second is the operand
// (a scalar or another instance of the class), and the result is a number or a new
// instance of the class.
fn assign_numeric(mut p Project, owner int, kind string, handler Func, path string,
	decl astquery.Declaration) {
	slot, _ := resolve_numeric(kind)
	c := p.classes[owner]
	if kind in c.numeric {
		report(mut p, path, decl, 'error: `${c.name}` already has a @[vc_${kind}]; `${c.numeric[kind].name}` is already it')
		return
	}
	if handler.params.len != slot.arity {
		report(mut p, path, decl, 'error: `@[vc_${kind}] ${handler.name}` takes ${handler.params.len} argument(s); the ${slot.name} operator takes ${slot.arity}')
		return
	}
	self_type := '&' + c.name
	if handler.params[0].v_type.trim_space() != self_type {
		report(mut p, path, decl, 'error: `@[vc_${kind}] ${handler.name}` takes `${handler.params[0].v_type}` first; an operator takes `${self_type}`')
		return
	}
	// The operand and result types are spelled out rather than taken from the strategy
	// table: `int`, `u64`, `f64` and `bool` are the widths the converters produce and
	// consume exactly, and a narrower `i64` or `f32` would generate a call the V compiler
	// rejects.
	if slot.arity == 2 {
		operand := handler.params[1].v_type.trim_space()
		if operand != self_type && operand !in numeric_operand_types {
			report(mut p, path, decl, 'error: `@[vc_${kind}] ${handler.name}` takes `${handler.params[1].v_type}` as its operand; use `int`, `u64`, `f64`, `bool` or `${self_type}`')
			return
		}
	}
	ret := handler.v_ret.trim_space()
	if ret != c.name && ret !in numeric_operand_types {
		report(mut p, path, decl, 'error: `@[vc_${kind}] ${handler.name}` returns `${handler.v_ret}`; an operator returns `int`, `u64`, `f64`, `bool` or a `${c.name}`')
		return
	}
	p.classes[owner].numeric[kind] = handler
}

fn collect_operator(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) bool {
	block := read_above(lines, decl.line)
	kind := operator_kind(block)
	if kind.len == 0 {
		return false
	}
	// A numeric operator carries its own signature -- the operand and result types decide
	// how the trampoline marshals -- so the built function travels with it, unlike the
	// fixed calling convention of the comparison operators.
	if is_numeric_kind(kind) {
		if find_fn_node(ast, decl.name) == none {
			report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
			return true
		}
		mut handler := build_func(decl, ast, block, false)
		handler.origin = path
		handler.line = decl.line
		handler.column = decl.column
		owner := find_eq_owner(decl.name, p.classes)
		if owner < 0 {
			p.operators << Operator{
				name:    decl.name
				kind:    kind
				origin:  path
				line:    decl.line
				column:  decl.column
				handler: handler
			}
			return true
		}
		assign_numeric(mut p, owner, kind, handler, path, decl)
		return true
	}
	// The owner is looked up when the function is seen, but a class declared later in
	// the file is not in `p.classes` yet. `link_classes` fills in anything that was
	// still unmatched, which is why the field can be empty here and correct there.
	owner := find_eq_owner(decl.name, p.classes)
	if owner < 0 {
		p.operators << Operator{
			name:   decl.name
			line:   decl.line
			column: decl.column
			origin: path
			kind:   kind
		}
		return true
	}
	if find_fn_node(ast, decl.name) == none {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return true
	}
	assign_operator(mut p, owner, kind, decl.name, path, decl)
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

// link_iterators pairs each class's `@[vc_iter]` with its `@[vc_next]`.
//
// Deferred to here because both halves have to be seen before either means anything:
// an iterator that cannot produce items is a trap, and items without an iterator are
// unreachable, so a half pair is reported rather than emitted. Each half alone would
// compile and then fail at the call -- `iter()` succeeding and `next()` missing, or
// the reverse -- with nothing pointing at the missing annotation.
fn link_iterators(mut p Project) {
	for i, c in p.classes {
		mut iters := []Func{}
		mut nexts := []Func{}
		for m in c.methods {
			if m.is_iter {
				iters << m
			}
			if m.is_next {
				nexts << m
			}
		}
		if iters.len == 0 && nexts.len == 0 {
			continue
		}
		if iters.len == 0 {
			report(mut p, c.origin, astquery.Declaration{
				name:   c.name
				line:   c.line
				column: c.column
			}, 'error: `${c.name}` has `@[vc_next]` but no `@[vc_iter]`: items without an iterator are unreachable from Python')
			continue
		}
		if nexts.len == 0 {
			report(mut p, c.origin, astquery.Declaration{
				name:   c.name
				line:   c.line
				column: c.column
			}, 'error: `${c.name}` has `@[vc_iter]` but no `@[vc_next]`: an iterator that cannot produce items fails at the first `next()`')
			continue
		}
		if iters.len > 1 || nexts.len > 1 {
			report(mut p, c.origin, astquery.Declaration{
				name:   c.name
				line:   c.line
				column: c.column
			}, 'error: `${c.name}` has ${iters.len} `@[vc_iter]` and ${nexts.len} `@[vc_next]`; a type has one iterator and one item source')
			continue
		}
		p.classes[i].iter_fn = 'vcraft_generated__iter_${c.key}'
		p.classes[i].next_fn = 'vcraft_generated__next_${c.key}'
	}
}

// const_kind classifies a `@[vc_const]` literal as `int`, `float`, `bool`, `str`, or `''`
// when it is not a literal the generator can box itself.
//
// A const is read at generation time, not at run time, so only a literal crosses: a
// reference to another const, an expression, or a call has no value to emit.
fn const_kind(value string) string {
	v := value.trim_space()
	if v.len == 0 {
		return ''
	}
	if v == 'true' || v == 'false' {
		return 'bool'
	}
	if v.len >= 2 && (v[0] == `'` || v[0] == `"`) && v[v.len - 1] == v[0] {
		return 'str'
	}
	mut body := v
	if body[0] == `-` || body[0] == `+` {
		body = body[1..]
	}
	if body.len == 0 {
		return ''
	}
	mut is_float := false
	for ch in body {
		if ch == `.` || ch == `e` || ch == `E` {
			is_float = true
			continue
		}
		if ch == `+` || ch == `-` || ch == `_` || ch.is_digit() {
			continue
		}
		// Anything else -- a letter, a bracket, a call -- is not a numeric literal.
		return ''
	}
	return if is_float { 'float' } else { 'int' }
}

// collect_const records a `@[vc_const] pub const NAME = literal`, exposed as a
// module-level Python attribute of the same name.
fn collect_const(path string, lines []string, decl astquery.Declaration, mut p Project) {
	block := read_above(lines, decl.line)
	if attr_const !in block.attrs {
		return
	}
	if decl.line - 1 >= lines.len || decl.line < 1 {
		report(mut p, path, decl, 'error: could not read the value of `@[vc_const] ${decl.name}`')
		return
	}
	src := lines[decl.line - 1]
	eq := src.index('=') or {
		report(mut p, path, decl, 'error: `@[vc_const] ${decl.name}` has no `= value`')
		return
	}
	mut value := src[eq + 1..].trim_space()
	if value.contains('//') {
		value = value.all_before('//').trim_space()
	}
	kind := const_kind(value)
	if kind.len == 0 {
		report(mut p, path, decl, 'error: `@[vc_const] ${decl.name}` must be an int, a float, a bool or a string literal; `${value}` is not one')
		return
	}
	for existing in p.consts {
		if existing.name == decl.name {
			report(mut p, path, decl, 'error: `@[vc_const] ${decl.name}` is declared more than once')
			return
		}
	}
	p.consts << Const{
		name:   decl.name
		value:  value
		kind:   kind
		origin: path
		line:   decl.line
		column: decl.column
	}
}

// link_sequences names the `sq_length`, `sq_item` and `sq_contains` trampolines for the
// methods that fill them, and reports a class that declares one of them twice.
//
// Unlike the iterator pair, each is independent: a class may define `__len__` without
// `__getitem__`, or `__contains__` alone.
fn link_sequences(mut p Project) {
	for i, c in p.classes {
		mut lens := 0
		mut items := 0
		mut contains := 0
		for m in c.methods {
			if m.is_len {
				lens++
			}
			if m.is_getitem {
				items++
			}
			if m.is_contains {
				contains++
			}
		}
		if lens > 1 || items > 1 || contains > 1 {
			report(mut p, c.origin, astquery.Declaration{
				name:   c.name
				line:   c.line
				column: c.column
			}, 'error: `${c.name}` declares more than one @[vc_len], @[vc_getitem] or @[vc_contains]; a type has one of each')
			continue
		}
		if lens == 1 {
			p.classes[i].len_fn = 'vcraft_generated__len_${c.key}'
		}
		if items == 1 {
			p.classes[i].item_fn = 'vcraft_generated__item_${c.key}'
		}
		if contains == 1 {
			p.classes[i].contains_fn = 'vcraft_generated__contains_${c.key}'
		}
	}
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
		decl := astquery.Declaration{
			name:   o.name
			line:   o.line
			column: o.column
		}
		if is_numeric_kind(o.kind) {
			assign_numeric(mut p, owner, o.kind, o.handler, o.origin, decl)
		} else {
			assign_operator(mut p, owner, o.kind, o.name, o.origin, decl)
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
	// `@[vc_eq]` and `@[vc_hash]` stand in for `@[vc_method]` on the two slots they
	// fill. They are separate annotations rather than modifiers because the receiver
	// signature is different -- two receivers for eq, an integer result for hash -- and
	// a user who writes `@[vc_method] @[vc_eq]` would get a method *and* an operator.
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
			'error: `${decl.name}` is annotated @[vc_method] but `${decl.receiver}` is not annotated @[vc_class]')
		return
	}
	if find_fn_node(ast, decl.name) == none {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return
	}
	mut m := build_func(decl, ast, block, true)
	m.origin = path
	m.line = decl.line
	m.column = decl.column
	m.property = attr_property in block.attrs
	m.is_iter = attr_iter in block.attrs
	m.is_next = attr_next in block.attrs
	m.is_len = attr_len in block.attrs
	m.is_getitem = attr_getitem in block.attrs
	m.is_contains = attr_contains in block.attrs
	if [m.is_len, m.is_getitem, m.is_contains].filter(it).len > 1 {
		report(mut p, path, decl,
			'error: `${decl.name}` carries more than one of @[vc_len], @[vc_getitem] and @[vc_contains]; each fills a different slot')
		return
	}
	if (m.is_len || m.is_getitem || m.is_contains) && (m.property || m.is_iter || m.is_next) {
		report(mut p, path, decl,
			'error: `@[vc_len]`, `@[vc_getitem]` and `@[vc_contains]` cannot be combined with @[vc_property], @[vc_iter] or @[vc_next] on `${decl.name}`')
		return
	}
	if m.is_len {
		if m.params.len > 0 {
			report(mut p, path, decl,
				'error: `@[vc_len] ${decl.name}` takes ${m.params.len} argument(s); `__len__` takes none')
			return
		}
		if lookup(m.v_ret) !in [.int, .uint] {
			report(mut p, path, decl,
				'error: `@[vc_len] ${decl.name}` returns `${m.v_ret}`; `__len__` returns an integer')
			return
		}
	}
	if m.is_getitem {
		if m.params.len != 1 {
			report(mut p, path, decl,
				'error: `@[vc_getitem] ${decl.name}` takes ${m.params.len} argument(s); `__getitem__` takes one index')
			return
		}
		if lookup(m.params[0].v_type) !in [.int, .uint] {
			report(mut p, path, decl,
				'error: `@[vc_getitem] ${decl.name}` takes a `${m.params[0].v_type}` index; `__getitem__` takes an integer')
			return
		}
		if m.v_ret == 'void' || lookup(m.v_ret) == .unsupported {
			report(mut p, path, decl,
				'error: `@[vc_getitem] ${decl.name}` returns `${m.v_ret}`, which has no marshalling rule')
			return
		}
	}
	if m.is_contains {
		if m.params.len != 1 {
			report(mut p, path, decl,
				'error: `@[vc_contains] ${decl.name}` takes ${m.params.len} argument(s); `__contains__` takes one item')
			return
		}
		if lookup(m.v_ret) != .bool {
			report(mut p, path, decl,
				'error: `@[vc_contains] ${decl.name}` returns `${m.v_ret}`; `__contains__` returns a bool')
			return
		}
	}
	if (m.is_iter || m.is_next) && m.property {
		report(mut p, path, decl,
			'error: `@[vc_iter]` and `@[vc_next]` are calls, not properties: `${decl.name}` cannot also be `@[vc_property]`')
		return
	}
	if m.is_iter && m.params.len > 0 {
		report(mut p, path, decl,
			'error: `@[vc_iter] ${decl.name}` takes ${m.params.len} argument(s); `__iter__` takes none')
		return
	}
	if m.is_next && m.params.len > 0 {
		report(mut p, path, decl,
			'error: `@[vc_next] ${decl.name}` takes ${m.params.len} argument(s); `__next__` takes none')
		return
	}
	if m.is_iter && ((m.v_ret.len > 0 && m.v_ret != 'void') || m.returns_result) {
		report(mut p, path, decl,
			'error: `@[vc_iter] ${decl.name}` must return nothing; the instance is its own iterator, so the slot returns the instance and a method return would go nowhere')
		return
	}
	if m.is_next && m.v_ret.len > 0 && lookup(m.v_ret) == .unsupported {
		report(mut p, path, decl,
			'error: `@[vc_next] ${decl.name}` returns `${m.v_ret}`, which has no marshalling rule')
		return
	}
	if attr_static in block.attrs {
		report(mut p, path, decl,
			'error: `@[vc_static] ${decl.name}` is on a method with a receiver; a static method is written `fn ${decl.receiver}.${decl.name}(...)` without a receiver')
		return
	}
	if m.property && m.params.len > 0 {
		report(mut p, path, decl,
			'error: `@[vc_property] ${decl.name}` takes ${m.params.len} argument(s); a property getter takes none')
		return
	}
	// Same rule as for functions: an unsupported parameter or return type is a
	// diagnostic here, not a compile error in the generated glue.
	validate(mut p, path, decl, m)
	// The flag is set before the method is appended. V copies a struct on assignment, so
	// a field set afterwards is set on the local and the list keeps a copy without it --
	// which reads as "the annotation was ignored" rather than as a lost assignment.
	p.classes[target].methods << m
}


// collect_static_method records a `@[vc_static]` declaration. V reports a static method
// as a `.fn` whose name is `Receiver@static@name`, so it arrives on the function path
// rather than the method one. Returns true when the declaration was a static method,
// whether or not it was accepted, so the ordinary function path does not then try to
// export `Receiver@static@name`.
fn collect_static_method(path string, lines []string, ast &flat.FlatAst,
	decl astquery.Declaration, mut p Project) bool {
	if !decl.name.contains('@static@') {
		return false
	}
	block := read_above(lines, decl.line)
	is_static := attr_static in block.attrs
	is_class := attr_classmethod in block.attrs
	if !is_static && !is_class {
		// A V static method without the annotation is an ordinary V helper. Take the
		// declaration so it is not exported under its mangled name.
		return true
	}
	if is_static && is_class {
		report(mut p, path, decl,
			'error: `${decl.name}` is annotated both @[vc_static] and @[vc_classmethod]; choose one')
		return true
	}
	parts := decl.name.split('@static@')
	if parts.len != 2 || parts[0].len == 0 || parts[1].len == 0 {
		report(mut p, path, decl, 'error: could not read the receiver and name of `@[vc_static] ${decl.name}`')
		return true
	}
	receiver := parts[0]
	name := parts[1]
	mut target := -1
	for i, c in p.classes {
		if c.name == receiver {
			target = i
			break
		}
	}
	if target < 0 {
		report(mut p, path, decl,
			'error: `${decl.name}` is annotated @[vc_static] but `${receiver}` is not annotated @[vc_class]')
		return true
	}
	if attr_raw in block.attrs {
		report(mut p, path, decl,
			'error: `@[vc_static]` and `@[vc_raw]` cannot be combined on `${decl.name}`; a static method uses the ordinary marshalling rules')
		return true
	}
	node := find_fn_node(ast, decl.name) or {
		report(mut p, path, decl, 'error: could not read the signature of `${decl.name}`')
		return true
	}
	mut m := Func{
		name:            name
		doc:             block.doc
		static:          is_static
		classmethod:     is_class
		static_receiver: receiver
		export_buffer:   attr_memoryview in block.attrs
		params:          params_of(ast, node, false)
	}
	defaults := parse_defaults(block.args[attr_defaults] or { '' })
	for dname, value in defaults {
		mut found := false
		for mut param in m.params {
			if param.name == dname {
				param.default = value
				found = true
			}
		}
		if !found {
			m.unknown_defaults << dname
		}
	}
	m.v_ret, m.returns_result = split_result(decl.type_name)
	m.trampoline = 'vcraft_generated__static_${receiver.to_lower()}_${name}'
	m.origin = path
	m.line = decl.line
	m.column = decl.column
	validate(mut p, path, decl, m)
	p.classes[target].methods << m
	return true
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
		line := field_line(ast, f.name)
		// V also accepts an attribute on the line above a declaration, so people write a
		// field annotation there and it is silently dropped: a field's own line is the
		// only place `read_inline` looks. Warn rather than let the field vanish.
		stray := stray_field_annotation(lines, line)
		if stray.len > 0 {
			report(mut p, path, astquery.Declaration{
				name:      f.name
				type_name: f.v_type
				line:      line
				column:    1
			}, 'warning: `@[${stray}]` on the line above `${struct_name}.${f.name}` is ignored; a field annotation goes on the field\'s own line')
		}
		block := read_inline(lines, line)
		if attr_field !in block.attrs && attr_ref !in block.attrs && attr_buffer !in block.attrs
			&& attr_buffer_typed !in block.attrs {
			continue
		}
		f.doc = block.doc
		if attr_buffer_typed in block.attrs && attr_buffer !in block.attrs {
			report(mut p, path, astquery.Declaration{
				name:      f.name
				type_name: f.v_type
				line:      field_line(ast, f.name)
				column:    1
			}, 'error: `@[vc_buffer_typed] ${struct_name}.${f.name}` needs a `@[vc_buffer]` on the same field: it only chooses how that buffer is reported, and there is no buffer here')
			continue
		}
		if attr_buffer in block.attrs {
			// A buffer is a slice of scalars. A slice of anything else would be a pointer
			// V's collector cannot follow into CPython-owned memory, which is the case
			// the buffer exists to avoid, so it is refused with the element named.
			if !f.v_type.trim_space().starts_with('[]') {
				report(mut p, path, astquery.Declaration{
					name:      f.name
					type_name: f.v_type
					line:      field_line(ast, f.name)
					column:    1
				}, 'error: `@[vc_buffer] ${struct_name}.${f.name}` has type `${f.v_type}`, but a native buffer must be a slice: declare it `[]int`, `[]f64` or another slice of a scalar')
				continue
			}
			element := element_type(f.v_type)
			if !is_scalar_type(element) {
				report(mut p, path, astquery.Declaration{
					name:      f.name
					type_name: f.v_type
					line:      field_line(ast, f.name)
					column:    1
				}, 'error: `@[vc_buffer] ${struct_name}.${f.name}` holds `${element}`, which has no native buffer rule; a buffer holds bool, integers or floats')
				continue
			}
			f.buffer = true
			f.buffer_typed = attr_buffer_typed in block.attrs
			exposed << f
			continue
		}
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

// stray_field_annotation returns the field annotation sitting on the line above a field,
// when that line holds nothing but annotation blocks.
//
// A field annotation belongs on the field's own line -- `@[vc_field] value int` -- which
// is the only line `read_inline` reads. V accepts an attribute on the line above, so a
// reader writes it there and the field is quietly left unexposed; this finds that case so
// the collector can warn. A line that carries a field after its annotation is a previous
// field, not an annotation block, and returns nothing.
fn stray_field_annotation(lines []string, line int) string {
	if line < 2 || line > lines.len {
		return ''
	}
	text := lines[line - 2].trim_space()
	if !annotation_only(text) {
		return ''
	}
	for name in parse_attr_names(text) {
		canonical := canonical_attr(name)
		if canonical in [attr_field, attr_ref, attr_buffer, attr_buffer_typed] {
			return canonical
		}
	}
	return ''
}

// annotation_only reports whether a line is one or more `@[...]` blocks and nothing else.
fn annotation_only(text string) bool {
	mut i := 0
	mut seen := false
	for i < text.len {
		if text[i] == ` ` || text[i] == `\t` {
			i++
			continue
		}
		if text[i] != `@` || i + 1 >= text.len || text[i + 1] != `[` {
			return false
		}
		i += 2
		mut depth := 1
		for i < text.len && depth > 0 {
			if text[i] == `[` {
				depth++
			} else if text[i] == `]` {
				depth--
			}
			i++
		}
		if depth != 0 {
			return false
		}
		seen = true
	}
	return seen
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
	link_iterators(mut p)
	link_sequences(mut p)
	mut ctors := []string{}
	for i, c in p.classes {
		// A constructor is named after its class, and V snake-cases a multi-word type, so
		// `TallyBuffer` is built by `new_tally_buffer`. Matching with the underscores
		// removed accepts both spellings rather than guessing which one the user wrote.
		wanted := ('new_' + c.name).to_lower().replace('_', '')
		for f in p.funcs {
			if f.name.to_lower().replace('_', '') == wanted {
				p.classes[i].ctor_fn = f.name
				p.classes[i].ctor_params = f.params
				ctors << f.name
			}
		}
	}
	// A subclass's state is built base first, so the base's constructor parameters have
	// to arrive through the subclass's `tp_new` and be forwarded. The subclass's full
	// parameter list is therefore the base's followed by its own, and `newstate` splits
	// it again: the leading `base_ctor_count` go to the base's state constructor, the
	// rest to the class's own. `p.classes` is sorted base first, so the base's list is
	// already known here.
	for i, c in p.classes {
		mut params := []Param{}
		if c.base_index >= 0 {
			params << p.classes[c.base_index].newstate_params
		}
		base_count := params.len
		// The one Python signature carries the base's parameters and the subclass's, so a
		// name used on both sides would be two parameters of the same name: untypeable in
		// the stub and ambiguous for a keyword call. The collision is the user's to fix.
		for param in c.ctor_params {
			if param.name in params.map(it.name) {
				report(mut p, c.origin, astquery.Declaration{
					name:   c.name
					line:   c.line
					column: c.column
				}, 'error: `${c.name}` and its base `${p.classes[c.base_index].name}` both name a constructor parameter `${param.name}`, and the one Python signature `${c.name}()` binds carries both: give them distinct names')
			}
		}
		params << c.ctor_params
		p.classes[i].base_ctor_count = base_count
		p.classes[i].newstate_params = params
	}
	// Last, because it needs every class known and sorted: `&T` parameters and results
	// carry a layout offset computed from `T`'s ancestors, which only exists once
	// `link_bases` has resolved the chain.
	link_instances(mut p, ctors)
	if ctors.len == 0 {
		return
	}
	link_iterators(mut p)
	// A `new_X` function is the class's `tp_new`, not a module-level callable. It
	// returns `&X`, which has no marshalling rule of its own, so that one diagnostic is
	// dropped. A diagnostic about its parameters is kept: those are the user's to fix.
	p.funcs = p.funcs.filter(it.name !in ctors)
	mut kept := []Diagnostic{}
	for d in p.diagnostics {
		mut skip := false
		for ctor in ctors {
			if d.message.contains('`' + ctor + '`') && d.message.contains('return type') {
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

// link_instances resolves every `&T` parameter and result to the class it names.
//
// A `&T` parameter is an instance reference: the wrapper checks the argument is an
// instance of `T` and hands the V function a pointer into its state. A `&T` result hands
// back the instance the pointer points into, matched against the receiver and the
// instance arguments of the call. Both need `T` to be a class, and the layout offset of
// `T`'s struct inside the state block, so this runs once every class is known.
//
// `ctors` are the `new_*` functions, which `link_classes` will drop from `p.funcs`.
// Their `&Class` result is not an instance result to resolve -- the constructor's own
// trampoline handles it -- but their parameters still go through `param_reader`, so a
// constructor can take an instance of another class.
fn link_instances(mut p Project, ctors []string) {
	for i in 0 .. p.funcs.len {
		mut f := p.funcs[i]
		link_instance_params(mut p, mut f)
		link_instance_result(mut p, mut f, false, f.name in ctors)
		p.funcs[i] = f
	}
	for i in 0 .. p.classes.len {
		c := p.classes[i]
		for j in 0 .. c.methods.len {
			mut m := c.methods[j]
			link_instance_params(mut p, mut m)
			link_instance_result(mut p, mut m, !m.static, false)
			p.classes[i].methods[j] = m
		}
		p.classes[i].ctor_params = link_instance_param_list(mut p, c.ctor_params, c.name,
			c.origin, c.line, c.column)
		p.classes[i].newstate_params = link_instance_param_list(mut p, c.newstate_params,
			c.name, c.origin, c.line, c.column)
	}
}

// link_instance_params resolves the instance references in one function's parameters.
fn link_instance_params(mut p Project, mut f Func) {
	f.params = link_instance_param_list(mut p, f.params, f.name, f.origin, f.line, f.column)
}

// link_instance_param_list resolves a parameter list, reporting each `&T` that does not
// name a class against the declaration it came from.
fn link_instance_param_list(mut p Project, params []Param, func_name string, origin string,
	line int, column int) []Param {
	mut out := params.clone()
	for i in 0 .. out.len {
		target := pointer_target(out[i].v_type)
		if target.len == 0 {
			continue
		}
		ci := class_index(p, target)
		if ci < 0 {
			report(mut p, origin, astquery.Declaration{
				name:   func_name
				line:   line
				column: column
			}, 'error: cannot expose `${func_name}`: parameter `${out[i].name}` is `${out[i].v_type}`, but `${target}` is not a class')
			continue
		}
		handle, offset := instance_layout(p, ci)
		out[i].instance_target = target
		out[i].instance_handle = handle
		out[i].instance_offset = offset
	}
	return out
}

// link_instance_result resolves a `&T` result. `has_receiver` is true for a method, whose
// receiver is always a candidate for the pointer; `is_ctor` marks the `new_*` functions,
// whose `&Class` result the constructor trampoline handles separately.
fn link_instance_result(mut p Project, mut f Func, has_receiver bool, is_ctor bool) {
	if is_ctor {
		return
	}
	target := pointer_target(f.v_ret)
	if target.len == 0 {
		return
	}
	ci := class_index(p, target)
	if ci < 0 {
		report(mut p, f.origin, astquery.Declaration{
			name:   f.name
			line:   f.line
			column: f.column
		}, 'error: cannot expose `${f.name}`: return type `${f.v_ret}` names `${target}`, which is not a class')
		return
	}
	handle, offset := instance_layout(p, ci)
	f.instance_result = target
	f.instance_result_handle = handle
	f.instance_result_offset = offset
	if !has_receiver && !f.params.any(it.instance_target.len > 0) {
		report(mut p, f.origin, astquery.Declaration{
			name:   f.name
			line:   f.line
			column: f.column
		}, 'error: cannot expose `${f.name}`: return type `${f.v_ret}` is an instance reference, but the call receives no instance it could point into; add an instance parameter or make it a method')
	}
}

// instance_layout returns the V expression for a class's type object and the expression
// for where its struct starts inside the state block.
//
// The state nests: `SubState` is `{ base <base's state>; self <Sub> }`, so the class's own
// struct sits exactly one base-state after the start. The offset is therefore the
// immediate base's size, or zero for a class with no base. It does not matter what class
// the instance really is: a subclass's `base` field is typed as this class's state, so the
// struct is at the same offset in every instance this class accepts.
//
// The size is the base's generated `sizeof_*` helper, so the offset is arithmetic the
// compiler emits rather than a read of `tp_basicsize`, which the limited API hides.
fn instance_layout(p Project, ci int) (string, string) {
	c := p.classes[ci]
	offset := if c.base_index >= 0 { p.classes[c.base_index].size_fn + '()' } else { '0' }
	return 'g_vc_type_${c.key}.ptr', offset
}

fn report(mut p Project, path string, decl astquery.Declaration, message string) {
	p.diagnostics << Diagnostic{
		file:    path
		line:    decl.line
		column:  decl.column
		message: message
	}
}

// parse_defaults splits `step=1, name="a, b"` into its pairs. Commas and `=` inside a
// quoted value belong to the value.
pub fn parse_defaults(text string) map[string]string {
	mut out := map[string]string{}
	mut parts := []string{}
	mut current := []u8{}
	mut quote := u8(0)
	for ch in text.bytes() {
		if quote != 0 {
			current << ch
			if ch == quote {
				quote = 0
			}
		} else if ch == `"` || ch == `'` {
			quote = ch
			current << ch
		} else if ch == `,` {
			parts << current.bytestr()
			current = []u8{}
		} else {
			current << ch
		}
	}
	parts << current.bytestr()
	for part in parts {
		eq := part.index('=') or { continue }
		name := part[..eq].trim_space()
		if name.len > 0 {
			out[name] = part[eq + 1..].trim_space()
		}
	}
	return out
}

// default_fits reports whether a default written in `@[vc_defaults]` is a literal of
// the parameter's kind: a quoted string for a str, true or false for a bool, a whole
// number for an integer (not negative for an unsigned one), and a number for a float.
pub fn default_fits(strategy Strategy, value string) bool {
	v := value.trim_space()
	if v.len == 0 {
		return false
	}
	is_int := (v[0] == `-` && v.len > 1 && v[1..].bytes().all(it.is_digit())) || v.bytes().all(it.is_digit())
	return match strategy {
		.str { v.len >= 2 && (v[0] == `"` || v[0] == `'`) && v[v.len - 1] == v[0] }
		.bool { v in ['true', 'false'] }
		.int { is_int }
		.uint { is_int && v[0] != `-` }
		.float { is_int || v.f64() != 0.0 || v in ['0.0', '0.', '.0'] }
		else { false }
	}
}

// validate rejects a declaration the generator cannot honour, with a position.
fn validate(mut p Project, path string, decl astquery.Declaration, f Func) {
	for name in f.unknown_defaults {
		report(mut p, path, decl,
			'error: `@[vc_defaults]` on `${decl.name}` names `${name}`, which is not one of its parameters')
		return
	}
	for param in f.params {
		if param.default.len == 0 {
			continue
		}
		if pointer_target(param.v_type).len > 0 {
			report(mut p, path, decl,
				'error: `@[vc_defaults]` on `${decl.name}` gives `${param.name}` a default, but a `${param.v_type}` instance reference must come from the caller')
			return
		}
		strategy := lookup(param.v_type)
		if strategy == .optional {
			report(mut p, path, decl,
				'error: `@[vc_defaults]` on `${decl.name}` gives `${param.name}` a default, but `${param.v_type}` already defaults to None')
			return
		}
		if strategy !in [.bool, .int, .uint, .float, .str] {
			report(mut p, path, decl,
				'error: `@[vc_defaults]` on `${decl.name}`: `${param.name}` has type `${param.v_type}`; defaults are for bool, integer, float and string parameters')
			return
		}
		if !default_fits(strategy, param.default) {
			report(mut p, path, decl,
				'error: `@[vc_defaults]` on `${decl.name}`: `${param.default}` is not a `${param.v_type}` default for `${param.name}`')
			return
		}
	}
	for param in f.params {
		// A `&T` is resolved later, once every class is known: whether `T` names a class
		// cannot be decided here.
		if pointer_target(param.v_type).len > 0 {
			continue
		}
		if lookup(param.v_type) == .unsupported {
			report(mut p, path, decl,
				'error: cannot expose `${decl.name}`: type `${param.v_type}` of parameter `${param.name}` has no marshalling rule')
			return
		}
		// A multi-value type exists in V only as a result: a function cannot take one,
		// and a Python tuple has no V parameter type to land in.
		if lookup(param.v_type) == .tuple {
			report(mut p, path, decl,
				'error: cannot expose `${decl.name}`: parameter `${param.name}` has the multi-value type `${param.v_type}`, which V only allows as a result')
			return
		}
		// A fixed-size array is read as the slice of its element, so the element needs
		// a sequence reader, as for `[]T`.
		if lookup(param.v_type) == .fixed && !element_is_readable(fixed_element(param.v_type)) {
			report(mut p, path, decl,
				'error: cannot expose `${decl.name}`: type `${param.v_type}` of parameter `${param.name}` holds `${fixed_element(param.v_type)}`, which has no sequence reader')
			return
		}
		// A `[]T` parameter reads each element, so the element needs a reader of
		// its own. Without one the glue names a function that does not exist,
		// and the error points at the generated file instead of here.
		if lookup(param.v_type) == .seq &&
			!element_is_readable(element_type(param.v_type)) {
			report(mut p, path, decl,
				'error: cannot expose `${decl.name}`: type `${param.v_type}` of parameter `${param.name}` holds `${element_type(param.v_type)}`, which has no sequence reader; a sequence holds bool, integers, floats or strings')
			return
		}
	}
	// `@[vc_nogil]` promises the call touches no Python, and `@[vc_raw]` promises the
	// opposite: the function handles `PyObject *` itself. Both together would release
	// the GIL around code that reads the objects it was given, which corrupts the
	// interpreter rather than failing loudly, so the combination is refused here where
	// the message can name both annotations.
	if f.nogil && f.raw {
		report(mut p, path, decl,
			'error: `@[vc_nogil]` on `${decl.name}` contradicts `@[vc_raw]`: raw means the function handles `PyObject *` itself, and touching one without the GIL corrupts the interpreter')
		return
	}
	if f.raw && f.export_buffer {
		report(mut p, path, decl,
			'error: `@[vc_memoryview]` on `${decl.name}` contradicts `@[vc_raw]`: a raw function returns a `voidptr` the wrapper does not marshal')
		return
	}
	if f.raw {
		return
	}
	// A `@[vc_memoryview]` result is a slice of a buffer scalar: it becomes a writable
	// `memoryview` over native-backed memory, so the element needs a buffer rule and the
	// result needs to be a slice. Anything else has no view format to carry.
	if f.export_buffer {
		strategy := lookup(f.v_ret)
		if strategy !in [.seq, .bytes] {
			report(mut p, path, decl,
				'error: `@[vc_memoryview]` on `${decl.name}` needs a `[]T` result of a buffer scalar, but it returns `${f.v_ret}`')
			return
		}
		if !is_scalar_type(element_type(f.v_ret)) {
			report(mut p, path, decl,
				'error: `@[vc_memoryview]` on `${decl.name}`: `${element_type(f.v_ret)}` has no native buffer rule; a buffer holds bool, integers or floats')
			return
		}
	}
	if f.v_ret.len > 0 && pointer_target(f.v_ret).len == 0 && lookup(f.v_ret) == .unsupported {
		report(mut p, path, decl,
			'error: cannot expose `${decl.name}`: return type `${f.v_ret}` has no marshalling rule')
		return
	}
	// A returned `[]T` boxes each element, so the element needs a rule of its own. A
	// slice of structs or of slices would otherwise generate glue that does not
	// compile, and the error would point at the generated file instead of here.
	if lookup(f.v_ret) == .seq && !element_is_boxable(element_type(f.v_ret)) {
		report(mut p, path, decl,
			'error: cannot expose `${decl.name}`: return type `${f.v_ret}` has elements of type `${element_type(f.v_ret)}`, which have no marshalling rule; a returned list holds bool, integers, floats or strings')
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
			// `vc_`, the prefix every annotation has. This compared against `vc.`, which
			// none has, so a misspelt annotation was never reported and the declaration
			// it was on was silently left out of the module.
			if !name.starts_with('vc_') {
				continue
			}
			if name in deprecated_attrs {
				p.diagnostics << Diagnostic{
					file:    path
					line:    i + 1
					column:  indent + 1
					message: 'warning: `@[${name}]` is deprecated and goes in vcraft 2.0; write `@[${deprecated_attrs[name]}]`'
				}
			} else if name !in known_attrs {
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
