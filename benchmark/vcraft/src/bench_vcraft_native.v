module bench_vcraft_native

import math.complex
import vcraft

// The same workloads as the PyO3 and zig-maturin projects, with the same semantics and
// 64-bit integers throughout.

// add is call overhead: two ints in, one int out.
@[vc_fn]
pub fn add(a i64, b i64) i64 {
	return a + b
}

// fib is pure compute: naive recursion.
@[vc_fn]
pub fn fib(n i64) i64 {
	if n < 2 {
		return n
	}
	return fib(n - 1) + fib(n - 2)
}

// count_primes is compute plus a native heap allocation of n + 1 bytes.
@[vc_fn]
pub fn count_primes(n i64) i64 {
	if n < 2 {
		return 0
	}
	size := int(n + 1)
	mut composite := []bool{len: size}
	mut count := i64(0)
	for i in 2 .. size {
		if !composite[i] {
			count++
			mut j := i * i
			for j < size {
				composite[j] = true
				j += i
			}
		}
	}
	return count
}

// sum_squares is pure compute that releases the GIL, for thread scaling.
@[vc_fn]
@[vc_nogil]
pub fn sum_squares(n i64) i64 {
	mut total := i64(0)
	for i in i64(1) .. n + 1 {
		total += i * i
	}
	return total
}

// lcg is a serial integer loop with the GIL released: a dependency between
// iterations, so no compiler turns it into a vector or a closed form, and no
// allocation, so the work is identical in every backend.
@[vc_fn]
@[vc_nogil]
pub fn lcg(n i64) i64 {
	mut x := i64(12345)
	for _ in i64(1) .. n + 1 {
		x = (x * 1103515245 + 12345) & 0x7fffffff
	}
	return x
}

// sum_floats converts a Python list of floats into a native slice.
@[vc_fn]
pub fn sum_floats(xs []f64) f64 {
	mut total := 0.0
	for x in xs {
		total += x
	}
	return total
}

// make_range returns a native sequence as a Python list of ints.
@[vc_fn]
pub fn make_range(n i64) []i64 {
	mut out := []i64{cap: int(n)}
	for i in i64(0) .. n {
		out << i
	}
	return out
}

// greet takes a str and returns a freshly allocated str.
@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}

// describe formats a count with a step and a label, both defaulted and all four
// addressable by name: keyword arguments and defaults in one call.
@[vc_fn]
@[vc_defaults: 'step=1, label="item"']
pub fn describe(count int, step int, label string, unit ?string) string {
	suffix := unit or { '' }
	return '${label}: ${count * step}${suffix}'
}

// maybe_double doubles a value or returns none: an optional parameter and result.
@[vc_fn]
pub fn maybe_double(x ?int) ?int {
	if v := x {
		return v * 2
	}
	return none
}

// histogram counts how often each word appears: a map result.
@[vc_fn]
pub fn histogram(words []string) map[string]int {
	mut counts := map[string]int{}
	for word in words {
		counts[word]++
	}
	return counts
}

// minmax returns the smallest and largest value: a multi-value (tuple) result.
@[vc_fn]
pub fn minmax(xs []int) !(int, int) {
	if xs.len == 0 {
		return vcraft.raise_domain(.value_error, 'minmax() arg is an empty sequence')
	}
	mut lo := xs[0]
	mut hi := xs[0]
	for x in xs {
		if x < lo {
			lo = x
		}
		if x > hi {
			hi = x
		}
	}
	return lo, hi
}

// reverse3 reverses three values: a fixed-size array in and out.
@[vc_fn]
pub fn reverse3(a [3]int) [3]int {
	return [a[2], a[1], a[0]]!
}

// checksum sums bytes without copying them: the `[]u8` parameter aliases any
// bytes-like object through the buffer protocol.
@[vc_fn]
pub fn checksum(data []u8) u64 {
	return vcraft.checksum_bytes(data)
}

// expect_positive is the error path: a bad value raises ValueError.
@[vc_fn]
pub fn expect_positive(n i64) !i64 {
	if n < 0 {
		return vcraft.raise_domain(.value_error, 'expect_positive() expected n >= 0')
	}
	return n
}

// join_strings converts a list of str and returns a new str.
@[vc_fn]
pub fn join_strings(parts []string) string {
	return parts.join(',')
}

// echo_bytes takes bytes without copying and returns a fresh copy.
@[vc_fn]
pub fn echo_bytes(data []u8) []u8 {
	return data
}

// Counter measures method-call overhead on a native object.
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value i64
}

// new_counter is the constructor.
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{}
}

// increment adds one and returns the new value.
@[vc_method]
pub fn (mut c Counter) increment() i64 {
	c.value++
	return c.value
}

// add adds n and returns the new value.
@[vc_method]
pub fn (mut c Counter) add(n i64) i64 {
	c.value += n
	return c.value
}

// is_zero reports whether the value is still zero: a read-only property.
@[vc_method]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}

// counter_eq gives the class value equality.
@[vc_eq]
pub fn counter_eq(a voidptr, b voidptr) bool {
	mut x := Counter{}
	mut y := Counter{}
	vcraft.load_state(a, voidptr(&x), sizeof(Counter))
	vcraft.load_state(b, voidptr(&y), sizeof(Counter))
	return x.value == y.value
}

// counter_hash hashes the value, so equal counters collapse in a set or dict key.
@[vc_hash]
pub fn counter_hash(self voidptr) int {
	mut c := Counter{}
	vcraft.load_state(self, voidptr(&c), sizeof(Counter))
	return int(c.value)
}

// Countdown is its own iterator: it yields start, start-1, ... 1.
@[vc_class]
pub struct Countdown {
mut:
	@[vc_field] current i64
	@[vc_field] start i64
}

// new_countdown is the constructor; the instance is already positioned.
@[vc_fn]
pub fn new_countdown() &Countdown {
	return &Countdown{ start: 3, current: 3 }
}

// iter is the iterator entry point. It exists to pair with `advance`; the instance is
// already positioned, and the slot returns the instance itself.
@[vc_method]
@[vc_iter]
pub fn (mut c Countdown) iter() {}

// advance yields the current value and steps down, ending at zero.
@[vc_method]
@[vc_next]
pub fn (mut c Countdown) advance() !i64 {
	if c.current <= 0 {
		return vcraft.raise_domain(.stop_iteration, 'no more values')
	}
	c.current--
	return c.current + 1
}

// zero is a static method: it belongs to Counter but takes no instance.
@[vc_static]
pub fn Counter.zero() i64 {
	return 0
}

// complex_scale multiplies a complex number by a real, both Python complex.
@[vc_fn]
pub fn complex_scale(z complex.Complex, k f64) complex.Complex {
	return complex.complex(z.re * k, z.im * k)
}

// Vector owns a native f64 buffer: the constructor sizes it, `set`/`total` work on it
// in place, and it is freed when the object is collected. No per-element crossing.
@[vc_class]
pub struct Vector {
mut:
	@[vc_buffer] data []f64
}

// new_vector allocates the buffer; the constructor takes its length.
@[vc_fn]
pub fn new_vector(n int) &Vector {
	return &Vector{
		data: vcraft.buffer_new_f64(n)
	}
}

// set writes one element.
@[vc_method]
pub fn (mut v Vector) set(i int, x f64) {
	if i >= 0 && i < v.data.len {
		v.data[i] = x
	}
}

// get reads one element.
@[vc_method]
pub fn (v &Vector) get(i int) f64 {
	if i >= 0 && i < v.data.len {
		return v.data[i]
	}
	return 0.0
}

// total sums the buffer in V.
@[vc_method]
pub fn (v &Vector) total() f64 {
	mut sum := 0.0
	for x in v.data {
		sum += x
	}
	return sum
}

// BoundedCounter inherits Counter and refuses to pass a limit.
//
// It declares no `new_*` of its own: a subclass reuses the base's constructor, so
// `BoundedCounter()` runs `new_counter` and zeroes `limit`.
@[vc_class]
@[vc_base(Counter)]
pub struct BoundedCounter {
mut:
	@[vc_field] limit i64
}

// bump adds `by`, refusing to pass the limit.
@[vc_method]
pub fn (mut c BoundedCounter) bump(by i64) !i64 {
	mut base := unsafe { &Counter(vcraft.state_at(1)) }
	if base.value + by > c.limit {
		return vcraft.raise_domain(.value_error, 'the counter would pass its limit')
	}
	base.value += by
	return base.value
}
