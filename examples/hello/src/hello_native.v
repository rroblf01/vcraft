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

// BoundedCounter inherits Counter's state and adds a limit.
//
// A subclass declares `@[vc_base(Name)]`. Its instances get the base's fields, methods
// and properties as well as its own, and the state block is one value holding the base
// struct followed by this one.
//
// V has no struct inheritance, so `BoundedCounter` names only `limit` and a method of
// the subclass cannot write `c.value`. A method that needs the base's fields reads them
// through `vcraft.load_state`, which is what the generated accessors do.
@[vc_class]
@[vc_base(Counter)]
pub struct BoundedCounter {
mut:
	@[vc_field] limit int
}

// base_of is the inherited Counter of the instance a method is running on.
//
// `vcraft.state_at(1)` is the generation one step below the running method's class, and
// the trampoline has published the address of that struct there. It points into the live
// state block, so writing through it updates the instance: the trampoline writes the whole
// block back when the method returns.
//
// This is the shape a method of a subclass takes when it touches the base's fields. V
// gives the subclass no field access to them, and the receiver vcraft passes is the
// subclass struct, which does not even contain those bytes.
fn base_of() &Counter {
	return unsafe { &Counter(vcraft.state_at(1)) }
}

// at_limit reports whether the counter has reached its limit.
@[vc_methods]
@[vc_property]
pub fn (mut c BoundedCounter) at_limit() bool {
	return base_of().value >= c.limit
}

// bump adds `by` and refuses to pass the limit.
//
// Reading and writing the inherited `value` goes through `base_of`, because V gives a
// subclass no field access to its base's struct.
//
// The name is not `step` because that is a field of the base: a method on the subclass
// shadows an inherited attribute of the same name, so `b.step` would reach this method
// rather than the field. That is Python's rule, not vcraft's, and the example would be a
// poor advertisement for a shadowing nobody asked for.
@[vc_methods]
pub fn (mut c BoundedCounter) bump(by int) !int {
	mut base := base_of()
	if base.value + by > c.limit {
		return vcraft.raise_domain(.value_error, 'the counter would pass its limit')
	}
	base.value += by
	return base.value
}

// counter_eq reports whether two counters hold the same state.
//
// `@[vc_eq]` makes this the class's `__eq__`. The operator is not a parameter: `==` and
// `!=` both come here, and `!=` is the negation of the answer.
//
// It is a free function rather than a method because V allows exactly one receiver per
// method and rejects a second parameter outright: the parser reads `&Counter, other` as a
// second receiver type and reports "unexpected name `voidptr`, expecting `,`". So the
// class is named in the function's name and both operands arrive as state pointers.
//
// Only `==` and `!=` reach here. The ordering operators return NotImplemented, which is
// what lets Python try the other operand's reflected method before giving up with an
// error that names the type.
@[vc_eq]
pub fn counter_eq(a voidptr, b voidptr) bool {
	mut x := Counter{}
	mut y := Counter{}
	vcraft.load_state(a, voidptr(&x), sizeof(Counter))
	vcraft.load_state(b, voidptr(&y), sizeof(Counter))
	return x.value == y.value && x.step == y.step
}

// two_counters_hash returns a hash consistent with `two_counters_equal`.
//
// Required alongside `@[vc_eq]`. Python's dicts assume that two objects which compare
// equal hash the same, so a value comparison with an identity-based hash makes every
// lookup in a set or a dict key miss without an error.
@[vc_hash]
pub fn counter_hash(self voidptr) int {
	mut c := Counter{}
	vcraft.load_state(self, voidptr(&c), sizeof(Counter))
	return c.value * 31 + c.step
}

// is_zero reports whether the value is still zero.
@[vc_methods]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}

// A node in a chain, and the class that exists to show a cycle being collected.
//
// `peer` is a strong reference: Node holds it, and a Node can hold one of these back.
// Neither instance is reachable from Python once both names are dropped, so only the
// collector can free them, and only a type with `Py_TPFLAGS_HAVE_GC` is ever a candidate.
//
// The field is declared `PyObj` because that is what it holds: a pointer and a reference
// count, and nothing V's collector would recognise. Declaring it as `&Pair` would put a
// V-visible reference to memory CPython allocated into a V-local copy of the state, and
// V would try to free it.
@[vc_class]
pub struct Pair {
mut:
	// tag is an ordinary field, so the repr shows a cycle is still readable.
	@[vc_field] tag int
	// peer is the other half of the pair, or None.
	@[vc_ref(Pair)] peer vcraft.PyObj
}

// A pair with nothing set.
@[vc_fn]
pub fn new_pair() &Pair {
	return &Pair{}
}

// link makes two instances point at each other, which is the cycle the collector
// exists to break.
@[vc_methods]
pub fn (mut p Pair) link(other voidptr) {
	// `retain`, not `steal`: a function parameter is borrowed, and the field has to keep
	// the object alive on its own.
	p.peer = vcraft.retain(other)
}

// other returns the peer as an object, or None when it was never set.
//
// `state_at(0)` is the block the trampoline loaded, which for a class with no base is
// the class's own struct, so the peer's own struct is one step along.
@[vc_methods]
pub fn (p &Pair) other() vcraft.PyObj {
	if vcraft.is_null(p.peer) {
		return vcraft.to_py_none()
	}
	return vcraft.incref(p.peer)
}

// A V error type, so a `!T` function can fail in a way Python names precisely.
//
// V's error interface is `msg()` and `code()`, and this struct has both, which is all V
// requires to be returned from a `!T` function. What vcraft adds is the Python exception:
// `code()` returning a `PyExc` value *is* the choice, and `raise_from_error` reads it on
// the far side of the call, where the error value has been erased to `IError` and the
// message is all that is left.
//
// No generated code is involved in that path, and none is needed: the choice travels in the
// error itself. The raiser below is for the case the code cannot express -- an exception
// class that is not one of CPython's builtins.
@[vc_error]
pub struct ConfigError {
pub:
	// detail is what the caller would have written in the message.
	detail string
	// line is where it went wrong, kept as data rather than folded into the message so a
	// caller in V can read it.
	line int
}

pub fn (e ConfigError) msg() string {
	return 'line ${e.line}: ${e.detail}'
}

// code is the exception, not an error code: `PyExc.value_error` is 2, and
// `raise_from_error` turns it into the class Python sees.
pub fn (e ConfigError) code() int {
	return int(vcraft.PyExc(.value_error))
}

// A custom exception class, defined by the caller rather than by vcraft.
//
// This one carries a Python exception object, so the generator emits a raiser for it and
// `code()` has nothing to say: the class is not one of the `PyExc` values.
@[vc_error]
pub struct CustomError {
pub:
	exc    vcraft.PyObj
	detail string
}

pub fn (e CustomError) msg() string {
	return e.detail
}

pub fn (e CustomError) code() int {
	return 0
}

// load_config reads a `name=value` line out of some configuration text.
//
// Two failure modes, two exception classes: a malformed line is the caller's mistake and
// is a ValueError, while a name that is not there is a LookupError.
@[vc_fn]
pub fn load_config(text string, name string, missing voidptr) !string {
	for line in text.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}
		mut parts := trimmed.split('=')
		if parts.len != 2 {
			return ConfigError{
				detail: 'not a name=value line'
				line:   1
			}
		}
		if parts[0].trim_space() == name {
			return parts[1].trim_space()
		}
	}
	// The class is borrowed and CPython keeps its own reference on the exception it
	// builds. `raise_custom` sets it and returns an error carrying the message.
	return vcraft.raise_custom(missing, 'no setting named ${name}')
}

// checked reports a custom error for a caller-defined exception class.
//
// This is the shape the generated raiser exists for: the V code names the class, and the
// exception reaches Python as that class rather than as a RuntimeError.
@[vc_fn]
pub fn checked(value int, exc voidptr) !int {
	if value < 0 {
		return vcraft_generated__raise_customerror(CustomError{
			exc:    vcraft.borrow(exc)
			detail: 'value must not be negative'
		})
	}
	return value * 2
}
