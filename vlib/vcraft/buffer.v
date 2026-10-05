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
pub fn buffer_bytes(view voidptr) []u8 {
	unsafe {
		n := C.vpy_buffer_len(view)
		mut out := []u8{len: n, cap: n}
		out.data = C.vpy_buffer_ptr(view)
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
