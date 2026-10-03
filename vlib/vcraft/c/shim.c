// Accessors for CPython symbols that are data rather than functions.
//
// V cannot name a C global, so every CPython singleton the runtime needs gets a
// one-line accessor here. This file is compiled into the extension by the
// `#flag @VMODROOT/c/shim.c` directive in vlib/vcraft/cpython.c.v.
//
// Every accessor that would touch a concrete object struct has a `Py_LIMITED_API`
// variant. Under the stable ABI CPython hides `PyTypeObject` and friends behind
// incomplete typedefs and turns the `Py*_GET_SIZE` family into macros that are not
// exported, so the code below has to go through functions instead. `vcraft build
// --abi3` defines `vcraft_limited_api`, which is what selects these branches.

#include "shim.h"

#include <string.h>

int vpy_python_api_version(void) {
	return PYTHON_API_VERSION;
}

unsigned long vpy_version_hex(void) {
	return PY_VERSION_HEX;
}

const char *vpy_version_string(void) {
	return Py_GetVersion();
}

Py_ssize_t vpy_ssize_size(void) {
	return (Py_ssize_t)sizeof(Py_ssize_t);
}

int vpy_int_size(void) {
	return (int)sizeof(int);
}

Py_ssize_t vpy_size_PyModuleDef(void) {
	// `sizeof` is valid under `Py_LIMITED_API` even for a struct the ABI does not
	// expose: the headers still define the type, they just do not let a caller reach
	// its fields. An earlier version of this file answered 0 here "because the struct
	// is hidden", and the runtime used that to compute `tp_basicsize`, which came out
	// as 8 instead of 16 and made every class fail with "tp_basicsize ... too small for
	// base 'object'". A guard that guesses is worse than no guard.
	return (Py_ssize_t)sizeof(PyModuleDef);
}

Py_ssize_t vpy_size_PyMethodDef(void) {
	return (Py_ssize_t)sizeof(PyMethodDef);
}

Py_ssize_t vpy_size_PyObject(void) {
	return (Py_ssize_t)sizeof(PyObject);
}

// The interpreter's own Py_TPFLAGS_DEFAULT, which is a union whose contents depend
// on how CPython was built. Asking beats hard-coding a bitmask.
unsigned int vpy_tpflags_default(void) {
	return (unsigned int)Py_TPFLAGS_DEFAULT;
}

#ifdef vcraft_limited_api

// Under the stable ABI there is no `PyTypeObject` to read a field out of and no
// exported `Py*_GET_SIZE`. Everything below goes through a function CPython does
// export, which is the whole point of the limited API.

void *vpy_memcpy(void *dst, const void *src, size_t n) {
	// `memcpy` is a C library function rather than a CPython one, so the limited API
	// does not hide it. The header that declares it is the reason for the guard above.
	return memcpy(dst, src, n);
}

void *vpy_type_ptr(PyObject *self) {
	return (void *)Py_TYPE(self);
}

// vpy_is_limited_api reports which CPython API this object was compiled against.
//
// A run-time answer rather than a compile-time one because V's `$if` cannot see a
// `-cflags` define. The two module-creation paths both compile either way; only one of
// them links against an abi3 build.
int vpy_is_limited_api(void) {
#ifdef vcraft_limited_api
	return 1;
#else
	return 0;
#endif
}

// vpy_call_exec invokes the generated `Py_mod_exec` callback.
//
// The return value is CPython's: 0 for success, -1 with an exception set. vcraft
// returns it rather than checking, because only the generated code knows whether the
// classes it tried to attach actually were.
int vpy_call_exec(void *fn_ptr, void *module) {
	int (*exec_fn)(PyObject *) = (int (*)(PyObject *))fn_ptr;
	return exec_fn((PyObject *)module);
}

// vpy_hash returns an object's default hash.
//
// `PyObject_Hash` is not in the limited API, and under `Py_LIMITED_API` a type's
// `tp_hash` has to be filled with a function that reaches the hash through whatever the
// stable ABI offers. There is nothing it offers here, so an abi3 build reports -1,
// which CPython reads as "hash failed" -- the correct answer for a type whose hash is
// identity, since an address-based hash cannot be computed without the concrete object
// header.
Py_hash_t vpy_hash(PyObject *self) {
	// The address, shifted right by four bits: the low bits of a pointer are always
	// zero, so folding them in would halve the hash's range for nothing.
	//
	// `_Py_HashPointer` is not available under `Py_LIMITED_API`, so the shift is done
	// here rather than through it. An abi3 build that used the helper would fail to
	// compile on an implicit declaration.
	return (Py_hash_t)((size_t)self >> 4);
}

// vpy_hash_bits reports the width of `Py_hash_t`, which is a `long` and therefore
// platform dependent: 64 bits where `long` is 64, 32 where it is not.
long vpy_hash_bits(void) {
	return (long)sizeof(Py_hash_t) * 8;
}

// vpy_type_check reports whether an object is an instance of a type, subclasses
// included.
//
// Written here rather than called because `PyObject_TypeCheck` is a `static inline` in
// object.h, not an exported symbol. Under `Py_LIMITED_API` at 3.11 and above it is
// additionally a macro wrapping itself, which V expands before the declaration is ever
// resolved and the compiler then reports `expected declaration specifiers ... before
// '(' token` from inside Python's own header. `PyType_IsSubtype` is exported and says
// the same thing once identity is added.
// vpy_not_implemented returns the `NotImplemented` singleton.
//
// Through an accessor because `Py_NotImplemented` is a macro over `&_Py_NotImplementedStruct`,
// and V expands it before the declaration is resolved: the compiler then reports "the
// object called is not a function nor a pointer to function" from inside object.h.
PyObject *vpy_not_implemented(void) {
	Py_INCREF(Py_NotImplemented);
	return Py_NotImplemented;
}

int vpy_type_check(PyObject *o, PyTypeObject *type) {
	if (o == NULL || type == NULL) {
		return 0;
	}
	if ((PyObject *)type == (PyObject *)o) {
		return 1;
	}
	return PyType_IsSubtype(Py_TYPE(o), type);
}

Py_ssize_t vpy_tuple_size(PyObject *self) {
	if (self == NULL) {
		return 0;
	}
	return PyTuple_Size(self);
}

Py_ssize_t vpy_ob_size(PyObject *self) {
	// `Py_SIZE` is a macro over a struct field. The function that answers the same
	// question for an arbitrary object does not exist, so the size of a non-container
	// is reported as zero, which is what the runtime uses it for anyway: deciding
	// whether a sequence argument is a tuple or a list.
	(void)self;
	return 0;
}

void vpy_type_free(PyObject *self) {
	Py_DECREF(self);
}

#else

void *vpy_memcpy(void *dst, const void *src, size_t n) {
	return memcpy(dst, src, n);
}

void *vpy_type_ptr(PyObject *self) {
	return (void *)Py_TYPE(self);
}

// vpy_is_limited_api reports which CPython API this object was compiled against.
//
// A run-time answer rather than a compile-time one because V's `$if` cannot see a
// `-cflags` define. The two module-creation paths both compile either way; only one of
// them links against an abi3 build.
int vpy_is_limited_api(void) {
#ifdef vcraft_limited_api
	return 1;
#else
	return 0;
#endif
}

// vpy_call_exec invokes the generated `Py_mod_exec` callback.
//
// The return value is CPython's: 0 for success, -1 with an exception set. vcraft
// returns it rather than checking, because only the generated code knows whether the
// classes it tried to attach actually were.
int vpy_call_exec(void *fn_ptr, void *module) {
	int (*exec_fn)(PyObject *) = (int (*)(PyObject *))fn_ptr;
	return exec_fn((PyObject *)module);
}

// vpy_hash returns an object's default hash.
//
// `PyObject_Hash` is not in the limited API, and under `Py_LIMITED_API` a type's
// `tp_hash` has to be filled with a function that reaches the hash through whatever the
// stable ABI offers. There is nothing it offers here, so an abi3 build reports -1,
// which CPython reads as "hash failed" -- the correct answer for a type whose hash is
// identity, since an address-based hash cannot be computed without the concrete object
// header.
Py_hash_t vpy_hash(PyObject *self) {
	// The address, shifted right by four bits: the low bits of a pointer are always
	// zero, so folding them in would halve the hash's range for nothing.
	//
	// `_Py_HashPointer` is not available under `Py_LIMITED_API`, so the shift is done
	// here rather than through it. An abi3 build that used the helper would fail to
	// compile on an implicit declaration.
	return (Py_hash_t)((size_t)self >> 4);
}

// vpy_hash_bits reports the width of `Py_hash_t`, which is a `long` and therefore
// platform dependent: 64 bits where `long` is 64, 32 where it is not.
long vpy_hash_bits(void) {
	return (long)sizeof(Py_hash_t) * 8;
}

// vpy_type_check reports whether an object is an instance of a type, subclasses
// included.
//
// Written here rather than called because `PyObject_TypeCheck` is a `static inline` in
// object.h, not an exported symbol. Under `Py_LIMITED_API` at 3.11 and above it is
// additionally a macro wrapping itself, which V expands before the declaration is ever
// resolved and the compiler then reports `expected declaration specifiers ... before
// '(' token` from inside Python's own header. `PyType_IsSubtype` is exported and says
// the same thing once identity is added.
// vpy_not_implemented returns the `NotImplemented` singleton.
//
// Through an accessor because `Py_NotImplemented` is a macro over `&_Py_NotImplementedStruct`,
// and V expands it before the declaration is resolved: the compiler then reports "the
// object called is not a function nor a pointer to function" from inside object.h.
PyObject *vpy_not_implemented(void) {
	Py_INCREF(Py_NotImplemented);
	return Py_NotImplemented;
}

int vpy_type_check(PyObject *o, PyTypeObject *type) {
	if (o == NULL || type == NULL) {
		return 0;
	}
	if ((PyObject *)type == (PyObject *)o) {
		return 1;
	}
	return PyType_IsSubtype(Py_TYPE(o), type);
}

Py_ssize_t vpy_tuple_size(PyObject *self) {
	if (self == NULL) {
		return 0;
	}
	return PyTuple_GET_SIZE(self);
}

Py_ssize_t vpy_ob_size(PyObject *self) {
	return (Py_ssize_t)Py_SIZE(self);
}

void vpy_type_free(PyObject *self) {
	Py_TYPE(self)->tp_free(self);
}

#endif

void *vpy_instance_alloc(size_t n) {
	return PyObject_Malloc(n);
}

void vpy_instance_free(void *p) {
	PyObject_Free(p);
}

PyObject *vpy_none(void) {
	return Py_None;
}

PyObject *vpy_notimplemented(void) {
	return Py_NotImplemented;
}

PyObject *vpy_bool_type(void) {
	return (PyObject *)&PyBool_Type;
}

PyObject *vpy_long_type(void) {
	return (PyObject *)&PyLong_Type;
}

PyObject *vpy_float_type(void) {
	return (PyObject *)&PyFloat_Type;
}

PyObject *vpy_str_type(void) {
	return (PyObject *)&PyUnicode_Type;
}

PyObject *vpy_bytes_type(void) {
	return (PyObject *)&PyBytes_Type;
}

PyObject *vpy_tuple_type(void) {
	return (PyObject *)&PyTuple_Type;
}

PyObject *vpy_list_type(void) {
	return (PyObject *)&PyList_Type;
}

PyObject *vpy_dict_type(void) {
	return (PyObject *)&PyDict_Type;
}

PyObject *vpy_module_type(void) {
	return (PyObject *)&PyModule_Type;
}

PyObject *vpy_exc_type_error(void) {
	return PyExc_TypeError;
}

PyObject *vpy_exc_value_error(void) {
	return PyExc_ValueError;
}

PyObject *vpy_exc_runtime_error(void) {
	return PyExc_RuntimeError;
}

PyObject *vpy_exc_not_implemented_error(void) {
	return PyExc_NotImplementedError;
}

PyObject *vpy_exc_attribute_error(void) {
	return PyExc_AttributeError;
}

PyObject *vpy_exc_index_error(void) {
	return PyExc_IndexError;
}

PyObject *vpy_exc_key_error(void) {
	return PyExc_KeyError;
}

PyObject *vpy_exc_stop_iteration(void) {
	return PyExc_StopIteration;
}

PyObject *vpy_exc_memory_error(void) {
	return PyExc_MemoryError;
}

PyObject *vpy_exc_system_error(void) {
	return PyExc_SystemError;
}

PyObject *vpy_exc_zero_division_error(void) {
	return PyExc_ZeroDivisionError;
}

PyObject *vpy_exc_arithmetic_error(void) {
	return PyExc_ArithmeticError;
}

PyObject *vpy_exc_overflow_error(void) {
	return PyExc_OverflowError;
}
