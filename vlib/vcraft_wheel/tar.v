module vcraft_wheel

// A tar writer, enough for a source distribution.
//
// An sdist is a gzipped tar, not a ZIP, and that is not a formality: `pip install
// <sdist>` unpacks it with tarfile and reads `PKG-INFO` from the top level. A ZIP with
// the right bytes inside installs on some versions and fails on others with an error
// that does not mention the format.
//
// Only the ustar subset is written, with the fields every reader needs and none of the
// extensions. GNU and pax headers exist to carry things a V project does not have:
// long names past 100 bytes, nanosecond timestamps, and checksums for sparse files.

// Tar is an archive being written.
pub struct Tar {
mut:
	out []u8
}

// new_tar returns an empty archive.
pub fn new_tar() &Tar {
	return &Tar{}
}

// tar_block is 512 bytes, the unit everything in the format is measured in.
const tar_block = 512

// tar_header builds one 512-byte header.
//
// The fields are octal ASCII, NUL-padded, and every numeric field is written with a
// trailing space and NUL rather than a bare NUL: some readers stop at the first NUL and
// read an empty field, which they then take as zero.
fn tar_header(name string, size int, mode string, is_dir bool) [tar_block]u8 {
	mut h := [tar_block]u8{}
	// The ustar field offsets. Every one is load-bearing, and a field written one
	// position late does not fail: it lands in the next field, and `tar` then reads a
	// directory's uid as its mode and its size as its modification time. The archive
	// still has the right length and still unpacks, because the only check the reader
	// makes before trusting a header is that the checksum adds up.
	copy_raw(mut h, 0, name, 100) // name
	copy_raw(mut h, 100, mode, 8) // mode
	copy_raw(mut h, 108, '0000000', 8) // uid
	copy_raw(mut h, 116, '0000000', 8) // gid
	copy_raw(mut h, 124, octal(u32(size), 12), 12) // size
	// A fixed timestamp keeps the archive reproducible: the same sources produce the
	// same bytes, so a rebuild that changed nothing shows as no diff at all. The value
	// is 2024-01-01T00:00:00Z in octal.
	copy_raw(mut h, 136, '1704067200', 12) // mtime
	// The checksum is six octal digits, a NUL and a space. While it is being computed
	// the field reads as eight spaces, because it covers itself and cannot contain its
	// own value.
	for i in 148 .. 156 {
		h[i] = ` `
	}
	// The type flag. It is the difference between a directory and a file, and a
	// directory written as a file extracts to a zero-byte file with the same name: the
	// archive has the right length, `tar` lists every entry, and only the frontend
	// notices when it tries to create `pep517demo-0.1.0/src/` and finds a file in the
	// way. Python reports it as "Not a directory: .../pep517demo-0.1.0".
	h[156] = if is_dir { `5` } else { `0` }
	// "ustar" at 257 and the version "00" at 263. A reader that does not find them
	// falls back to its own default, and GNU tar and BSD tar have different ones.
	copy_raw(mut h, 257, 'ustar', 8)
	copy_raw(mut h, 265, 'vcraft', 32) // uname
	copy_raw(mut h, 297, 'vcraft', 32) // gname
	mut sum := u32(0)
	for byte in h {
		sum += u32(byte)
	}
	copy_raw(mut h, 148, octal(sum, 6), 8)
	h[154] = ` `
	return h
}

// octal renders a number as zero-padded octal, which is how tar writes every numeric
// field.
fn octal(value u32, width int) string {
	mut digits := []u8{}
	mut n := value
	for n > 0 {
		digits.prepend(u8(`0` + int(n % 8)))
		n /= 8
	}
	mut out := []u8{}
	for _ in digits.len .. width {
		out << `0`
	}
	for d in digits {
		out << d
	}
	return out.bytestr()
}

// copy_field writes text into `h` at `offset`, NUL-padded to `width`.
fn copy_field(mut h [tar_block]u8, offset int, text string, width int) {
	copy_raw(mut h, offset, text, width)
}

// copy_raw writes `text` into `h` at `offset`, zero-padded to `width`.
fn copy_raw(mut h [tar_block]u8, offset int, text string, width int) {
	for i in 0 .. width {
		if i < text.len {
			h[offset + i] = text[i]
		} else {
			h[offset + i] = 0
		}
	}
}

// add_file appends one regular file.
//
// A name longer than 100 bytes cannot be represented in the ustar header without the
// GNU long-name extension, so it is refused rather than truncated: a truncated name
// unpacks to a file nobody asked for, and the error surfaces as a missing module much
// later.
pub fn (mut t Tar) add_file(name string, data []u8) ! {
	if name.len > 100 {
		return error('${name}: a tar member name is limited to 100 bytes without the GNU extension')
	}
	h := tar_header(name, data.len, '0000644', false)
	// Appended through `put_bytes` rather than with `t.out << h[:]`: a fixed-size array
	// is not a slice in V, and `<<` on one does not append the header at all. The result
	// is an archive that begins with the file's own contents, which tar rejects as
	// neither a header nor garbage it can skip.
	//
	// The padding is computed from the member's own length, not from the archive's. A
	// member is `header + data` rounded up to 512, and padding from the running total
	// instead puts the next header at the wrong offset: the archive is the right length
	// and every field after the first short file is read as a header, so `tar` lists
	// the file's contents as further members.
	mut member := []u8{}
	member = put_bytes(mut member, h[..])
	member = put_bytes(mut member, data)
	t.out = put_bytes(mut t.out, pad(mut member))
	return
}

// pad rounds a member up to a whole number of blocks.
//
// A tar reader computes the next member's offset as `size` rounded up to 512, so the
// padding is part of the format rather than alignment. A member whose length is already
// a multiple gets no padding at all: a whole empty block would be read as the end of
// the archive.
fn pad(mut member []u8) []u8 {
	mut remainder := member.len % tar_block
	if remainder == 0 {
		return member
	}
	mut n := remainder
	for n < tar_block {
		member << u8(0)
		n++
	}
	return member
}

// add_directory appends one directory entry.
//
// Not strictly needed: a reader creates the parent directories of a file it finds. It
// is written anyway because a tarball with no directory entries has a flat listing that
// is harder to read, and because the paths in it are the ones a person would expect.
pub fn (mut t Tar) add_directory(name string) {
	mut path := name
	if !path.ends_with('/') {
		path += '/'
	}
	h := tar_header(path, 0, '0000755', true)
	t.out = put_bytes(mut t.out, h[..])
}

// finish appends the two zero blocks that mark the end of the archive.
//
// A tar with no terminator is not an error to read; `tarfile` warns and recovers. Two
// blocks, not one, because that is what the format specifies and what every writer has
// always emitted.
pub fn (t &Tar) finish() []u8 {
	// Cloned rather than appended to through the field, because V makes a struct field
	// read-only through the variable that holds it.
	mut out := t.out.clone()
	mut n := 0
	for n < tar_block * 2 {
		out << u8(0)
		n++
	}
	return out
}

// bytes returns the finished archive.
pub fn (t &Tar) bytes() []u8 {
	return t.finish()
}

// Gzip, because a `.tar.gz` is what an sdist is called and what pip looks for.
//
// A tar of a V project's sources compresses about 4x, and the format is small: a
// 10-byte header, a deflate stream, and an 8-byte trailer. Storing the tar
// uncompressed under a `.tar.gz` name would satisfy a filename check and fail the first
// real read, which is worse than either honest option.

// crc_table is built once, on the first call.
__global (
	gzip_crc = []u32{}
	gzip_crc_ready = false
)

fn ensure_gzip_crc() {
	if gzip_crc_ready {
		return
	}
	gzip_crc = []u32{len: 256}
	for n in 0 .. 256 {
		mut c := u32(n)
		for _ in 0 .. 8 {
			if c & 1 != 0 {
				c = 0xEDB8_8320 ^ (c >> 1)
			} else {
				c = c >> 1
			}
		}
		gzip_crc[n] = c
	}
	gzip_crc_ready = true
}

// gzip_crc32 returns the CRC-32 gzip stores in its trailer.
fn gzip_crc32(data []u8) u32 {
	ensure_gzip_crc()
	mut c := u32(0xFFFF_FFFF)
	for byte in data {
		c = gzip_crc[(c ^ u32(byte)) & 0xFF] ^ (c >> 8)
	}
	return c ^ 0xFFFF_FFFF
}

// gzip wraps `data` in a gzip container holding one deflate stream.
//
// The header carries no name and no timestamp. Both are optional and both would make
// the output differ between two builds of identical sources, which turns a reproducible
// build into one whose artefact always has a diff.
pub fn gzip(data []u8) []u8 {
	mut out := []u8{}
	// The magic, the deflate method, no flags, no mtime, no extra flags, unknown OS.
	out = put_u8(mut out, 0x1f)
	out = put_u8(mut out, 0x8b)
	out = put_u8(mut out, 8)
	out = put_u8(mut out, 0)
	for _ in 0 .. 4 {
		out = put_u8(mut out, 0)
	}
	out = put_u8(mut out, 0)
	out = put_u8(mut out, 255)

	// A raw deflate stream and nothing around it. The two-byte zlib header and the
	// four-byte Adler-32 trailer belong to the `.zlib` format, not to gzip: gzip's own
	// header is the ten bytes above and its own trailer is the eight below. Putting the
	// zlib pair inside gzip produces a file every decoder rejects with "invalid
	// compressed data -- format violated", which says nothing about the extra wrapper.
	out = put_bytes(mut out, compress(data))

	// The trailer: the CRC of the *uncompressed* bytes and the length modulo 2^32.
	out = put_u32(mut out, gzip_crc32(data))
	out = put_u32(mut out, u32(data.len))
	return out
}
