module vcraft

// Value marshalling between V and CPython.
//
// Two directions, named for where the data comes from:
//
//   - `to_py_*` takes a V value and returns a new reference. It cannot fail in a
//     way the caller can act on, because allocating a Python object either
//     succeeds or raises MemoryError, which CPython records on its own.
//   - `from_py_*` reads a Python object into a V value, or returns an error. A
//     type mismatch and a range problem are reported separately because Python
//     distinguishes TypeError from OverflowError and callers expect that.
//
// Both directions prefer a direct CPython call. There is no intermediate value
// tree, so converting an int is one call to PyLong_AsLongLongAndOverflow.
//
// Integers use V's `int`, not `i64`. They are the same width in V 0.5.2 but they
// are distinct types, and `int` is what a V programmer writes, so the code
// generator hands parameters over as `int` and a function declared with `i64`
// gets an explicit conversion at the call site.

// -------------------------------------------------------------- from Python

// from_py_int reads a Python int.
//
// bool is rejected. It is a subclass of int in Python, so PyLong_AsLongLong
// would happily accept it, but `True` becoming `1` in a V function is almost
// never what the caller meant.
pub fn from_py_int(obj PyObj, name string) !int {
	if obj.is_null() {
		set_error(pyexc_obj(.type_error), '${name}: missing argument')
		return error('${name}: missing')
	}
	if obj.type_is(bool_type()) {
		set_error(pyexc_obj(.type_error), '${name}: expected int, got bool')
		return error('${name}: expected int, got bool')
	}
	if !obj.type_is(long_type()) {
		set_error(pyexc_obj(.type_error), '${name}: expected int, got ${obj.type_name()}')
		return error('${name}: expected int')
	}
	unsafe {
		mut overflow := 0
		value := C.PyLong_AsLongLongAndOverflow(obj.ptr, &overflow)
		if error_is_set() {
			return error('${name}: ${pending_error_text()}')
		}
		if overflow != 0 {
			raise(.overflow_error, '${name}: value out of range for int')
			return error('${name}: out of range')
		}
		return int(value)
	}
}

// from_py_uint reads a Python int into a u64. PyLong_AsUnsignedLongLong already
// raises OverflowError for a negative input, so the range check comes for free.
pub fn from_py_uint(obj PyObj, name string) !u64 {
	if obj.type_is(bool_type()) || !obj.type_is(long_type()) {
		set_error(pyexc_obj(.type_error), '${name}: expected int, got ${obj.type_name()}')
		return error('${name}: expected int')
	}
	value := C.PyLong_AsUnsignedLongLong(obj.ptr)
	if error_is_set() {
		return error('${name}: ${pending_error_text()}')
	}
	return value
}

// from_py_f64 reads a Python float. An int is accepted and widened, which is what
// Python does for a float parameter.
pub fn from_py_f64(obj PyObj, name string) !f64 {
	if obj.type_is(float_type()) {
		value := C.PyFloat_AsDouble(obj.ptr)
		if error_is_set() {
			return error('${name}: ${pending_error_text()}')
		}
		return value
	}
	if obj.type_is(long_type()) {
		return f64(from_py_int(obj, name)!)
	}
	set_error(pyexc_obj(.type_error), '${name}: expected float, got ${obj.type_name()}')
	return error('${name}: expected float')
}

// from_py_bool reads any object as Python's `bool()` would.
pub fn from_py_bool(obj PyObj) bool {
	return obj.is_true()
}

// from_py_string reads a Python str. bytes is rejected: CPython separates the
// two on purpose, and silently decoding one as the other hides bugs.
pub fn from_py_string(obj PyObj, name string) !string {
	if !obj.type_is(str_type()) {
		set_error(pyexc_obj(.type_error), '${name}: expected str, got ${obj.type_name()}')
		return error('${name}: expected str')
	}
	ptr, size := utf8_of(obj)
	if ptr == unsafe { nil } {
		return error('${name}: ${pending_error_text()}')
	}
	return from_utf8(ptr, size)
}

// from_py_bytes reads a Python bytes object into a V string holding the same
// bytes. The result aliases CPython's buffer, so a caller that needs it to
// outlive the source object must copy it.
pub fn from_py_bytes(obj PyObj, name string) !string {
	if !obj.type_is(bytes_type()) {
		set_error(pyexc_obj(.type_error),
			'${name}: expected bytes, got ${obj.type_name()}')
		return error('${name}: expected bytes')
	}
	ptr, size := bytes_of(obj)
	if ptr == unsafe { nil } {
		return error('${name}: ${pending_error_text()}')
	}
	return from_utf8(ptr, size)
}

// from_py_voidptr adopts any object as an opaque handle. There is no type check
// on purpose: this is the escape hatch that lets a V function take a PyObject *
// directly.
pub fn from_py_voidptr(obj PyObj) voidptr {
	return obj.ptr
}

// ------------------------------------------------------------- to Python

// to_py_int boxes a V int.
pub fn to_py_int(value int) PyObj {
	return steal(C.PyLong_FromLongLong(i64(value)))
}

// to_py_uint boxes a V u64.
pub fn to_py_uint(value u64) PyObj {
	return steal(C.PyLong_FromUnsignedLongLong(value))
}

// to_py_f64 boxes a V float.
pub fn to_py_f64(value f64) PyObj {
	return steal(C.PyFloat_FromDouble(value))
}

// to_py_string boxes a V string as a Python str, decoding it as UTF-8.
pub fn to_py_string(value string) PyObj {
	unsafe {
		return steal(C.PyUnicode_FromStringAndSize(value.str, value.len))
	}
}

// to_py_bytes boxes a V string as Python bytes, with no decoding.
pub fn to_py_bytes(value string) PyObj {
	unsafe {
		return steal(C.PyBytes_FromStringAndSize(value.str, value.len))
	}
}

// to_py_bool boxes a V bool.
pub fn to_py_bool(value bool) PyObj {
	return bool_obj(value)
}

// to_py_list boxes a V slice of pointers as a Python list, calling `to_py_object`
// on each element.
//
// The element conversion is a function because the element type is only known to
// the code generator, so it passes the boxing rule in rather than this module
// hard-coding one.
pub fn to_py_list[T](items []T, box fn (T) PyObj) PyObj {
	list := steal(C.PyList_New(0))
	for item in items {
		value := box(item)
		C.PyList_Append(list.ptr, value.ptr)
		value.decref()
	}
	return list
}

// to_py_object is the default boxing rule for a `[]voidptr` sequence: each element
// is already a PyObject pointer, and it is passed through with its own reference
// kept by the list.
pub fn sequence_element_box(value voidptr) PyObj {
	return borrow(value).new_ref()
}

// to_py_none is the result of a V function returning nothing.
pub fn to_py_none() PyObj {
	return py_none().new_ref()
}

// to_py_voidptr boxes an opaque pointer back into a Python object without
// touching its reference count, which is only correct for a pointer the caller
// already owns a reference to.
pub fn to_py_voidptr(p voidptr) PyObj {
	return borrow(p)
}

// unbox_int, unbox_uint, unbox_f64 and unbox_bool convert a value a field setter was
// handed into the V type the field holds.
//
// A setter receives a `PyObject *`. That object is a `PyLong` or a `PyFloat` with
// CPython's own layout, so the value has to be converted rather than copied: memcpy'ing
// the bytes would read the interpreter's internals as if they were a V value.
//
// The object is borrowed. CPython owns the argument for the duration of the call, so
// taking a reference would leak one per assignment.
pub fn unbox_int(value voidptr, name string) !int {
	return from_py_int(borrow(value), name)
}

pub fn unbox_uint(value voidptr, name string) !u64 {
	return from_py_uint(borrow(value), name)
}

pub fn unbox_f64(value voidptr, name string) !f64 {
	return from_py_f64(borrow(value), name)
}

pub fn unbox_bool(value voidptr) !bool {
	if value == unsafe { nil } {
		return error('a setter was called without a value')
	}
	return from_py_bool(borrow(value))
}

// repr_int, repr_uint, repr_f64, repr_bool and repr_string render a V value the way
// Python's own repr would, so an instance's repr reads like a Python one.
pub fn repr_int(value int) string {
	return '${value}'
}

pub fn repr_uint(value u64) string {
	return '${value}'
}

pub fn repr_f64(value f64) string {
	return '${value}'
}

pub fn repr_bool(value bool) string {
	return if value { 'True' } else { 'False' }
}

pub fn repr_string(value string) string {
	return "'${value}'"
}
