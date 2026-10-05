module vcraft

// Building the Python module object.
//
// CPython's single-phase initialisation API wants a PyModuleDef and a
// null-terminated PyMethodDef array. Both are built at runtime rather than
// declared as C statics, because vcraft discovers the API surface after parsing
// the V sources and so cannot emit a fixed C table.
//
// The lifetime works out. PyModule_Create2 installs the methods into the module
// dict as it creates the module, so the table only has to stay valid for the
// duration of that call. Module-level strings are allocated once and never
// freed, which is the right lifetime for a process-wide module.

// Module is a Python module under construction. After `seal` it is a finished
// module with a new reference the caller owns.
pub struct Module {
pub mut:
	obj     PyObj
	methods []PyMethodDef
	def     PyModuleDef
	name    voidptr
	doc     voidptr
	// slots is the multi-phase slot table, used only by an abi3 build. It holds a
	// `Py_mod_exec` entry pointing at the same function that `seal` runs, so the
	// interpreter calls back into the generated code rather than vcraft doing the work
	// itself.
	slots []PyModuleDefSlot
	// exec_fn is that callback. It cannot be a method value, because a V method value
	// has a receiver and CPython calls it with one argument.
	exec_fn voidptr
}

// The multi-phase exec callback's signature: a module, and a status to set on failure.
pub type PyModuleExecFunc = fn (voidptr) int

// The two calling conventions a generated trampoline can use. CPython stores
// both in the same PyMethodDef field, so they are kept as raw pointers here.
pub type PyCFunctionNoArgs = fn (voidptr, voidptr) voidptr

pub type PyCFunctionFast = fn (voidptr, voidptr, isize) voidptr

// new_module starts a module definition. Nothing is handed to CPython yet, so
// functions may still be added. `name` and `docstring` are copied into buffers
// that live as long as the module does.
pub fn new_module(name string, docstring string) Module {
	return Module{
		name: cstring(name)
		doc:  cstring(docstring)
	}
}

// install_functions copies the method table into the module.
//
// Single-phase initialisation does this itself, inside `PyModule_Create2`. Multi-phase
// initialisation does not: the module is created empty and filled by `Py_mod_exec`, so
// the table has to be installed by hand or every function is missing.
//
// `PyModule_AddFunctions` is the stable-ABI call that does it, and it is what makes one
// generated source serve both APIs: the loop here runs under `Py_mod_exec` on an abi3
// build and is never reached on a normal one, where `seal` has already done the work.
pub fn (m Module) install_functions(module voidptr) ! {
	if m.methods.len <= 1 {
		return
	}
	unsafe {
		if C.PyModule_AddFunctions(module, voidptr(&m.methods[0])) != 0 {
			return error('vcraft: cannot install the module functions')
		}
	}
	return
}

// add_function appends a function to the table.
//
// `name` and `docstring` are pointers the module keeps for its lifetime, so pass
// a string literal as `voidptr(c'name')` or the result of `cstring`. An empty
// docstring becomes a null pointer, which is how CPython spells "no docstring".
//
// This must be called before `seal`.
pub fn (mut m Module) add_function(name voidptr, trampoline voidptr, flags int, docstring voidptr) {
	m.methods << PyMethodDef{
		name:  name
		meth:  trampoline
		flags: flags
		doc:   docstring
	}
}

// add_function_owned is `add_function` for names and docstrings that are V
// strings. It allocates the buffers once and never frees them, which matches the
// lifetime of a module that lives until the process exits.
pub fn (mut m Module) add_function_owned(name string, trampoline voidptr, flags int, docstring string) {
	docptr := if docstring.len > 0 { cstring(docstring) } else { unsafe { nil } }
	m.add_function(cstring(name), trampoline, flags, docptr)
}

// seal finishes construction: it terminates the method table, creates the module
// and returns it with a new reference that the caller owns.
//
// Two paths, because CPython has two module initialisation APIs and only one of them is
// in the limited API.
//
// `PyModule_Create2` is single-phase: it takes a `PyModuleDef` whose fields are filled
// in here and hands back a finished module. That is the cheaper path and it is what a
// normal build uses, but the struct it needs is a concrete type the stable ABI hides,
// so an abi3 build cannot call it at all.
//
// Under `Py_LIMITED_API` the module declares a `Py_mod_exec` slot instead, and the
// interpreter calls it to populate the module. That is multi-phase initialisation, and
// it is the only form available to an abi3 extension.
pub fn (mut m Module) seal() PyObj {
	unsafe {
		m.methods << PyMethodDef{}
		m.def.m_name = m.name
		m.def.m_doc = m.doc
		m.def.m_size = -1
		m.def.m_methods = if m.methods.len > 1 { voidptr(&m.methods[0]) } else { nil }
		if is_limited_api() {
			// The module definition carries a `Py_mod_exec` slot and the interpreter
			// calls back through it. `m_size` must be 0 rather than -1 here: a
			// multi-phase module declares its state through `Py_mod_create` instead,
			// and CPython rejects a definition that claims single-phase state *and*
			// slots.
			m.def.m_size = 0
			// The method table is cleared because under multi-phase initialisation the
			// module's contents are added by `Py_mod_exec`, not by the creation call.
			// Leaving the table in place makes CPython install the functions twice: once
			// from here and once from the callback. What is worse, the second install
			// fails, and the module comes out with no functions at all — the `for` loop
			// below reports success while every attribute is missing.
			m.def.m_methods = unsafe { nil }
			m.slots << PyModuleDefSlot{
				slot:  mod_exec
				value: m.exec_fn
			}
			m.slots << PyModuleDefSlot{}
			m.def.m_slots = voidptr(&m.slots[0])
			// `PyInit_` returns the module *spec* under multi-phase initialisation, and
			// `PyModuleDef_Init` is what produces it. Returning the definition itself
			// instead gives CPython something that is neither a module nor a spec, and it
			// reports "returned uninitialized object" — a message that names neither of
			// the two mistakes that lead to it.
			return steal(C.PyModuleDef_Init(voidptr(&m.def)))
		}
		m.obj = steal(C.PyModule_Create2(voidptr(&m.def), python_api_version()))
		$if vcraft_free_threaded ? {
			// Declared GIL-free, so the interpreter keeps the GIL disabled for this
			// module instead of enabling it on import with a warning. A slot cannot do
			// this: single-phase initialisation refuses a definition carrying any.
			if C.vpy_module_set_gil(m.obj.ptr, C.vpy_mod_gil_not_used()) != 0 {
				C.Py_DecRef(m.obj.ptr)
				C.PyErr_SetString(C.vpy_exc_runtime_error(), c'vcraft: cannot mark the module GIL-free')
				return PyObj{}
			}
		}
		// Single-phase initialisation creates the module with its functions already in
		// it, so `seal` returns a finished module and nothing calls `exec`. The classes
		// live in the callback, so on this path the callback has to be called here.
		//
		// Two shapes rather than one shared helper, because the two APIs disagree about
		// what the module is at this point: here it is an object, under multi-phase it
		// is a definition the interpreter will call back into. Calling the same code
		// with the wrong one installs the classes on nothing and reports success.
		if m.exec_fn != unsafe { nil } {
			C.vpy_call_exec(m.exec_fn, m.obj.ptr)
		}
		return m.obj
	}
}

// set_exec records the callback the interpreter invokes through `Py_mod_exec`.
//
// An abi3 build cannot populate the module from `pyinit`, because `pyinit` returns a
// definition rather than a module and the interpreter calls back afterwards. The
// callback is a plain function pointer rather than a V method value, since CPython
// calls it with one argument and no receiver.
pub fn (mut m Module) set_exec(fn_ptr voidptr) {
	m.exec_fn = fn_ptr
}

// is_limited_api reports whether this build targets the stable ABI.
//
// A C define rather than a V one, because the two builds differ in which CPython
// functions exist at all: asking at run time would work, and asking at compile time
// keeps the single-phase code out of an abi3 binary entirely.
fn is_limited_api() bool {
	return C.vpy_is_limited_api() != 0
}

// module_create_multi_phase creates a module using only stable-ABI functions.
//
// `PyModule_Create2` is single-phase initialisation and reads a `PyModuleDef`'s fields
// directly, which the limited API does not expose. The equivalent available to an abi3
// build is to hand the interpreter a module definition carrying a `Py_mod_exec` slot and
// let it call back: that is multi-phase initialisation, and `PyModuleDef_Init` returning
// the spec is the whole of it.
//
// `PyModuleDef_Init` is a macro of one argument, not a function of two, and that is not
// a detail: declaring it with the two-argument form compiles and then hands the
// interpreter's API version where it expects a definition pointer, so the first call
// segfaults inside CPython with nothing in the V sources to explain it.
//
// The definition stays in the caller's `Module`, so its address outlives this call.
// CPython keeps the definition rather than copying it, which is why the `Module` may not
// be a temporary.
fn module_create_multi_phase(def voidptr) voidptr {
	unsafe {
		return C.PyModuleDef_Init(def)
	}
}

// add_object installs an attribute on a finished module, stealing a reference to
// `value`. This is how classes, constants and submodules are attached.
pub fn (m Module) add_object(name string, value PyObj) {
	namep := cstring(name)
	unsafe {
		C.PyModule_AddObject(m.obj.ptr, namep, value.ptr)
	}
	free_cstring(namep)
}

// add_object_ref_on installs an attribute on a finished module without stealing the
// reference, which is the safer choice when the caller keeps using the value.
//
// It takes the module as a `voidptr` rather than a `Module`, because by the time anything
// is attached the module is already sealed: under multi-phase initialisation the caller
// is the interpreter's `Py_mod_exec` callback, which receives the module as a plain
// pointer and never sees the `Module` at all.
pub fn add_object_ref_on(module voidptr, name string, value PyObj) {
	namep := cstring(name)
	unsafe {
		C.PyModule_AddObjectRef(module, namep, value.ptr)
	}
	free_cstring(namep)
}

// add_object_ref installs an attribute without stealing.
pub fn (m Module) add_object_ref(name string, value PyObj) {
	namep := cstring(name)
	unsafe {
		C.PyModule_AddObjectRef(m.obj.ptr, namep, value.ptr)
	}
	free_cstring(namep)
}

// set_docstring replaces the module docstring after construction.
pub fn (m Module) set_docstring(docstring string) {
	docp := cstring(docstring)
	unsafe {
		C.PyObject_SetAttrString(m.obj.ptr, voidptr(c'__doc__'), docp)
	}
	free_cstring(docp)
}

// check_layout compares the V mirrors of CPython's structs against the sizes the
// C compiler agrees with, and reports a mismatch as a Python SystemError.
//
// This is cheap insurance. If a mirror ever drifts from the CPython headers,
// every later symptom would be a wild pointer dereference inside the
// interpreter, which is close to impossible to diagnose. Checking once at import
// turns that into a message naming the struct.
//
// It also catches the mistake that motivated it: V's `int` is 64 bits while C's
// `int` is 32, so the two are the same width nowhere and must never be assumed
// interchangeable in a layout.
pub fn check_layout() ! {
	if unsafe { sizeof(PyModuleDef) } != int(C.vpy_size_PyModuleDef()) {
		raise(.system_error, 'vcraft: PyModuleDef size mismatch')
		return error('layout')
	}
	if unsafe { sizeof(PyMethodDef) } != int(C.vpy_size_PyMethodDef()) {
		raise(.system_error, 'vcraft: PyMethodDef size mismatch')
		return error('layout')
	}
	if unsafe { sizeof(isize) } != int(C.vpy_ssize_size()) {
		raise(.system_error, 'vcraft: Py_ssize_t size mismatch')
		return error('layout')
	}
}
