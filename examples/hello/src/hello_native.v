module hello_native

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
@[vc_fn]
pub fn divide(a f64, b f64) !f64 {
	if b == 0.0 {
		return error('division by zero')
	}
	return a / b
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
