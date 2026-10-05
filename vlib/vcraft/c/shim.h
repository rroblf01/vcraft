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
Py_ssize_t vpy_size_PyObject(void);
unsigned int vpy_tpflags_default(void);

// A real memcpy, reached through a prototype.
//
// V's `memcpy` builtin compiles to `v_memcpy`, whose declaration the backend emits
// late in the file, so calling it from a helper declared early trips gcc's implicit
// declaration rule. This is the same reason the module includes <Python.h>.
void *vpy_memcpy(void *dst, const void *src, size_t n);

// Calls the base deallocator for a heap type.
//
// `Py_TYPE(self)->tp_free(self)` is the required last step of a subtype's
// `tp_dealloc`, and it needs the full PyTypeObject layout, which the runtime does
// not mirror.
void vpy_type_free(PyObject *self);
void *vpy_type_ptr(PyObject *self);
Py_ssize_t vpy_ob_size(PyObject *self);
Py_ssize_t vpy_tuple_size(PyObject *self);
int vpy_is_limited_api(void);
int vpy_call_exec(void *fn_ptr, void *module);
Py_hash_t vpy_hash(PyObject *self);
long vpy_hash_bits(void);
int vpy_type_check(PyObject *o, PyTypeObject *type);
PyObject *vpy_not_implemented(void);

// Instance storage.
//
// A class instance keeps its V state in memory CPython owns, so it is released
// with the matching allocator and no V object is ever left for the garbage
// collector to find or lose.
void *vpy_instance_alloc(size_t n);
void vpy_instance_free(void *p);

// CPython's singletons, which are exported as data.
// Cycle collection.
//
// `visitproc` is a function-pointer typedef and `traverseproc` takes one, so V cannot
// spell a `tp_traverse` trampoline: it would have to declare a struct field of a callback
// type. These three do the calling instead, so the trampoline in V is an ordinary
// function that hands its work over.
int vpy_visit(void *obj, void *visit, void *arg);
int vpy_traverse_ref(void *ref, void *visit, void *arg);
void vpy_gc_untrack(void *self);
void vpy_gc_track(void *self);

// The state chain, one per thread.
//
// Every generated trampoline publishes the state block it loaded so a method of a
// subclass can reach what it inherited. With the GIL held that could be one global,
// but a `@[vc_gil]` call runs without it: two threads in two trampolines would publish
// into the same slots and each would read the other's instance. So the chain lives in
// thread-local storage, keyed once at module import.
//
// `enter_state` and `leave_state` move eight pointers, which is what `vcraft` passes
// around opaquely; the level accessors read and write single slots.
void vpy_state_init(void);
void *vpy_enter_state(void *block);
void vpy_leave_state(void *previous);
void vpy_publish_state(int level, void *ptr);
void *vpy_state_at(int level);

// The type object itself.
//
// A heap type with `Py_TPFLAGS_HAVE_GC` is tracked by the collector too, so `tp_traverse`
// and `tp_clear` are called on the type as well as on its instances. A type's own
// references -- its dict, its bases, its MRO -- are not in the state block, so that case
// is handed to CPython's own implementation of `type`.
int vpy_is_type_object(void *self);
int vpy_type_traverse(void *self, void *visit, void *arg);
void vpy_type_clear(void *self);

// Releasing the global interpreter lock.
//
// `Py_BEGIN_ALLOW_THREADS` is a macro over `PyEval_SaveThread`, so V cannot spell it:
// the backend emits no prototype for a macro and calling it blind passes the wrong
// shape. These two do the calling instead. The saved thread state travels as a void
// pointer because V cannot name `PyThreadState *` either, for the same reason.
void *vpy_allow_threads(void);
void vpy_end_allow_threads(void *state);

// The buffer protocol.
//
// `Py_buffer` is opaque under the limited API, so V cannot hold one, read its `buf`
// and `len`, or pass `PyBUF_SIMPLE`. These five do all of that in C, and V only ever
// sees the view as an opaque pointer it hands back.
void *vpy_buffer_new(void);
int vpy_buffer_get(void *obj, void *view);
void *vpy_buffer_ptr(void *view);
long vpy_buffer_len(void *view);
void vpy_buffer_release(void *view);

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
PyObject *vpy_exc_zero_division_error(void);
PyObject *vpy_exc_arithmetic_error(void);

#endif // VCRAFT_SHIM_H
