module vcraft_wheel

// CRC-32 as ZIP uses it.
//
// Every ZIP entry carries one of these over its uncompressed bytes. It is the
// same polynomial as the Ethernet FCS and PNG chunk CRC, reflected, with the
// standard 0xEDB88320 table and an initial and final value of 0xFFFFFFFF.
//
// The table is built on first use rather than written out as 256 literals. It is
// 1 KiB of source for a value derivable in four lines, and a table transcribed by
// hand is a table that eventually has a typo in it.

// crc32_table is built once, on the first call.
__global (
	crc32_table = []u32{}
	crc32_table_ready = false
)

fn ensure_crc32_table() {
	if crc32_table_ready {
		return
	}
	crc32_table = []u32{len: 256}
	for n in 0 .. 256 {
		mut c := u32(n)
		for _ in 0 .. 8 {
			if c & 1 != 0 {
				c = 0xEDB8_8320 ^ (c >> 1)
			} else {
				c = c >> 1
			}
		}
		crc32_table[n] = c
	}
	crc32_table_ready = true
}

// crc32 returns the ZIP CRC-32 of `data`, which is the value a ZIP entry stores.
//
// The seed and final inversion are what make this the same function the one in
// zlib, so a wheel written here verifies against `zipfile` and `unzip`.
pub fn crc32(data []u8) u32 {
	ensure_crc32_table()
	mut c := u32(0xFFFF_FFFF)
	for byte in data {
		c = crc32_table[(c ^ u32(byte)) & 0xFF] ^ (c >> 8)
	}
	return c ^ 0xFFFF_FFFF
}
