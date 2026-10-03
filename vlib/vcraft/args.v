module vcraft

// Reading the argument tuple of a Python call.
//
// A generated trampoline receives the positional arguments as a borrowed pointer
// array plus a count. This module turns those into V values.
//
// Everything here is a plain function over C data, deliberately with no mutable
// state and no reader object. That is forced by a V 0.5.2 limitation: calling a
// `mut` receiver method on a struct imported from another module generates C that
// passes the struct by value where the callee expects a pointer, so it does not
// compile. A reader struct with a `consumed` cursor would have been the obvious
// design and it cannot work. See vlib/vcraft/README.md.
//
// The consequence is that the generated glue keeps the call state in its own
// locals and passes the argument index explicitly, which reads about as well.

// arg_at returns the i-th positional argument as a borrowed reference.
//
// It does not bounds-check: the glue calls `require_nargs` first, which raises if
// the call is short, so every index it goes on to read is known to be present. A
// check per argument would be redundant work on the hot path.
pub fn arg_at(argv voidptr, i int) PyObj {
	unsafe {
		return borrow(*(&voidptr(argv) + i))
	}
}

// arg_count is the number of positional arguments CPython passed. The glue knows
// it from the METH_FASTCALL `nargs` parameter, so it is passed in rather than
// derived here.
pub fn require_nargs(name string, expected int, given int) {
	if given < expected {
		raise(.type_error,
			'${name}() takes ${expected} positional argument(s) but ${given} were given')
	}
}

// reject_extra_args reports a call that passed more arguments than the V function
// accepts. Called after the last parameter.
pub fn reject_extra_args(name string, expected int, given int) {
	if given > expected {
		raise(.type_error,
			'${name}() takes at most ${expected} argument(s) but ${given} were given')
	}
}

// unexpected_kwarg reports an unknown keyword argument.
pub fn unexpected_kwarg(name string, keyword string) {
	raise(.type_error, "${name}() got an unexpected keyword argument '${keyword}'")
}

// from_py_int_arg reads positional argument `i` as an int.
pub fn from_py_int_arg(argv voidptr, i int, func string, name string) !int {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_int(obj, name)!
}

// from_py_uint_arg reads positional argument `i` as a u64.
pub fn from_py_uint_arg(argv voidptr, i int, func string, name string) !u64 {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_uint(obj, name)!
}

// from_py_f64_arg reads positional argument `i` as a float.
pub fn from_py_f64_arg(argv voidptr, i int, func string, name string) !f64 {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_f64(obj, name)!
}

// from_py_string_arg reads positional argument `i` as a str.
pub fn from_py_string_arg(argv voidptr, i int, func string, name string) !string {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_string(obj, name)!
}

// from_py_bytes_arg reads positional argument `i` as bytes.
pub fn from_py_bytes_arg(argv voidptr, i int, func string, name string) !string {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_bytes(obj, name)!
}

// from_py_bool_arg reads positional argument `i` as a bool.
pub fn from_py_bool_arg(argv voidptr, i int, func string, name string) !bool {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return from_py_bool(obj)
}

// require_arg returns positional argument `i` as an opaque object, raising if the
// call was short. This is the `@[vc.raw]` path, where no type check applies.
pub fn require_arg(argv voidptr, i int, func string, name string) PyObj {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
	}
	return obj
}
