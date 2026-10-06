module bench_vcraft_native

import vcraft

// The same seven workloads as the PyO3 and zig-maturin projects, with the same
// semantics. Integers are i64 in signatures, like the other two projects. With this V
// `int` is also 64 bits, but the two are distinct types to the checker.
//
// Two workarounds, both for vcraft limitations the benchmark found (see ../README.md):
// a returned list has no typed spelling that builds, so make_range is `@[vc_raw]`, and
// an i64 class field does not compile, so Counter.value is an int.

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
//
// Written with `@[vc_raw]`, the escape hatch, because every typed spelling of a list
// return fails: `[]i64` generates a `vcraft.to_py_list` call with one argument where
// the runtime takes two, `vcraft.PyObj` crashes the generator, and a `voidptr` under
// `@[vc_fn]` generates `result.ptr` on a pointer.
@[vc_raw]
pub fn make_range(n voidptr) voidptr {
	count := vcraft.from_py_int(vcraft.borrow(n), 'n') or { return unsafe { nil } }
	mut out := []int{cap: count}
	for i in 0 .. count {
		out << i
	}
	return vcraft.to_py_list(out, vcraft.to_py_int).ptr
}

// greet takes a str and returns a freshly allocated str.
@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}

// Counter measures method-call overhead on a native object.
//
// `value` is an int because the generated getter and repr for an i64 field call
// `vcraft.to_py_int` and `vcraft.repr_int`, which only take an int. Both are 64 bits
// here, so nothing is lost; the field type is the only difference.
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
}

// new_counter is the constructor.
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{}
}

// increment adds one and returns the new value.
@[vc_methods]
pub fn (mut c Counter) increment() int {
	c.value++
	return c.value
}
