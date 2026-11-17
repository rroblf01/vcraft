module ndkernel

// Numeric kernels over N-dimensional buffers. A `vcraft.NdArray` parameter takes a NumPy
// array, an `array.array` or a `memoryview` without copying it, and a `vcraft.NdOut`
// result reaches Python as a memoryview that `numpy.asarray` wraps without a copy. The
// extension never imports NumPy, so it builds and runs without it.

import math
import vcraft

// moving_average averages each run of `window` consecutive samples of a 1-D float64
// array: `len(a) - window + 1` values, in one pass with a running sum.
@[vc_fn]
pub fn moving_average(a vcraft.NdArray, window int) !vcraft.NdOut {
	if a.shape.len != 1 {
		return vcraft.raise_domain(.value_error, 'expected a 1-D array, got ${a.shape.len} dimensions')
	}
	n := a.shape[0]
	if window < 1 || window > n {
		return vcraft.raise_domain(.value_error, 'window must be between 1 and ${n}')
	}
	src := a.f64s()!
	out := vcraft.nd_out_f64([n - window + 1])
	mut dst := out.f64s()
	mut sum := 0.0
	for i in 0 .. window {
		sum += src[i]
	}
	dst[0] = sum / window
	for i in window .. n {
		sum += src[i] - src[i - window]
		dst[i - window + 1] = sum / window
	}
	return out
}

// matmul multiplies two 2-D float64 arrays. It reads through the strides, so a
// transposed or sliced NumPy view is used as it is, without a contiguous copy.
@[vc_fn]
pub fn matmul(a vcraft.NdArray, b vcraft.NdArray) !vcraft.NdOut {
	if a.shape.len != 2 || b.shape.len != 2 {
		return vcraft.raise_domain(.value_error, 'matmul takes two 2-D arrays')
	}
	if a.kind != `d` || b.kind != `d` {
		return vcraft.raise_domain(.type_error, 'matmul takes float64 arrays')
	}
	n, inner, m := a.shape[0], a.shape[1], b.shape[1]
	if b.shape[0] != inner {
		return vcraft.raise_domain(.value_error, 'shapes (${n}, ${inner}) and (${b.shape[0]}, ${m}) do not align')
	}
	out := vcraft.nd_out_f64([n, m])
	mut dst := out.f64s()
	for i in 0 .. n {
		for k in 0 .. inner {
			aik := a.at_f64(i, k)
			for j in 0 .. m {
				dst[i * m + j] += aik * b.at_f64(k, j)
			}
		}
	}
	return out
}

// normalize scales a float64 array in place so its values have mean 0 and standard
// deviation 1, and returns the mean and the deviation it removed. The array is written
// through the buffer, so the caller's own NumPy array changes.
@[vc_fn]
pub fn normalize(a vcraft.NdArray) !(f64, f64) {
	if a.readonly {
		return vcraft.raise_domain(.value_error, 'the array is read-only')
	}
	mut data := a.f64s()!
	if data.len == 0 {
		return vcraft.raise_domain(.value_error, 'the array is empty')
	}
	mut mean := 0.0
	for x in data {
		mean += x
	}
	mean /= data.len
	mut variance := 0.0
	for x in data {
		variance += (x - mean) * (x - mean)
	}
	std := math.sqrt(variance / data.len)
	scale := if std == 0 { 1.0 } else { std }
	for i in 0 .. data.len {
		data[i] = (data[i] - mean) / scale
	}
	return mean, std
}
