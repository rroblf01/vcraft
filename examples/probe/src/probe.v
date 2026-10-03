// Gate 0: prove that a shared object produced by the V compiler can be loaded
// by CPython as a native extension module.
//
// This is the load-bearing assumption behind the whole project. A CPython
// extension module is a shared library that exports `PyInit_<name>`, and
// `v -shared` already produces a shared library whose dynamic symbol table is
// restricted to `@[export: ...]` declarations. If this program works, the
// remaining work is ordinary engineering.
module probe

// The calling convention CPython uses for METH_NOARGS builtins.
fn answer_trampoline(self voidptr, args voidptr) voidptr {
	return C.PyLong_FromLongLong(42)
}

// The calling convention CPython uses for METH_FASTCALL builtins. This is the
// shape vcraft generates for every annotated function: the arguments arrive as
// a borrowed PyObject pointer array plus a count, and the return value is a new
// reference, or nil with an exception set.
fn add_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	if nargs != 2 {
		C.PyErr_SetString(C.vpyprobe_type_error(), c'add() takes exactly 2 arguments')
		return unsafe { nil }
	}
	// A C `PyObject *const *` seen as a V array of borrowed references.
	unsafe {
		argv := &voidptr(args)
		mut total := i64(0)
		for i in 0 .. int(nargs) {
			total += C.PyLong_AsLongLong(argv[i])
			if C.PyErr_Occurred() != nil {
				// A PyLong_AsLongLong failure already set TypeError; propagate it.
				return nil
			}
		}
		return C.PyLong_FromLongLong(total)
	}
}

@[export: 'PyInit_probe']
fn pyinit_probe() voidptr {
	// A PyMethodDef array is terminated by an all-zero entry, which is exactly
	// what an omitted-field V struct literal produces.
	mut methods := [PyMethodDef{
		name:  voidptr(c'answer')
		meth:  voidptr(answer_trampoline)
		flags: meth_noargs
		doc:   voidptr(c'Return the answer.')
	}, PyMethodDef{
		name:  voidptr(c'add')
		meth:  voidptr(add_trampoline)
		flags: meth_fastcall
		doc:   voidptr(c'add(a, b)')
	}, PyMethodDef{}]
	unsafe {
		def := &PyModuleDef{
			m_name:    voidptr(c'probe')
			m_doc:     voidptr(c'A CPython extension module compiled by the V compiler.')
			m_size:    -1
			m_methods: voidptr(&methods[0])
		}
		return C.PyModule_Create2(voidptr(def), py_api_version)
	}
}
