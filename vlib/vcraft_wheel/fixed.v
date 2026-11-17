module vcraft_wheel

// The compressor: LZ77 matches with lazy evaluation, emitted in blocks that are each
// written with whichever Huffman code is smaller for them, the fixed one or one built
// from the block's own symbol counts.

// window is how far back a match may reach: a distance is at most 32768.
const window = 32768

// hash_bits sizes the hash table. 15 bits is 32 KiB of positions, which is a
// compromise: larger chains find longer matches and cost more to walk.
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

// max_lazy is the match length past which the next position is not searched for a
// longer one. A match this long is rarely beaten one byte later, and skipping the
// search keeps highly repetitive input fast (zlib's level 6 uses 16).
const max_lazy = 32

// block_tokens is how many literals and matches one block holds before it is written.
// A block's Huffman code is fitted to its own contents, so smaller blocks track the
// data more closely and pay a header more often; zlib uses the same 16 Ki.
const block_tokens = 16384

// match_flag marks a token as a match: `match_flag | length << 16 | distance`. A token
// without it is a literal byte.
const match_flag = u32(0x8000_0000)

// end_of_block is the symbol that terminates a block.
const end_of_block = 256

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
	// tokens is the block being built.
	tokens []u32
}

// compress returns the DEFLATE stream for `input`.
pub fn compress(input []u8) []u8 {
	mut c := Compressor{}
	// The bit writer is initialised explicitly rather than left to the zero value of a
	// nested struct. A zeroed `BitWriter` is correct in principle, but `out` must be a
	// real empty slice with room to append; a nil slice that has never been allocated
	// makes the first `<<` write past the end of nothing, and the bits land in memory
	// the struct does not own.
	c.w = BitWriter{
		out:        []u8{cap: input.len / 2 + 64}
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
	c.tokens = []u32{cap: block_tokens}
	return c.run(input)
}

// run walks the input, collecting literals and matches, and writes a block each time
// one is full.
//
// The match choice is lazy, as zlib's: a match found at `pos` is held while `pos + 1`
// is searched too, and when the later one is longer the byte at `pos` goes out as a
// literal instead. One byte of delay routinely buys a longer match on binary data.
fn (mut c Compressor) run(input []u8) []u8 {
	n := input.len
	mut pos := 0
	// The match found at `pos - 1`, still waiting to be compared with the one at `pos`.
	mut prev_length := 0
	mut prev_distance := 0
	mut pending := false
	for pos < n {
		mut length := 0
		mut distance := 0
		if prev_length < max_lazy {
			length, distance = c.find_match(input, pos)
		}
		c.insert(input, pos)
		if pending && prev_length >= hash_min && length <= prev_length {
			// The held match wins. It started at `pos - 1`, both of which are already in
			// the hash chains; every later position it covers is registered now, or the
			// search would miss a match starting inside it.
			c.add_token(match_flag | (u32(prev_length) << 16) | u32(prev_distance), input, n,
				pos - 1 + prev_length)
			end := pos - 1 + prev_length
			for k in pos + 1 .. end {
				c.insert(input, k)
			}
			pos = end
			pending = false
			prev_length = 0
			continue
		}
		if pending {
			c.add_token(u32(input[pos - 1]), input, n, pos)
		}
		prev_length = length
		prev_distance = distance
		pending = true
		pos++
	}
	if pending {
		// Three bytes are needed for a match, so whatever is held at the last byte is
		// shorter than that: a literal.
		c.tokens << u32(input[n - 1])
	}
	if n == 0 || c.tokens.len > 0 {
		c.write_block(true)
	}
	c.w.flush()
	return c.w.out
}

// add_token appends one literal or match and writes the block when it is full.
// `next` is the position the input continues from, which decides whether the block
// just filled is the last one.
fn (mut c Compressor) add_token(token u32, input []u8, n int, next int) {
	c.tokens << token
	if c.tokens.len >= block_tokens && next < n {
		c.write_block(false)
	}
}

// write_block writes the collected tokens as one block, with whichever code is smaller.
//
// The dynamic code is fitted to this block's symbol counts and pays for its own
// description in the block header; the fixed code costs nothing to describe and fits
// nothing in particular. Both sizes are known exactly before a bit is written, so the
// choice is never a guess. An empty input still needs one block, carrying only the
// end-of-block symbol, and the fixed code is the smaller one for it.
fn (mut c Compressor) write_block(final bool) {
	mut lit_freq := []int{len: 286}
	mut dist_freq := []int{len: 30}
	for token in c.tokens {
		if token & match_flag != 0 {
			length := int((token >> 16) & 0x1FF)
			distance := int(token & 0xFFFF)
			lit_freq[length_symbol(length)]++
			dist_freq[distance_symbol(distance)]++
		} else {
			lit_freq[int(token)]++
		}
	}
	lit_freq[end_of_block]++
	// A code with a single symbol is legal only in a corner of the format that not every
	// decoder agrees on, so each alphabet is given at least two symbols. The extra one
	// is never emitted; it only completes the code.
	ensure_two(mut lit_freq)
	ensure_two(mut dist_freq)
	lit_len := huffman_lengths(lit_freq, 15)
	dist_len := huffman_lengths(dist_freq, 15)
	lit_code := canonical_codes(lit_len, 15)
	dist_code := canonical_codes(dist_len, 15)

	mut hlit := 286
	for hlit > 257 && lit_len[hlit - 1] == 0 {
		hlit--
	}
	mut hdist := 30
	for hdist > 1 && dist_len[hdist - 1] == 0 {
		hdist--
	}
	mut all_lens := []int{cap: hlit + hdist}
	all_lens << lit_len[..hlit]
	all_lens << dist_len[..hdist]
	rle := run_length(all_lens)
	mut cl_freq := []int{len: 19}
	for item in rle {
		cl_freq[item & 0xFF]++
	}
	ensure_two(mut cl_freq)
	cl_len := huffman_lengths(cl_freq, 7)
	cl_code := canonical_codes(cl_len, 7)
	mut hclen := 19
	for hclen > 4 && cl_len[code_length_order[hclen - 1]] == 0 {
		hclen--
	}

	// The two sizes, in bits, excluding the 3-bit block header both share.
	mut extra_bits := 0
	mut fixed_bits := literal_bits(end_of_block)
	mut dynamic_bits := 14 + 3 * hclen + lit_len[end_of_block]
	for item in rle {
		sym := item & 0xFF
		dynamic_bits += cl_len[sym] + code_length_extra(sym)
	}
	for sym in 0 .. 286 {
		if lit_freq[sym] == 0 || sym == end_of_block {
			continue
		}
		count := lit_freq[sym]
		// The symbols `ensure_two` added are counted once, which overstates both sizes
		// by the same few bits and so never changes the choice.
		fixed_bits += count * literal_bits(sym)
		dynamic_bits += count * lit_len[sym]
		if sym > end_of_block {
			extra_bits += count * length_extra[sym - 257]
		}
	}
	for sym in 0 .. 30 {
		count := dist_freq[sym]
		fixed_bits += count * distance_bits(sym)
		dynamic_bits += count * dist_len[sym]
		extra_bits += count * distance_extra[sym]
	}
	use_dynamic := dynamic_bits + extra_bits < fixed_bits + extra_bits

	c.w.write_bits(if final { u32(1) } else { u32(0) }, 1)
	if use_dynamic {
		c.w.write_bits(2, 2)
		c.w.write_bits(u32(hlit - 257), 5)
		c.w.write_bits(u32(hdist - 1), 5)
		c.w.write_bits(u32(hclen - 4), 4)
		for i in 0 .. hclen {
			c.w.write_bits(u32(cl_len[code_length_order[i]]), 3)
		}
		for item in rle {
			sym := item & 0xFF
			c.w.write_code(cl_code[sym], cl_len[sym])
			extra := code_length_extra(sym)
			if extra > 0 {
				c.w.write_bits(u32(item >> 8), extra)
			}
		}
		for token in c.tokens {
			c.write_token(token, lit_code, lit_len, dist_code, dist_len)
		}
		c.w.write_code(lit_code[end_of_block], lit_len[end_of_block])
	} else {
		c.w.write_bits(1, 2)
		for token in c.tokens {
			c.write_token_fixed(token)
		}
		c.w.write_code(literal_code(end_of_block), literal_bits(end_of_block))
	}
	c.tokens.clear()
}

// write_token writes one literal or match with a block's own code.
fn (mut c Compressor) write_token(token u32, lit_code []u32, lit_len []int, dist_code []u32,
	dist_len []int) {
	if token & match_flag == 0 {
		c.w.write_code(lit_code[int(token)], lit_len[int(token)])
		return
	}
	length := int((token >> 16) & 0x1FF)
	distance := int(token & 0xFFFF)
	sym := length_symbol(length)
	c.w.write_code(lit_code[sym], lit_len[sym])
	extra := length_extra[sym - 257]
	if extra > 0 {
		c.w.write_bits(u32(length - length_base[sym - 257]), extra)
	}
	dsym := distance_symbol(distance)
	c.w.write_code(dist_code[dsym], dist_len[dsym])
	dextra := distance_extra[dsym]
	if dextra > 0 {
		c.w.write_bits(u32(distance - distance_base[dsym]), dextra)
	}
}

// write_token_fixed writes one literal or match with the fixed code.
fn (mut c Compressor) write_token_fixed(token u32) {
	if token & match_flag == 0 {
		c.w.write_code(literal_code(int(token)), literal_bits(int(token)))
		return
	}
	length := int((token >> 16) & 0x1FF)
	distance := int(token & 0xFFFF)
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

// find_match returns the longest match for position `pos`, and its distance.
//
// A length of zero means no match worth emitting. Distance is one-based, as the
// format defines it, so a match right before `pos` has distance 1. `pos` itself must
// not be in the chains yet, or it would match itself.
fn (mut c Compressor) find_match(input []u8, pos int) (int, int) {
	if pos + hash_min > input.len {
		return 0, 0
	}
	mut best_length := 0
	mut best_distance := 0
	h := hash_of(input, pos)
	mut candidate := c.head[h]
	mut chain := max_chain
	mut limit := pos - window
	if limit < 0 {
		limit = 0
	}
	mut max_length := hash_max
	if input.len - pos < max_length {
		max_length = input.len - pos
	}
	for candidate >= 0 && chain > 0 {
		start := int(candidate)
		if start < limit {
			break
		}
		mut length := 0
		for length < max_length && input[start + length] == input[pos + length] {
			length++
		}
		if length > best_length {
			best_length = length
			best_distance = pos - start
			if best_length >= max_length {
				break
			}
		}
		candidate = c.prev[start]
		chain--
	}
	if best_length < hash_min {
		return 0, 0
	}
	return best_length, best_distance
}
