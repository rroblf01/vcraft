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
	// An exact int that fits is decided by one pointer comparison. Everything else,
	// including every error, takes the checks below.
	mut fast := i64(0)
	if C.vpy_exact_long_as_i64(obj.ptr, &fast) == 1 {
		return int(fast)
	}
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
		if overflow != 0 {
			raise(.overflow_error, '${name}: value out of range for int')
			return error('${name}: out of range')
		}
		if error_is_set() {
			// Some other failure, with CPython's own exception already set.
			// It stays set: the V error only travels the `!` chain back to the
			// trampoline, which returns NULL for it.
			return error('${name}: cannot read int')
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
		// OverflowError for a negative or too-large int, left set: the V error
		// only travels the `!` chain back to the trampoline.
		return error('${name}: value out of range for u64')
	}
	return value
}

// from_py_f64 reads a Python float. An int is accepted and widened, which is what
// Python does for a float parameter.
pub fn from_py_f64(obj PyObj, name string) !f64 {
	if obj.type_is(float_type()) {
		value := C.PyFloat_AsDouble(obj.ptr)
		if error_is_set() {
			// Practically unreachable for an exact float, but if it fails the
			// exception is already set and stays set.
			return error('${name}: cannot read float')
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

// Narrowing a Python int into a smaller V integer.
//
// `from_py_int` and `from_py_uint` read the full-width value with the usual
// TypeError behaviour; what is left is refusing what does not fit, with the
// OverflowError Python raises for the same input. V casts truncate silently,
// so the check comes before the cast, never after it. `isize` and `usize`
// need no check: on the 64-bit targets vcraft builds for they are the full
// width already.

// i8_from_py_int reads a Python int into an i8.
pub fn i8_from_py_int(obj PyObj, name string) !i8 {
	value := from_py_int(obj, name)!
	if value < -128 || value > 127 {
		raise(.overflow_error, '${name}: value out of range for i8')
		return error('${name}: out of range')
	}
	return i8(value)
}

// i16_from_py_int reads a Python int into an i16.
pub fn i16_from_py_int(obj PyObj, name string) !i16 {
	value := from_py_int(obj, name)!
	if value < -32768 || value > 32767 {
		raise(.overflow_error, '${name}: value out of range for i16')
		return error('${name}: out of range')
	}
	return i16(value)
}

// i32_from_py_int reads a Python int into an i32.
pub fn i32_from_py_int(obj PyObj, name string) !i32 {
	value := from_py_int(obj, name)!
	if value < -2147483648 || value > 2147483647 {
		raise(.overflow_error, '${name}: value out of range for i32')
		return error('${name}: out of range')
	}
	return i32(value)
}

// isize_from_py_int reads a Python int into an isize.
pub fn isize_from_py_int(obj PyObj, name string) !isize {
	return isize(from_py_int(obj, name)!)
}

// rune_from_py_int reads a Python int into a rune.
pub fn rune_from_py_int(obj PyObj, name string) !rune {
	value := from_py_int(obj, name)!
	if value < -2147483648 || value > 2147483647 {
		raise(.overflow_error, '${name}: value out of range for rune')
		return error('${name}: out of range')
	}
	return rune(value)
}

// u16_from_py_uint reads a Python int into an u16.
pub fn u16_from_py_uint(obj PyObj, name string) !u16 {
	value := from_py_uint(obj, name)!
	if value > 65535 {
		raise(.overflow_error, '${name}: value out of range for u16')
		return error('${name}: out of range')
	}
	return u16(value)
}

// u32_from_py_uint reads a Python int into a u32.
pub fn u32_from_py_uint(obj PyObj, name string) !u32 {
	value := from_py_uint(obj, name)!
	if value > 4294967295 {
		raise(.overflow_error, '${name}: value out of range for u32')
		return error('${name}: out of range')
	}
	return u32(value)
}

// usize_from_py_uint reads a Python int into a usize.
pub fn usize_from_py_uint(obj PyObj, name string) !usize {
	return usize(from_py_uint(obj, name)!)
}

// f32_from_py_f64 reads a Python float or int into an f32, with the same
// acceptance as `from_py_f64`. Any f64 converts; one far outside the f32
// range becomes an infinity, as a V `f32()` cast does.
pub fn f32_from_py_f64(obj PyObj, name string) !f32 {
	return f32(from_py_f64(obj, name)!)
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
		// CPython set the exception (usually MemoryError); it stays set.
		return error('${name}: cannot read str')
	}
	return from_utf8(ptr, size)
}

// from_py_str_borrowed reads a Python str without copying it: the V string
// aliases the str object's UTF-8 buffer for exactly the call.
//
// Same checks and errors as `from_py_string`; only the copy is skipped. The
// argument keeps the str alive for the call's duration, so the alias must not
// outlive the call -- the same documented contract as `buffer_bytes`, and for
// the same reason: V's collector cannot see CPython's memory. Safe against
// mutation rather than lifetime only because `str` is immutable: nothing can
// change the aliased bytes under the reader, which a `bytearray` alias cannot
// promise.
pub fn from_py_str_borrowed(obj PyObj, name string) !string {
	if !obj.type_is(str_type()) {
		set_error(pyexc_obj(.type_error), '${name}: expected str, got ${obj.type_name()}')
		return error('${name}: expected str')
	}
	// Inlined rather than through `utf8_of`: a multi-return value travels in an
	// 8-byte result struct V allocates per call, which would put one GC block per
	// item back into exactly the loop this function exists to keep allocation-free.
	unsafe {
		mut size := int(0)
		ptr := C.PyUnicode_AsUTF8AndSize(obj.ptr, voidptr(&size))
		if ptr == nil {
			// CPython set the exception (usually MemoryError); it stays set.
			return error('${name}: cannot read str')
		}
		mut out := string{}
		out.str = &u8(ptr)
		out.len = size
		return out
	}
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
		// CPython set the exception (usually MemoryError); it stays set.
		return error('${name}: cannot read bytes')
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

// to_py_int boxes a V integer.
//
// It takes an i64 so that every signed width boxes through it: V widens an `int`,
// an `i32` or an `i16` implicitly, but refuses to narrow an `i64`, so an `int`
// parameter made every generated `i64` getter a compile error.
pub fn to_py_int(value i64) PyObj {
	return steal(C.PyLong_FromLongLong(value))
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

// to_py_list boxes a V slice as a Python list, calling `box` on each element.
//
// The element conversion is a function because the element type is only known to
// the code generator, so it passes the boxing rule in rather than this module
// hard-coding one.
//
// The list is created at its final length and each slot filled once. Appending to an
// empty list instead regrows it as it goes, and costs a third more for a large one.
// `PyList_SetItem` steals the element's reference, so nothing is released here on
// success; a failed box releases the half-built list and returns a null object with
// the exception already set.
pub fn to_py_list[T](items []T, box fn (T) PyObj) PyObj {
	list := steal(C.PyList_New(isize(items.len)))
	if list.is_null() {
		return list
	}
	for i, item in items {
		value := box(item)
		if value.is_null() {
			list.decref()
			return steal(unsafe { nil })
		}
		C.PyList_SetItem(list.ptr, isize(i), value.ptr)
	}
	return list
}

// to_py_i64_list, to_py_int_list and to_py_f64_list box a slice of plain numbers as a
// list in one pass in C, with no function call per element. The generated glue uses
// them for those element types and `to_py_list` for the rest.
pub fn to_py_i64_list(items []i64) PyObj {
	return steal(C.vpy_list_from_i64(unsafe { &i64(items.data) }, isize(items.len)))
}

pub fn to_py_int_list(items []int) PyObj {
	// The C pass reads 64-bit integers, so it only applies where an int is that wide.
	if sizeof(int) == sizeof(i64) {
		return steal(C.vpy_list_from_i64(unsafe { &i64(items.data) }, isize(items.len)))
	}
	return to_py_list(items, fn (x int) PyObj {
		return to_py_int(x)
	})
}

pub fn to_py_f64_list(items []f64) PyObj {
	return steal(C.vpy_list_from_f64(unsafe { &f64(items.data) }, isize(items.len)))
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
pub fn repr_int(value i64) string {
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
