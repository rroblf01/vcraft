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
//
// `.none` is not one of them -- `pyexc_obj` resolves it to the null pointer -- so it
// becomes a RuntimeError rather than being passed on. `PyErr_SetString` does not check for
// a null type: it writes through it, and the crash lands inside CPython on a line that
// mentions neither V nor the code that asked for it.
pub fn raise(kind PyExc, message string) {
	// A local rather than a rewritten parameter: a `mut` parameter would make every one
	// of the thirty-odd call sites in the runtime pass `mut .type_error`.
	resolved := if kind == .none { PyExc.runtime_error } else { kind }
	set_error(pyexc_obj(resolved), message)
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

// set_error_object sets an arbitrary Python exception class with a message.
//
// `exc` is the class, not an instance: CPython instantiates it. That is what
// `PyErr_SetObject` takes and what lets a V error name an exception the user defined in
// Python, which no `PyExc` member can.
//
// The reference is borrowed. CPython stores the class on the exception it builds, which
// increments it, so there is nothing for the caller to release.
pub fn set_error_object(exc voidptr, message string) {
	if exc == unsafe { nil } {
		raise(.runtime_error, message)
		return
	}
	unsafe {
		// `PyErr_SetObject` with a `str` rather than `PyErr_SetString`, because the
		// latter hardcodes the class and this is the whole point: a class the caller
		// chose. The message is built first so a failure to build it is reported as
		// itself instead of leaving no exception set at all.
		text := C.PyUnicode_FromString(message.str)
		if text == nil {
			raise(.runtime_error, message)
			return
		}
		C.PyErr_SetObject(exc, text)
	}
}

// raise_custom raises an arbitrary Python exception class and returns an error carrying
// the same message.
//
// The counterpart of `raise_domain` for an exception vcraft has no name for:
//
//	pub fn parse(text string) !int {
//		if !is_digits(text) {
//			return vcraft.raise_custom(python_error_class('BadNumber'), 'not a number')
//		}
//		...
//	}
//
// The class is borrowed and the error value cannot carry it, for the same reason
// `raise_domain` sets the exception here rather than inside it: V erases an error to
// `IError` by the time the wrapper sees it, and everything but the message is gone.
pub fn raise_custom(exc voidptr, message string) IError {
	set_error_object(exc, message)
	return error(message)
}

// pyexc_from_code turns an error's `code()` back into the exception it names.
//
// The inverse of the enum's own numbering, which is what lets a custom V error type
// choose its exception with no wrapper code at all:
//
//	@[vc_error]
//	pub struct ConfigError {
//	pub:
//		message string
//	}
//
//	pub fn (e ConfigError) msg() string { return e.message }
//
//	// The code *is* the exception: `PyExc.value_error` is 2.
//	pub fn (e ConfigError) code() int { return int(vcraft.PyExc(.value_error)) }
//
// A code outside the enum is not an exception choice at all -- it is an ordinary error
// code, and those are common -- so it falls back to `.runtime_error` rather than being
// read as one.
pub fn pyexc_from_code(code int) PyExc {
	// One through thirteen, which is every member of `PyExc` that names a class. Zero is
	// `.none`, whose object is the null pointer, and it is deliberately not in the list:
	// `code()` is 0 for every anonymous `error('...')`, so mapping it would send every
	// plain V error to a null exception type. `PyErr_SetString(NULL, msg)` does not
	// complain about that; it dereferences it, and the interpreter dies inside the call
	// with a message about nothing at all.
	return match code {
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 { unsafe { PyExc(code) } }
		else { .runtime_error }
	}
}

// raise_from_error turns a V error value into a Python exception.
//
// IError is V's builtin error interface, so this accepts any error a `!T` function can
// produce: the anonymous ones `error('...')` creates, and any struct implementing `msg()`
// and `code()`.
//
// Three ways an error can name its exception, in the order they are consulted:
//
//   - An exception already set. `raise_domain` and `raise_custom` set one at the point of
//     failure, and it wins: replacing it would undo the choice the V code made.
//   - A `code()` that is one of the `PyExc` values. This is how a custom error type
//     carries a builtin exception with no help from the generator.
//   - Otherwise a RuntimeError, because a bare message says nothing about which exception
//     was meant.
pub fn raise_from_error(err IError) {
	if error_is_set() {
		return
	}
	raise(pyexc_from_code(err.code()), err.msg())
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
