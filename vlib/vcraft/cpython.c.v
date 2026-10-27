module vcraft

// Declarations for the slice of the CPython C API that the runtime needs.
//
// The #include is load-bearing. The V C backend does not emit prototypes for
// `fn C.` declarations, so without the real header in scope gcc applies the C89
// implicit-declaration rule and treats every one of these calls as returning
// int. That truncates the returned PyObject pointer to 32 bits and crashes the
// interpreter on a module that loaded perfectly. It also makes the V compiler
// fall back to its compatibility compiler, which hides the real diagnostic
// behind a confusing C error.
//
// The include path is not known at authoring time, so vcraft passes it with
// `-cflags -I<sysconfig include>` when it invokes the compiler.

// Pulled into the extension by the driver. Accessors for CPython data symbols.
#flag @VMODROOT/c/shim.c
#include "c/shim.h"
// glibc declares `struct dl_phdr_info` and `dl_iterate_phdr` only with
// `_GNU_SOURCE`, which the header below needs for its Linux root walk. A `#define`
// there comes too late (system headers precede it in the generated TU), so it
// arrives as a compiler flag instead. Here rather than in any one driver, so every
// way of building an extension gets it: `vcraft build`, `scripts/build-example.sh`
// and plain `v`.
$if linux {
	#flag -D_GNU_SOURCE
}
// Before V's collector starts on macOS; see the header.
#include "c/gc_preinit.h"

#include <Python.h>

// ---------------------------------------------------------------- lifecycle

fn C.vpy_gc_enter()

// gc_enter makes the calling thread known to V's collector; see `vpy_gc_enter` in
// `c/gc_preinit.h`. The generated glue calls it first thing in every function, so an
// extension can be called from any Python thread.
@[inline]
pub fn gc_enter() {
	C.vpy_gc_enter()
}

fn C.vpy_python_api_version() int

fn C.vpy_version_hex() u64

fn C.vpy_version_string() &char

fn C.vpy_ssize_size() isize

fn C.vpy_type_name_into(o voidptr, buf voidptr, n isize) int

fn C.vpy_size_PyModuleDef() isize

fn C.vpy_size_PyMethodDef() isize

fn C.vpy_size_PyObject() isize

fn C.vpy_tpflags_default() u32

fn C.PyType_FromSpec(spec voidptr) voidptr

fn C.PyType_GenericAlloc(typ voidptr, nitems isize) voidptr

fn C.PyErr_NoMemory()

fn C.vpy_memcpy(dst voidptr, src voidptr, n usize) voidptr

fn C.vpy_type_free(self voidptr)
fn C.vpy_visit(obj voidptr, visit voidptr, arg voidptr) int
fn C.vpy_traverse_ref(field voidptr, visit voidptr, arg voidptr) int
fn C.vpy_gc_untrack(self voidptr)
fn C.Py_ReprLeave(self voidptr)
fn C.vpy_allow_threads() voidptr
fn C.vpy_end_allow_threads(state voidptr)
fn C.vpy_gil_ensure() int
fn C.vpy_gil_release(state int)
fn C.vpy_mod_gil_not_used() voidptr
fn C.vpy_module_set_gil(m voidptr, gil voidptr) int
fn C.vpy_module_def_head(dst voidptr, n usize)
fn C.vpy_buffer_new() voidptr
fn C.vpy_buffer_get(obj voidptr, view voidptr) int
fn C.vpy_buffer_ptr(view voidptr) voidptr
fn C.vpy_buffer_len(view voidptr) int
fn C.vpy_buffer_release(view voidptr)
fn C.vpy_is_exact_bytes(obj voidptr) int
fn C.vpy_buffer_export(data voidptr, owner voidptr, nbytes isize, itemsize isize, kind int) voidptr
fn C.vpy_buffer_fill_typed(view voidptr, exporter voidptr, data voidptr, nbytes isize, itemsize isize, kind int, readonly int, flags int) int
fn C.vpy_state_init()
fn C.vpy_enter_state(block voidptr) voidptr
fn C.vpy_leave_state(previous voidptr)
fn C.vpy_publish_state(level int, ptr voidptr)
fn C.vpy_state_at(level int) voidptr
fn C.vpy_is_type_object(self voidptr) int
fn C.vpy_type_traverse(self voidptr, visit voidptr, arg voidptr) int
fn C.vpy_type_clear(self voidptr)
fn C.vpy_gc_track(self voidptr)

fn C.vpy_type_ptr(self voidptr) voidptr

fn C.vpy_ob_size(self voidptr) isize

fn C.vpy_tuple_size(self voidptr) isize

// `Py_LIMITED_API` arrives on the compiler's `-cflags`, set from the project's `abi3`
// floor, and this file picks it up from there rather than hard-coding a version.
//
// Under the limited API CPython hides the concrete object structs behind the stable
// ABI, so the runtime reaches everything through functions instead of reading struct
// fields. The `$if` is optional: a full build does not define the symbol at all, and
// without the `?` V rejects the whole conditional.
$if vcraft_limited_api ? {
	#flag -DPy_LIMITED_API=0x030D0000
}

// ------------------------------------------------------------------ object

fn C.vpy_none() voidptr

fn C.vpy_import(name voidptr) voidptr

fn C.vpy_notimplemented() voidptr

fn C.Py_Is(a voidptr, b voidptr) int

fn C.Py_IncRef(o voidptr)

fn C.Py_DecRef(o voidptr)

fn C.PyObject_Type(o voidptr) voidptr

fn C.PyObject_Hash(o voidptr) isize

fn C.Py_ReprEnter(o voidptr) int

fn C.PyType_IsSubtype(a voidptr, b voidptr) int

fn C.PyObject_Str(o voidptr) voidptr

fn C.PyObject_Repr(o voidptr) voidptr

fn C.PyObject_Length(o voidptr) isize

fn C.PyNumber_Check(o voidptr) int

fn C.PyNumber_Index(o voidptr) voidptr

fn C.PyLong_AsLongLongAndOverflow(o voidptr, overflow voidptr) i64

// --------------------------------------------------------------- booleans

fn C.PyBool_FromLong(v i64) voidptr

fn C.PyObject_IsTrue(o voidptr) int

// ---------------------------------------------------------------- integers

fn C.PyLong_FromLongLong(v i64) voidptr

fn C.PyLong_AsLongLong(o voidptr) i64

fn C.PyLong_FromUnsignedLongLong(v u64) voidptr

fn C.PyLong_AsUnsignedLongLong(o voidptr) u64

// ------------------------------------------------------------------ floats

fn C.PyFloat_FromDouble(v f64) voidptr

fn C.PyFloat_AsDouble(o voidptr) f64

// ----------------------------------------------------------------- complex

// `PyComplex_Check` is a macro over `PyObject_TypeCheck`, so it goes through the shim.
// The other three are exported functions even under the limited API.
fn C.PyComplex_FromDoubles(re f64, im f64) voidptr

fn C.PyComplex_RealAsDouble(o voidptr) f64

fn C.PyComplex_ImagAsDouble(o voidptr) f64

fn C.vpy_is_complex(o voidptr) int

// ----------------------------------------------------------------- strings

fn C.PyUnicode_FromStringAndSize(s voidptr, len isize) voidptr
fn C.PyUnicode_FromString(s voidptr) voidptr
fn C.PyErr_SetObject(exc voidptr, value voidptr)

fn C.PyUnicode_AsUTF8AndSize(o voidptr, len voidptr) voidptr

fn C.PyUnicode_FromFormat(format voidptr) voidptr

fn C.PyBytes_FromStringAndSize(s voidptr, len isize) voidptr

fn C.PyBytes_AsStringAndSize(o voidptr, s voidptr, len voidptr) int

// ------------------------------------------------------------------ tuples

fn C.PyTuple_Size(t voidptr) isize

fn C.PyTuple_GetItem(t voidptr, i isize) voidptr

fn C.PyTuple_New(size isize) voidptr

fn C.PyTuple_SetItem(t voidptr, i isize, item voidptr) int

// ------------------------------------------------------------- containers

fn C.PyList_New(size isize) voidptr

fn C.PyList_Append(l voidptr, item voidptr) int

fn C.PyList_SetItem(l voidptr, i isize, item voidptr) int

fn C.PySequence_GetItem(o voidptr, i isize) voidptr

fn C.PyDict_New() voidptr

fn C.PyDict_SetItemString(d voidptr, key voidptr, value voidptr) int

fn C.PyDict_GetItemString(d voidptr, key voidptr) voidptr

fn C.PyDict_SetItem(d voidptr, key voidptr, value voidptr) int

fn C.PyDict_Next(d voidptr, pos &isize, key &voidptr, value &voidptr) int

fn C.PyObject_GetAttrString(o voidptr, name voidptr) voidptr

fn C.PyObject_SetAttrString(o voidptr, name voidptr, value voidptr) int
fn C.PyObject_HasAttrString(o voidptr, name voidptr) int

// ------------------------------------------------------------------ module

fn C.PyModule_Create2(def voidptr, apiver int) voidptr

// The multi-phase initialisation entry points. `PyModule_Create2` is single-phase and
// is not part of the limited API, so an abi3 build has to declare its own `Py_mod_exec`
// slot and let the interpreter call it.
fn C.PyModuleDef_Init(def voidptr) voidptr

fn C.PyModule_AddFunctions(module voidptr, functions voidptr) int

fn C.vpy_is_limited_api() int
fn C.vpy_call_exec(fn_ptr voidptr, module voidptr) int
fn C.vpy_hash(self voidptr) isize
fn C.vpy_hash_bits() isize
fn C.vpy_type_check(o voidptr, typ voidptr) int

fn C.vpy_exact_long_as_i64(o voidptr, out &i64) int

fn C.vpy_is_instance(o voidptr, typ voidptr) int

fn C.vpy_seq_item(o voidptr, i isize) voidptr

fn C.vpy_seq_fill_f64(o voidptr, out &f64, n isize) isize

fn C.vpy_seq_fill_i64(o voidptr, out &i64, n isize) isize

fn C.vpy_list_from_i64(items &i64, n isize) voidptr

fn C.vpy_list_from_f64(items &f64, n isize) voidptr

fn C.vpy_list_from_str(items voidptr, n isize) voidptr

fn C.vpy_list_from_bytes(items voidptr, n isize) voidptr

// vpy_call calls a Python callable with borrowed positional arguments, returning a new
// reference or null with an exception set.
fn C.vpy_call(callee voidptr, args voidptr, nargs isize) voidptr

fn C.vpy_not_implemented() voidptr
fn C.PyTuple_New(size isize) voidptr
fn C.PyTuple_SET_ITEM(tuple voidptr, index isize, item voidptr)

fn C.PyModule_AddFunctions(module voidptr, functions voidptr) int



// Py_mod_exec is the multi-phase slot id and Py_mod_create is the one before it. They are
// macros, and PEP 820 renumbered them in CPython 3.15, so they come from the headers
// through the shim rather than as constants.
fn C.vpy_slot_mod_exec() int

fn C.vpy_slot_mod_create() int

fn C.PyModule_GetDict(m voidptr) voidptr

fn C.PyModule_AddObject(m voidptr, name voidptr, value voidptr) int

fn C.PyModule_AddObjectRef(m voidptr, name voidptr, value voidptr) int

// ------------------------------------------------------------------ errors

fn C.PyErr_Occurred() voidptr

fn C.PyErr_SetString(exc voidptr, msg voidptr)

fn C.PyErr_Clear()

fn C.PyErr_ExceptionMatches(exc voidptr) int

fn C.PyErr_Fetch(t voidptr, v voidptr, tb voidptr)

fn C.PyErr_NormalizeException(t voidptr, v voidptr, tb voidptr)

fn C.PyErr_Restore(t voidptr, v voidptr, tb voidptr)

// ------------------------------------------------------- shim, for brevity

fn C.vpy_bool_type() voidptr

fn C.vpy_long_type() voidptr

fn C.vpy_float_type() voidptr

fn C.vpy_str_type() voidptr

fn C.vpy_bytes_type() voidptr

fn C.vpy_tuple_type() voidptr

fn C.vpy_list_type() voidptr

fn C.vpy_dict_type() voidptr

fn C.vpy_module_type() voidptr

fn C.vpy_exc_type_error() voidptr

fn C.vpy_exc_value_error() voidptr

fn C.vpy_exc_runtime_error() voidptr

fn C.vpy_exc_not_implemented_error() voidptr

fn C.vpy_exc_attribute_error() voidptr

fn C.vpy_exc_index_error() voidptr

fn C.vpy_exc_key_error() voidptr

fn C.vpy_exc_stop_iteration() voidptr

fn C.vpy_exc_memory_error() voidptr

fn C.vpy_exc_system_error() voidptr

fn C.vpy_exc_overflow_error() voidptr
fn C.vpy_exc_zero_division_error() voidptr
fn C.vpy_exc_arithmetic_error() voidptr
fn C.vpy_exc_buffer_error() voidptr

// vpy_set_error_utf8 raises an exception with a message given as a pointer and a length,
// so the runtime does not copy a V string into a NUL-terminated buffer first.
fn C.vpy_set_error_utf8(exc voidptr, msg voidptr, len isize)

// ----------------------------------------------------------------- capsules

// PyCapsule carries an arbitrary native pointer across the Python boundary, with a
// destructor that runs when the capsule is collected. It is how a V value that is not
// marshallable -- a handle from a C library, a struct full of pointers -- can still be
// owned by a Python object. All three are part of the stable ABI.
fn C.PyCapsule_New(pointer voidptr, name voidptr, destructor voidptr) voidptr

fn C.PyCapsule_GetPointer(capsule voidptr, name voidptr) voidptr

fn C.PyCapsule_SetName(capsule voidptr, name voidptr) int

// ------------------------------------------------------------------- buffers

// PyBuffer_FillInfo fills a `Py_buffer` for an exporter that shares one contiguous
// run of bytes. It sets `view->obj` to the exporter and takes a reference, which is
// what makes the memoryview keep the instance alive; the generated `bf_releasebuffer`
// and this pair are the whole of the zero-copy contract. Stable ABI.
fn C.PyBuffer_FillInfo(view voidptr, o voidptr, buf voidptr, len isize, readonly int, flags int) int

// The CPython allocator. The state of a class is CPython-owned memory that V's
// collector does not scan, so a native buffer kept in it is owned manually and freed
// by `tp_dealloc`. These are the matching allocator and are part of the stable ABI.
fn C.PyObject_Malloc(n usize) voidptr

fn C.PyObject_Calloc(n usize, size usize) voidptr

fn C.PyObject_Realloc(p voidptr, n usize) voidptr

fn C.PyObject_Free(p voidptr)

// ---------------------------------------------------------------- constants

// PYTHON_API_VERSION, surfaced as a function because V cannot read a C macro.
pub fn python_api_version() int {
	return C.vpy_python_api_version()
}

// Py_GetVersion, the hex value such as 0x030E00A0 for CPython 3.14.
pub fn version_hex() u64 {
	return C.vpy_version_hex()
}

// The interpreter version string, for example "3.14.7 (main, ...)".
pub fn version_string() string {
	return unsafe { &char(C.vpy_version_string()).vstring() }
}

// major.minor of the running interpreter, derived from version_hex.
pub fn version_major_minor() (int, int) {
	value := version_hex()
	return int((value >> 24) & 0xff), int((value >> 16) & 0xff)
}

// METH_NOARGS
pub const meth_noargs = 0x0004

// METH_O
pub const meth_o = 0x0008

// METH_FASTCALL
pub const meth_fastcall = 0x0080

// METH_FASTCALL | METH_KEYWORDS
pub const meth_fastcall_keywords = meth_fastcall | 0x0002

// METH_STATIC makes a `PyMethodDef` entry a static method: CPython passes NULL as the
// receiver, so the trampoline gets no instance. `@[vc_static]` is its only user.
pub const meth_static = 0x0020

// meth_class is CPython's METH_CLASS: the trampoline is a classmethod, so CPython passes
// the class (the subclass on a subclass call) rather than NULL.
pub const meth_class = 0x0010

// Type slot identifiers, from CPython's typeslots.h. A slot id is a macro, so the
// runtime repeats the numbers and `check_layout` would catch a future change only
// by name, not by value. They are part of the stable ABI.
pub const slot_doc = i32(56)

pub const slot_dealloc = i32(52)

pub const slot_init = i32(60)

pub const slot_methods = i32(64)

pub const slot_new = i32(65)

pub const slot_repr = i32(66)

pub const slot_traverse = i32(71)

pub const slot_bases = i32(49)

pub const slot_clear = i32(51)

pub const slot_iter = i32(62)

pub const slot_iternext = i32(63)

pub const slot_hash = i32(59)

pub const slot_richcompare = i32(67)

// The sequence protocol: `__len__`, `__getitem__` and `__contains__` are `sq_*` slots
// rather than `tp_*`, so `len()`, `obj[i]` and `x in obj` reach them.
pub const slot_sq_length = i32(45)

pub const slot_sq_item = i32(44)

pub const slot_sq_contains = i32(41)

// The number protocol. `nb_*` slots are what `+`, `-`, `*`, `&`, `|` and the unary
// operators reach; the ids are the `PyType_Slot` ones, which sit below the `Py_sq_*`
// and `Py_tp_*` ranges. They have not moved across 3.11-3.15 and the codegen suite
// compares them with the installed headers through scripts/check-slot-ids.sh.
pub const slot_nb_add = i32(7)

pub const slot_nb_subtract = i32(36)

pub const slot_nb_multiply = i32(29)

pub const slot_nb_remainder = i32(34)

pub const slot_nb_power = i32(33)

pub const slot_nb_negative = i32(30)

pub const slot_nb_positive = i32(32)

pub const slot_nb_absolute = i32(6)

pub const slot_nb_invert = i32(27)

pub const slot_nb_lshift = i32(28)

pub const slot_nb_rshift = i32(35)

pub const slot_nb_and = i32(8)

pub const slot_nb_xor = i32(38)

pub const slot_nb_or = i32(31)

pub const slot_nb_floor_divide = i32(12)

pub const slot_nb_true_divide = i32(37)

pub const slot_members = i32(72)

pub const slot_getset = i32(73)

// The two buffer-protocol slots are not written down as constants like the `Py_tp_*`
// ones: they are macros whose value PEP 820 changed in CPython 3.15, so they come from
// the headers through the shim. A build with the limited API below 3.15 keeps the old
// value (the alias the headers define for it); a full build reads the new one.
fn C.vpy_slot_bf_getbuffer() int

fn C.vpy_slot_bf_releasebuffer() int

// Py_TPFLAGS_BASETYPE, required before a Python class may be subclassed.
pub const tpflags_basetype = u32(1 << 10)

// Py_TPFLAGS_HAVE_GC, required on any type whose instances hold references to other
// objects. CPython refuses a type that claims it and leaves tp_traverse null, and it
// never collects a type that does not claim it, so an instance in a cycle would leak
// rather than be collected.
pub const tpflags_have_gc = u32(1 << 14)

// ------------------------------------------------------------- C layouts
//
// Pointer-like members are declared as voidptr and every field sits in a `mut:`
// section. V's ownership rules would otherwise require initialisers for
// reference-typed fields, and an omitted-field literal has to be able to produce
// C's all-zero sentinels, such as the PyMethodDef terminator.

// Every C `int` here is `i32`, never V's `int`. V's `int` is 64 bits and C's is 32,
// which for `PyTypeSpec` moves `flags` and `slots` to the wrong offsets and makes
// CPython read a garbage pointer. Most of the other mirrors happen to line up
// anyway; none of them are worth relying on.
pub struct PyMethodDef {
pub mut:
	name  voidptr
	meth  voidptr
	flags i32
	doc   voidptr
}

// PyObject_HEAD plus the three single-phase fields.
//
// The header is 16 bytes with the GIL and 32 without it: free-threaded CPython
// keeps a thread id, flags, a per-object lock and split reference counts where the
// GIL build keeps one count. A mirror with the wrong header puts `m_name` 16 bytes
// off, and the module then imports on a GIL interpreter and segfaults on a
// free-threaded one inside `PyUnicode_FromString`, with nothing in the frame
// pointing at the mirror. Nothing reads these fields -- only their total size
// matters -- so the free-threaded half is opaque bytes, and `check_layout` proves
// the size against the headers on every import.
$if vcraft_free_threaded ? {
pub struct PyModuleDefBase {
pub mut:
	head_pad [32]u8
	m_init voidptr
	m_index isize
	m_copy voidptr
}
} $else {
pub struct PyModuleDefBase {
pub mut:
	ob_refcnt isize
	ob_type   voidptr
	m_init    voidptr
	m_index   isize
	m_copy    voidptr
}
}

// PyModuleDef_Slot is one entry of a multi-phase module's slot table. The two members
// are the slot id and the function that implements it, both from the stable ABI.
//
// Present under `Py_LIMITED_API` as well as without it, so the same mirror serves a
// build of either kind.
pub struct PyModuleDefSlot {
pub mut:
	slot  i32
	value voidptr
}

pub struct PyModuleDef {
pub mut:
	base       PyModuleDefBase
	m_name     voidptr
	m_doc      voidptr
	m_size     isize
	m_methods  voidptr
	m_slots    voidptr
	m_traverse voidptr
	m_clear    voidptr
	m_free     voidptr
}

pub struct PyTypeSlot {
pub mut:
	slot  i32
	value voidptr
}

// There is no `doc` member. CPython's PyType_Spec is exactly five fields, and a
// mirror that adds one does not merely lose `__doc__`: `basicsize`, `flags` and
// `slots` all shift and CPython reads a garbage pointer. A type's docstring travels
// in the `Py_tp_doc` slot instead.
pub struct PyTypeSpec {
mut:
	name      voidptr
	basicsize i32
	itemsize  i32
	flags     u32
	slots     voidptr
}

// PyGetSetDef is a property descriptor. A nil `set` makes it read only, which is
// what a V method marked as a property produces.
pub struct PyGetSetDef {
pub mut:
	name    voidptr
	get     voidptr
	set     voidptr
	doc     voidptr
	closure voidptr
}
