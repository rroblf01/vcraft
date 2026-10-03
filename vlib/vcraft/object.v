module vcraft

// PyObj is a reference to a CPython object.
//
// Reference counting is explicit, following the C API rather than V's ownership
// rules. A PyObj value is a *borrowed* reference unless a function's doc comment
// says otherwise, which is how a CPython caller reads. The two functions that
// move ownership say so in their names:
//
//   - `new_ref` returns a reference the caller owns and must release with
//     `decref`.
//   - `steal` adopts a reference that is already new, typically the return value
//     of a CPython constructor such as PyLong_FromLongLong.
//
// This is deliberately not a V reference type. If it were, V would assume it
// could collect the pointee, and CPython owns every object. A false positive
// would be a use-after-free inside the interpreter.
pub struct PyObj {
pub:
	ptr voidptr
}

// null is the null pointer. CPython spells it NULL; it is never a valid object,
// so it doubles as "no result" when a function reports failure by returning it.
pub const null = PyObj{}

// borrow wraps a pointer the caller does not own. The count does not change.
pub fn borrow(p voidptr) PyObj {
	return PyObj{ptr: p}
}

// steal adopts an existing new reference, so the caller must eventually release
// it with `decref`.
pub fn steal(p voidptr) PyObj {
	return PyObj{ptr: p}
}

// new_ref returns an owned reference to the same object.
pub fn (o PyObj) new_ref() PyObj {
	if o.ptr == unsafe { nil } {
		return o
	}
	C.Py_IncRef(o.ptr)
	return o
}

// decref releases one reference. Calling it on the null pointer is harmless,
// which matches Py_DECREF.
pub fn (o PyObj) decref() {
	if o.ptr != unsafe { nil } {
		C.Py_DecRef(o.ptr)
	}
}

// is_null reports whether the reference is the null pointer.
pub fn (o PyObj) is_null() bool {
	return o.ptr == unsafe { nil }
}

// is_none reports whether the reference is None.
pub fn (o PyObj) is_none() bool {
	return o.ptr != unsafe { nil } && C.Py_Is(o.ptr, C.vpy_none()) == 1
}

// is compares by identity, which is what Python's `is` does.
pub fn (o PyObj) is(other PyObj) bool {
	return C.Py_Is(o.ptr, other.ptr) == 1
}

// is_true reports the truth value of the object, as Python's `bool()` would.
pub fn (o PyObj) is_true() bool {
	if o.ptr == unsafe { nil } {
		return false
	}
	return C.PyObject_IsTrue(o.ptr) == 1
}

// type returns the type of the object as a new reference.
pub fn (o PyObj) type() PyObj {
	return steal(C.PyObject_Type(o.ptr))
}

// type_is reports whether the object is an instance of `wanted` or of a class
// deriving from it.
pub fn (o PyObj) type_is(wanted PyObj) bool {
	return C.PyType_IsSubtype(C.PyObject_Type(o.ptr), wanted.ptr) == 1
}

// type_name returns the name of the object's type, for error messages.
pub fn (o PyObj) type_name() string {
	typ := o.type()
	name := C.PyObject_GetAttrString(typ.ptr, voidptr(c'__name__'))
	if name == unsafe { nil } {
		return '?'
	}
	return steal(name).to_vstring()
}

// hash_value returns the Python hash of the object, or -1 with an error set.
pub fn (o PyObj) hash_value() isize {
	return C.PyObject_Hash(o.ptr)
}

// len returns the length of a sized object, or -1 with an error set.
pub fn (o PyObj) len() isize {
	return C.PyObject_Length(o.ptr)
}

// item returns the i-th element of a sequence as a borrowed reference, which is
// what PyList_GetItem and PyTuple_GetItem both hand back. It raises IndexError on
// an out-of-range index.
pub fn (o PyObj) item(i int) PyObj {
	unsafe {
		return borrow(C.PySequence_GetItem(o.ptr, isize(i)))
	}
}

// append adds a value to a list, stealing a reference to it.
pub fn (o PyObj) append(value PyObj) int {
	unsafe {
		return C.PyList_Append(o.ptr, value.ptr)
	}
}

// repr renders the object the way Python's `repr` would.
pub fn (o PyObj) repr() string {
	return steal(C.PyObject_Repr(o.ptr)).to_vstring()
}

// str renders the object the way Python's `str` would.
pub fn (o PyObj) str() string {
	return steal(C.PyObject_Str(o.ptr)).to_vstring()
}

// to_vstring converts a Python str into a V string. CPython caches the UTF-8
// form on the str object, so this does not transcode and the result shares
// memory with the object, which keeps the receiver alive through the call.
pub fn (o PyObj) to_vstring() string {
	ptr, size := utf8_of(o)
	return from_utf8(ptr, size)
}

// get_attr looks an attribute up by name, returning a borrowed reference. It
// leaves a Python exception set when the attribute is missing.
pub fn (o PyObj) get_attr(name string) PyObj {
	namep := cstring(name)
	defer {
		free_cstring(namep)
	}
	return borrow(C.PyObject_GetAttrString(o.ptr, namep))
}

// set_attr sets an attribute by name, stealing a reference to `value`.
pub fn (o PyObj) set_attr(name string, value PyObj) int {
	namep := cstring(name)
	defer {
		free_cstring(namep)
	}
	return C.PyObject_SetAttrString(o.ptr, namep, value.ptr)
}

// none is Python's None singleton.
pub fn py_none() PyObj {
	return borrow(C.vpy_none())
}

// not_implemented is Python's NotImplemented singleton.
pub fn not_implemented() PyObj {
	return borrow(C.vpy_notimplemented())
}

// bool_obj returns True or False.
pub fn bool_obj(value bool) PyObj {
	return steal(C.PyBool_FromLong(if value { 1 } else { 0 }))
}

// The CPython singletons the runtime type-checks against. Exposed so the code
// generator can compare against them without repeating the shim calls.
pub fn bool_type() PyObj {
	return borrow(C.vpy_bool_type())
}

pub fn long_type() PyObj {
	return borrow(C.vpy_long_type())
}

pub fn float_type() PyObj {
	return borrow(C.vpy_float_type())
}

pub fn str_type() PyObj {
	return borrow(C.vpy_str_type())
}

pub fn bytes_type() PyObj {
	return borrow(C.vpy_bytes_type())
}

pub fn tuple_type() PyObj {
	return borrow(C.vpy_tuple_type())
}

pub fn list_type() PyObj {
	return borrow(C.vpy_list_type())
}

pub fn dict_type() PyObj {
	return borrow(C.vpy_dict_type())
}

pub fn module_type() PyObj {
	return borrow(C.vpy_module_type())
}
