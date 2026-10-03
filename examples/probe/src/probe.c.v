module probe

// CPython's own declarations.
//
// The #include is load-bearing. The V C backend does not emit prototypes for
// `fn C.` declarations, so without the real header in scope gcc treats these
// calls as returning int, which truncates the returned PyObject pointer to 32
// bits and crashes the interpreter on dereference. Any module that binds to
// CPython must include the header rather than rely on V to declare the
// prototypes.

#flag -I/usr/include/python3.14
#include <Python.h>

// CPython exposes its builtin exception types as data symbols, which V cannot
// name directly. A small C accessor plus its header is the documented way to
// reach them; the header is needed because V does not emit prototypes.
#flag @VMODROOT/c/shim.c
#include "c/shim.h"

fn C.vpyprobe_type_error() voidptr

fn C.PyLong_FromLongLong(v i64) voidptr

fn C.PyLong_AsLongLong(o voidptr) i64

fn C.PyErr_Occurred() voidptr

fn C.PyErr_SetString(exc voidptr, msg &char)

fn C.PyModule_Create2(def voidptr, apiver int) voidptr

// PYTHON_API_VERSION
pub const py_api_version = 1013

// METH_NOARGS
pub const meth_noargs = 0x0004

// METH_FASTCALL
pub const meth_fastcall = 0x0080

// The calling convention METH_FASTCALL uses. It is the cheapest way CPython can
// pass positional arguments, and it is the shape vcraft generates by default.
pub type PyCFunctionFast = fn (voidptr, voidptr, isize) voidptr

// C declarations of CPython structs are described with voidptr for every
// pointer-like member. Two reasons: V's ownership rules would otherwise demand
// initialisers for reference-typed fields, and a zero-initialised literal has
// to produce C's all-zero sentinel. Fields are in a `mut:` section so that V
// does not impose its mutability rules on C layout.
pub struct PyMethodDef {
mut:
	name  voidptr
	meth  voidptr
	flags int
	doc   voidptr
}

// PyObject_HEAD plus the three single-phase fields.
pub struct PyModuleDefBase {
mut:
	ob_refcnt i64
	ob_type   voidptr
	m_init    voidptr
	m_index   i64
	m_copy    voidptr
}

pub struct PyModuleDef {
mut:
	base       PyModuleDefBase
	m_name     voidptr
	m_doc      voidptr
	m_size     i64
	m_methods  voidptr
	m_slots    voidptr
	m_traverse voidptr
	m_clear    voidptr
	m_free     voidptr
}
