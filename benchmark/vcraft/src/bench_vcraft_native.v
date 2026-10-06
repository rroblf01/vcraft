module bench_vcraft_native

// The same seven workloads as the PyO3 and zig-maturin projects, with the same
// semantics and 64-bit integers throughout.

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
@[vc_methods]
pub fn (mut c Counter) increment() i64 {
	c.value++
	return c.value
}
