module vcraft_codegen

// Emitting classes.
//
// A class is four things: a heap type, a `tp_new` that allocates the state block,
// accessors that work on that block in place, and a `tp_dealloc` that releases it.
//
// A method receives a pointer to the block, so it writes the instance directly, as a
// PyO3 method writes its cell. A method that panics halfway leaves the fields it had
// already written:
//
//	fn vcraft_generated__method_Counter_increment(self voidptr, args voidptr, nargs isize) voidptr {
//		if nargs != 1 { vcraft.wrong_nargs('increment', 1, int(nargs)) return unsafe { nil } }
//		arg0 := vcraft.from_py_int_arg(args, 0, 'increment', 'by') or { return unsafe { nil } }
//		mut state := unsafe { &Counter(vcraft.instance_storage(self)) }
//		if isnil(state) { vcraft.raise_runtime_error('Counter instance has no state') return unsafe { nil } }
//		defer {
//			if message := recover() { vcraft.raise_runtime_error('panic in V code: ${message}') }
//		}
//		state.increment(arg0)
//		if vcraft.error_is_set() { return unsafe { nil } }
//		return vcraft.to_py_none().ptr
//	}

import strings as _

// emit_class renders one class: its size helper, its tables and its accessors.
fn emit_class(p Project, c Class) string {
	mut w := new_builder()
	w.write_string('\n// ---- ${c.name}\n\n')
	if c.base_index >= 0 {
		w.write_string(emit_class_state_struct(p, c))
	}
	w.write_string('fn ${c.size_fn}() usize {\n')
	w.write_string('\tunsafe { return sizeof(' + c.state_type() + ') }\n')
	w.write_string('}\n\n')
	w.write_string(emit_class_newstate(p, c))
	w.write_string(emit_class_getsets(c))
	w.write_string(emit_class_methods(c))
	w.write_string(emit_field_accessors(p, c))
	w.write_string(emit_class_new(c))
	w.write_string(emit_class_iterators(p, c))
	w.write_string(emit_class_traverse(p, c))
	w.write_string(emit_class_clear(p, c))
	w.write_string(emit_class_dealloc(p, c))
	w.write_string(emit_class_repr(p, c))
	w.write_string(emit_class_richcompare(c))
	w.write_string(emit_class_hash(c))
	return w.str()
}

// doc_pointer renders a `.ptr` for a docstring field of a static table, or null when
// there is no docstring. A null doc is different from an empty one: CPython leaves
// `__doc__` absent rather than set to "".
pub fn doc_pointer(doc string) string {
	if doc.len == 0 {
		return 'unsafe { nil }'
	}
	return 'voidptr(c' + vstring_literal(doc) + ')'
}

// emit_class_getsets renders the property table: one entry per field and per
// property method.
fn emit_class_getsets(c Class) string {
	mut count := c.fields.len
	for m in c.methods {
		if m.property {
			count++
		}
	}
	if count == 0 {
		return ''
	}
	mut w := new_builder()
	w.write_string('__global (\n')
	w.write_string('\tg_vc_getsets_${c.key} = [\n')
	for f in c.fields {
		w.write_string('\t\tvcraft.PyGetSetDef{\n')
		w.write_string("\t\t\tname:    voidptr(c'${f.name}')\n")
		w.write_string("\t\t\tget:     voidptr(vcraft_generated__get_${c.key}_${f.name})\n")
		w.write_string("\t\t\tset:     voidptr(vcraft_generated__set_${c.key}_${f.name})\n")
		w.write_string('\t\t\tdoc:     ' + doc_pointer(f.doc) + '\n')
		w.write_string('\t\t\tclosure: unsafe { nil }\n')
		w.write_string('\t\t},\n')
	}
	for m in c.methods {
		if !m.property {
			continue
		}
		w.write_string('\t\tvcraft.PyGetSetDef{\n')
		w.write_string("\t\t\tname:    voidptr(c'${m.name}')\n")
		w.write_string("\t\t\tget:     voidptr(${m.trampoline})\n")
		w.write_string('\t\t\tset:     unsafe { nil }\n')
		w.write_string('\t\t\tdoc:     ' + doc_pointer(m.doc) + '\n')
		w.write_string('\t\t\tclosure: unsafe { nil }\n')
		w.write_string('\t\t},\n')
	}
	w.write_string('\t\tvcraft.PyGetSetDef{},\n')
	w.write_string('\t]\n')
	w.write_string(')\n\n')
	return w.str()
}

// emit_field_accessors renders a getter and a setter per exposed field.
//
// An exposed field is always read/write. The flat AST does not record whether a field
// sits in a `mut:` section, so the emitter cannot honour immutability, and the useful
// default is what Python expects of an attribute.
fn emit_field_accessors(p Project, c Class) string {
	if c.fields.len == 0 {
		return ''
	}
	mut w := new_builder()
	for f in c.fields {
		w.write_string('fn vcraft_generated__get_${c.key}_${f.name}(self voidptr, closure voidptr) voidptr {\n')
		w.write_string(emit_state_pointer(c, no_state_exit(c, 'unsafe { nil }')))
		w.write_string(emit_enter_state(p, c))
		if f.is_reference() {
			// A new reference, because CPython steals whatever a getter returns and the
			// instance keeps the one it already has. Returning the borrowed pointer
			// instead would leave the caller holding a reference nobody counted, and the
			// object would be freed while Python still had it.
			// A reference field holds null when it was never set or was set to None, and
			// null is not an object: returning it would hand CPython a null from a getter
			// with no exception set, which it reports as "error return without exception
			// set". None is what Python prints for an attribute holding nothing, so None is
			// what an unset field reads as.
			w.write_string('\tif vcraft.is_null(state.' + c.field_access(f.name) +
				') {\n')
			w.write_string('\t\treturn vcraft.to_py_none().ptr\n\t}\n')
			w.write_string('\treturn vcraft.incref(state.' + c.field_access(f.name) +
				').ptr\n')
			w.write_string('}\n\n')
			w.write_string('fn vcraft_generated__set_${c.key}_${f.name}(self voidptr, value voidptr) int {\n')
			w.write_string('\tif value == unsafe { nil } {\n')
			w.write_string("\t\tvcraft.raise_attribute_error('${c.name}.${f.name} cannot be deleted')\n")
			w.write_string('\t\treturn -1\n\t}\n')
			w.write_string(emit_ref_type_check(p, c, f))
			w.write_string(emit_state_pointer(c, no_state_exit(c, '-1')))
			w.write_string(emit_enter_state(p, c))
			// `value` is the reference CPython handed over and this setter now owns.
			// `set_ref` releases whatever the field held, so assigning over a field does
			// not leak and assigning the same object to it does not release it twice.
			w.write_string('\tvcraft.set_ref(unsafe { voidptr(&state.' +
				c.field_access(f.name) + ')}, vcraft.none_or_null(value))\n')
			w.write_string('\treturn 0\n')
			w.write_string('}\n\n')
			continue
		}
		w.write_string('\treturn ' + boxed_expr(lookup(f.v_type), 'state.' +
			c.field_access(f.name)) + '.ptr\n')
		w.write_string('}\n\n')
		// The converted value is written through the field's address rather than
		// assigned, because assigning would need the field itself to be `mut`, and a
		// plain `@[vc_field]` does not have to be.
		conv := unbox_expr(lookup(f.v_type), 'value', f.v_type)
		// No `mut` on the parameters: V wraps a C callback whose parameters are `mut`,
		// and the wrapper shifts the incoming arguments.
		//
		// The return type is `int` rather than `voidptr` because CPython reads it as
		// one. A null pointer is 0, which means "the assignment succeeded", so a
		// rejected value would be silently accepted with an exception left set.
		w.write_string('fn vcraft_generated__set_${c.key}_${f.name}(self voidptr, value voidptr) int {\n')
		// CPython passes a null value to delete an attribute.
		w.write_string('\tif value == unsafe { nil } {\n')
		w.write_string("\t\tvcraft.raise_attribute_error('${c.name}.${f.name} cannot be deleted')\n")
		w.write_string('\t\treturn -1\n\t}\n')
		// The converter has already raised, naming the type it got. Raising a second
		// error here would leave two set at once, which CPython later reports as an
		// unrelated SystemError.
		w.write_string('\tmut field := ' + conv + ' or { return -1 }\n')
		w.write_string(emit_state_pointer(c, no_state_exit(c, '-1')))
		w.write_string(emit_enter_state(p, c))
		// Only the field is copied, so the size is the field's, not the struct's.
		w.write_string('\tvcraft.set_state(unsafe { voidptr(&state.' +
			c.field_access(f.name) + ')}, ' +
			'unsafe { voidptr(&field) }, sizeof(${f.v_type}))\n')
		w.write_string('\treturn 0\n')
		w.write_string('}\n\n')
	}
	return w.str()
}

// ref_fields returns every reference field an instance of the class holds, its own and
// its bases'.
//
// The flattened list rather than the class's own fields, because the state block is the
// base's state followed by the class's own struct: an inherited reference is in there and
// has to be reported to the collector or a cycle through the base is never broken.
pub fn (c Class) ref_fields() []Field {
	return c.state_fields.filter(it.ref)
}

// emit_ref_type_check renders the guard a reference setter runs on its argument.
//
// Without a target any object is accepted, so the check is left out entirely rather than
// emitted as a test that cannot fail. A target means the assignment is checked the way a
// typed attribute is, and the message names the class the caller should have used.
fn emit_ref_type_check(p Project, c Class, f Field) string {
	if f.ref_target.len == 0 {
		return ''
	}
	target := class_index(p, f.ref_target)
	if target < 0 {
		// Reported by the collector, which runs first. Emitting a reference to a type
		// handle that was never created would be a compile error instead of the
		// diagnostic.
		return ''
	}
	mut w := new_builder()
	// `.ptr`, like every other place a type handle reaches the runtime: `g_vc_type_x` is
	// a `PyObj`, and handing one where a `voidptr` is expected relies on V dereferencing
	// the single-field struct.
	w.write_string('\tif !vcraft.ref_target_ok(value, ' + p.classes[target].ctype +
		'.ptr) {\n')
	w.write_string('\t\tvcraft.raise_type_error(')
	w.write_string(vstring_literal('${c.name}.${f.name} must be a ${f.ref_target}, not '))
	w.write_string(' + vcraft.type_name_of(value))\n')
	w.write_string('\t\treturn -1\n\t}\n')
	return w.str()
}

// emit_class_methods renders the method table of the ordinary methods.
fn emit_class_methods(c Class) string {
	ordinary := c.methods.filter(it.property == false)
	if ordinary.len == 0 {
		return ''
	}
	mut w := new_builder()
	w.write_string('__global (\n')
	w.write_string('\tg_vc_methods_${c.key} = [\n')
	for m in ordinary {
		w.write_string('\t\tvcraft.PyMethodDef{\n')
		w.write_string("\t\t\tname:  voidptr(c'${m.name}')\n")
		w.write_string("\t\t\tmeth:  voidptr(${m.trampoline})\n")
		w.write_string('\t\t\tflags: ${method_flags(m)}\n')
		w.write_string('\t\t\tdoc:   ' + doc_pointer(m.doc) + '\n')
		w.write_string('\t\t},\n')
	}
	w.write_string('\t\tvcraft.PyMethodDef{},\n')
	w.write_string('\t]\n')
	w.write_string(')\n\n')
	return w.str()
}

fn method_flags(m Func) string {
	return if m.params.len == 0 { 'vcraft.meth_noargs' } else { 'vcraft.meth_fastcall' }
}

// emit_class_new renders `tp_new`.
//
// The first argument CPython passes is the type, so the instance is allocated here
// with tp_alloc. Storing the state without allocating first writes over the type
// object and makes `Class()` hand back the class itself.
// emit_iter_trampoline renders `tp_iter`.
//
// The instance is its own iterator, so the slot returns the instance itself: a new
// reference, because CPython steals whatever a slot returns and the instance keeps the
// one it already has. The user's `@[vc_iter]` method runs first, for its side effects --
// resetting a cursor, for example -- and its return value is ignored, which is why the
// collector refuses a method that declares one.
//
// The state is written back like in an ordinary method: an `__iter__` that mutates is
// the normal case, not the exception.
fn emit_iter_trampoline(p Project, c Class, f Func) string {
	mut w := new_builder()
	w.write_string('fn ${c.iter_fn}(self voidptr) voidptr {\n')
	w.write_string(emit_state_pointer(c, no_state_exit(c, 'unsafe { nil }')))
	w.write_string(emit_enter_state(p, c))
	if f.nogil {
		w.write_string(emit_nogil_open())
	} else {
		w.write_string('\tdefer {\n')
		w.write_string('\t\tif message := recover() {\n')
		w.write_string("\t\t\tvcraft.raise_runtime_error('panic in V code: \${message}')\n")
		w.write_string('\t\t}\n')
		w.write_string('\t}\n')
	}
	w.write_string('\tstate.' + c.self_access() + '${f.name}()\n')
	if f.nogil {
		w.write_string(emit_nogil_close())
	}
	w.write_string('\tif vcraft.error_is_set() {\n\t\treturn unsafe { nil }\n\t}\n')
	w.write_string('\treturn vcraft.incref(vcraft.borrow(self)).ptr\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_next_trampoline renders `tp_iternext`.
//
// One call produces one item, which is an ordinary no-argument method call with the
// state moved in and out around it. A V error becomes whatever Python exception is set
// when it arrives: `StopIteration` ends the iteration cleanly, and anything else
// propagates to the caller, which is exactly CPython's own contract for the slot.
fn emit_next_trampoline(p Project, c Class, f Func) string {
	mut w := new_builder()
	w.write_string('fn ${c.next_fn}(self voidptr) voidptr {\n')
	w.write_string(emit_state_pointer(c, no_state_exit(c, 'unsafe { nil }')))
	w.write_string(emit_enter_state(p, c))
	ret := lookup(f.v_ret)
	has_value := ret != .void
	if has_value {
		w.write_string('\tmut result := ${zero_value(ret, f.v_ret)}\n')
	}
	if f.nogil {
		w.write_string(emit_nogil_open())
	} else {
		w.write_string('\tdefer {\n')
		w.write_string('\t\tif message := recover() {\n')
		w.write_string("\t\t\tvcraft.raise_runtime_error('panic in V code: \${message}')\n")
		w.write_string('\t\t}\n')
		w.write_string('\t}\n')
	}
	call := 'state.' + c.self_access() + '${f.name}()'
	if f.returns_result {
		inner := 'vcraft.raise_from_error(err)\n\t\treturn unsafe { nil }'
		if has_value {
			if f.nogil {
				w.write_string('\tresult = ${call} or {\n' + emit_nogil_failure(inner) +
					'\t}\n')
			} else {
				w.write_string('\tresult = ${call} or {\n\t\t${inner}\n\t}\n')
			}
		} else {
			if f.nogil {
				w.write_string('\t${call} or {\n' + emit_nogil_failure(inner) + '\t}\n')
			} else {
				w.write_string('\t${call} or {\n\t\t${inner}\n\t}\n')
			}
		}
		if f.nogil {
			w.write_string(emit_nogil_close())
		}
		w.write_string('\tif vcraft.error_is_set() {\n\t\treturn unsafe { nil }\n\t}\n')
	} else if has_value {
		w.write_string('\tresult = ${call}\n')
		if f.nogil {
			w.write_string(emit_nogil_close())
		}
	} else {
		w.write_string('\t${call}\n')
		if f.nogil {
			w.write_string(emit_nogil_close())
		}
	}
	w.write_string('\tif vcraft.error_is_set() {\n\t\treturn unsafe { nil }\n\t}\n')
	if has_value {
		w.write_string('\treturn ${return_expr(ret, 'result', false, f.v_ret)}\n')
	} else {
		w.write_string('\treturn vcraft.to_py_none().ptr\n')
	}
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_iterators renders both trampolines when the class declares the pair.
fn emit_class_iterators(p Project, c Class) string {
	if c.iter_fn.len == 0 {
		return ''
	}
	mut iter_method := Func{}
	mut next_method := Func{}
	for m in c.methods {
		if m.is_iter {
			iter_method = m
		}
		if m.is_next {
			next_method = m
		}
	}
	mut w := new_builder()
	w.write_string(emit_iter_trampoline(p, c, iter_method))
	w.write_string(emit_next_trampoline(p, c, next_method))
	return w.str()
}

fn emit_class_new(c Class) string {
	mut w := new_builder()
	w.write_string('fn ${c.ctor}(type_obj voidptr, args voidptr, kwds voidptr) voidptr {\n')
	// `tp_init` is left null, so the arguments land here, and `object.__init__` stays
	// quiet about extra ones whenever `tp_new` is overridden. Rejecting them here is
	// what makes `Counter(1)` an error rather than a silently ignored argument.
	w.write_string('\tif C.vpy_tuple_size(args) != 0 || kwds != unsafe { nil } {\n')
	w.write_string("\t\tvcraft.raise_type_error('${c.name}() takes no arguments')\n")
	w.write_string('\t\treturn unsafe { nil }\n\t}\n')
	w.write_string('\tinstance := vcraft.type_alloc(type_obj)\n')
	w.write_string('\tif instance == unsafe { nil } {\n\t\treturn vcraft.no_memory()\n\t}\n')
	w.write_string('\tstorage := vcraft.instance_alloc(${c.size_fn}())\n')
	w.write_string('\tif storage == unsafe { nil } {\n\t\treturn vcraft.no_memory()\n\t}\n')
	w.write_string('\tvcraft.instance_set_storage(instance, storage)\n')
	// A class whose whole state is its own struct can be left uninitialised when there is
	// no constructor. A subclass cannot: its state includes the base's, so the base's
	// constructor still has to run even when this class declares none of its own.
	if c.ctor_fn == '' && c.base_index < 0 {
		w.write_string('\treturn instance\n}\n\n')
		return w.str()
	}
	w.write_string('\tdefer {\n')
	w.write_string('\t\tif message := recover() {\n')
	w.write_string("\t\t\tvcraft.raise_runtime_error('panic in V code: \${message}')\n")
	w.write_string('\t\t}\n')
	w.write_string('\t}\n')
	w.write_string('\tinitial := ${c.newstate_fn}()\n')
	w.write_string('\tvcraft.load_state(unsafe { voidptr(&initial) }, storage, ${c.size_fn}())\n')
	w.write_string('\tif vcraft.error_is_set() {\n')
	w.write_string('\t\tvcraft.instance_free(storage)\n')
	w.write_string('\t\treturn unsafe { nil }\n')
	w.write_string('\t}\n')
	w.write_string('\treturn instance\n}\n\n')
	return w.str()
}

// emit_state_pointer renders `state`, a pointer to the instance's state block.
//
// Methods, accessors and slots work on the block in place, as PyO3 does with the cell
// that holds a `#[pyclass]`. They used to load a copy of the whole struct before the
// call and store it back after, which was most of what a method cost. The trade is the
// one PyO3 makes: a method that panics halfway leaves the fields it had already written.
//
// `fail` is the body of the branch taken when the instance has no block. Every instance
// that reaches Python has one, but an instance whose block failed to allocate is
// already tracked by the cycle collector and can reach `tp_traverse` without one.
fn emit_state_pointer(c Class, fail string) string {
	return '\tmut state := unsafe { &${c.state_type()}(vcraft.instance_storage(self)) }\n' +
		'\tif isnil(state) {\n' + fail + '\t}\n'
}

// no_state_exit raises for an instance with no state block and returns `value`, the
// failure value of the slot being emitted.
fn no_state_exit(c Class, value string) string {
	return "\t\tvcraft.raise_runtime_error('${c.name} instance has no state')\n" +
		'\t\treturn ${value}\n'
}

// emit_enter_state publishes the state block and every generation above it, so a method
// that is about to run can reach what it inherited.
//
// A method of a subclass cannot reach the base's half of the state through its own
// receiver: V hands it the subclass struct, and the base's bytes are not in it. The
// trampoline publishes one pointer per generation and `vcraft.state_at` hands them over,
// level by level.
//
// One pointer per generation rather than a single base pointer because the offsets are not
// uniform. `level_path` walks the state struct member by member -- `state.base.self` for
// the immediate base of a class whose base has none of its own, `state.base.base.self` for
// the next one up -- and each address is computed here, where the layout is known.
//
// The chain is saved and restored whole, so a nested call cannot leave the outer
// trampoline's levels pointing at the inner one's instance.
//
// Publishing costs an allocation and two copies of the chain per call, and the only
// reader is `vcraft.state_at`. A module that never calls it gets nothing emitted.
fn emit_enter_state(p Project, c Class) string {
	if !p.uses_state_at {
		return ''
	}
	mut w := new_builder()
	w.write_string('\tprevious := vcraft.enter_state(unsafe { voidptr(state) })\n')
	// Only a class with a base has anything to publish. A trampoline of a class with no
	// base loads just that class's struct, so there is no room in it for a generation
	// above: the level stays nil rather than pointing at the receiver, which would be a
	// type confusion rather than a missing value.
	if c.base_index >= 0 {
		mut level := 1
		// Two paths, because a generation's state and its own struct are at different
		// addresses whenever it has a base of its own: the state is the base followed by
		// the struct, so the struct sits after it.
		mut state_path := 'state'
		mut struct_path := 'state.self'
		for base := c.base_index; base >= 0; base = p.classes[base].base_index {
			// Whatever the base's state is, it begins in this class's `base` member.
			state_path += '.base'
			if p.classes[base].base_index >= 0 {
				struct_path = state_path + '.self'
			} else {
				// A base with no base of its own has no state of its own, so its struct
				// and its state are the same bytes. Also the last step: there is nothing
				// above a class with no base.
				struct_path = state_path
			}
			w.write_string('\tvcraft.publish_base(' + level.str() + ', unsafe { voidptr(&' +
				struct_path + ') })\n')
			level++
		}
	}
	w.write_string('\tdefer { vcraft.leave_state(previous) }\n')
	return w.str()
}

// emit_class_dealloc renders `tp_dealloc`.
//
// The state block is released first, then the base deallocator runs. Calling the
// base last is the documented requirement for a subtype.
//
// A class holding references releases them before the block goes. `tp_clear` is not
// enough on its own: the collector calls it for an instance it found in a cycle, but an
// instance whose last reference is simply dropped reaches `tp_dealloc` with its reference
// count already at zero and nothing else having released what it pointed at.
fn emit_class_dealloc(p Project, c Class) string {
	mut w := new_builder()
	w.write_string('fn vcraft_generated__dealloc_${c.key}(self voidptr) voidptr {\n')
	if c.ref_fields().len > 0 {
		w.write_string(emit_state_pointer(c, '\t\treturn vcraft.class_dealloc(self)\n'))
		w.write_string(emit_clear_refs(c))
	}
	w.write_string('\treturn vcraft.class_dealloc(self)\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_traverse renders `tp_traverse`, the half of cycle collection that reports
// what an instance holds.
//
// One `traverse_ref` per reference field in the whole state, the base's included, because
// the block is the base's state followed by the class's own and the collector cannot see
// either half on its own. The return value is checked per field rather than accumulated:
// `tp_traverse` returns non-zero to say the traversal failed, and CPython's own types
// stop at the first field that does.
fn emit_class_traverse(p Project, c Class) string {
	refs := c.ref_fields()
	if refs.len == 0 {
		return ''
	}
	mut w := new_builder()
	w.write_string('fn vcraft_generated__traverse_${c.key}(self voidptr, visit voidptr, ' +
		'arg voidptr) int {\n')
	// The collector calls this on the type object as well, because a heap type with
	// `Py_TPFLAGS_HAVE_GC` is tracked itself. A type's bytes after the header are its
	// dict, not a state block, so that case goes to CPython before anything is read.
	w.write_string('\tif vcraft.is_type_object(self) {\n')
	w.write_string('\t\treturn vcraft.traverse_type(self, visit, arg)\n\t}\n')
	w.write_string(emit_state_pointer(c, '\t\treturn 0\n'))
	for f in refs {
		w.write_string('\tif vcraft.traverse_ref(unsafe { voidptr(&state.' + f.path +
			')}, visit, arg) != 0 {\n')
		w.write_string('\t\treturn 1\n\t}\n')
	}
	w.write_string('\treturn 0\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_clear renders `tp_clear`, the half that breaks the cycle.
//
// The same fields as `tp_traverse`, released and nulled. Nulling is what makes it safe to
// run twice: the collector clears an object, and the object may already be on its way out
// by the time its reference count reaches zero.
fn emit_class_clear(p Project, c Class) string {
	refs := c.ref_fields()
	if refs.len == 0 {
		return ''
	}
	mut w := new_builder()
	w.write_string('fn vcraft_generated__clear_${c.key}(self voidptr) voidptr {\n')
	// The type object reaches here too, during finalisation. See the traverse trampoline.
	w.write_string('\tif vcraft.is_type_object(self) {\n')
	w.write_string('\t\tvcraft.clear_type(self)\n')
	w.write_string('\t\treturn unsafe { nil }\n\t}\n')
	w.write_string(emit_state_pointer(c, '\t\treturn unsafe { nil }\n'))
	w.write_string(emit_clear_refs(c))
	w.write_string('\treturn unsafe { nil }\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_clear_refs releases every reference field of a loaded state, in place.
fn emit_clear_refs(c Class) string {
	mut w := new_builder()
	for f in c.ref_fields() {
		w.write_string('\tvcraft.clear_ref(unsafe { voidptr(&state.' + f.path + ')})\n')
	}
	return w.str()
}

// emit_class_state_struct renders the struct that holds an instance's fields.
//
// A class with no base uses its own struct directly. A subclass gets a struct holding
// the base's fields followed by its own, because V has no struct inheritance: a V
// `BoundedCounter` names only `limit`, and a method reading `value` needs those bytes
// laid out the way the base's method expects them.
//
// The base field is typed as the base's *state*, not as the base's own struct. A base
// with no base of its own is the same either way, but one level further down the
// difference is the whole of that class's inherited state, and typing it as the base's
// own struct would silently drop the base's own base from the layout.
//
// Two names reach the same bytes: a method of the base is handed `self` typed as the base
// and reads `state.field` directly, while a method of the subclass is handed `self` typed
// as the subclass and reaches its own fields through `state.self.field`.
fn emit_class_state_struct(p Project, c Class) string {
	mut w := new_builder()
	w.write_string('// ' + c.state_name() + ' is ' + c.name + '\'s instance state: ' +
		p.classes[c.base_index].state_type() + ', then its own.\n')
	// `mut` on both halves: the state is built up field by field, so the base and the
	// subclass are both written after the block exists.
	w.write_string('struct ' + c.state_name() + ' {\n')
	w.write_string('mut:\n')
	w.write_string('\tbase ' + p.classes[c.base_index].state_type() + '\n')
	w.write_string('\tself ' + c.name + '\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_newstate renders the constructor of the whole state block.
//
// Recursive rather than flat, which is what makes a chain of arbitrary depth work: the
// base's part is built by its own generated constructor and assigned in one typed copy,
// so a subclass never has to know how many structs its base's state is made of.
//
// A class with no base returns its own struct, so `BoundedCounter()` and
// `vcraft_generated__newstate_boundedcounter()` build the same value.
fn emit_class_newstate(p Project, c Class) string {
	mut w := new_builder()
	w.write_string('fn ${c.newstate_fn}() ${c.state_type()} {\n')
	w.write_string('\tmut state := ${c.state_type()}{}\n')
	if c.base_index >= 0 {
		base := p.classes[c.base_index]
		// An assignment rather than a literal: `BoundedCounterState{}` already holds the
		// base's zero value, and this is the only thing that replaces it with the base's
		// constructor result.
		w.write_string('\tstate.base = ' + base.newstate_fn + '()\n')
	}
	if c.ctor_fn != '' {
	// A class with no base holds its own struct, so the whole of `state` is replaced. A
	// subclass holds the base followed by its own, so only the `self` half is.
	if c.base_index >= 0 {
		w.write_string('\tstate.self = *${c.ctor_fn}()\n')
	} else {
		w.write_string('\tstate = *${c.ctor_fn}()\n')
	}
	}
	w.write_string('\treturn state\n}\n\n')
	return w.str()
}

// emit_class_richcompare renders `tp_richcompare`.
//
// The user's `@[vc_eq]` method takes two receivers and returns a bool, and CPython's
// `tp_richcompare` takes the operator as an argument and returns an object. The gap
// between the two is what this function closes, and it is worth being explicit about:
// `==` calls the method and returns its answer, `!=` returns its negation, and every
// other operator returns `NotImplemented`.
//
// `NotImplemented` rather than `False` is what lets `a < b` try `b.__gt__(a)` and then
// fall back to an error naming the type. Returning `False` makes a class that only
// defines `==` quietly claim to be smaller than everything.
fn emit_class_richcompare(c Class) string {
	mut w := new_builder()
	w.write_string('fn ${c.richcompare}(self voidptr, other voidptr, op int) voidptr {\n')
	if c.eq_fn.len == 0 {
		// No `@[vc_eq]`, so the defaults are the identity comparison CPython gives every
		// other object: `==` and `!=` by address, and nothing else.
		w.write_string('\treturn vcraft.identity_richcompare(self, other, op)\n')
		w.write_string('}\n\n')
		return w.str()
	}
	w.write_string('\tif op == vcraft.op_lt || op == vcraft.op_le || op == vcraft.op_gt ' +
		'|| op == vcraft.op_ge {\n')
	w.write_string('\t\treturn vcraft.richcompare_not_implemented()\n')
	w.write_string('\t}\n')
	// `.ptr` on both: the type handle is a `PyObj` and `is_instance_of` takes the raw
	// pointer. Passing the struct makes V emit a cast of the wrong thing, and the check
	// then answers for an address rather than for the type.
	w.write_string('\tif !vcraft.is_instance_of(other, g_vc_type_${c.key}.ptr) {\n')
	w.write_string('\t\treturn vcraft.richcompare_not_implemented()\n')
	w.write_string('\t}\n')
	// Both operands are passed as the state block's address rather than as a copy of the
	// struct. A copy would have to be written back afterwards, and a method that panicked
	// between the load and the store would leave the instance holding a half-written
	// value. The user reads the fields through `state_from_ptr`, which is what makes the
	// signature a free function taking two pointers.
	w.write_string('\tmut same := ${c.eq_fn}(vcraft.instance_storage(self), ' +
		'vcraft.instance_storage(other))\n')
	// `!=` is the negation of `==` rather than a call of its own. A V `bool` is not
	// the same thing as a Python `True`, so the negation happens here rather than in the
	// user's code, where `a != b` would mean comparing the two answers.
	w.write_string('\tif op == vcraft.op_ne {\n\t\tsame = !same\n\t}\n')
	w.write_string('\treturn vcraft.to_py_bool(same).ptr\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_hash renders `tp_hash`.
//
// A class that defines `__eq__` gets its hash filled from `tp_hash` only when it also
// defines `__hash__`. That pairing is not optional: Python's dicts assume that two
// objects which compare equal hash the same, and a value comparison with an
// identity-based hash breaks every lookup in a set or a dict key without an error.
fn emit_class_hash(c Class) string {
	mut w := new_builder()
	w.write_string('fn ${c.hash_fn}(self voidptr) isize {\n')
	if c.hash_name.len == 0 {
		w.write_string('\treturn vcraft.identity_hash(self)\n')
		w.write_string('}\n\n')
		return w.str()
	}
	// The state block's address rather than a copy, for the same reason `richcompare`
	// passes one: a copy would have to be written back, and a panic in between would
	// leave the instance half written.
	w.write_string('\treturn vcraft.hash_from_int(${c.hash_name}' +
		'(vcraft.instance_storage(self)))\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_repr renders `tp_repr`, so an instance prints as `Counter(value: 4)`
// rather than as an address.
fn emit_class_repr(p Project, c Class) string {
	mut w := new_builder()
	w.write_string('fn vcraft_generated__repr_${c.key}(self voidptr) voidptr {\n')
	// A class holding references can be its own ancestor: a cycle renders as `Pair(...)`
	// whose field renders the peer, which renders this one again. CPython's containers
	// guard against that with `Py_ReprEnter`, and the second arrival prints `...`.
	//
	// Only for a class that can recurse. A class with no reference field prints scalars,
	// which cannot reach back, and paying for the guard on every repr of every instance
	// would be a cost paid by the common case for the sake of the rare one.
	if c.ref_fields().len > 0 {
		w.write_string('\tif vcraft.repr_enter(self) {\n')
		w.write_string("\t\treturn vcraft.to_py_string('${c.name}(...)').ptr\n\t}\n")
		w.write_string('\tdefer { vcraft.repr_leave(self) }\n')
	}
	w.write_string(emit_state_pointer(c, no_state_exit(c, 'unsafe { nil }')))
	w.write_string(emit_enter_state(p, c))
	if c.fields.len == 0 {
		w.write_string("\treturn vcraft.to_py_string('${c.name}()').ptr\n}\n\n")
		return w.str()
	}
	w.write_string('\tmut parts := []string{}\n')
	// Every field the instance holds, not just this class's: a repr of a subclass that
	// left out the inherited fields would print a different shape from the repr of the
	// base holding the same values, which is exactly what a repr is for.
	for f in c.state_fields {
		// Concatenated rather than interpolated: inside one V literal the call would be
		// text, so the repr would print `vcraft.repr_int(state.value)` instead of 4.
		//
		// A reference field goes through `repr_ref` rather than the type table: it holds
		// an object, so what it prints is that object's own repr, and `None` for a field
		// that was never set.
		mut rendered := ''
		if f.is_reference() {
			rendered = 'vcraft.repr_ref(state.' + f.path + '.ptr)'
		} else {
			rendered = py_repr_expr(lookup(f.v_type), 'state.' + f.path)
		}
		w.write_string("\tparts << " + vstring_literal('${f.name}: ') + " + " + rendered +
			'\n')
	}
	w.write_string("\treturn vcraft.to_py_string('${c.name}(' + parts.join(', ') + ')').ptr\n")
	w.write_string('}\n\n')
	return w.str()
}

