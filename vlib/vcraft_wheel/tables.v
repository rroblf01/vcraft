module vcraft_wheel

// The fixed tables of RFC 1951 section 3.2.6.

// literal_bits is the code length of each literal and length symbol in a fixed
// block: 8 bits for 0-143, 9 for 144-255, 7 for 256-279, 8 for 280-287.
fn literal_bits(symbol int) int {
	if symbol <= 143 {
		return 8
	}
	if symbol <= 255 {
		return 9
	}
	if symbol <= 279 {
		return 7
	}
	return 8
}

// literal_code returns the fixed Huffman code of a literal or length symbol.
//
// The fixed code is the code's own bits read as a number, so it comes straight out
// of the reversal: symbol 0 is 8 bits of 00110000, which is 0x30.
fn literal_code(symbol int) u32 {
	mut bits := literal_bits(symbol)
	mut value := u32(symbol)
	if symbol <= 143 {
		// 00110000 through 10111111.
		value = u32(0x30 + symbol)
		bits = 8
	} else if symbol <= 255 {
		// 110010000 through 111111111.
		value = u32(0x190 + symbol - 144)
		bits = 9
	} else if symbol <= 279 {
		// 0000000 through 0010111.
		value = u32(symbol - 256)
		bits = 7
	} else {
		// 11000000 through 11000111.
		value = u32(0xC0 + symbol - 280)
		bits = 8
	}
	// RFC 1951 section 3.2.6 gives these codes already in the order a decoder reads
	// them, and `write_code` emits the most significant bit of `code` first. So the
	// value is returned as it stands: reversing it here and letting `write_code`
	// reverse it again would undo the reversal and emit every code backwards, which
	// decodes to a different symbol rather than failing.
	_ = bits
	return value
}

// distance_bits is the code length of a distance symbol in a fixed block: 5 bits
// for every one of the 30 symbols.
fn distance_bits(symbol int) int {
	return 5
}

// distance_code returns the fixed Huffman code of a distance symbol.
//
// Distances are 5-bit codes in symbol order, so symbol 0 is 00000 and symbol 29 is
// 11101. As with literals, `write_code` reverses them, so the symbol is the code.
fn distance_code(symbol int) u32 {
	return u32(symbol)
}

// length_base is where each of the 29 length codes starts, and length_extra how many
// extra bits that code carries. Code 257 covers a length of 3 with no extra bits.
const length_base = [
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
	115, 131, 163, 195, 227, 258,
]

const length_extra = [
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
]

const distance_base = [
	1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
	1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

const distance_extra = [
	0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
	12, 13, 13,
]

// length_symbol returns the code for a match length of 3 to 258.
//
// The table is searched rather than computed: the ranges overlap irregularly, so
// the arithmetic that would avoid the search is the arithmetic most likely to be
// written wrong, and a wrong length code produces output that decodes to garbage
// rather than an error.
fn length_symbol(length int) int {
	// Walked downwards with an explicit decrement, because V rejects a descending
	// range literal at compile time for being always empty, and the code must be
	// tried from the longest length down: the first hit is the only one that fits.
	for i := 28; i >= 0; i-- {
		if length >= length_base[i] {
			return 257 + i
		}
	}
	return 257
}

// distance_symbol returns the code for a match distance of 1 to 32768.
fn distance_symbol(distance int) int {
	for i := 29; i >= 0; i-- {
		if distance >= distance_base[i] {
			return i
		}
	}
	return 0
}

// literal_code_of and literal_bits_of expose the tables for tests.
pub fn literal_code_of(symbol int) u32 {
	return literal_code(symbol)
}

pub fn literal_bits_of(symbol int) int {
	return literal_bits(symbol)
}
