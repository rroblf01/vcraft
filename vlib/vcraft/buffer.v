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
//
// The one exception is reading a bytes-like object Python *handed back* from a call:
// `bytes_view` aliases it the same way an argument is aliased, which is what a server needs
// to write a large body without copying it twice on the way out.

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
	return buffer_view_of(obj, '${func}() argument ${name}')
}

// buffer_view_of acquires a buffer-protocol view of any object, which is what `buffer_view`
// does for a positional argument.
//
// It is the shape a hand-written extension needs for an object that did not arrive as an
// argument: a value that came back from a call. The view holds a reference on the exporter,
// so `buffer_release` is what lets the exporter go. Fails with the `TypeError` CPython sets
// itself when the object is not bytes-like.
pub fn buffer_view_of(obj PyObj, name string) !voidptr {
	if obj.is_null() {
		raise(.type_error, '${name} is not bytes-like')
		return error('${name} is not bytes-like')
	}
	unsafe {
		view := C.vpy_buffer_new()
		if view == nil {
			raise(.memory_error, 'cannot view ${name}')
			return error('cannot view ${name}')
		}
		// CPython sets the exception itself on failure -- "a bytes-like object is
		// required" -- so there is nothing to raise here, only an error value to
		// return. The view is zeroed on allocation, so releasing it after a failed
		// acquisition finds nothing.
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

// bytes_view reads any bytes-like object as a borrowed `[]u8`, without copying.
//
// `bytes_arg` is the argument-shaped version of this and indexes into a vectorcall tuple;
// this is the one for a value that came back from a call, which is just an object. Exact
// `bytes` is aliased directly -- no view, no acquisition -- and anything else bytes-like
// goes through a buffer view, whose reference pins the exporter. `bytes_of`, in cstring.v,
// is the lower-level exact-`bytes` pointer+length with no view at all.
//
// The slice aliases memory the caller does not own, so two rules are absolute. For an
// exact `bytes` alias nothing but the caller keeps the object alive, so a reference to it
// must be held for as long as the slice is used; a view, by contrast, holds its own. And
// `release` has to run on every path, success or failure.
//
// Hand-written V is the audience: a `[]u8` parameter already crosses without copying, but
// a large buffer that Python built and handed back (`await request.body()`, a cached
// response) otherwise costs a copy into a V `string` and another into a `[]u8` before the
// server can write it. Generated glue never needs this.
pub fn bytes_view(obj PyObj, name string) !BytesArg {
	if obj.is_null() {
		raise(.type_error, '${name} is not bytes-like')
		return error('${name} is not bytes-like')
	}
	if C.vpy_is_exact_bytes(obj.ptr) != 0 {
		unsafe {
			mut buf := voidptr(nil)
			mut n := isize(0)
			if C.PyBytes_AsStringAndSize(obj.ptr, voidptr(&buf), voidptr(&n)) != 0 {
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
	view := buffer_view_of(obj, name)!
	return BytesArg{
		data: buffer_bytes(view)
		view: view
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

// Persistent native buffers.
//
// A `@[vc_class]` field annotated `@[vc_buffer]` holds a slice whose backing lives for the
// object's lifetime and is owned manually, because the state block is CPython memory V's
// collector does not scan. The backing is allocated with the CPython allocator and freed
// by the generated `tp_dealloc` through `buffer_free`. The only values such a field may
// ever hold come from the `buffer_new_*` helpers below; assigning an ordinary V array to it
// would hand `buffer_free` a pointer it does not own.
//
// An eight-byte header precedes the payload and counts the open memoryviews, so a resize
// can refuse while one is alive: `realloc` moves the block, and a live `Py_buffer` still
// points at the old address.

// native_header is the size of the bookkeeping that precedes every native buffer's
// payload: the open-view count, then the allocated payload size in bytes. The capacity is
// kept so a resize can zero only the newly grown part.
const native_header = isize(16)

// native_base returns the start of the allocation, which is the payload minus its header.
fn native_base(p voidptr) voidptr {
	return unsafe { voidptr(&u8(p) - native_header) }
}

// native_views_ptr and native_cap_ptr address the two header words of a live buffer.
fn native_views_ptr(p voidptr) &isize {
	return unsafe { &isize(native_base(p)) }
}

fn native_cap_ptr(p voidptr) &isize {
	return unsafe { &isize(voidptr(&u8(native_base(p)) + 8)) }
}

// buffer_new_backing allocates `nbytes` of zeroed native memory and returns the payload
// pointer, with an empty view count and the capacity recorded.
fn buffer_new_backing(nbytes usize) voidptr {
	p := C.PyObject_Calloc(1, nbytes + usize(native_header))
	if p == unsafe { nil } {
		// The exact spelling is what `raise_panic` maps to MemoryError.
		panic('memory allocation failure')
	}
	unsafe {
		native_cap_ptr(voidptr(&u8(p) + native_header))[0] = isize(nbytes)
	}
	return unsafe { voidptr(&u8(p) + native_header) }
}

// buffer_resize_backing reallocates a native buffer, refusing while a view is open.
//
// A fresh zeroed block is allocated rather than `realloc`ed, so only the bytes that were
// there are carried over and the growth is zeroed: `realloc` would leave the extension
// uninitialised, and a buffer is documented as zeroed.
fn buffer_resize_backing(old voidptr, nbytes usize) !voidptr {
	if buffer_views(old) > 0 {
		return raise_domain(.buffer_error, 'cannot resize a buffer while a memoryview of it is open')
	}
	if old == unsafe { nil } {
		return buffer_new_backing(nbytes)
	}
	old_cap := unsafe { int(native_cap_ptr(old)[0]) }
	p := C.PyObject_Calloc(1, nbytes + usize(native_header))
	if p == unsafe { nil } {
		return raise_domain(.memory_error, 'cannot grow a buffer')
	}
	copy := if old_cap < int(nbytes) { old_cap } else { int(nbytes) }
	if copy > 0 {
		C.vpy_memcpy(unsafe { voidptr(&u8(p) + native_header) }, old, usize(copy))
	}
	C.PyObject_Free(native_base(old))
	unsafe {
		native_cap_ptr(voidptr(&u8(p) + native_header))[0] = isize(nbytes)
	}
	return unsafe { voidptr(&u8(p) + native_header) }
}

// native_alloc allocates `nbytes` of CPython-owned memory, released with `native_free`.
//
// The block has no header and no view count; it is the raw allocator, for the capsule
// escape hatch and anything that is not a `@[vc_buffer]` slice.
pub fn native_alloc(nbytes usize) voidptr {
	return C.PyObject_Malloc(nbytes)
}

// native_free releases a block allocated with `native_alloc`.
pub fn native_free(p voidptr) {
	if p != unsafe { nil } {
		C.PyObject_Free(p)
	}
}

// buffer_free releases a native buffer. Safe on a nil pointer, which is what an
// unallocated or zero-length field holds, and on a buffer with views open: the view count
// is for refusing resizes, not frees.
pub fn buffer_free(p voidptr) {
	if p != unsafe { nil } {
		C.PyObject_Free(native_base(p))
	}
}

// buffer_views reports how many memoryviews of a native buffer are open, zero for nil.
pub fn buffer_views(p voidptr) int {
	if p == unsafe { nil } {
		return 0
	}
	unsafe {
		return int(native_views_ptr(p)[0])
	}
}

// buffer_views_incr is called by a generated `bf_getbuffer` after a successful fill.
pub fn buffer_views_incr(p voidptr) {
	if p == unsafe { nil } {
		return
	}
	unsafe {
		slot := native_views_ptr(p)
		slot[0] = slot[0] + 1
	}
}

// buffer_views_decr is called by a generated `bf_releasebuffer`.
pub fn buffer_views_decr(p voidptr) {
	if p == unsafe { nil } {
		return
	}
	unsafe {
		slot := native_views_ptr(p)
		if slot[0] > 0 {
			slot[0] = slot[0] - 1
		}
	}
}

// buffer_fill wraps one contiguous run of bytes in a `Py_buffer`.
//
// `exporter` is the object the view keeps alive: `PyBuffer_FillInfo` takes a reference on
// it and `PyBuffer_Release` gives it back, which is the whole reason the memoryview is
// sound where `PyMemoryView_FromMemory` is not. Returns CPython's status.
pub fn buffer_fill(view voidptr, exporter voidptr, data voidptr, len_bytes isize,
	readonly int, flags int) int {
	return C.PyBuffer_FillInfo(view, exporter, data, len_bytes, readonly, flags)
}

// buffer_fill_typed wraps a run of bytes in a typed `Py_buffer`, for a class whose
// `@[vc_buffer_typed]` field implements the buffer protocol. `itemsize` is the element's
// width and `kind` its family (0 unsigned, 1 signed, 2 float, 3 bool), so the view
// reports one item per element with the matching format instead of a byte view.
// `PyBuffer_FillInfo`, which only expresses a byte view, backs `buffer_fill` instead.
// Returns CPython's status.
pub fn buffer_fill_typed(view voidptr, exporter voidptr, data voidptr, len_bytes isize,
	itemsize isize, kind int, readonly int, flags int) int {
	return C.vpy_buffer_fill_typed(view, exporter, data, len_bytes, itemsize, kind, readonly,
		flags)
}

// new_handle wraps a native pointer in a Python capsule.
//
// The general escape hatch for state that is not a plain slice: a handle from a C library,
// a struct full of pointers, anything a class would be overkill for. The capsule owns the
// pointer and calls `destructor` when the capsule is collected. CPython passes the
// destructor the *capsule object*, not the stored pointer, so the destructor calls
// `handle_data(capsule)` to recover it. The capsule is anonymous, so `handle_data` needs
// no name that would have to outlive the capsule.
pub fn new_handle(value voidptr, destructor voidptr) PyObj {
	return steal(C.PyCapsule_New(value, unsafe { nil }, destructor))
}

// handle_data returns the pointer a capsule holds, or nil when `obj` is not one (with a
// Python exception set, as `PyCapsule_GetPointer` does).
pub fn handle_data(obj voidptr) voidptr {
	if obj == unsafe { nil } {
		return unsafe { nil }
	}
	unsafe {
		return C.PyCapsule_GetPointer(obj, nil)
	}
}

// buffer_new_backing's typed wrappers. One per scalar element type, because a generic
// helper called from generated code in another module gets no forward declaration in V.
// Each returns a zeroed native-backed slice; `buffer_resize_*` grows or shrinks one.

// buffer_new_bool allocates a native-backed `[]bool` of `n` elements, zero-initialised.
pub fn buffer_new_bool(n int) []bool {
	mut out := []bool{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(bool))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_bool reallocates a native-backed `[]bool`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_bool(s []bool, n int) ![]bool {
	mut out := []bool{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(bool))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_int allocates a native-backed `[]int` of `n` elements, zero-initialised.
pub fn buffer_new_int(n int) []int {
	mut out := []int{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(int))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_int reallocates a native-backed `[]int`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_int(s []int, n int) ![]int {
	mut out := []int{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(int))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_i8 allocates a native-backed `[]i8` of `n` elements, zero-initialised.
pub fn buffer_new_i8(n int) []i8 {
	mut out := []i8{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(i8))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_i8 reallocates a native-backed `[]i8`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_i8(s []i8, n int) ![]i8 {
	mut out := []i8{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(i8))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_i16 allocates a native-backed `[]i16` of `n` elements, zero-initialised.
pub fn buffer_new_i16(n int) []i16 {
	mut out := []i16{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(i16))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_i16 reallocates a native-backed `[]i16`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_i16(s []i16, n int) ![]i16 {
	mut out := []i16{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(i16))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_i32 allocates a native-backed `[]i32` of `n` elements, zero-initialised.
pub fn buffer_new_i32(n int) []i32 {
	mut out := []i32{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(i32))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_i32 reallocates a native-backed `[]i32`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_i32(s []i32, n int) ![]i32 {
	mut out := []i32{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(i32))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_i64 allocates a native-backed `[]i64` of `n` elements, zero-initialised.
pub fn buffer_new_i64(n int) []i64 {
	mut out := []i64{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(i64))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_i64 reallocates a native-backed `[]i64`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_i64(s []i64, n int) ![]i64 {
	mut out := []i64{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(i64))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_isize allocates a native-backed `[]isize` of `n` elements, zero-initialised.
pub fn buffer_new_isize(n int) []isize {
	mut out := []isize{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(isize))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_isize reallocates a native-backed `[]isize`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_isize(s []isize, n int) ![]isize {
	mut out := []isize{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(isize))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_u8 allocates a native-backed `[]u8` of `n` elements, zero-initialised.
pub fn buffer_new_u8(n int) []u8 {
	mut out := []u8{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(u8))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_u8 reallocates a native-backed `[]u8`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_u8(s []u8, n int) ![]u8 {
	mut out := []u8{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(u8))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_u16 allocates a native-backed `[]u16` of `n` elements, zero-initialised.
pub fn buffer_new_u16(n int) []u16 {
	mut out := []u16{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(u16))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_u16 reallocates a native-backed `[]u16`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_u16(s []u16, n int) ![]u16 {
	mut out := []u16{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(u16))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_u32 allocates a native-backed `[]u32` of `n` elements, zero-initialised.
pub fn buffer_new_u32(n int) []u32 {
	mut out := []u32{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(u32))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_u32 reallocates a native-backed `[]u32`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_u32(s []u32, n int) ![]u32 {
	mut out := []u32{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(u32))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_u64 allocates a native-backed `[]u64` of `n` elements, zero-initialised.
pub fn buffer_new_u64(n int) []u64 {
	mut out := []u64{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(u64))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_u64 reallocates a native-backed `[]u64`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_u64(s []u64, n int) ![]u64 {
	mut out := []u64{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(u64))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_usize allocates a native-backed `[]usize` of `n` elements, zero-initialised.
pub fn buffer_new_usize(n int) []usize {
	mut out := []usize{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(usize))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_usize reallocates a native-backed `[]usize`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_usize(s []usize, n int) ![]usize {
	mut out := []usize{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(usize))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_f32 allocates a native-backed `[]f32` of `n` elements, zero-initialised.
pub fn buffer_new_f32(n int) []f32 {
	mut out := []f32{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(f32))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_f32 reallocates a native-backed `[]f32`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_f32(s []f32, n int) ![]f32 {
	mut out := []f32{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(f32))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// buffer_new_f64 allocates a native-backed `[]f64` of `n` elements, zero-initialised.
pub fn buffer_new_f64(n int) []f64 {
	mut out := []f64{}
	if n > 0 {
		unsafe {
			out.data = buffer_new_backing(usize(n) * sizeof(f64))
			out.len = n
			out.cap = n
		}
	}
	return out
}

// buffer_resize_f64 reallocates a native-backed `[]f64`, or raises BufferError while a
// memoryview of it is open. The address may move, so the result must be stored back.
pub fn buffer_resize_f64(s []f64, n int) ![]f64 {
	mut out := []f64{}
	if n > 0 {
		unsafe {
			out.data = buffer_resize_backing(s.data, usize(n) * sizeof(f64))!
			out.len = n
			out.cap = n
		}
	} else {
		buffer_free(s.data)
	}
	return out
}

// Exporting a native buffer as a Python `memoryview`, with no copy.
//
// Returns go the other way and copy by default: `to_py_bytes_slice` builds a Python
// `bytes` that owns its storage, so there is nothing to alias into. A function whose
// result is a `buffer_new_*` slice and is annotated `@[vc_memoryview]` takes the other
// path: the slice's backing is handed to a CPython object that implements the buffer
// protocol, and the wrapper returns a writable `memoryview` over it. No element is
// boxed and no byte is copied, so a large numeric result crosses as a view instead of as
// a list of Python objects.
//
// Ownership moves to the view: the exporter frees the backing through its header when
// the last `memoryview` of it is released. The slice must therefore come from
// `buffer_new_*` (or from a `buffer_resize_*` of one); exporting an ordinary V slice
// would hand the exporter a pointer the CPython allocator does not own.
//
// `buffer_export_kind_*` is the element's format family; the element's size picks the
// width, so `int` and `i64` share a family and differ in `itemsize`.

const buffer_export_kind_uint = 0

const buffer_export_kind_int = 1

const buffer_export_kind_float = 2

const buffer_export_kind_bool = 3

// buffer_export hands a native-backed payload to CPython. `owner` is the allocation to
// free (the payload minus its header), nil for an empty slice that was never allocated.
fn buffer_export(data voidptr, owner voidptr, nbytes isize, itemsize isize, kind int) PyObj {
	return steal(C.vpy_buffer_export(data, owner, nbytes, itemsize, kind))
}

// buffer_export_owner is the allocation behind an exported payload, nil when the slice is
// empty and nothing was allocated.
fn buffer_export_owner(data voidptr) voidptr {
	if data == unsafe { nil } {
		return unsafe { nil }
	}
	return native_base(data)
}

// buffer_export_bool exports a `[]bool` as a writable memoryview, transferring ownership.
pub fn buffer_export_bool(s []bool) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(bool)), isize(sizeof(bool)), buffer_export_kind_bool)
	}
}

// buffer_export_int exports a `[]int` as a writable memoryview, transferring ownership.
pub fn buffer_export_int(s []int) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(int)), isize(sizeof(int)), buffer_export_kind_int)
	}
}

// buffer_export_i8 exports a `[]i8` as a writable memoryview, transferring ownership.
pub fn buffer_export_i8(s []i8) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(i8)), isize(sizeof(i8)), buffer_export_kind_int)
	}
}

// buffer_export_i16 exports a `[]i16` as a writable memoryview, transferring ownership.
pub fn buffer_export_i16(s []i16) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(i16)), isize(sizeof(i16)), buffer_export_kind_int)
	}
}

// buffer_export_i32 exports a `[]i32` as a writable memoryview, transferring ownership.
pub fn buffer_export_i32(s []i32) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(i32)), isize(sizeof(i32)), buffer_export_kind_int)
	}
}

// buffer_export_i64 exports a `[]i64` as a writable memoryview, transferring ownership.
pub fn buffer_export_i64(s []i64) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(i64)), isize(sizeof(i64)), buffer_export_kind_int)
	}
}

// buffer_export_isize exports a `[]isize` as a writable memoryview, transferring ownership.
pub fn buffer_export_isize(s []isize) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(isize)), isize(sizeof(isize)), buffer_export_kind_int)
	}
}

// buffer_export_u8 exports a `[]u8` as a writable memoryview, transferring ownership.
pub fn buffer_export_u8(s []u8) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(u8)), isize(sizeof(u8)), buffer_export_kind_uint)
	}
}

// buffer_export_u16 exports a `[]u16` as a writable memoryview, transferring ownership.
pub fn buffer_export_u16(s []u16) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(u16)), isize(sizeof(u16)), buffer_export_kind_uint)
	}
}

// buffer_export_u32 exports a `[]u32` as a writable memoryview, transferring ownership.
pub fn buffer_export_u32(s []u32) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(u32)), isize(sizeof(u32)), buffer_export_kind_uint)
	}
}

// buffer_export_u64 exports a `[]u64` as a writable memoryview, transferring ownership.
pub fn buffer_export_u64(s []u64) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(u64)), isize(sizeof(u64)), buffer_export_kind_uint)
	}
}

// buffer_export_usize exports a `[]usize` as a writable memoryview, transferring ownership.
pub fn buffer_export_usize(s []usize) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(usize)), isize(sizeof(usize)), buffer_export_kind_uint)
	}
}

// buffer_export_f32 exports a `[]f32` as a writable memoryview, transferring ownership.
pub fn buffer_export_f32(s []f32) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(f32)), isize(sizeof(f32)), buffer_export_kind_float)
	}
}

// buffer_export_f64 exports a `[]f64` as a writable memoryview, transferring ownership.
pub fn buffer_export_f64(s []f64) PyObj {
	unsafe {
		return buffer_export(voidptr(s.data), buffer_export_owner(voidptr(s.data)),
			isize(s.len) * isize(sizeof(f64)), isize(sizeof(f64)), buffer_export_kind_float)
	}
}
