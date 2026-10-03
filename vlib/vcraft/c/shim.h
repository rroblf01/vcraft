// Accessors for CPython symbols that are data rather than functions.
//
// The V C backend does not emit prototypes for `fn C.` declarations, so this
// header is required for the generated C to see both the accessors below and
// the CPython declarations they rely on. See vlib/vcraft/cpython.c.v.

#ifndef VCRAFT_SHIM_H
#define VCRAFT_SHIM_H

#include <Python.h>

// Constants that are macros in Python.h. V cannot read a C macro, so they are
// surfaced as functions.
int vpy_python_api_version(void);
unsigned long vpy_version_hex(void);
const char *vpy_version_string(void);
Py_ssize_t vpy_ssize_size(void);
int vpy_int_size(void);

// Real C sizes of the structs the runtime mirrors, so `check_layout` can prove
// the mirrors still agree with the headers the extension was built against.
Py_ssize_t vpy_size_PyModuleDef(void);
Py_ssize_t vpy_size_PyMethodDef(void);

// CPython's singletons, which are exported as data.
PyObject *vpy_none(void);
PyObject *vpy_notimplemented(void);
PyObject *vpy_bool_type(void);
PyObject *vpy_long_type(void);
PyObject *vpy_float_type(void);
PyObject *vpy_str_type(void);
PyObject *vpy_bytes_type(void);
PyObject *vpy_tuple_type(void);
PyObject *vpy_list_type(void);
PyObject *vpy_dict_type(void);
PyObject *vpy_module_type(void);

// The builtin exception set vcraft maps V errors onto.
PyObject *vpy_exc_type_error(void);
PyObject *vpy_exc_value_error(void);
PyObject *vpy_exc_runtime_error(void);
PyObject *vpy_exc_not_implemented_error(void);
PyObject *vpy_exc_attribute_error(void);
PyObject *vpy_exc_index_error(void);
PyObject *vpy_exc_key_error(void);
PyObject *vpy_exc_stop_iteration(void);
PyObject *vpy_exc_memory_error(void);
PyObject *vpy_exc_system_error(void);
PyObject *vpy_exc_overflow_error(void);

#endif // VCRAFT_SHIM_H
