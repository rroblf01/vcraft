module vcraft_wheel

// The ZIP container, as far as a wheel needs it.
//
// A wheel is a ZIP with a particular layout, so this writes the container and nothing
// about wheels: local file headers, a central directory, and the record that ends it.
//
// Not implemented, because no wheel needs them: ZIP64, encryption, file comments and
// data descriptors. The archive is bounded by the 4 GiB and 65535-entry limits, which
// `to_bytes` checks rather than assumes.

// Entry is one file in the archive.
struct Entry {
mut:
	name   string
	data   []u8
	crc    u32
	method u16
	packed []u8
	offset u64
}

// Archive collects entries and writes them as a ZIP.
pub struct Archive {
mut:
	entries []Entry
}

// new_archive returns an empty archive.
pub fn new_archive() &Archive {
	return &Archive{}
}

// add_file adds a file, compressing it unless it is empty.
pub fn (mut a Archive) add_file(name string, data []u8) {
	mut e := Entry{
		name:   name
		data:   data
		crc:    crc32(data)
		method: 8
	}
	// An empty file is stored rather than deflated. Deflating nothing produces a valid
	// two-byte stream, which some readers report as a size mismatch against the
	// directory.
	if data.len == 0 {
		e.method = 0
	} else {
		e.packed = compress(data)
	}
	a.entries << e
}

// add_stored adds a file without compressing it.
pub fn (mut a Archive) add_stored(name string, data []u8) {
	a.entries << Entry{
		name:   name
		data:   data
		crc:    crc32(data)
		method: 0
	}
}

// to_bytes writes the whole archive.
pub fn (a &Archive) to_bytes() ![]u8 {
	if a.entries.len > 65535 {
		return error('too many entries: a wheel is limited to 65535')
	}
	mut out := []u8{}
	mut dir := []u8{}
	for e in a.entries {
		mut offset := u64(out.len)
		out = write_local(mut out, e)
		dir = write_central(mut dir, e, offset)
	}
	out = write_end(mut out, dir, a.entries.len)
	if out.len > 0xFFFF_FFFF {
		return error('archive too large: a non-ZIP64 wheel is limited to 4 GiB')
	}
	return out
}

// write_local writes a local file header and the entry's data.
//
// The sizes appear twice, here and in the central directory. Both are needed and the
// two must agree: a reader that trusts the local header should not have to seek to the
// directory to learn the entry is complete, and one that trusts the directory should
// find the same numbers.
fn write_local(mut out []u8, e Entry) []u8 {
	mut name := e.name.bytes()
	// Stored entries keep their bytes as they are; deflated entries use the
	// compressed form. Both sizes go into the header, so `csize` and `size` differ.
	mut body := unsafe { e.data.clone() }
	if e.method == 8 {
		body = e.packed
	}
	out = put_u32(mut out, 0x0403_4b50) // local file header signature
	out = put_u16(mut out, 20) // version needed to extract
	out = put_u16(mut out, 0x0800) // flags: the name is UTF-8
	out = put_u16(mut out, e.method)
	out = put_u16(mut out, 0) // modification time
	out = put_u16(mut out, 0x21) // modification date, 1980-01-01
	out = put_u32(mut out, e.crc)
	out = put_u32(mut out, u32(body.len))
	out = put_u32(mut out, u32(e.data.len))
	out = put_u16(mut out, u16(name.len))
	out = put_u16(mut out, 0) // extra field length
	out = put_bytes(mut out, name)
	out = put_bytes(mut out, body)
	return out
}

// write_central writes one central directory record.
fn write_central(mut dir []u8, e Entry, offset u64) []u8 {
	mut name := e.name.bytes()
	mut body_len := e.data.len
	if e.method == 8 {
		body_len = e.packed.len
	}
	dir = put_u32(mut dir, 0x0201_4b50) // central directory signature
	dir = put_u16(mut dir, 0x031E) // version made by: 3.0, unix
	dir = put_u16(mut dir, 20) // version needed to extract
	dir = put_u16(mut dir, 0x0800) // flags: the name is UTF-8
	dir = put_u16(mut dir, e.method)
	dir = put_u16(mut dir, 0) // modification time
	dir = put_u16(mut dir, 0x21) // modification date
	dir = put_u32(mut dir, e.crc)
	dir = put_u32(mut dir, u32(body_len))
	dir = put_u32(mut dir, u32(e.data.len))
	dir = put_u16(mut dir, u16(name.len))
	dir = put_u16(mut dir, 0) // extra field length
	dir = put_u16(mut dir, 0) // comment length
	dir = put_u16(mut dir, 0) // disk number start
	dir = put_u16(mut dir, 0) // internal attributes
	dir = put_u32(mut dir, 0o100644 << 16) // a regular file, mode 644
	dir = put_u32(mut dir, u32(offset))
	dir = put_bytes(mut dir, name)
	return dir
}

// write_end writes the end-of-central-directory record, completing the archive.
fn write_end(mut out []u8, dir []u8, count int) []u8 {
	mut start := u64(out.len)
	out = put_bytes(mut out, dir)
	out = put_u32(mut out, 0x0605_4b50) // end of central directory signature
	out = put_u16(mut out, 0) // this disk
	out = put_u16(mut out, 0) // disk holding the central directory
	out = put_u16(mut out, u16(count))
	out = put_u16(mut out, u16(count))
	out = put_u32(mut out, u32(dir.len))
	out = put_u32(mut out, u32(start))
	out = put_u16(mut out, 0) // comment length
	return out
}
