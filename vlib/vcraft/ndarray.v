module vcraft

// N-dimensional arrays: NumPy and anything else with the buffer protocol.
//
// A `vcraft.NdArray` parameter takes any object that exports a buffer -- a NumPy array, an
// `array.array`, a `memoryview`, `bytes` -- without copying it and without depending on
// NumPy. It carries the element format, the shape and the strides, and is valid for the
// call, like a `[]u8` parameter: the view pins the exporter and the generated wrapper
// releases it on every path. The typed accessors (`f64s`, `i32s`, ...) alias a C-contiguous
// array of the right element type as a V slice; `at_f64` and friends follow the strides of
// any other.
//
// A `vcraft.NdOut` result is the other direction: a native buffer with a shape, which
// Python receives as an N-dimensional `memoryview`. `numpy.asarray(result)` wraps it
// without a copy, and the buffer is freed when the last view of it goes.
//
//	@[vc_fn]
//	pub fn scale(a vcraft.NdArray, k f64) !vcraft.NdOut {
//		src := a.f64s()!
//		out := vcraft.nd_out_f64(a.shape)
//		mut dst := out.f64s()
//		for i, x in src {
//			dst[i] = x * k
//		}
//		return out
//	}

// NdArray is a borrowed view of an N-dimensional buffer, valid for the call.
pub struct NdArray {
pub:
	// data is the first element.
	data voidptr
	// shape is the length of each dimension; empty for a 0-dimensional (scalar) buffer.
	shape []int
	// strides is the byte step of each dimension, in the same order.
	strides []int
	// size is the number of elements, the product of the shape.
	size int
	// itemsize is the width of one element in bytes.
	itemsize int
	// kind is the element type as a struct-module format character, byte order removed
	// and C `long` resolved to its width: `d` f64, `f` f32, `q` i64, `i` i32, `h` i16,
	// `b` i8, `Q` u64, `I` u32, `H` u16, `B` u8, `?` bool.
	kind u8
	// readonly is set when the exporter refused a writable view (`bytes`, a read-only
	// NumPy array). Writing through such an array is undefined.
	readonly bool
	// c_contiguous is set when the elements are laid out row-major with no gaps, which
	// is what the typed slice accessors require.
	c_contiguous bool
	view         voidptr
}

// nd_arg reads positional argument `i` as an N-dimensional view. Used by the generated
// wrapper for a `vcraft.NdArray` parameter, which defers `release`.
pub fn nd_arg(argv voidptr, i int, func string, name string) !NdArray {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return nd_of(obj, '${func}() argument ${name}')
}

// nd_of views any object that exports a buffer. Release it with `release`.
pub fn nd_of(obj PyObj, name string) !NdArray {
	view := unsafe { C.vpy_buffer_new() }
	if view == unsafe { nil } {
		raise(.memory_error, 'cannot view ${name}')
		return error(name)
	}
	if C.vpy_nd_get(obj.ptr, view) != 0 {
		C.vpy_buffer_release(view)
		return error(name)
	}
	ndim := C.vpy_view_ndim(view)
	itemsize := int(C.vpy_view_itemsize(view))
	mut shape := []int{cap: ndim}
	mut strides := []int{cap: ndim}
	mut size := 1
	for d in 0 .. ndim {
		n := int(C.vpy_view_shape(view, d))
		shape << n
		strides << int(C.vpy_view_stride(view, d))
		size *= n
	}
	format := unsafe { cstring_to_vstring(C.vpy_view_format(view)) }
	kind := nd_kind(format, itemsize) or {
		C.vpy_buffer_release(view)
		raise(.type_error, '${name}: unsupported element format `${format}`')
		return error(name)
	}
	mut contiguous := true
	mut expected := itemsize
	for d := ndim - 1; d >= 0; d-- {
		if shape[d] > 1 && strides[d] != expected {
			contiguous = false
			break
		}
		expected *= shape[d]
	}
	return NdArray{
		data:         C.vpy_buffer_ptr(view)
		shape:        shape
		strides:      strides
		size:         size
		itemsize:     itemsize
		kind:         kind
		readonly:     C.vpy_view_readonly(view) != 0
		c_contiguous: contiguous
		view:         view
	}
}

// nd_kind normalises a buffer format to one element character: native byte order only,
// and the C `long`/`size_t` codes resolved to the fixed width they have here.
fn nd_kind(format string, itemsize int) ?u8 {
	mut f := format
	if f.len > 1 && f[0] in [`@`, `=`, `<`] {
		f = f[1..]
	}
	if f.len != 1 {
		return none
	}
	c := f[0]
	return match c {
		`d`, `f`, `q`, `i`, `h`, `b`, `Q`, `I`, `H`, `B`, `?` { c }
		`l`, `n` { if itemsize == 8 { `q` } else { `i` } }
		`L`, `N` { if itemsize == 8 { `Q` } else { `I` } }
		`c` { `B` }
		else { none }
	}
}

// release gives the view back. The generated wrapper defers it; hand-written code calls it
// once it is done with the array and every slice taken from it.
pub fn (a NdArray) release() {
	C.vpy_buffer_release(a.view)
}

// ndim is the number of dimensions.
pub fn (a NdArray) ndim() int {
	return a.shape.len
}

// typed checks that the array can be read as a flat slice of `kind`.
fn (a NdArray) typed(kind u8, label string) ! {
	if a.kind != kind {
		raise(.type_error, 'expected ${label} elements, got format `${a.kind.ascii_str()}`')
		return error('wrong element type')
	}
	if !a.c_contiguous {
		raise(.value_error, 'expected a C-contiguous array; pass numpy.ascontiguousarray(x)')
		return error('not contiguous')
	}
}

// f64s aliases a C-contiguous float64 array as a `[]f64` in row-major order, without
// copying. Valid for the call; write through it only when `readonly` is false.
pub fn (a NdArray) f64s() ![]f64 {
	a.typed(`d`, 'float64')!
	mut out := []f64{}
	unsafe {
		out.data = a.data
		out.len = a.size
		out.cap = a.size
	}
	return out
}

// f32s is `f64s` for a float32 array.
pub fn (a NdArray) f32s() ![]f32 {
	a.typed(`f`, 'float32')!
	mut out := []f32{}
	unsafe {
		out.data = a.data
		out.len = a.size
		out.cap = a.size
	}
	return out
}

// i64s is `f64s` for an int64 array.
pub fn (a NdArray) i64s() ![]i64 {
	a.typed(`q`, 'int64')!
	mut out := []i64{}
	unsafe {
		out.data = a.data
		out.len = a.size
		out.cap = a.size
	}
	return out
}

// i32s is `f64s` for an int32 array.
pub fn (a NdArray) i32s() ![]i32 {
	a.typed(`i`, 'int32')!
	mut out := []i32{}
	unsafe {
		out.data = a.data
		out.len = a.size
		out.cap = a.size
	}
	return out
}

// u8s is `f64s` for a uint8 array.
pub fn (a NdArray) u8s() ![]u8 {
	a.typed(`B`, 'uint8')!
	mut out := []u8{}
	unsafe {
		out.data = a.data
		out.len = a.size
		out.cap = a.size
	}
	return out
}

// offset is the byte offset of the element at `idx`, following the strides, so it works
// for a transposed or sliced array too. It panics on an index out of range.
pub fn (a NdArray) offset(idx []int) int {
	if idx.len != a.shape.len {
		panic('NdArray: ${idx.len} indices for ${a.shape.len} dimensions')
	}
	mut off := 0
	for d, i in idx {
		if i < 0 || i >= a.shape[d] {
			panic('NdArray: index ${i} out of range for dimension ${d} of length ${a.shape[d]}')
		}
		off += i * a.strides[d]
	}
	return off
}

// at_f64 reads the float64 element at `idx`, whatever the layout.
pub fn (a NdArray) at_f64(idx ...int) f64 {
	if a.kind != `d` {
		panic('NdArray: at_f64 on a `${a.kind.ascii_str()}` array')
	}
	return unsafe { *(&f64(&u8(a.data) + a.offset(idx))) }
}

// at_i64 reads the int64 element at `idx`, whatever the layout.
pub fn (a NdArray) at_i64(idx ...int) i64 {
	if a.kind != `q` {
		panic('NdArray: at_i64 on a `${a.kind.ascii_str()}` array')
	}
	return unsafe { *(&i64(&u8(a.data) + a.offset(idx))) }
}

// set_f64 writes the float64 element at `idx`, refusing a read-only array.
pub fn (a NdArray) set_f64(value f64, idx ...int) ! {
	if a.readonly {
		return raise_domain(.value_error, 'the array is read-only')
	}
	if a.kind != `d` {
		return raise_domain(.type_error, 'set_f64 on a `${a.kind.ascii_str()}` array')
	}
	unsafe {
		*(&f64(&u8(a.data) + a.offset(idx))) = value
	}
}

// NdOut is a native N-dimensional buffer a function returns: Python receives it as a
// `memoryview` with this shape, which `numpy.asarray` wraps without copying.
pub struct NdOut {
pub:
	data     voidptr
	shape    []int
	size     int
	itemsize int
	// kind is the element format character, as in `NdArray.kind`.
	kind u8
}

fn nd_out(shape []int, itemsize int, kind u8) NdOut {
	mut size := 1
	for n in shape {
		if n < 0 {
			panic('NdOut: negative dimension ${n}')
		}
		size *= n
	}
	data := if size > 0 { buffer_new_backing(usize(size) * usize(itemsize)) } else { unsafe { nil } }
	return NdOut{
		data:     data
		shape:    shape.clone()
		size:     size
		itemsize: itemsize
		kind:     kind
	}
}

// nd_out_f64 allocates a zeroed float64 result of `shape`.
pub fn nd_out_f64(shape []int) NdOut {
	return nd_out(shape, 8, `d`)
}

// nd_out_f32 allocates a zeroed float32 result of `shape`.
pub fn nd_out_f32(shape []int) NdOut {
	return nd_out(shape, 4, `f`)
}

// nd_out_i64 allocates a zeroed int64 result of `shape`.
pub fn nd_out_i64(shape []int) NdOut {
	return nd_out(shape, 8, `q`)
}

// nd_out_i32 allocates a zeroed int32 result of `shape`.
pub fn nd_out_i32(shape []int) NdOut {
	return nd_out(shape, 4, `i`)
}

// nd_out_u8 allocates a zeroed uint8 result of `shape`.
pub fn nd_out_u8(shape []int) NdOut {
	return nd_out(shape, 1, `B`)
}

// f64s is the result's storage as a `[]f64`, row-major, to fill before returning it.
pub fn (o NdOut) f64s() []f64 {
	if o.kind != `d` {
		panic('NdOut: f64s on a `${o.kind.ascii_str()}` result')
	}
	mut out := []f64{}
	unsafe {
		out.data = o.data
		out.len = o.size
		out.cap = o.size
	}
	return out
}

// f32s is `f64s` for a float32 result.
pub fn (o NdOut) f32s() []f32 {
	if o.kind != `f` {
		panic('NdOut: f32s on a `${o.kind.ascii_str()}` result')
	}
	mut out := []f32{}
	unsafe {
		out.data = o.data
		out.len = o.size
		out.cap = o.size
	}
	return out
}

// i64s is `f64s` for an int64 result.
pub fn (o NdOut) i64s() []i64 {
	if o.kind != `q` {
		panic('NdOut: i64s on a `${o.kind.ascii_str()}` result')
	}
	mut out := []i64{}
	unsafe {
		out.data = o.data
		out.len = o.size
		out.cap = o.size
	}
	return out
}

// i32s is `f64s` for an int32 result.
pub fn (o NdOut) i32s() []i32 {
	if o.kind != `i` {
		panic('NdOut: i32s on a `${o.kind.ascii_str()}` result')
	}
	mut out := []i32{}
	unsafe {
		out.data = o.data
		out.len = o.size
		out.cap = o.size
	}
	return out
}

// u8s is `f64s` for a uint8 result.
pub fn (o NdOut) u8s() []u8 {
	if o.kind != `B` {
		panic('NdOut: u8s on a `${o.kind.ascii_str()}` result')
	}
	mut out := []u8{}
	unsafe {
		out.data = o.data
		out.len = o.size
		out.cap = o.size
	}
	return out
}

// nd_export hands a result to Python as an N-dimensional memoryview that owns the buffer.
// The flat view is cast to bytes and then to the element format with the shape, because a
// memoryview cannot be reshaped between two non-byte formats directly.
pub fn nd_export(o NdOut) PyObj {
	family := match o.kind {
		`d`, `f` { buffer_export_kind_float }
		`B`, `H`, `I`, `Q` { buffer_export_kind_uint }
		else { buffer_export_kind_int }
	}
	flat := buffer_export(o.data, buffer_export_owner(o.data), isize(o.size) * isize(o.itemsize),
		isize(o.itemsize), family)
	if flat.is_null() || o.shape.len == 1 {
		return flat
	}
	fmt := to_py_string(o.kind.ascii_str())
	bytes_fmt := to_py_string('B')
	as_bytes := call_method(flat.ptr, 'cast', [bytes_fmt.ptr])
	flat.decref()
	bytes_fmt.decref()
	if as_bytes.is_null() {
		fmt.decref()
		return as_bytes
	}
	shape := to_py_int_list(o.shape)
	shaped := call_method(as_bytes.ptr, 'cast', [fmt.ptr, shape.ptr])
	as_bytes.decref()
	fmt.decref()
	shape.decref()
	return shaped
}
