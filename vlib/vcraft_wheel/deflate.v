module vcraft_wheel

// DEFLATE (RFC 1951), enough of it to compress a wheel.
//
// A wheel has to be a ZIP with method 8, because that is what installers expect.
// The alternative is method 0, stored, which every tool also reads and which needs
// no compressor at all. Storing would work, and it is deliberately not what this
// does: an uncompressed `.so` is roughly twice the size, and a wheel that doubles
// the download for a packaging tool is a bug users notice.
//
// zlib is not linked. It is present on most build hosts but not all, and linking it
// makes the extension depend on a shared library the manylinux and musllinux images
// have to agree on. Vendoring zlib is worse. About 250 lines of fixed-Huffman
// DEFLATE is cheaper than either, and produces output every unzip reads.
//
// What is implemented: a single fixed-Huffman block per 64 KiB of input, with a
// hash-chain match finder. That is compression, roughly 2-3x on a binary, which is
// what a wheel needs. Dynamic Huffman would do better and is not written; the
// section at the bottom says what it would cost.

// BitWriter appends bits to a byte slice, least significant bit first.
//
// DEFLATE packs bits into bytes starting at the bottom, and a Huffman code is
// written most significant bit of the code first. Both are handled here so that
// `put_bits` and `put_code` are the only two places that know it.
pub struct BitWriter {
pub mut:
	out    []u8
	// bit_buffer holds the bits not yet written out. It is at most 16 bits: the
	// longest Huffman code here is 15 bits, and a literal adds 8 on top.
	bit_buffer u32
	// bit_count is how many bits of bit_buffer are real.
	bit_count int
}

// write_bits appends `count` bits of `value`, least significant bit first.
//
// This is how DEFLATE stores everything that is not a Huffman code: the block
// header, the extra bits of a length or distance, and a stored block's bytes.
pub fn (mut w BitWriter) write_bits(value u32, count int) {
	w.bit_buffer |= (value & bit_mask(count)) << w.bit_count
	w.bit_count += count
	for w.bit_count >= 8 {
		w.out << u8(w.bit_buffer & 0xFF)
		w.bit_buffer >>= 8
		w.bit_count -= 8
	}
}

// write_code appends a Huffman code, most significant bit first.
//
// The order is the reverse of `write_bits`, which is not a typo: RFC 1951 says
// Huffman codes are packed starting with the most significant bit, while
// everything else is packed least significant bit first.
pub fn (mut w BitWriter) write_code(code u32, count int) {
	// An explicit countdown, not a descending range. V reads `count - 1 .. 0` as an
	// empty range, because a descending range literal is rejected as never executing
	// and `count` is not a constant it can see. The loop then never runs, every
	// Huffman code writes zero bits, and the output is a bare block header that no
	// decoder will accept.
	for i := count - 1; i >= 0; i-- {
		bit := (code >> u32(i)) & 1
		w.write_bits(bit, 1)
	}
}

// flush pads to a byte boundary, writing the pending bits.
//
// The final block is followed by whatever bits remain in the buffer, so the padding
// is part of the format rather than an afterthought.
pub fn (mut w BitWriter) flush() {
	if w.bit_count > 0 {
		w.out << u8(w.bit_buffer & 0xFF)
		w.bit_buffer = 0
		w.bit_count = 0
	}
}

// bit_mask returns a mask of `count` low bits. `write_bits` uses it so a caller
// passing a wider value does not corrupt the bits above the count.
fn bit_mask(count int) u32 {
	if count >= 32 {
		return 0xFFFF_FFFF
	}
	return (u32(1) << u32(count)) - 1
}
