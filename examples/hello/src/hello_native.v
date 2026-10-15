module hello_native

import math.complex
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

// Sums a sequence of 64-bit integers.
@[vc_fn]
pub fn total64(values []i64) i64 {
	mut sum := i64(0)
	for v in values {
		sum += v
	}
	return sum
}

// Averages a sequence of numbers, ints and floats alike.
@[vc_fn]
pub fn mean(values []f64) f64 {
	if values.len == 0 {
		return 0.0
	}
	mut sum := 0.0
	for v in values {
		sum += v
	}
	return sum / f64(values.len)
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

// Halves each number, returning floats.
@[vc_fn]
pub fn halves(values []f64) []f64 {
	return values.map(it / 2.0)
}

// Squares of zero up to `n`, as ints.
@[vc_fn]
pub fn squares(n int) []int {
	mut out := []int{cap: n}
	for i in 0 .. n {
		out << i * i
	}
	return out
}

// Squares of zero up to `n`, handed to Python as a zero-copy `memoryview`.
//
// The result is a native-backed `[]int`, so it crosses as a writable view rather than a
// list of boxed ints. The memoryview owns the buffer and frees it once it is collected.
@[vc_fn]
@[vc_memoryview]
pub fn squares_view(n int) []int {
	mut out := vcraft.buffer_new_int(n)
	for i in 0 .. n {
		out[i] = i * i
	}
	return out
}

// Splits text on spaces into a list of words.
@[vc_fn]
pub fn words(text string) []string {
	return text.split(' ')
}

// scale_complex multiplies a complex number by a real one.
//
// `complex.Complex` marshals to and from a Python `complex`, and a plain real is accepted
// where a complex is expected, as Python itself coerces.
@[vc_fn]
pub fn scale_complex(z complex.Complex, k f64) complex.Complex {
	return complex.complex(z.re * k, z.im * k)
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
@[vc_method]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}

// set_step changes how much each increment adds.
@[vc_method]
pub fn (mut c Counter) set_step(step int) {
	c.step = step
}

// Doubles the counter, so a method can change state beyond the fields.
//
// The receiver is by value. vcraft copies the struct in before the call and back
// out after it, so a mutating method is written the idiomatic V way.
@[vc_method]
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
@[vc_method]
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
@[vc_method]
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
@[vc_method]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}

// triple is a static method: it belongs to the class but takes no instance.
//
// `@[vc_static]` on a `fn Counter.triple()` (no receiver) makes a Python
// `staticmethod`, so `Counter.triple(4)` works without constructing anything.
@[vc_static]
pub fn Counter.triple(n int) int {
	return n * 3
}

// counter_value reads a counter through a borrowed reference.
//
// A `&Counter` parameter is an instance reference: the caller must pass a `Counter` or an
// instance of a subclass, and the function reads that instance's state in place. A
// `BoundedCounter`, which inherits `Counter`, is accepted and its inherited `value` read
// through the same pointer.
@[vc_fn]
pub fn counter_value(c &Counter) int {
	return c.value
}

// bounded_limit reads a subclass-only field through a borrowed reference.
//
// `&BoundedCounter` accepts only a `BoundedCounter` or a class below it, and the pointer
// lands on the subclass half of the state, after the inherited `Counter`. The offset is
// the base's size, which the generator emits, so this is what proves it is right.
@[vc_fn]
pub fn bounded_limit(b &BoundedCounter) int {
	return b.limit
}

// pick returns one of its two arguments as the instance it came from.
//
// A `&Counter` result is handed to Python as an instance, not a pointer: the wrapper
// matches the returned address against the receiver and the instance arguments of the
// call, and gives back the one that owns it. Returning a pointer that is not one of them
// raises rather than handing Python an object it does not own.
@[vc_fn]
pub fn pick(first &Counter, second &Counter) &Counter {
	return first
}

// orphan returns an instance no argument owns, which the wrapper must refuse.
//
// A `&T` result is only handed to Python when the pointer points into the receiver or one
// of the call's instance arguments; a pointer into anything else would give Python an
// object it does not own, so the wrapper raises instead of guessing. The function compiles
// -- it takes an instance, so the generator has something to match against -- and fails at
// the call.
@[vc_fn]
pub fn orphan(first &Counter) &Counter {
	return &Counter{ step: 1 }
}

// self_ref returns the receiver itself, the simplest `&T` result.
@[vc_method]
pub fn (c &Counter) self_ref() &Counter {
	return c
}

// add_counter reads another instance's state through a borrowed reference.
//
// A method may take an instance reference alongside its receiver, so an instance can be
// combined with another of the same class or of a subclass.
@[vc_method]
pub fn (mut c Counter) add_counter(other &Counter) int {
	c.value += other.value
	return c.value
}

// raw_echo hands one Python object through untouched.
//
// `@[vc_raw]` on a method skips marshalling for its arguments exactly as it does on a
// module function: the receiver still works on the instance's state, each argument is
// the borrowed `PyObject` itself, and the return is owned by the caller.
@[vc_method]
@[vc_raw]
pub fn (mut c Counter) raw_echo(obj voidptr) voidptr {
	return obj
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
@[vc_method]
pub fn (mut p Pair) link(other voidptr) {
	// `retain`, not `steal`: a function parameter is borrowed, and the field has to keep
	// the object alive on its own.
	p.peer = vcraft.retain(other)
}

// other returns the peer as an object, or None when it was never set.
@[vc_method]
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
// `@[vc_nogil]` is a promise, not a hint: nothing in here touches Python, raises, or
// allocates in a way the collector would need the interpreter for. The wrapper releases
// the GIL around the call, so N threads each burn their own core instead of queuing
// behind one lock.
@[vc_fn]
@[vc_nogil]
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
// Python, which a `@[vc_nogil]` function must never do. The wrapper turns the value into
// a RuntimeError after it holds the GIL again.
@[vc_fn]
@[vc_nogil]
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
@[vc_method]
@[vc_iter]
pub fn (mut c Countdown) rewind() {
	c.current = c.start
}

// next yields the current value and steps down, refusing past zero.
//
// `StopIteration` is raised the way every domain failure is: at the point of failure,
// with the pending exception set before the error value travels out.
@[vc_method]
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
@[vc_method]
pub fn (mut t Tally) add_then_fail(by i64) {
	t.sum += by
	panic('failed after writing')
}

// A vector of doubles held in a native buffer.
//
// The buffer lives for the object's lifetime, is not copied on every call, and is freed
// exactly once at dealloc. `memoryview(v)` exposes it without a copy, and the methods
// below read and write it in place.
@[vc_class]
pub struct Vector {
mut:
	@[vc_buffer] data []f64
}

// A vector of `n` zeroed doubles.
//
// The constructor takes an argument, which `tp_new` binds from Python's tuple and dict
// and passes here; it sizes the native buffer through `buffer_new_f64`.
@[vc_fn]
pub fn new_vector(n int) &Vector {
	return &Vector{
		data: vcraft.buffer_new_f64(n)
	}
}

// set stores a value at `i`, ignoring an out-of-range index.
@[vc_method]
pub fn (mut v Vector) set(i int, value f64) {
	if i >= 0 && i < v.data.len {
		v.data[i] = value
	}
}

// get reads the value at `i`, or zero when the index is out of range.
@[vc_method]
pub fn (v &Vector) get(i int) f64 {
	if i >= 0 && i < v.data.len {
		return v.data[i]
	}
	return 0.0
}

// total sums the buffer in V, with no per-element crossing of the boundary.
@[vc_method]
pub fn (v &Vector) size() int {
	return v.data.len
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

// resize replaces the buffer with `n` zeroed doubles, refusing while a memoryview is open.
@[vc_method]
pub fn (mut v Vector) resize(n int) ! {
	v.data = vcraft.buffer_resize_f64(v.data, n)!
}

// A class whose buffer is exposed as a *typed* `memoryview`.
//
// `@[vc_buffer_typed]` makes `memoryview(instance)` report one item per element with the
// element's own format, instead of the default 1-D byte view: `format "d"`, `itemsize 8`,
// and a length in elements rather than bytes.
@[vc_class]
pub struct Samples {
mut:
	@[vc_buffer; vc_buffer_typed] samples []f64
}

// A Samples with an `n`-element buffer of doubles.
@[vc_fn]
pub fn new_samples(n int) &Samples {
	return &Samples{
		samples: vcraft.buffer_new_f64(n)
	}
}

// set stores a value at `i`, ignoring an out-of-range index.
@[vc_method]
pub fn (mut s Samples) set(i int, value f64) {
	if i >= 0 && i < s.samples.len {
		s.samples[i] = value
	}
}

// at reads the value at `i`, or zero when the index is out of range.
@[vc_method]
pub fn (s &Samples) at(i int) f64 {
	if i >= 0 && i < s.samples.len {
		return s.samples[i]
	}
	return 0.0
}

// A subclass with a native buffer of its own, on top of Counter.
//
// The buffer field is freed by the most-derived `tp_dealloc`, alongside whatever the base
// holds, because the state block is one allocation.
@[vc_class]
@[vc_base(Counter)]
pub struct TallyBuffer {
mut:
	@[vc_field] count int
	@[vc_buffer] buf []int
}

// A TallyBuffer with an `n`-element buffer.
//
// A subclass may take constructor arguments because its base, Counter, is
// argument-free: the base's constructor runs with no arguments and this one keeps
// the arguments it was given.
//
// A negative size is refused. The exception is set here, after `tp_new` has already
// allocated the object and run the base's constructor, so this is the shape a
// constructor failure takes: vcraft releases the half-built instance and Python sees
// the ValueError.
@[vc_fn]
pub fn new_tally_buffer(n int) &TallyBuffer {
	if n < 0 {
		vcraft.raise(.value_error, 'buffer size must not be negative')
	}
	return &TallyBuffer{
		buf: vcraft.buffer_new_int(n)
	}
}

// push stores a value at the next free slot, or does nothing when full.
@[vc_method]
pub fn (mut t TallyBuffer) push(value int) {
	if t.count < t.buf.len {
		t.buf[t.count] = value
		t.count++
	}
}

// A class that holds both a reference and a native buffer, so the type is collectable and
// still owns memory that has to be freed.
@[vc_class]
pub struct Chunk {
mut:
	// buddy is a unique field name: the generator matches a field's annotation by name
	// across the whole project, so two classes sharing a field name would share its
	// annotation too.
	@[vc_ref] buddy vcraft.PyObj
	@[vc_buffer] bytes []u8
}

// A chunk with a four-byte buffer.
@[vc_fn]
pub fn new_chunk() &Chunk {
	return &Chunk{
		bytes: vcraft.buffer_new_u8(4)
	}
}

// fill writes one byte into the buffer.
@[vc_method]
pub fn (mut c Chunk) fill(b u8) {
	for i in 0 .. c.bytes.len {
		c.bytes[i] = b
	}
}

// A native pointer wrapped in a capsule.
//
// A capsule is the escape hatch for state that is not a plain slice: it carries a native
// pointer with a destructor that runs when Python collects it. `new_box` allocates one
// int, `box_value` reads it, and `box_free` releases the allocation.
@[vc_fn]
pub fn new_box(value int) vcraft.PyObj {
	p := vcraft.native_alloc(usize(sizeof(int)))
	if p == unsafe { nil } {
		panic('memory allocation failure')
	}
	unsafe {
		*(&int(p)) = value
	}
	return vcraft.new_handle(p, voidptr(box_free))
}

// box_free releases the int a capsule owns.
//
// A capsule destructor is called with the *capsule object*, not the pointer it holds, so
// it extracts the pointer first. `handle_data` is that extraction.
pub fn box_free(capsule voidptr) {
	vcraft.native_free(vcraft.handle_data(capsule))
}

// box_value reads the int a capsule holds, or zero when it is not a capsule.
@[vc_fn]
pub fn box_value(handle voidptr) int {
	p := vcraft.handle_data(handle)
	if p == unsafe { nil } {
		return 0
	}
	return unsafe { *(&int(p)) }
}
