module vcraft

// Turning V failures into Python exceptions.
//
// Three kinds of failure can cross the boundary, and each has its own entry
// point here:
//
//   - A CPython call that failed on its own, such as PyLong_AsLongLong handed a
//     str. It has already set a Python exception; `error_is_set` reports it and
//     the generated wrapper returns the null pointer without inventing one.
//   - A V `error` value travelling through a `!T` return. `raise_from_error`
//     turns it into a RuntimeError.
//   - A V `panic`. A panicking V program prints a message and calls exit(1),
//     which inside CPython would take the whole interpreter down. The generated
//     glue closes that hole with a `defer` and `recover`; see the note at the
//     bottom of this file for why the guard is inlined rather than shared.

// VError carries a V error value across the boundary so it can be turned into a
// Python exception with the original message intact.
pub struct VError {
pub:
	msg string
}

// Error gives VError the `Error` interface.
pub fn (e VError) str() string {
	return e.msg
}

// error_is_set reports whether a Python exception is pending. A wrapper that
// has just called into V checks this before returning a result, so a failure
// never leaves a stale value where the caller expects an object.
pub fn error_is_set() bool {
	return C.PyErr_Occurred() != unsafe { nil }
}

// clear_error discards a pending exception. Used when a wrapper replaces a
// CPython-level failure with a more specific V error.
pub fn clear_error() {
	C.PyErr_Clear()
}

// set_error raises `exc` with `message` as its text.
pub fn set_error(exc PyObj, message string) {
	msg := cstring(message)
	unsafe {
		C.PyErr_SetString(exc.ptr, msg)
	}
	free_cstring(msg)
}

// fetch_error takes the pending exception out of CPython and returns its type,
// value and traceback. It returns null objects when nothing was pending.
pub fn fetch_error() (PyObj, PyObj, PyObj) {
	unsafe {
		mut t := voidptr(nil)
		mut v := voidptr(nil)
		mut tb := voidptr(nil)
		C.PyErr_Fetch(&t, &v, &tb)
		C.PyErr_NormalizeException(&t, &v, &tb)
		return steal(t), steal(v), steal(tb)
	}
}

// restore_error puts an exception triple back, as PyErr_Restore does. Steals all
// three references.
pub fn restore_error(t PyObj, v PyObj, tb PyObj) {
	unsafe {
		C.PyErr_Restore(t.ptr, v.ptr, tb.ptr)
	}
}

// error_text renders the pending exception the way Python's traceback would show
// it, for embedding into a V error message.
pub fn pending_error_text() string {
	t, v, tb := fetch_error()
	if t.is_null() {
		return 'unknown error'
	}
	kind := t.type_name()
	detail := v.str()
	mut out := '${kind}: ${detail}'
	if !tb.is_null() {
		trace := steal(C.PyObject_Str(tb.ptr))
		if !trace.is_null() {
			out += '\n${trace.to_vstring()}'
		}
	}
	t.decref()
	v.decref()
	tb.decref()
	return out
}

// The builtin exceptions, exposed as a typed enum so callers write
// `vcraft.pyexc(.runtime_error)` rather than reaching for a shim symbol.

pub enum PyExc {
	none
	type_error
	value_error
	runtime_error
	not_implemented_error
	attribute_error
	index_error
	key_error
	stop_iteration
	memory_error
	system_error
	overflow_error
	zero_division_error
	arithmetic_error
}

// pyexc_obj resolves an enum member to the CPython exception type.
pub fn pyexc_obj(kind PyExc) PyObj {
	return borrow(match kind {
		.none { unsafe { nil } }
		.type_error { C.vpy_exc_type_error() }
		.value_error { C.vpy_exc_value_error() }
		.runtime_error { C.vpy_exc_runtime_error() }
		.not_implemented_error { C.vpy_exc_not_implemented_error() }
		.attribute_error { C.vpy_exc_attribute_error() }
		.index_error { C.vpy_exc_index_error() }
		.key_error { C.vpy_exc_key_error() }
		.stop_iteration { C.vpy_exc_stop_iteration() }
		.memory_error { C.vpy_exc_memory_error() }
		.system_error { C.vpy_exc_system_error() }
		.overflow_error { C.vpy_exc_overflow_error() }
		.zero_division_error { C.vpy_exc_zero_division_error() }
		.arithmetic_error { C.vpy_exc_arithmetic_error() }
	})
}

// raise raises one of the builtin exceptions.
pub fn raise(kind PyExc, message string) {
	set_error(pyexc_obj(kind), message)
}

// raise_type_error reports a value of the wrong Python type.
pub fn raise_type_error(message string) {
	raise(.type_error, message)
}

// raise_attribute_error reports a missing or undeletable attribute.
pub fn raise_attribute_error(message string) {
	raise(.attribute_error, message)
}

// raise_value_error reports a value of the right type but an unusable value.
pub fn raise_value_error(message string) {
	raise(.value_error, message)
}

// raise_runtime_error reports a failure with no more specific mapping.
pub fn raise_runtime_error(message string) {
	raise(.runtime_error, message)
}

// raise_domain raises the Python exception a domain failure maps to, and returns an
// error carrying the same message.
//
// This is how a `!T` function reports a specific exception:
//
//	if b == 0.0 {
//		return vcraft.raise_domain(.zero_division_error, 'division by zero')
//	}
//
// The exception is set here rather than in the wrapper because V gives a wrapper no
// way to tell a ZeroDivisionError from a ValueError: both arrive as an IError with a
// message and nothing else. Once set, the wrapper's `error_is_set` check stops the
// value from reaching Python as a result, and the exception set here is the one
// Python sees.
//
// A custom V error struct cannot be returned from a `!T` function in V 0.5.2: the
// compiler rejects a value whose type is not IError, and a struct that implements
// `msg()` is not one. That is why the choice travels out of band, through the
// pending Python exception, instead of inside the error value.
pub fn raise_domain(kind PyExc, message string) IError {
	raise(kind, message)
	return error(message)
}

// raise_from_error turns a V error value into a Python exception.
//
// IError is V's builtin error interface, so this accepts any error a `!T` function
// can produce, including the anonymous ones `error('...')` creates. Those become a
// RuntimeError, since a bare message says nothing about which exception was meant.
// A DomainError carries the choice instead.
pub fn raise_from_error(err IError) {
	// An exception already set means `raise_domain` named the right one at the point
	// of failure. Replacing it here would undo that choice and turn every domain
	// failure into a RuntimeError, which is the one thing the caller was avoiding.
	if error_is_set() {
		return
	}
	raise(.runtime_error, err.str())
}

// Panic guard.
//
// There is deliberately no `guard` function here. V does not emit a forward
// declaration for a generic function used from another module, so a shared
// generic wrapper fails to compile with an implicit-declaration error. The code
// generator therefore inlines the guard into each trampoline it writes:
//
// ```v
// fn _vcraft_generated__wrap_div(a int, b int) int {
// 	defer {
// 		if message := recover() {
// 			vcraft.raise_runtime_error('panic in V code: ${message}')
// 		}
// 	}
// 	return divide(a, b)
// }
//```
//
// The generated wrapper then checks `error_is_set` before returning, so a
// recovered panic is reported as a RuntimeError instead of reaching Python as a
// half-written result.
//
// Two properties of V make this work. Its `defer` frames are only given a
// setjmp landing pad once some code in the program calls `recover`, which this
// does. And panic state is thread-local, so the mechanism stays correct when
// several threads enter V at once, as they can in a free-threaded interpreter.
