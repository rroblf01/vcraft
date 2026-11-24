module fastc

// An extension that brings C of its own: `c/fastc.c` is compiled into the module with
// the generated glue, through the `#flag` below, and declared to V with `fn C.`. The
// same shape wraps an existing C library: its sources (or `-l` and `-I` flags) instead
// of this file. `vcraft sdist` ships everything under `c/`.

import vcraft

#flag -I @VMODROOT/c
#flag @VMODROOT/c/fastc.c
#include "fastc.h"

// C's `uint32_t`, `size_t` and `ptrdiff_t` are V's `u32`, `u64` and `i64`. V's `int`
// is 64 bits and C's 32: never declare a C `int` as V `int`.
fn C.fastc_fnv1a(data &u8, len u64) u32
fn C.fastc_rle(src &u8, len u64, dst &u8, dst_cap u64) i64

// fnv1a hashes bytes with the C function, reading Python's buffer in place.
@[vc_fn]
pub fn fnv1a(data []u8) u32 {
	return C.fastc_fnv1a(data.data, u64(data.len))
}

// rle run-length encodes bytes in C, as (count, byte) pairs.
@[vc_fn]
pub fn rle(data []u8) ![]u8 {
	mut out := []u8{len: data.len * 2}
	written := C.fastc_rle(data.data, u64(data.len), out.data, u64(out.len))
	if written < 0 {
		return vcraft.raise_domain(.runtime_error, 'rle: output buffer too small')
	}
	return out[..int(written)]
}

// unrle reverses `rle`, in V: the two languages share the module freely.
@[vc_fn]
pub fn unrle(data []u8) ![]u8 {
	if data.len % 2 != 0 {
		return vcraft.raise_domain(.value_error, 'rle data has an odd length')
	}
	mut out := []u8{}
	for i := 0; i < data.len; i += 2 {
		for _ in 0 .. int(data[i]) {
			out << data[i + 1]
		}
	}
	return out
}
