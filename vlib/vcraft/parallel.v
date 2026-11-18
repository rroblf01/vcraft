module vcraft

// Data parallelism for the hot loop of a function, the way rayon's `par_iter` is for
// PyO3: `par_range(n, body)` splits `0 .. n` into one contiguous chunk per core and runs
// `body(start, end)` for each on its own thread, returning when all are done.
//
//	@[vc_fn]
//	@[vc_nogil]
//	pub fn squares(xs []f64) []f64 {
//		mut out := []f64{len: xs.len}
//		vcraft.par_range(xs.len, fn [xs, mut out] (start int, end int) {
//			for i in start .. end {
//				out[i] = xs[i] * xs[i]
//			}
//		})
//		return out
//	}
//
// Each chunk writes its own part of a result allocated beforehand, so the threads share
// nothing they both write. The workers run V code only -- no Python object may be touched
// from them -- and a panic in one is raised again in the calling thread once all have
// finished, where the function's guard turns it into a RuntimeError as for any panic.
// The calling thread keeps the GIL unless the function is `@[vc_nogil]`, which lets other
// Python threads run meanwhile.
//
// `body` is released once every chunk has run (see `release_closure`): V keeps a closure
// and what it captured -- `xs` and `out` above -- alive until something frees it, so pass
// a closure literal and do not call it again afterwards.
//
// It is not generic -- V compiles a generic function called from another module without
// its declaration -- so the body is a closure over the slices it reads and writes.

import runtime

// par_range runs `body` over `0 .. n` in one chunk per core.
pub fn par_range(n int, body fn (start int, end int)) {
	par_range_with(n, 0, body)
}

// par_range_with is `par_range` with an explicit number of workers; 0 means one per core.
// A small `n` uses fewer threads, and a single worker runs on the calling thread.
pub fn par_range_with(n int, workers int, body fn (start int, end int)) {
	defer {
		release_closure(voidptr(body))
	}
	if n <= 0 {
		return
	}
	mut w := if workers > 0 { workers } else { runtime.nr_cpus() }
	if w > n {
		w = n
	}
	if w <= 1 {
		body(0, n)
		return
	}
	chunk := (n + w - 1) / w
	mut threads := []thread{cap: w}
	mut messages := []string{len: w}
	for i in 0 .. w {
		start := i * chunk
		end := if start + chunk < n { start + chunk } else { n }
		if start >= end {
			break
		}
		threads << spawn par_worker(body, start, end, unsafe { &messages[i] })
	}
	threads.wait()
	for message in messages {
		if message.len > 0 {
			panic(message)
		}
	}
}

// par_worker runs one chunk and records a panic instead of letting it end the process.
fn par_worker(body fn (start int, end int), start int, end int, slot &string) {
	defer {
		if message := recover() {
			unsafe {
				*slot = message.clone()
			}
		}
	}
	body(start, end)
}
