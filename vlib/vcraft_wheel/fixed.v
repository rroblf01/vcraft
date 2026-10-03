module vcraft_wheel

// The compressor: LZ77 matches, emitted as one fixed-Huffman block per 64 KiB.

// block_size is how much input one block covers.
//
// It is 32768 because that is the furthest back DEFLATE can address: a distance is 15
// bits of extra value over a base of 24577, giving a maximum of 32768. A block larger
// than that is not a choice, it is unimplementable here, and using 65536 produces a
// stream that decodes to garbage for any input past the halfway point: the encoder
// finds a match it can describe and the decoder cannot reach it.
const block_size = 32768

// hash_bits sizes the hash table. 15 bits is 32 KiB of positions, which is a
// compromise: larger chains find longer matches and cost more to walk, and this
// compresses a `.so` within a few percent of zlib level 6.
const hash_bits = 15

const hash_size = 1 << hash_bits

// hash_min is the shortest match worth emitting. Three is the format's minimum, so
// a two-byte coincidence is never stored.
const hash_min = 3

// hash_max is the longest match the length tables can express.
const hash_max = 258

// max_chain is how far back a hash chain is walked before giving up.
//
// The chain is walked nearest-first, so the first hit is the most recent and
// usually the longest. Stopping early costs a little ratio and saves a lot of time
// on data that repeats a lot, which a `.so` does.
const max_chain = 64

// Compressor holds the state one deflate call needs: the output, the block being
// built, and the match finder's tables.
struct Compressor {
mut:
	// w is the bit writer for the whole output.
	w BitWriter
	// prev links each position to the previous position with the same hash, which
	// is what makes the search a chain rather than a scan.
	prev []i32
	// head maps a hash to the most recent position carrying it.
	head []i32
	// block_start is the position in `input` where the current block began.
	block_start int
	// pos is the next position in `input` to look at.
	pos int
	// block_first tells whether anything has been written to the current block yet.
	block_first bool
	// pending_final is the BFINAL value for the block about to start. `run` sets it,
	// because only it knows whether the input ends inside this block.
	pending_final bool
}

// compress returns the DEFLATE stream for `input`.
//
// The result is a single fixed-Huffman block when the input fits in one window, and
// one block per 64 KiB otherwise, with the last block marked final.
pub fn compress(input []u8) []u8 {
	mut c := Compressor{}
	// The bit writer is initialised explicitly rather than left to the zero value of a
	// nested struct. A zeroed `BitWriter` is correct in principle, but `out` must be a
	// real empty slice with room to append; a nil slice that has never been allocated
	// makes the first `<<` write past the end of nothing, and the bits land in memory
	// the struct does not own.
	c.w = BitWriter{
		out:        []u8{}
		bit_buffer: 0
		bit_count:  0
	}
	// Both tables are filled by an explicit loop rather than an `init:` field on the
	// literal. V accepts `init:`, but a `len:` plus `init:` literal is not guaranteed
	// to have written the initialiser before use, and an uninitialised `head` makes
	// `find_match` follow a chain of arbitrary positions and emit matches the decoder
	// rejects.
	c.prev = []i32{len: input.len}
	c.head = []i32{len: hash_size}
	for i in 0 .. c.prev.len {
		c.prev[i] = -1
	}
	for i in 0 .. c.head.len {
		c.head[i] = -1
	}
	c.pos = 0
	c.block_start = 0
	return c.run(input)
}

// run walks the input, emitting literals and matches.
fn (mut c Compressor) run(input []u8) []u8 {
	c.pos = 0
	c.block_start = 0
	c.block_first = true
	for c.pos < input.len {
		// A block ends before its window is full when a match would run past it, so the
		// check is on where the *match* ends rather than on the current position.
		if c.pos - c.block_start + hash_max > block_size && !c.block_first {
			c.end_block(false)
			c.block_start = c.pos
			c.block_first = true
		}
		// Whether the block starting here is the last one: it is, if the rest of the
		// input fits inside this block's window. `find_match` never emits a match
		// longer than the window allows, so once the flush above has run, everything
		// left fits.
		c.pending_final = input.len - c.pos <= block_size - hash_max
		mut length := 0
		mut distance := 0
		if c.pos + hash_min <= input.len {
			mut best_length := 0
			mut best_distance := 0
			best_length, best_distance = c.find_match(input)
			length = best_length
			distance = best_distance
		}
		if length >= hash_min {
			c.emit_match(length, distance)
			// Every position the match covers is registered, not just its first, or the
			// search would miss a match starting one byte inside it.
			for i in 0 .. length {
				if c.pos + i < input.len {
					c.insert(input, c.pos + i)
				}
			}
			c.pos += length
		} else {
					c.emit_literal(input[c.pos])
			c.insert(input, c.pos)
			c.pos++
		}
	}
	if !c.block_first {
		c.end_block(true)
	} else {
		// An empty input still needs one block, carrying the end-of-block symbol.
		c.write_header(true)
		c.w.write_code(literal_code(256), literal_bits(256))
	}
	c.w.flush()
	return c.w.out
}

// end_of_block is the symbol that terminates a block.
const end_of_block = 256

// write_header writes the 3-bit block header.
//
// BFINAL is 1 bit, BTYPE is 2, and both are written least significant bit first, so
// a final fixed block is `1` then `01`, giving the byte pattern every unzip expects.
//
// BFINAL cannot be decided when the header is written, because the compressor does
// not yet know whether more input follows and the bit cannot be patched in later.
//
// The obvious workaround, writing every block with BFINAL=0 and marking only the last,
// does not work either: the bit is the *first* bit of the block, so by the time the
// last block is known the earlier headers are already in the byte stream. A stream
// whose final block is not marked final has no end, and a decoder rejects it once it
// runs out of input.
//
// So the decision is made before any of it: `run` knows the input length, and it can
// see whether a given position starts the last block by comparing against the end.
// The first block is written with BFINAL=1 only when the whole input fits in it,
// which is the common case for the small files a wheel is made of.
fn (mut c Compressor) write_header(final bool) {
	bt := u32(1) // fixed Huffman
	bfinal := if final { u32(1) } else { u32(0) }
	c.w.write_bits(bfinal, 1)
	c.w.write_bits(bt, 2)
	c.block_first = false
}

// end_block writes the end-of-block symbol for the block in progress.
//
// `final` marks BFINAL, which belongs to the block being closed. Writing it as 0
// and leaving it out entirely produces a stream every decoder rejects at the end,
// because the last block is not marked final and the stream never terminates.
// `final` sets BFINAL, but the header is not written here.
//
// The header was already written, by `emit_literal` or `emit_match`, when the block
// opened: `pending_final` was decided then, which is the only point that knows whether
// the input ends inside this block. Writing it again here appends three stray bits
// before the end-of-block symbol, and the decoder reads those as the first bits of the
// code and desynchronises from there to the end of the stream.
fn (mut c Compressor) end_block(final bool) {
	_ = final
	c.w.write_code(literal_code(end_of_block), literal_bits(end_of_block))
}

// emit_literal writes one byte as a literal.
fn (mut c Compressor) emit_literal(byte u8) {
	if c.block_first {
		c.write_header(c.pending_final)
	}
	c.w.write_code(literal_code(int(byte)), literal_bits(int(byte)))
}

// emit_match writes a length and distance pair.
fn (mut c Compressor) emit_match(length int, distance int) {
	if c.block_first {
		c.write_header(c.pending_final)
	}
	sym := length_symbol(length)
	c.w.write_code(literal_code(sym), literal_bits(sym))
	extra := length_extra[sym - 257]
	if extra > 0 {
		c.w.write_bits(u32(length - length_base[sym - 257]), extra)
	}
	dsym := distance_symbol(distance)
	c.w.write_code(distance_code(dsym), distance_bits(dsym))
	dextra := distance_extra[dsym]
	if dextra > 0 {
		c.w.write_bits(u32(distance - distance_base[dsym]), dextra)
	}
}

// hash_of returns the table index for the three bytes at `at`.
//
// It reads three bytes rather than four because three is the shortest match the
// format can express, and a four-byte hash would leave every three-byte match
// unhashable and therefore unfindable.
fn hash_of(input []u8, at int) int {
	mut h := (u32(input[at]) << 16) | (u32(input[at + 1]) << 8) | u32(input[at + 2])
	// A multiplicative hash: the table is far smaller than the input, so the low bits
	// of the raw value would collide heavily.
	h = h * 2654435761
	return int((h >> u32(32 - hash_bits)) & u32(hash_size - 1))
}

// insert records `at` in the hash chain, provided it can start a match.
fn (mut c Compressor) insert(input []u8, at int) {
	if at + hash_min > input.len {
		return
	}
	h := hash_of(input, at)
	c.prev[at] = c.head[h]
	c.head[h] = i32(at)
}

// find_match returns the longest match for the current position, and its distance.
//
// A length of zero means no match worth emitting. Distance is one-based, as the
// format defines it, so a match right before `pos` has distance 1.
fn (mut c Compressor) find_match(input []u8) (int, int) {
	if c.pos + hash_min > input.len {
		return 0, 0
	}
	mut best_length := 0
	mut best_distance := 0
	h := hash_of(input, c.pos)
	mut candidate := c.head[h]
	mut chain := max_chain
	mut limit := c.pos - block_size
	if limit < 0 {
		limit = 0
	}
	// A match may not reach back past the start of the current block, because the
	// previous block's data is no longer in the window.
	for candidate >= 0 && chain > 0 {
		start := int(candidate)
		if start < limit {
			break
		}
		mut length := 0
		mut max_length := hash_max
		if input.len - c.pos < max_length {
			max_length = input.len - c.pos
		}
		for length < max_length && input[start + length] == input[c.pos + length] {
			length++
		}
		if length > best_length {
			best_length = length
			best_distance = c.pos - start
			if best_length >= max_length {
				break
			}
		}
		candidate = c.prev[start]
		chain--
	}
	return best_length, best_distance
}
