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
}

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
pub fn (mut m Module) seal() PyObj {
	unsafe {
		m.methods << PyMethodDef{}
		m.def.m_name = m.name
		m.def.m_doc = m.doc
		m.def.m_size = -1
		m.def.m_methods = if m.methods.len > 1 { voidptr(&m.methods[0]) } else { nil }
		m.obj = steal(C.PyModule_Create2(voidptr(&m.def), python_api_version()))
		return m.obj
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
// It takes the module as a `PyObj` rather than a `Module`, because by the time
// anything is attached the module is already sealed and `Module.obj` is what the
// generated glue holds.
pub fn add_object_ref_on(module PyObj, name string, value PyObj) {
	namep := cstring(name)
	unsafe {
		C.PyModule_AddObjectRef(module.ptr, namep, value.ptr)
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
