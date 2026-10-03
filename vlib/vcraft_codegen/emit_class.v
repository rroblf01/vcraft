module vcraft_codegen

// Emitting classes.
//
// A class is four things: a heap type, a `tp_new` that allocates the state block,
// accessors that move the V value between that block and a local, and a `tp_dealloc`
// that releases it.
//
// The state is loaded before the guard and stored back after the call, so a method
// that panics halfway leaves the instance as it was rather than half written:
//
//	fn vcraft_generated__method_Counter_increment(self voidptr, args voidptr, nargs isize) voidptr {
//		vcraft.require_nargs('increment', 1, int(nargs))
//		if vcraft.error_is_set() { return unsafe { nil } }
//		arg0 := vcraft.from_py_int_arg(args, 0, 'increment', 'by') or { return unsafe { nil } }
//		mut state := Counter{}
//		vcraft.load_state(vcraft.instance_storage(self), voidptr(&state), ${c.size_fn})
//		defer {
//			if message := recover() { vcraft.raise_runtime_error('panic in V code: ${message}') }
//		}
//		state.increment(arg0)
//		vcraft.store_state(voidptr(&state), vcraft.instance_storage(self), ${c.size_fn})
//		if vcraft.error_is_set() { return unsafe { nil } }
//		return vcraft.to_py_none().ptr
//	}

import strings

// emit_class renders one class: its size helper, its tables and its accessors.
fn emit_class(c Class) string {
	mut w := new_builder()
	w.write_string('\n// ---- ${c.name}\n\n')
	w.write_string('fn ${c.size_fn}() usize {\n')
	w.write_string('\tunsafe { return sizeof(${c.name}) }\n')
	w.write_string('}\n\n')
	w.write_string(emit_class_getsets(c))
	w.write_string(emit_class_methods(c))
	w.write_string(emit_field_accessors(c))
	w.write_string(emit_class_new(c))
	w.write_string(emit_class_dealloc(c))
	w.write_string(emit_class_repr(c))
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
fn emit_field_accessors(c Class) string {
	if c.fields.len == 0 {
		return ''
	}
	mut w := new_builder()
	for f in c.fields {
		w.write_string('fn vcraft_generated__get_${c.key}_${f.name}(self voidptr, closure voidptr) voidptr {\n')
		w.write_string("\tmut state := ${c.name}{}\n")
		w.write_string('\tvcraft.load_state(vcraft.instance_storage(self), voidptr(&state), ' +
			'${c.size_fn}())\n')
		w.write_string('\treturn ${boxed_expr(lookup(f.v_type), 'state.' + f.name)}.ptr\n')
		w.write_string('}\n\n')
		// The converted value is written through the field's address rather than
		// assigned, because assigning would need the field itself to be `mut`, and a
		// plain `@[vc_field]` does not have to be.
		conv := unbox_expr(lookup(f.v_type), 'value')
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
		w.write_string("\tmut state := ${c.name}{}\n")
		w.write_string('\tvcraft.load_state(vcraft.instance_storage(self), voidptr(&state), ' +
			'${c.size_fn}())\n')
		// Only the field is copied, so the size is the field's, not the struct's.
		w.write_string('\tvcraft.set_state(unsafe { voidptr(&state.${f.name}) }, ' +
			'unsafe { voidptr(&field) }, sizeof(${f.v_type}))\n')
		// The field was written through the local copy, so the copy goes back; without
		// this the assignment reaches nothing.
		w.write_string('\tvcraft.store_state(unsafe { voidptr(&state) }, ' +
			'vcraft.instance_storage(self), ${c.size_fn}())\n')
		w.write_string('\treturn 0\n')
		w.write_string('}\n\n')
	}
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
	if c.ctor_fn == '' {
		w.write_string('\treturn instance\n}\n\n')
		return w.str()
	}
	w.write_string('\tdefer {\n')
	w.write_string('\t\tif message := recover() {\n')
	w.write_string("\t\t\tvcraft.raise_runtime_error('panic in V code: \${message}')\n")
	w.write_string('\t\t}\n')
	w.write_string('\t}\n')
	w.write_string('\tinitial := ${c.ctor_fn}()\n')
	w.write_string('\tvcraft.load_state(unsafe { voidptr(initial) }, storage, ${c.size_fn}())\n')
	w.write_string('\tif vcraft.error_is_set() {\n')
	w.write_string('\t\tvcraft.instance_free(storage)\n')
	w.write_string('\t\treturn unsafe { nil }\n')
	w.write_string('\t}\n')
	w.write_string('\treturn instance\n}\n\n')
	return w.str()
}

// emit_class_dealloc renders `tp_dealloc`.
//
// The state block is released first, then the base deallocator runs. Calling the
// base last is the documented requirement for a subtype.
fn emit_class_dealloc(c Class) string {
	mut w := new_builder()
	w.write_string('fn vcraft_generated__dealloc_${c.key}(self voidptr) voidptr {\n')
	w.write_string('\treturn vcraft.class_dealloc(self)\n')
	w.write_string('}\n\n')
	return w.str()
}

// emit_class_repr renders `tp_repr`, so an instance prints as `Counter(value: 4)`
// rather than as an address.
fn emit_class_repr(c Class) string {
	mut w := new_builder()
	w.write_string('fn vcraft_generated__repr_${c.key}(self voidptr) voidptr {\n')
	w.write_string('\tmut state := ${c.name}{}\n')
	w.write_string('\tvcraft.load_state(vcraft.instance_storage(self), voidptr(&state), ' +
		'${c.size_fn}())\n')
	if c.fields.len == 0 {
		w.write_string("\treturn vcraft.to_py_string('${c.name}()').ptr\n}\n\n")
		return w.str()
	}
	w.write_string('\tmut parts := []string{}\n')
	for f in c.fields {
		// Concatenated rather than interpolated: inside one V literal the call would be
		// text, so the repr would print `vcraft.repr_int(state.value)` instead of 4.
		rendered := py_repr_expr(lookup(f.v_type), 'state.' + f.name)
		w.write_string("\tparts << " + vstring_literal('${f.name}: ') + " + " + rendered +
			'\n')
	}
	w.write_string("\treturn vcraft.to_py_string('${c.name}(' + parts.join(', ') + ')').ptr\n")
	w.write_string('}\n\n')
	return w.str()
}

