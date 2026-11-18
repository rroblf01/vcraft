// Accessors for CPython symbols that are data rather than functions.
//
// The V C backend does not emit prototypes for `fn C.` declarations, so this
// header is required for the generated C to see both the accessors below and
// the CPython declarations they rely on. See vlib/vcraft/cpython.c.v.

#ifndef VCRAFT_SHIM_H
#define VCRAFT_SHIM_H

#include <Python.h>
// The limited API's <Python.h> does not pull in <string.h>, and the inline `vpy_memcpy`
// below needs `memcpy` declared in every unit that includes this header.
#include <string.h>
#include <errno.h>

// Constants that are macros in Python.h. V cannot read a C macro, so they are
// surfaced as functions.
int vpy_python_api_version(void);
void vpy_add_v_frame(const char *file, int line, const char *func);
void vpy_critical_begin(void *cs, void *op);
void vpy_mark_boxed(void *type, size_t size);
int vpy_is_boxed(void *type);
size_t vpy_boxed_size(void *type);
void vpy_release_closure(void *f);
void vpy_critical_end(void *cs);
unsigned long vpy_version_hex(void);
const char *vpy_version_string(void);
Py_ssize_t vpy_ssize_size(void);
int vpy_int_size(void);

// Writes the unqualified type name of `o` into `buf` (NUL-terminated, truncated to
// `n - 1` bytes) and returns its length, or -1 with an exception set. Reading the
// name with `PyType_GetName` and the cached UTF-8 form allocates nothing, where
// `PyObject_GetAttrString(..., "__name__")` builds a temporary key str per call.
int vpy_type_name_into(PyObject *o, char *buf, size_t n);

// Real C sizes of the structs the runtime mirrors, so `check_layout` can prove
// the mirrors still agree with the headers the extension was built against.
Py_ssize_t vpy_size_PyModuleDef(void);
Py_ssize_t vpy_size_PyMethodDef(void);
// The object header's size, inline: every method, property and constructor of a class
// reaches its state as `obj + sizeof(PyObject)`, so an out-of-line call here was paid on
// every one of them. Header-only, so the generated unit sees the constant.
static inline Py_ssize_t vpy_size_PyObject(void) {
	return (Py_ssize_t)sizeof(PyObject);
}
unsigned int vpy_tpflags_default(void);

// vpy_complex_parts reads a complex's two halves in one step, returning 0 for anything
// that is not a complex. A full build reads them straight out of the object, inline: the
// check and the two `PyComplex_*AsDouble` calls it replaces were three calls into other
// units on every complex argument. The limited API hides the struct, so an abi3 build
// keeps the calls, gathered in `vpy_complex_parts_slow`.
int vpy_complex_parts_slow(void *o, double *re, double *im);
#ifndef Py_LIMITED_API
static inline int vpy_complex_parts(void *o, double *re, double *im) {
	if (o == NULL || !PyComplex_Check((PyObject *)o)) {
		return 0;
	}
	Py_complex value = ((PyComplexObject *)o)->cval;
	*re = value.real;
	*im = value.imag;
	return 1;
}
#else
#define vpy_complex_parts vpy_complex_parts_slow
#endif
unsigned int vpy_tpflags_weakref(void);
unsigned int vpy_tpflags_managed_dict(void);

// A real memcpy, reached through a prototype.
//
// V's `memcpy` builtin compiles to `v_memcpy`, whose declaration the backend emits
// late in the file, so calling it from a helper declared early trips gcc's implicit
// declaration rule. This is the same reason the module includes <Python.h>.
//
// Inline in the header rather than defined in shim.c: a class's state is a few bytes,
// copied on every construction and every field write, and only a `memcpy` the compiler
// can see becomes a couple of moves. `memcpy` is a C library function, so the limited
// API does not hide it; `<Python.h>` has already declared it.
static inline void *vpy_memcpy(void *dst, const void *src, size_t n) {
	return memcpy(dst, src, n);
}

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
int vpy_gil_ensure(void);
void vpy_gil_release(int state);

// Declaring that a module runs without the GIL.
//
// `Py_MOD_GIL_NOT_USED` is a macro, which V cannot read, and
// `PyUnstable_Module_SetGIL` only exists when compiling against free-threaded
// headers, so both go through here. The V side calls them only under
// `$if vcraft_free_threaded`, which the build passes exactly when the interpreter
// is free-threaded.
void *vpy_mod_gil_not_used(void);
int vpy_module_set_gil(void *module, void *gil);

// Fills the head of a module definition with the bytes `PyModuleDef_HEAD_INIT` would
// put there.
//
// CPython 3.15's `PyModuleDef_Init` rejects a free-threaded module whose head lacks
// `_Py_STATICALLY_ALLOCATED_FLAG`, which only the macro's initializer sets; a
// definition built field by field starts zeroed. The head is copied from a static
// definition and the fields are filled in after. Compiles everywhere, a no-op on a GIL
// build, and is called only under `$if vcraft_free_threaded`.
void vpy_module_def_head(void *dst, size_t n);

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
int vpy_is_exact_bytes(void *obj);

// Handing a native-backed slice to Python as a writable `memoryview`, with no copy.
//
// A `@[vc_memoryview]` return passes the slice's `data` and its allocation `owner`
// (the start of the block, which `owner` may be NULL to free nothing). The exporter
// object created here implements the buffer protocol over `data` and frees `owner`
// with `PyObject_Free` when the last memoryview of it is released. `kind` is the
// element's view format -- 0 unsigned integer, 1 signed integer, 2 float, 3 bool --
// and `itemsize` picks the width inside it. Returns a new memoryview, or NULL with an
// exception set.
PyObject *vpy_buffer_export(void *data, void *owner, Py_ssize_t nbytes,
	Py_ssize_t itemsize, int kind);

// vpy_buffer_fill_typed fills a `Py_buffer` with a typed view of a native-backed slice,
// for a class whose first `@[vc_buffer_typed]` field implements the buffer protocol.
// The default `PyBuffer_FillInfo` only expresses a byte view (itemsize 1, format "B");
// this sets `itemsize` and `format` from the element so `memoryview(instance)` is typed.
// Takes its own reference on `exporter`, as `PyBuffer_FillInfo` does. Returns CPython's
// status (0 on success, -1 with an exception set).
int vpy_buffer_fill_typed(void *view, void *exporter, void *data, Py_ssize_t nbytes,
	Py_ssize_t itemsize, int kind, int readonly, int flags);

PyObject *vpy_none(void);
PyObject *vpy_notimplemented(void);
PyObject *vpy_import(const char *name);
PyObject *vpy_bool_type(void);
PyObject *vpy_long_type(void);
PyObject *vpy_float_type(void);
PyObject *vpy_str_type(void);
PyObject *vpy_bytes_type(void);
PyObject *vpy_tuple_type(void);
PyObject *vpy_list_type(void);
PyObject *vpy_set_type(void);
PyObject *vpy_get_dict(PyObject *self, void *closure);
int vpy_set_dict(PyObject *self, PyObject *value, void *closure);
void vpy_enable_managed_dict(PyObject *type);
void vpy_enable_mapping(PyObject *type, void *mp_length, void *mp_subscript, void *mp_ass_subscript);
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
PyObject *vpy_exc_buffer_error(void);
PyObject *vpy_exc_lookup_error(void);
PyObject *vpy_exc_eof_error(void);
PyObject *vpy_exc_os_error(void);
PyObject *vpy_exc_file_not_found_error(void);
PyObject *vpy_exc_file_exists_error(void);
PyObject *vpy_exc_permission_error(void);
PyObject *vpy_exc_is_a_directory_error(void);
PyObject *vpy_exc_not_a_directory_error(void);
PyObject *vpy_exc_timeout_error(void);
PyObject *vpy_exc_connection_error(void);
PyObject *vpy_exc_connection_refused_error(void);
PyObject *vpy_exc_connection_reset_error(void);
PyObject *vpy_exc_connection_aborted_error(void);
PyObject *vpy_exc_broken_pipe_error(void);
PyObject *vpy_exc_blocking_io_error(void);
PyObject *vpy_exc_interrupted_error(void);
PyObject *vpy_exc_child_process_error(void);
PyObject *vpy_exc_process_lookup_error(void);
void vpy_raise_errno(int code, const char *context, Py_ssize_t len);
PyObject *vpy_running_loop(void);
void vpy_set_logger_name(const char *name);
PyObject *vpy_logger(void);
PyObject *vpy_cached_module(int which);
int vpy_nd_get(void *obj, void *view);
int vpy_view_ndim(void *view);
Py_ssize_t vpy_view_shape(void *view, int i);
Py_ssize_t vpy_view_stride(void *view, int i);
Py_ssize_t vpy_view_itemsize(void *view);
int vpy_view_readonly(void *view);
const char *vpy_view_format(void *view);
PyObject *vpy_async_settle_fn(void);
PyObject *vpy_new_runtime_error(void);
PyObject *vpy_structseq_type(const char *name, const char *const *fields, int count,
	const char *doc);
PyObject *vpy_structseq_new(PyObject *type);
void vpy_structseq_set(PyObject *seq, Py_ssize_t i, PyObject *value);
PyObject *vpy_structseq_pack(PyObject *type, PyObject **items, Py_ssize_t count);
PyObject *vpy_struct_field(PyObject *obj, const char *key, Py_ssize_t index, Py_ssize_t count,
	const char *name, Py_ssize_t name_len);
int vpy_last_errno(void);
void vpy_set_error_utf8(PyObject *exc, const char *msg, Py_ssize_t len);
int vpy_is_complex(void *o);
int vpy_slot_bf_getbuffer(void);
int vpy_slot_bf_releasebuffer(void);
int vpy_slot_mp_length(void);
int vpy_slot_mp_subscript(void);
int vpy_slot_mp_ass_subscript(void);
int vpy_slot_mod_exec(void);
int vpy_slot_mod_create(void);

// Fast paths for the common argument types, and an instance check that borrows.
int vpy_exact_long_as_i64(PyObject *o, long long *out);
int vpy_is_instance(PyObject *o, PyObject *type);

// Reading a list or a tuple: a borrowed item, and one-pass conversions of the leading
// items that need no Python call.
PyObject *vpy_seq_item(PyObject *o, Py_ssize_t i);
Py_ssize_t vpy_seq_fill_f64(PyObject *o, double *out, Py_ssize_t n);
Py_ssize_t vpy_seq_fill_i64(PyObject *o, long long *out, Py_ssize_t n);

// Building a list from a slice of plain numbers in one pass.
PyObject *vpy_list_from_i64(const long long *items, Py_ssize_t n);
// vpy_list_from_str builds a `list[str]` from a V `[]string` in one pass, so the per-element
// `to_py_string` call and the boxing closure in `to_py_list` are not paid per element.
// `data` points at the slice's backing, whose elements are V strings: `{str, len, is_lit}`.
PyObject *vpy_list_from_str(const void *data, Py_ssize_t count);
// vpy_list_from_bytes builds a `list[bytes]` from a V `[][]u8` in one pass.
// `data` points at the slice's backing, whose elements are V slices: `{data, len, cap}`.
PyObject *vpy_list_from_bytes(const void *data, Py_ssize_t count);
PyObject *vpy_list_from_f64(const double *items, Py_ssize_t n);

// Calling a Python callable with borrowed positional arguments, as a new reference.
PyObject *vpy_call(PyObject *callee, PyObject **args, Py_ssize_t nargs);
PyObject *vpy_call_kw(PyObject *callee, PyObject **args, Py_ssize_t nargs, PyObject *kwargs);
uint64_t vpy_checksum(const unsigned char *data, Py_ssize_t len);
int64_t vpy_sum_i64(const int64_t *data, Py_ssize_t len);
double vpy_sum_f64(const double *data, Py_ssize_t len);

#endif // VCRAFT_SHIM_H

/* Arena allocator for per-request memory */
typedef struct vpy_arena vpy_arena;
vpy_arena *vpy_arena_new(void);
void *vpy_arena_alloc(vpy_arena *a, size_t size);
void vpy_arena_free(vpy_arena *a);

/* Batch marshalling: V array -> Python list (single C call) */
PyObject *vpy_list_from_i64(const long long *ptr, Py_ssize_t len);
PyObject *vpy_list_from_f64(const double *ptr, Py_ssize_t len);
PyObject *vpy_bytes_from_ptr(const char *ptr, Py_ssize_t len);

/* Zero-copy: create a memoryview over V-owned memory (caller must keep V memory alive) */
PyObject *vpy_memoryview_from_ptr(const void *ptr, Py_ssize_t len);

/* Size of a pointer, for preheader calculations */
size_t vpy_size_voidptr(void);

/* Enable weak references on a heap type (Python 3.11 fallback, where managed
   weakrefs are not available). Sets tp_weaklistoffset to point at the weakref
   list stored at the end of the instance. */
void vpy_enable_weakref(PyObject *type, Py_ssize_t weaklistoffset);
void vpy_set_tp_descr_get(PyObject *type, void *fn);
void vpy_set_tp_descr_set(PyObject *type, void *fn);
