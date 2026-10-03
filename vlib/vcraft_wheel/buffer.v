module vcraft_wheel

// The little-endian writers a binary container needs.
//
// V's `<<` appends a whole value, which is wrong for a binary file twice over: it
// writes in V's own byte order, and it appends every value at its declared width, so a
// `u16` field would take four bytes. ZIP is little-endian throughout, so each of these
// writes one field, one byte at a time.
//
// The parameters are `mut []u8` and the result is returned. Both matter, and neither is
// the shape one would write in another language. `&[]u8` never grows the caller's
// slice, because V passes a slice header by value. `mut []u8` does grow it, but the
// callee has to be called as `mut b`, and a caller that forgets compiles fine and
// silently appends to a copy. Returning the slice as well makes the growth visible in
// both directions, so a mistake is a type error rather than a truncated file.

// put_u8 appends one byte.
pub fn put_u8(mut out []u8, v u8) []u8 {
	out << v
	return out
}

// put_u16 appends a 16-bit value little-endian.
pub fn put_u16(mut out []u8, v u16) []u8 {
	out << u8(v & 0xFF)
	out << u8((v >> 8) & 0xFF)
	return out
}

// put_u32 appends a 32-bit value little-endian.
pub fn put_u32(mut out []u8, v u32) []u8 {
	out << u8(v & 0xFF)
	out << u8((v >> 8) & 0xFF)
	out << u8((v >> 16) & 0xFF)
	out << u8((v >> 24) & 0xFF)
	return out
}

// put_u64 appends a 64-bit value little-endian.
pub fn put_u64(mut out []u8, v u64) []u8 {
	for i := 0; i < 8; i++ {
		out << u8((v >> u32(i * 8)) & 0xFF)
	}
	return out
}

// put_bytes appends raw bytes.
pub fn put_bytes(mut out []u8, v []u8) []u8 {
	out << v
	return out
}

// put_string appends a string's bytes, with no terminator.
pub fn put_string(mut out []u8, s string) []u8 {
	out << s.bytes()
	return out
}
