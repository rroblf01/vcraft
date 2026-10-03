module vcraft_wheel

// DEFLATE decompression, the inverse of what `fixed.v` writes.
//
// Needed because `vcraft develop` reads back a wheel it has just built in order to
// install it, and because a wheel reader has to be able to check what it wrote. A
// general inflater is more than that requires: this reads stored blocks, fixed
// Huffman blocks and dynamic Huffman blocks, because those are the three a ZIP can
// hold, and it rejects the fourth thing a ZIP can hold, which is a block type that does
// not exist.

// Inflater decodes one DEFLATE stream.
struct Inflater {
mut:
	data []u8
	// pos is the next byte to read.
	pos int
	// bit is the bit position within the current byte, 0 to 7.
	bit int
	out []u8
}

// inflate returns the bytes a raw DEFLATE stream decodes to.
pub fn inflate(data []u8) ![]u8 {
	mut f := Inflater{
		data: data
	}
	for {
		bfinal := f.read_bits(1)!
		btype := f.read_bits(2)!
		match btype {
			0 { f.read_stored() or { return err } }
			1 { f.read_fixed() or { return err } }
			2 { f.read_dynamic() or { return err } }
			else { return error('DEFLATE block type 3 does not exist') }
		}
		if bfinal == 1 {
			break
		}
	}
	return f.out
}

// read_bits returns `count` bits, least significant first.
fn (mut f Inflater) read_bits(count int) !u32 {
	mut value := u32(0)
	for i := 0; i < count; i++ {
		if f.pos >= f.data.len {
			return error('DEFLATE stream ended mid-symbol')
		}
		bit := (f.data[f.pos] >> u32(f.bit)) & 1
		value |= u32(bit) << u32(i)
		f.bit++
		if f.bit == 8 {
			f.bit = 0
			f.pos++
		}
	}
	return value
}

// read_stored reads an uncompressed block.
fn (mut f Inflater) read_stored() ! {
	// A stored block starts on a byte boundary, so the partial byte is dropped first.
	if f.bit != 0 {
		f.bit = 0
		f.pos++
	}
	if f.pos + 4 > f.data.len {
		return error('a stored block header is truncated')
	}
	length := int(f.data[f.pos]) | (int(f.data[f.pos + 1]) << 8)
	f.pos += 4 // LEN and its complement, which is not checked
	if f.pos + length > f.data.len {
		return error('a stored block body is truncated')
	}
	for i in 0 .. length {
		f.out << f.data[f.pos + i]
	}
	f.pos += length
	return
}

// Huffman is a canonical Huffman decoder.
//
// Built from a list of code lengths, in the way RFC 1951 section 3.2.2 describes:
// lengths are counted, the first code of each length is computed, and decoding walks
// one bit at a time comparing against the smallest code of the current length.
struct Huffman {
mut:
	// counts[i] is how many codes have length i.
	counts []int
	// symbols is the symbols ordered by code.
	symbols []int
}

// build_huffman returns a decoder for `lengths`, or an error for an over-subscribed set.
//
// The over-subscribed check matters: a corrupt header can describe more codes than a
// length can hold, and a decoder that does not check produces symbols rather than an
// error, which shows up much later as wrong output.
fn build_huffman(lengths []int) !Huffman {
	mut counts := []int{len: 16}
	for l in lengths {
		counts[l]++
	}
	counts[0] = 0
	mut left := 1
	for l in 1 .. 16 {
		left <<= 1
		left -= counts[l]
		if left < 0 {
			return error('over-subscribed Huffman code')
		}
	}
	mut offsets := []int{len: 16}
	for l in 1 .. 15 {
		offsets[l + 1] = offsets[l] + counts[l]
	}
	mut symbols := []int{len: lengths.len}
	for sym, l in lengths {
		if l != 0 {
			symbols[offsets[l]] = sym
			offsets[l]++
		}
	}
	return Huffman{
		counts:  counts
		symbols: symbols
	}
}

// decode reads one symbol.
fn (mut f Inflater) decode(h Huffman) !int {
	mut code := 0
	mut first := 0
	mut index := 0
	for length in 1 .. 16 {
		code |= int(f.read_bits(1)!)
		count := h.counts[length]
		if code - count < first {
			return h.symbols[index + (code - first)]
		}
		index += count
		first += count
		first <<= 1
		code <<= 1
	}
	return error('no Huffman code matched')
}

// read_fixed reads a block using the fixed tables.
fn (mut f Inflater) read_fixed() ! {
	mut lengths := []int{len: 288}
	for i in 0 .. 288 {
		if i < 144 {
			lengths[i] = 8
		} else if i < 256 {
			lengths[i] = 9
		} else if i < 280 {
			lengths[i] = 7
		} else {
			lengths[i] = 8
		}
	}
	literals := build_huffman(lengths) or { return err }
	mut distances := []int{len: 30, init: 5}
	distance_table := build_huffman(distances) or { return err }
	return f.read_block(literals, distance_table)
}

// read_dynamic reads a block whose tables are in the block header.
fn (mut f Inflater) read_dynamic() ! {
	hlit := int(f.read_bits(5) or { return err }) + 257
	hdist := int(f.read_bits(5) or { return err }) + 1
	hclen := int(f.read_bits(4) or { return err }) + 4
	// The order the code lengths for the code lengths appear in.
	order := [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
	mut code_lengths := []int{len: 19}
	for i in 0 .. hclen {
		code_lengths[order[i]] = int(f.read_bits(3)!)
	}
	code_table := build_huffman(code_lengths) or { return err }
	mut lengths := []int{len: hlit + hdist}
	mut i := 0
	for i < lengths.len {
		sym := f.decode(code_table) or { return err }
		if sym < 16 {
			lengths[i] = sym
			i++
			continue
		}
		mut repeat := 0
		mut value := 0
		if sym == 16 {
			if i == 0 {
				return error('a code length repeat with nothing to repeat')
			}
			value = lengths[i - 1]
			repeat = 3 + int(f.read_bits(2)!)
		} else if sym == 17 {
			repeat = 3 + int(f.read_bits(3)!)
		} else {
			repeat = 11 + int(f.read_bits(7)!)
		}
		for i < lengths.len && repeat > 0 {
			lengths[i] = value
			i++
			repeat--
		}
	}
	literals := build_huffman(lengths[..hlit]) or { return err }
	distance_table := build_huffman(lengths[hlit..]) or { return err }
	return f.read_block(literals, distance_table)
}

// read_block reads literals and matches until the end-of-block symbol.
fn (mut f Inflater) read_block(literals Huffman, distances Huffman) ! {
	for {
		sym := f.decode(literals) or { return err }
		if sym == 256 {
			return
		}
		if sym < 256 {
			f.out << u8(sym)
			continue
		}
		// A length symbol above 256 indexes the length tables.
		index := sym - 257
		if index >= length_base.len {
			return error('length symbol ${sym} is out of range')
		}
		length := length_base[index] + int(f.read_bits(length_extra[index])!)
		dsym := f.decode(distances) or { return err }
		if dsym >= distance_base.len {
			return error('distance symbol ${dsym} is out of range')
		}
		distance := distance_base[dsym] + int(f.read_bits(distance_extra[dsym])!)
		if distance > f.out.len {
			return error('a match reaches before the start of the output')
		}
		// Copied one byte at a time, because a match may overlap the bytes it is
		// producing: that overlap is how DEFLATE encodes a run, and a block copy would
		// truncate it.
		mut from := f.out.len - distance
		for i in 0 .. length {
			f.out << f.out[from + i]
		}
	}
}
