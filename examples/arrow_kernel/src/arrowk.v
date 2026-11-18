module arrowk

// Column kernels over the Arrow C Data Interface. A `vcraft.ArrowArray` parameter takes a
// pyarrow array, a polars Series or a pandas column backed by Arrow, and reads its
// buffers where they are; a `vcraft.ArrowOut` result goes back as a column pyarrow and
// polars adopt without copying. The extension depends on none of them.

import math
import vcraft

// zscore standardises a float64 column: (x - mean) / stddev, nulls skipped and kept null.
@[vc_fn]
pub fn zscore(col vcraft.ArrowArray) !vcraft.ArrowOut {
	xs := col.f64s()!
	mut n := 0
	mut sum := 0.0
	for i, x in xs {
		if !col.is_null(i) {
			sum += x
			n++
		}
	}
	if n == 0 {
		return vcraft.arrow_f64([]f64{len: xs.len, init: math.nan()})
	}
	mean := sum / n
	mut acc := 0.0
	for i, x in xs {
		if !col.is_null(i) {
			acc += (x - mean) * (x - mean)
		}
	}
	sd := math.sqrt(acc / n)
	mut out := []f64{len: xs.len}
	for i, x in xs {
		out[i] = if col.is_null(i) || sd == 0 { math.nan() } else { (x - mean) / sd }
	}
	return vcraft.arrow_f64(out)
}

// word_lengths is the length in characters of each string of a utf8 column.
@[vc_fn]
pub fn word_lengths(col vcraft.ArrowArray) !vcraft.ArrowOut {
	mut out := []i64{len: col.len}
	for i in 0 .. col.len {
		out[i] = if col.is_null(i) { 0 } else { i64(col.str_at(i)!.runes().len) }
	}
	return vcraft.arrow_i64(out)
}

// initials keeps the first character of each string.
@[vc_fn]
pub fn initials(col vcraft.ArrowArray) !vcraft.ArrowOut {
	mut out := []string{cap: col.len}
	for i in 0 .. col.len {
		s := col.str_at(i)!
		r := s.runes()
		out << if r.len > 0 { r[0].str() } else { '' }
	}
	return vcraft.arrow_strings(out)
}

// column makes a float64 Arrow column from a list, for tests and for callers without pyarrow.
@[vc_fn]
pub fn column(values []f64) vcraft.ArrowOut {
	return vcraft.arrow_f64(values)
}

// values reads a float64 Arrow column back into a list, nulls as NaN.
@[vc_fn]
pub fn values(col vcraft.ArrowArray) ![]f64 {
	xs := col.f64s()!
	mut out := []f64{len: xs.len}
	for i, x in xs {
		out[i] = if col.is_null(i) { math.nan() } else { x }
	}
	return out
}
