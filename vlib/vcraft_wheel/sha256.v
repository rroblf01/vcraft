module vcraft_wheel

// SHA-256, for the hashes `RECORD` carries.
//
// Every other wheel hash is optional, but this one is not: PEP 376 says a RECORD row
// holds `sha256=<digest>`, and pip verifies it on install. An installable wheel needs
// this to be right, so it is implemented rather than delegated.

// round_constants is the first 32 bits of the cube roots of the first 64 primes, as
// SHA-256 specifies. Written out because they are constants of the standard, not
// something to compute at run time.
const round_constants = [
	u32(0x428a2f98), u32(0x71374491), u32(0xb5c0fbcf), u32(0xe9b5dba5),
	u32(0x3956c25b), u32(0x59f111f1), u32(0x923f82a4), u32(0xab1c5ed5),
	u32(0xd807aa98), u32(0x12835b01), u32(0x243185be), u32(0x550c7dc3),
	u32(0x72be5d74), u32(0x80deb1fe), u32(0x9bdc06a7), u32(0xc19bf174),
	u32(0xe49b69c1), u32(0xefbe4786), u32(0x0fc19dc6), u32(0x240ca1cc),
	u32(0x2de92c6f), u32(0x4a7484aa), u32(0x5cb0a9dc), u32(0x76f988da),
	u32(0x983e5152), u32(0xa831c66d), u32(0xb00327c8), u32(0xbf597fc7),
	u32(0xc6e00bf3), u32(0xd5a79147), u32(0x06ca6351), u32(0x14292967),
	u32(0x27b70a85), u32(0x2e1b2138), u32(0x4d2c6dfc), u32(0x53380d13),
	u32(0x650a7354), u32(0x766a0abb), u32(0x81c2c92e), u32(0x92722c85),
	u32(0xa2bfe8a1), u32(0xa81a664b), u32(0xc24b8b70), u32(0xc76c51a3),
	u32(0xd192e819), u32(0xd6990624), u32(0xf40e3585), u32(0x106aa070),
	u32(0x19a4c116), u32(0x1e376c08), u32(0x2748774c), u32(0x34b0bcb5),
	u32(0x391c0cb3), u32(0x4ed8aa4a), u32(0x5b9cca4f), u32(0x682e6ff3),
	u32(0x748f82ee), u32(0x78a5636f), u32(0x84c87814), u32(0x8cc70208),
	u32(0x90befffa), u32(0xa4506ceb), u32(0xbef9a3f7), u32(0xc67178f2),
]

const initial_state = [
	u32(0x6a09e667), u32(0xbb67ae85), u32(0x3c6ef372), u32(0xa54ff53a),
	u32(0x510e527f), u32(0x9b05688c), u32(0x1f83d9ab), u32(0x5be0cd19),
]

// sha256 returns the hex digest of `data`.
pub fn sha256(data []u8) string {
	mut h := initial_state.clone()
	mut padded := data.clone()
	// The length in bits, as a 64-bit big-endian count of the original message.
	mut bit_len := u64(data.len) * 8
	padded << u8(0x80)
	// Padding is added by appending, so the loop condition is checked each pass.
	for padded.len % 64 != 56 {
		padded << u8(0)
	}
	for i := 0; i < 8; i++ {
		padded << u8(u8((bit_len >> u32(56 - 8 * i)) & 0xFF))
	}

	mut w := [64]u32{}
	// Walked 64 bytes at a time by index rather than with `chunks`, which V does not
	// have on a byte slice.
	mut base := 0
	for base < padded.len {
		for i := 0; i < 16; i++ {
			mut v := u32(0)
			for j := 0; j < 4; j++ {
				v = (v << 8) | u32(padded[base + i * 4 + j])
			}
			w[i] = v
		}
		for i := 16; i < 64; i++ {
			s0 := rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
			s1 := rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
			w[i] = w[i - 16] + s0 + w[i - 7] + s1
		}
		mut v := h.clone()
		for i := 0; i < 64; i++ {
			s1 := rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
			ch := (v[4] & v[5]) ^ ((~v[4]) & v[6])
			temp1 := v[7] + s1 + ch + round_constants[i] + w[i]
			s0 := rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
			maj := (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
			temp2 := s0 + maj
			v[7] = v[6]
			v[6] = v[5]
			v[5] = v[4]
			v[4] = v[3] + temp1
			v[3] = v[2]
			v[2] = v[1]
			v[1] = v[0]
			v[0] = temp1 + temp2
		}
		for i := 0; i < 8; i++ {
			h[i] += v[i]
		}
		base += 64
	}
	mut out := []u8{}
	for word in h {
		for j := 3; j >= 0; j-- {
			out << u8((word >> u32(j * 8)) & 0xFF)
		}
	}
	return out.hex()
}

// sha256_record returns the digest in the form PEP 376 wants: base64, URL-safe
// alphabet, no padding.
//
// Hex would be simpler and is wrong. PEP 376 specifies `urlsafe_b64encode` without the
// trailing `=`, and pip compares the string, so a hex digest makes every install fail
// verification.
pub fn sha256_record(data []u8) string {
	return hex_to_record_base64(sha256_bytes(data))
}

// sha256_bytes returns the raw 32-byte digest.
pub fn sha256_bytes(data []u8) []u8 {
	return hex_to_bytes(sha256(data))
}

fn hex_to_bytes(hex_text string) []u8 {
	mut out := []u8{len: hex_text.len / 2}
	for i := 0; i < out.len; i++ {
		out[i] = u8(u8(hex_value(hex_text[i * 2])) << 4 | u8(hex_value(hex_text[i * 2 + 1])))
	}
	return out
}

fn hex_value(ch u8) int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	return 0
}

// rotr rotates a 32-bit word right.
fn rotr(x u32, n int) u32 {
	return (x >> u32(n)) | (x << u32(32 - n))
}

// The base64 alphabet of RFC 4648 section 5, with `-` and `_` in place of `+` and `/`.
const b64_alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'

// hex_to_record_base64 encodes the digest with the URL-safe alphabet and no padding.
//
// A 32-byte digest is 256 bits: 42 whole groups of 6 and one group of 4, so the
// encoded length is 43 characters. The last group is written from its top 4 bits,
// shifted left by 2 to fill a 6-bit character, and the two padding bits are dropped
// rather than written as `=`.
fn hex_to_record_base64(data []u8) string {
	mut bits := []u8{}
	for byte in data {
		for i := 7; i >= 0; i-- {
			bits << u8((byte >> u32(i)) & 1)
		}
	}
	mut out := []u8{}
	mut alphabet := b64_alphabet.bytes()
	mut i := 0
	for i < bits.len {
		// Bits past the end of the input read as zero, which is what the padding
		// 'does: a 32-byte digest is 256 bits, leaving a last group of 4 that is shifted
		// up into a 6-bit character with two zero bits at the bottom.
		mut acc := u32(0)
		for j := 0; j < 6; j++ {
			acc <<= 1
			if i + j < bits.len {
				acc |= u32(bits[i + j])
			}
		}
		out << alphabet[acc & 63]
		i += 6
	}
	return out.bytestr()
}
