module vcraft

// Zero-copy buffers.
//
// A `[]u8` parameter accepts any object exposing the buffer protocol -- `bytes`,
// `bytearray`, `memoryview` -- without copying it. The generated wrapper acquires a
// view, aliases it as a V slice, calls the function, and releases the view on the
// way out, on every path including the error ones:
//
// ```v
// arg0_view := vcraft.buffer_view(args, 0, 'checksum', 'data') or { return unsafe { nil } }
// defer {
// 	vcraft.buffer_release(arg0_view)
// }
// arg0 := vcraft.buffer_bytes(arg0_view)
// ```
//
// Three properties make this sound, and each one is easy to get wrong:
//
//   - The slice aliases the exporter's memory rather than copying it, so it must not
//     outlive the call. The view holds a reference on the exporter for exactly the
//     call's duration, and the deferred release drops it; a slice stored in a global
//     or returned to Python would point at memory nobody owns.
//   - The release runs in a `defer`, not after the call, because the call can fail or
//     panic. A release on the fall-through path alone leaks the view on every error.
//   - The exporter is never written through this slice by generated code. V slices
//     are mutable in principle, and writing through the alias would mutate the
//     caller's `bytearray` from inside what reads as a pure function. Nothing stops
//     the V code from doing it -- the unsafety is documented, not enforced.
//
// Returns go the other way and copy: `to_py_bytes_slice` builds a Python `bytes`,
// which is immutable and owns its storage, so there is nothing to alias into. A
// zero-copy return would need a `memoryview` over V memory with a lifetime the
// collector cannot give it.

// buffer_view acquires a buffer-protocol view of positional argument `i`.
//
// Fails with the `TypeError` CPython sets itself when the argument is not bytes-like,
// and with a `TypeError` naming the missing argument when there is none. The view is
// released with `buffer_release`, and acquiring without releasing leaks the view and
// the reference it holds on the exporter.
pub fn buffer_view(argv voidptr, i int, func string, name string) !voidptr {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	unsafe {
		view := C.vpy_buffer_new()
		if view == nil {
			raise(.memory_error, '${func}() cannot view argument: ${name}')
			return error('cannot view ${name}')
		}
		// CPython sets the exception itself on failure -- "a bytes-like object is
		// required" -- so there is nothing to raise here, only an error value to
		// return so the wrapper takes its `or` branch. The view is zeroed on
		// allocation, so releasing it after a failed acquisition finds nothing.
		if C.vpy_buffer_get(obj.ptr, view) != 0 {
			C.vpy_buffer_release(view)
			return error('${name} is not bytes-like')
		}
		return view
	}
}

// buffer_bytes aliases a view's bytes as a V slice, without copying.
//
// The slice and the view share the exporter's memory. See the module comment for why
// the slice must not outlive the call.
//
// The header is built field by field from an empty literal: allocating `len`
// first and then overwriting `data` would abandon a GC block of the argument's
// size on every call, which is exactly the garbage a zero-copy path exists to
// avoid.
pub fn buffer_bytes(view voidptr) []u8 {
	unsafe {
		n := int(C.vpy_buffer_len(view))
		mut out := []u8{}
		out.data = C.vpy_buffer_ptr(view)
		out.len = n
		out.cap = n
		return out
	}
}

// buffer_release releases a view acquired with `buffer_view`.
//
// Safe on every path, including a view whose acquisition failed and a null view,
// because the view is zeroed on allocation. The generated wrapper defers this, so a
// call that fails or panics still gives the reference back.
pub fn buffer_release(view voidptr) {
	unsafe {
		C.vpy_buffer_release(view)
	}
}

// BytesArg is a `[]u8` argument together with whatever keeps it alive for the
// call: a buffer view, or nothing for exact `bytes`. `bytes` is immutable and
// the argument itself keeps the object alive, so aliasing it needs no view and
// pays no acquisition. The generated wrapper holds one, defers `release`, and
// reads `data`.
pub struct BytesArg {
pub:
	data []u8
	view voidptr
}

// bytes_arg reads positional argument `i` as bytes without copying.
//
// Exact `bytes` aliases the object directly. Anything else bytes-like goes
// through `buffer_view`, whose reference pins the exporter. Missing and
// non-bytes-like arguments fail exactly as `buffer_view` reports them, so the
// slow path stays the single place that shapes those errors.
pub fn bytes_arg(argv voidptr, i int, func string, name string) !BytesArg {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	if C.vpy_is_exact_bytes(obj.ptr) != 0 {
		// Inlined rather than through `bytes_of`: a multi-return value travels
		// in an 8-byte result struct V allocates per call, and this is the hot
		// path of every `[]u8` call with `bytes` input.
		unsafe {
			mut buf := voidptr(nil)
			mut n := isize(0)
			if C.PyBytes_AsStringAndSize(obj.ptr, voidptr(&buf), voidptr(&n)) != 0 {
				// Unreachable for exact `bytes`, which always exposes a buffer;
				// kept because CPython signals failure this way, not with NULL.
				return error('${name} is not bytes-like')
			}
			mut exact := []u8{}
			exact.data = buf
			exact.len = int(n)
			exact.cap = int(n)
			return BytesArg{
				data: exact
				view: nil
			}
		}
	}
	view := buffer_view(argv, i, func, name)!
	return BytesArg{
		data: buffer_bytes(view)
		view: view
	}
}

// release gives the view back, or nothing for exact `bytes`.
pub fn (b BytesArg) release() {
	if b.view != unsafe { nil } {
		unsafe { C.vpy_buffer_release(b.view) }
	}
}

// to_py_bytes_slice boxes a V slice as Python bytes, copying it.
//
// Copying because Python `bytes` are immutable and own their storage: there is no
// aliasing a V slice into them. For reads the other direction costs nothing; for
// writes this is the price of the type.
pub fn to_py_bytes_slice(value []u8) PyObj {
	unsafe {
		return steal(C.PyBytes_FromStringAndSize(value.data, value.len))
	}
}
