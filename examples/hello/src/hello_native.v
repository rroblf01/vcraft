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

// Counts up from zero, returning the numbers as a list.
@[vc_fn]
pub fn count_up(n i64) []i64 {
	mut out := []i64{cap: int(n)}
	for i in i64(0) .. n {
		out << i
	}
	return out
}

// Splits text on spaces into a list of words.
@[vc_fn]
pub fn words(text string) []string {
	return text.split(' ')
}

// Wraps an integer in a one-element list it builds itself.
//
// A `PyObj` result is a reference the function owns, and the caller receives it.
@[vc_fn]
pub fn boxed(n i64) vcraft.PyObj {
	return vcraft.to_py_list([n], fn (x i64) vcraft.PyObj {
		return vcraft.to_py_int(x)
	})
}

// Returns the object it was given, without the raw escape hatch.
//
// A `voidptr` result is borrowed, so the wrapper takes a reference of its own.
@[vc_fn]
pub fn identity(obj voidptr) voidptr {
	return obj
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

// spin burns time in pure V, so threads can prove the GIL is really released.
//
// `@[vc_gil]` is a promise, not a hint: nothing in here touches Python, raises, or
// allocates in a way the collector would need the interpreter for. The wrapper releases
// the GIL around the call, so N threads each burn their own core instead of queuing
// behind one lock.
@[vc_fn]
@[vc_gil]
pub fn spin(iterations int) int {
	mut total := 0
	for i in 0 .. iterations {
		total = (total + i * 7) & 0x7fffffff
	}
	return total
}

// spin_checked is the same shape with a failure mode, so the error path without the
// GIL is exercised too: the wrapper re-acquires before it raises.
//
// A plain `error(...)`, not `raise_domain`: setting a Python exception is touching
// Python, which a `@[vc_gil]` function must never do. The wrapper turns the value into
// a RuntimeError after it holds the GIL again.
@[vc_fn]
@[vc_gil]
pub fn spin_checked(iterations int) !int {
	if iterations < 0 {
		return error('iterations must not be negative')
	}
	return spin(iterations)
}

// checksum adds every byte it is given.
//
// The parameter is `[]u8`, so any bytes-like object works: `bytes`, `bytearray`,
// `memoryview`. Nothing is copied on the way in -- the wrapper aliases the caller's
// buffer for exactly the call's duration -- and the `bytes` returned the other way
// is a copy, because an immutable Python object cannot alias V memory.
@[vc_fn]
pub fn checksum(data []u8) int {
	mut total := 0
	for b in data {
		total = (total + int(b)) & 0xffffff
	}
	return total
}

// echoed returns its argument as immutable bytes, which copies.
//
// The copy is the point of this function existing next to `checksum`: reads alias
// and writes copy, and a test that asserts both proves the asymmetry rather than
// assuming it.
@[vc_fn]
pub fn echoed(data []u8) []u8 {
	return data.clone()
}

// A countdown that yields its values one at a time.
//
// The instance is its own iterator: `@[vc_iter]` runs for its side effects and the
// slot returns the instance, and `@[vc_next]` produces one item per call. A V error
// ends the iteration -- cleanly for `StopIteration`, loudly for anything else, which
// is CPython's own contract for the slot rather than something vcraft invented.
@[vc_class]
pub struct Countdown {
mut:
	// current is what is left to yield.
	@[vc_field] current int
	// start is what `rewind` restores it to.
	@[vc_field] start int
}

// A countdown starts from the given value... almost: constructors take no arguments,
// so it starts from zero and the caller sets `current` itself.
@[vc_fn]
pub fn new_countdown() &Countdown {
	return &Countdown{}
}

// rewind resets the countdown, so the same instance can be iterated twice.
@[vc_methods]
@[vc_iter]
pub fn (mut c Countdown) rewind() {
	c.current = c.start
}

// next yields the current value and steps down, refusing past zero.
//
// `StopIteration` is raised the way every domain failure is: at the point of failure,
// with the pending exception set before the error value travels out.
@[vc_methods]
@[vc_next]
pub fn (mut c Countdown) advance() !int {
	if c.current <= 0 {
		return vcraft.raise_domain(.stop_iteration, 'no more values')
	}
	c.current--
	return c.current + 1
}

// A running total too large for 32 bits.
//
// The field is an i64, which the generated getter, setter and repr have to box at its
// full width.
@[vc_class]
pub struct Tally {
mut:
	@[vc_field] sum i64
}

// A tally at zero.
@[vc_fn]
pub fn new_tally() &Tally {
	return &Tally{}
}

// add_then_fail adds `by` to the sum and then panics.
//
// A method works on the instance in place, as a PyO3 method does, so the write that
// happened before the panic stays.
@[vc_methods]
pub fn (mut t Tally) add_then_fail(by i64) {
	t.sum += by
	panic('failed after writing')
}
