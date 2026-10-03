module vcraft

// Marshalling between V strings and C strings.
//
// A V string carries an explicit length and no guarantee of a terminator, while
// the CPython functions that take a name or a message expect a `const char *`
// and read to the terminator. The reverse direction is safe because CPython
// reports the length alongside the pointer.

// cstring allocates a NUL-terminated copy of `s` on the C heap.
//
// The copy outlives the V value it came from and is released with
// `free_cstring`, so it stays valid for as long as the callee needs it without
// involving V's allocator or its ownership rules. V uses the same technique
// where it needs a terminator, see `string.replace`.
//
// A compile-time literal can be passed to CPython directly, as `c'name'`, and
// then nothing needs freeing.
pub fn cstring(s string) voidptr {
	unsafe {
		buf := malloc_noscan(s.len + 1)
		if buf == nil {
			return nil
		}
		// The copy goes through the shim's memcpy rather than V's builtin, because
		// the builtin compiles to `v_memcpy` whose declaration is emitted late in
		// the file and would trip gcc's implicit declaration rule here.
		C.vpy_memcpy(buf, s.str, usize(s.len))
		*(buf + s.len) = 0
		return buf
	}
}

// free_cstring releases a buffer returned by `cstring`.
pub fn free_cstring(p voidptr) {
	if p != unsafe { nil } {
		unsafe { free(p) }
	}
}

// with_cstring runs `f` with a NUL-terminated copy of `s` and frees it
// afterwards, so the allocation never leaks on an early return.
@[inline]
pub fn with_cstring[T](s string, f fn (voidptr) T) T {
	p := cstring(s)
	defer {
		free_cstring(p)
	}
	return f(p)
}

// from_utf8 turns the (pointer, length) pair that PyUnicode_AsUTF8AndSize and
// PyBytes_AsStringAndSize return into a V string. It reads exactly `len` bytes,
// so embedded NULs survive the round trip.
pub fn from_utf8(ptr voidptr, len int) string {
	if ptr == unsafe { nil } {
		return ''
	}
	unsafe {
		return (&u8(ptr)).vstring_with_len(len)
	}
}

// utf8_of returns the UTF-8 bytes and length of a Python str. The pointer is
// owned by the str object, so the caller must keep `obj` alive while using it.
pub fn utf8_of(obj PyObj) (voidptr, int) {
	mut size := int(0)
	p := unsafe { C.PyUnicode_AsUTF8AndSize(obj.ptr, &size) }
	return p, size
}

// bytes_of returns the buffer and length of a Python bytes object. The pointer
// is owned by the object.
pub fn bytes_of(obj PyObj) (voidptr, int) {
	mut size := int(0)
	p := unsafe { C.PyBytes_AsStringAndSize(obj.ptr, &size) }
	return p, size
}
