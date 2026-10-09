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

// wrong_nargs raises the TypeError for a call with the wrong number of positional
// arguments. The generated glue compares `nargs` itself and only calls this when
// the count is wrong, so the success path pays for one comparison.
pub fn wrong_nargs(name string, expected int, given int) {
	require_nargs(name, expected, given)
	reject_extra_args(name, expected, given)
}

// reject_extra_args reports a call that passed more arguments than the V function
// accepts. Called after the last parameter.
pub fn reject_extra_args(name string, expected int, given int) {
	if given > expected {
		raise(.type_error,
			'${name}() takes at most ${expected} argument(s) but ${given} were given')
	}
}

// bind_args places the arguments of a METH_FASTCALL | METH_KEYWORDS call in one slot
// per parameter, in declaration order, so the readers can take them by index as they
// take a positional call's.
//
// `args` holds `nargs` positional values followed by one value per name in `kwnames`, a
// tuple of str or null. `out` has `names.len` slots, zeroed by the caller: a slot left
// null is a parameter the caller left out, which only an optional one may be. Raises
// TypeError, and returns false, for what Python itself refuses: too many positional
// arguments, an unknown or repeated keyword, or a missing required parameter.
pub fn bind_args(args voidptr, nargs isize, kwnames voidptr, out voidptr, names []string,
	optional []bool, func string) bool {
	n := names.len
	if nargs > n {
		raise(.type_error, '${func}() takes at most ${n} argument${if n == 1 { '' } else { 's' }} (${nargs} given)')
		return false
	}
	for i in 0 .. int(nargs) {
		unsafe {
			*(&voidptr(out) + i) = *(&voidptr(args) + i)
		}
	}
	if kwnames != unsafe { nil } {
		count := int(C.PyTuple_Size(kwnames))
		for k in 0 .. count {
			key := borrow(C.PyTuple_GetItem(kwnames, isize(k)))
			data, size := utf8_of(key)
			if data == unsafe { nil } {
				return false
			}
			keyword := unsafe { tos(&u8(data), size) }
			mut slot := -1
			for j, name in names {
				if name == keyword {
					slot = j
					break
				}
			}
			if slot < 0 {
				unexpected_kwarg(func, keyword.clone())
				return false
			}
			if unsafe { *(&voidptr(out) + slot) } != unsafe { nil } {
				raise(.type_error, "${func}() got multiple values for argument '${keyword}'")
				return false
			}
			unsafe {
				*(&voidptr(out) + slot) = *(&voidptr(args) + int(nargs) + k)
			}
		}
	}
	for j in 0 .. n {
		if unsafe { *(&voidptr(out) + j) } == unsafe { nil } && !optional[j] {
			raise(.type_error, "${func}() missing required argument: '${names[j]}'")
			return false
		}
	}
	return true
}

// unexpected_kwarg reports an unknown keyword argument.
pub fn unexpected_kwarg(name string, keyword string) {
	raise(.type_error, "${name}() got an unexpected keyword argument '${keyword}'")
}

// required_arg returns positional argument `i`, raising TypeError when it is missing.
// The narrow scalar parameters read it through this and then convert it with the
// matching `*_from_py_*` narrower.
pub fn required_arg(argv voidptr, i int, func string, name string) !PyObj {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return obj
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

// require_voidptr_arg reads a required argument as an opaque handle.
//
// The `voidptr` counterpart of `require_arg`, and used for every parameter typed
// `voidptr` or `PyObj` in the generated glue. Handing a `PyObj` to a `voidptr` parameter
// happens to work because V dereferences the single-field struct for it, but it warns,
// it is documented as going away, and a `PyObj` is one field only by accident.
pub fn require_voidptr_arg(argv voidptr, i int, func string, name string) voidptr {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return unsafe { nil }
	}
	return obj.ptr
}

// Reading a sequence argument.
//
// A `[]T` parameter has to become a V slice of `T`, not of pointers, so the
// elements are converted one at a time with the same reader a scalar parameter
// would use. That means one function per element type rather than one generic
// function: V does not emit a forward declaration for a generic called across
// modules, so a generic here would not compile from generated code.
//
// Each function is named after the element type it produces.

fn seq_elements(argv voidptr, i int, func string, name string) ?PyObj {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return none
	}
	if !obj.type_is(list_type()) && !obj.type_is(tuple_type()) {
		set_error(pyexc_obj(.type_error),
			'${func}(): ${name} expected a sequence, got ${obj.type_name()}')
		return none
	}
	return obj
}

// from_py_int_seq_arg reads positional argument `i` as a sequence of ints.
//
// The leading items that are exact ints are converted in one pass in C; whatever is
// left, from the first item that is anything else, goes through the general reader,
// which raises the usual error for the item that is wrong.
pub fn from_py_int_seq_arg(argv voidptr, i int, func string, name string) ![]int {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []int{len: n}
	mut k := 0
	// The C pass writes 64-bit integers, so it only applies where an int is that wide.
	if sizeof(int) == sizeof(i64) && n > 0 {
		k = int(C.vpy_seq_fill_i64(obj.ptr, unsafe { &i64(out.data) }, isize(n)))
	}
	for k < n {
		out[k] = from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_i64_seq_arg reads positional argument `i` as a sequence of i64.
pub fn from_py_i64_seq_arg(argv voidptr, i int, func string, name string) ![]i64 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []i64{len: n}
	mut k := 0
	if n > 0 {
		k = int(C.vpy_seq_fill_i64(obj.ptr, unsafe { &i64(out.data) }, isize(n)))
	}
	for k < n {
		out[k] = i64(from_py_int(obj.item(k), name)!)
		k++
	}
	return out
}

// from_py_f64_seq_arg reads positional argument `i` as a sequence of floats.
//
// Exact floats and ints convert in one pass in C, the rest one at a time, as in
// `from_py_int_seq_arg`.
pub fn from_py_f64_seq_arg(argv voidptr, i int, func string, name string) ![]f64 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []f64{len: n}
	mut k := 0
	if n > 0 {
		k = int(C.vpy_seq_fill_f64(obj.ptr, unsafe { &f64(out.data) }, isize(n)))
	}
	for k < n {
		out[k] = from_py_f64(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_str_seq_arg reads positional argument `i` as a sequence of strings.
//
// Each item aliases its str object's buffer instead of copying it (see
// `from_py_str_borrowed`): a 10k-item list costs no per-item allocation, only
// the join or whatever the function builds from them. The slice must not
// outlive the call, because nothing pins the strs past it.
pub fn from_py_str_seq_arg(argv voidptr, i int, func string, name string) ![]string {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []string{cap: n}
	mut k := 0
	for k < n {
		out << from_py_str_borrowed(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_uint_seq_arg reads positional argument `i` as a sequence of unsigned
// integers.
pub fn from_py_uint_seq_arg(argv voidptr, i int, func string, name string) ![]u64 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []u64{cap: n}
	mut k := 0
	for k < n {
		out << from_py_uint(obj.item(k), name)!
		k++
	}
	return out
}

// The narrower widths below go through the scalar narrowers one item at a time,
// like `from_py_uint_seq_arg` does: the one-pass C readers only exist for the
// three hot widths (`int`, `i64`, `f64`). An item that is wrong raises the same
// TypeError or OverflowError a scalar parameter would.

// from_py_i8_seq_arg reads positional argument `i` as a sequence of i8.
pub fn from_py_i8_seq_arg(argv voidptr, i int, func string, name string) ![]i8 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []i8{cap: n}
	mut k := 0
	for k < n {
		out << i8_from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_i16_seq_arg reads positional argument `i` as a sequence of i16.
pub fn from_py_i16_seq_arg(argv voidptr, i int, func string, name string) ![]i16 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []i16{cap: n}
	mut k := 0
	for k < n {
		out << i16_from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_i32_seq_arg reads positional argument `i` as a sequence of i32.
pub fn from_py_i32_seq_arg(argv voidptr, i int, func string, name string) ![]i32 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []i32{cap: n}
	mut k := 0
	for k < n {
		out << i32_from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_isize_seq_arg reads positional argument `i` as a sequence of isize.
pub fn from_py_isize_seq_arg(argv voidptr, i int, func string, name string) ![]isize {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []isize{cap: n}
	mut k := 0
	for k < n {
		out << isize_from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_rune_seq_arg reads positional argument `i` as a sequence of runes.
pub fn from_py_rune_seq_arg(argv voidptr, i int, func string, name string) ![]rune {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []rune{cap: n}
	mut k := 0
	for k < n {
		out << rune_from_py_int(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_u16_seq_arg reads positional argument `i` as a sequence of u16.
pub fn from_py_u16_seq_arg(argv voidptr, i int, func string, name string) ![]u16 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []u16{cap: n}
	mut k := 0
	for k < n {
		out << u16_from_py_uint(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_u32_seq_arg reads positional argument `i` as a sequence of u32.
pub fn from_py_u32_seq_arg(argv voidptr, i int, func string, name string) ![]u32 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []u32{cap: n}
	mut k := 0
	for k < n {
		out << u32_from_py_uint(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_usize_seq_arg reads positional argument `i` as a sequence of usize.
pub fn from_py_usize_seq_arg(argv voidptr, i int, func string, name string) ![]usize {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []usize{cap: n}
	mut k := 0
	for k < n {
		out << usize_from_py_uint(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_f32_seq_arg reads positional argument `i` as a sequence of f32.
pub fn from_py_f32_seq_arg(argv voidptr, i int, func string, name string) ![]f32 {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []f32{cap: n}
	mut k := 0
	for k < n {
		out << f32_from_py_f64(obj.item(k), name)!
		k++
	}
	return out
}

// from_py_bool_seq_arg reads positional argument `i` as a sequence of bools.
pub fn from_py_bool_seq_arg(argv voidptr, i int, func string, name string) ![]bool {
	obj := seq_elements(argv, i, func, name) or { return error('${name}') }
	n := int(obj.len())
	mut out := []bool{cap: n}
	mut k := 0
	for k < n {
		out << from_py_bool(obj.item(k))
		k++
	}
	return out
}
