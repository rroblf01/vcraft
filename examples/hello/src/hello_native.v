module hello_native

import vcraft

// Adds two integers and returns the sum.
@[vc_fn]
pub fn add(a int, b int) int {
	return a + b
}

// Greets someone by name.
// Raises ValueError when the name is empty.
@[vc_fn]
pub fn greet(name string) !string {
	if name.len == 0 {
		return error('name must not be empty')
	}
	return 'Hello, ${name}!'
}

// Divides two floats, refusing a zero divisor.
//
// The failure is a ZeroDivisionError rather than a RuntimeError, because Python
// code dividing by zero expects to catch that. See vcraft/errors.v.
@[vc_fn]
pub fn divide(a f64, b f64) !f64 {
	if b == 0.0 {
		return vcraft.raise_domain(.zero_division_error, 'division by zero')
	}
	return a / b
}

// Parses an integer, refusing anything else.
//
// An out-of-range value is an OverflowError and a non-digit is a ValueError, which
// are what int() raises for the same inputs.
@[vc_fn]
pub fn parse_int(text string) !int {
	n := text.len
	for i in 0 .. n {
		ch := text[i]
		if ch < `0` || ch > `9` {
			return vcraft.raise_domain(.value_error, 'invalid literal for int(): ${text}')
		}
	}
	if n > 19 {
		return vcraft.raise_domain(.overflow_error, 'int too large to parse')
	}
	mut value := 0
	for i in 0 .. n {
		value = value * 10 + int(text[i] - `0`)
	}
	return value
}

// Reads past the end of a slice, to show what a V panic looks like from Python.
//
// A V panic would call exit(1) and take the interpreter with it. The generated
// wrapper recovers it and raises RuntimeError instead, so the process survives.
@[vc_fn]
pub fn first_char(text string) string {
	unsafe {
		return text[..1].str()
	}
}

// Repeats a string n times.
@[vc_fn]
pub fn repeat(text string, n int) string {
	mut out := ''
	for _ in 0 .. n {
		out += text
	}
	return out
}

// Returns nothing.
@[vc_fn]
pub fn noop() {}

// Sums a sequence of integers.
@[vc_fn]
pub fn total(values []int) int {
	mut sum := 0
	for v in values {
		sum += v
	}
	return sum
}

// Takes any Python object and returns it unchanged.
@[vc_fn]
@[vc_raw]
pub fn passthrough(obj voidptr) voidptr {
	return obj
}

// A counter with state.
//
// Fields must be scalars. A V string inside a Python object would be a pointer
// that V's collector cannot see, because it does not scan memory CPython
// allocated, so the string would be reclaimed while Python still held it. Reach a
// string through a method, which marshals it properly.
@[vc_class]
pub struct Counter {
mut:
	// value is the running total.
	@[vc_field] value int
	@[vc_field] step int
}

// A new counter starts at zero with a step of one.
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{ step: 1 }
}

// increment adds step to value and returns the new total.
@[vc_methods]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}

// set_step changes how much each increment adds.
@[vc_methods]
pub fn (mut c Counter) set_step(step int) {
	c.step = step
}

// Doubles the counter, so a method can change state beyond the fields.
//
// The receiver is by value. vcraft copies the struct in before the call and back
// out after it, so a mutating method is written the idiomatic V way.
@[vc_methods]
pub fn (mut c Counter) double() {
	c.value *= 2
}

// is_zero reports whether the value is still zero.
@[vc_methods]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}
