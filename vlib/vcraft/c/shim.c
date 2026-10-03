// Accessors for CPython symbols that are data rather than functions.
//
// V cannot name a C global, so every CPython singleton the runtime needs gets a
// one-line accessor here. This file is compiled into the extension by the
// `#flag @VMODROOT/c/shim.c` directive in vlib/vcraft/cpython.c.v.

#include "shim.h"

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

void *vpy_memcpy(void *dst, const void *src, size_t n) {
	return memcpy(dst, src, n);
}

void *vpy_type_ptr(PyObject *self) {
	return (void *)Py_TYPE(self);
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

PyObject *vpy_exc_overflow_error(void) {
	return PyExc_OverflowError;
}
