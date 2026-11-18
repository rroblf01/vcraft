module hello_native

import math.big
import math.complex
import json2
import time
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
	if n <= 0 || text.len == 0 {
		return ''
	}
	// Build in one pass: a V string is immutable, so `out += text` in a loop
	// is O(n^2) in the total length. Accumulate into a buffer and convert once.
	mut buf := []u8{cap: text.len * n}
	for _ in 0 .. n {
		buf << text.bytes()
	}
	return buf.bytestr()
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
	// A `voidptr` result is now an owned reference, so a pass-through takes one
	// of its own before handing it back.
	return vcraft.borrow(obj).new_ref().ptr
}

// Takes any Python object and returns it unchanged.
@[vc_fn]
@[vc_raw]
pub fn passthrough(obj voidptr) voidptr {
	return vcraft.borrow(obj).new_ref().ptr
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
	return vcraft.borrow(obj).new_ref().ptr
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

// first_char_nogil is `first_char` without the GIL: a panic in a `@[vc_nogil]` call
// unwinds through the GIL release and is still recovered as a RuntimeError.
@[vc_fn]
@[vc_nogil]
pub fn first_char_nogil(text string) string {
	unsafe {
		return text[..1].str()
	}
}

// stop_outside chooses StopIteration in an ordinary `!T` function. Only an iterator's
// `tp_iternext` ends silently on it; anywhere else it is raised with its message.
@[vc_fn]
pub fn stop_outside() !int {
	return vcraft.raise_domain(.stop_iteration, 'stopped here')
}

// RegistryState is ordinary V state -- a map and an array -- which the collector manages.
struct RegistryState {
mut:
	names map[string]int
	log   []string
}

// Registry keeps collector-managed state alive through `vcraft.own_gc`: each instance has
// its own, released when the instance is.
@[vc_class]
pub struct Registry {
mut:
	@[vc_handle] state vcraft.Owned
}

@[vc_fn]
pub fn new_registry() &Registry {
	return &Registry{
		state: vcraft.own_gc(&RegistryState{})
	}
}

// add records a name and returns how many the registry holds.
@[vc_method]
pub fn (mut r Registry) add(name string) int {
	mut s := unsafe { &RegistryState(r.state.get()) }
	s.names[name.clone()] = s.names.len
	s.log << name.clone()
	return s.names.len
}

// lookup returns the position a name was added at, or -1.
@[vc_method]
pub fn (r &Registry) lookup(name string) int {
	s := unsafe { &RegistryState(r.state.get()) }
	return s.names[name] or { -1 }
}

// Span is a plain struct: it crosses out as a dict, and in from a dict, a tuple of its
// fields (a namedtuple) or any object carrying them (a dataclass).
pub struct Span {
pub:
	start int
	end   int
	label string
}

// span_len reads a Span from whatever Python passes.
@[vc_fn]
pub fn span_len(s Span) string {
	return '${s.label}:${s.end - s.start}'
}

// make_span returns a Span, which Python receives as a dict.
@[vc_fn]
pub fn make_span(n int) Span {
	return Span{
		start: 1
		end:   1 + n
		label: 'span'
	}
}

// Point crosses out as a struct sequence: a tuple with named fields.
@[vc_structseq]
pub struct Point {
pub:
	x int
	y int
}

@[vc_fn]
pub fn make_point(x int, y int) Point {
	return Point{
		x: x
		y: y
	}
}

@[vc_fn]
pub fn point_sum(p Point) int {
	return p.x + p.y
}

// Shape is a sumtype: it crosses as whichever variant it holds.
pub type Shape = f64 | int | string | bool | Span

@[vc_fn]
pub fn shape_kind(s Shape) string {
	return match s {
		int { 'int ${s}' }
		f64 { 'f64 ${s}' }
		string { 'string ${s}' }
		bool { 'bool ${s}' }
		Span { 'span ${s.label}' }
	}
}

@[vc_fn]
pub fn make_shape(kind int) Shape {
	return match kind {
		0 { Shape(7) }
		1 { Shape('seven') }
		2 { Shape(7.5) }
		3 { Shape(true) }
		else { Shape(Span{ start: 0, end: 2, label: 's' }) }
	}
}

// slow_square is awaitable: it runs on a thread of its own, without the GIL, so several
// calls gathered together overlap. It runs without the GIL, so it reports a failure
// through the error's code rather than `raise_domain`, which would touch Python.
@[vc_fn]
@[vc_async]
pub fn slow_square(n int, label string) !string {
	if n < 0 {
		return error_with_code('negative input', int(vcraft.PyExc.value_error))
	}
	time.sleep(60 * time.millisecond)
	return '${label}:${n * n}'
}

// async_boom panics on its worker thread; the future gets the RuntimeError.
@[vc_fn]
@[vc_async]
pub fn async_boom(i int) int {
	values := [1, 2, 3]
	return values[i]
}

// nd_scale multiplies a float64 array of any shape by `k`: read through the buffer
// protocol without a copy, written into a new array of the same shape.
@[vc_fn]
pub fn nd_scale(a vcraft.NdArray, k f64) !vcraft.NdOut {
	src := a.f64s()!
	out := vcraft.nd_out_f64(a.shape)
	mut dst := out.f64s()
	for i, x in src {
		dst[i] = x * k
	}
	return out
}

// nd_trace sums the diagonal of a 2-D float64 array through its strides, so a transposed
// or sliced array works as well as a contiguous one.
@[vc_fn]
pub fn nd_trace(a vcraft.NdArray) !f64 {
	if a.ndim() != 2 {
		return error_with_code('expected a 2-D array', int(vcraft.PyExc.value_error))
	}
	mut total := 0.0
	n := if a.shape[0] < a.shape[1] { a.shape[0] } else { a.shape[1] }
	for i in 0 .. n {
		total += a.at_f64(i, i)
	}
	return total
}

// nd_fill writes into the caller's array in place.
@[vc_fn]
pub fn nd_fill(a vcraft.NdArray, value f64) ! {
	mut xs := a.f64s()!
	if a.readonly {
		return error_with_code('the array is read-only', int(vcraft.PyExc.value_error))
	}
	for i in 0 .. xs.len {
		xs[i] = value
	}
}

// nd_shape reports what the view saw.
@[vc_fn]
pub fn nd_shape(a vcraft.NdArray) string {
	return '${a.shape} ${a.kind.ascii_str()} ${a.readonly} ${a.c_contiguous}'
}

// sum_all adds `base` and any number of further ints: Python's `sum_all(1, 2, 3)`.
@[vc_fn]
pub fn sum_all(base int, xs ...int) int {
	mut t := base
	for x in xs {
		t += x
	}
	return t
}

// tag renders `name` with whatever keyword arguments it was given, sorted by name.
@[vc_fn]
@[vc_kwargs]
pub fn tag(name string, opts map[string]string) string {
	mut keys := opts.keys()
	keys.sort()
	mut out := name
	for k in keys {
		out += ' ${k}=${opts[k]}'
	}
	return out
}

// both takes a prefix, any number of strings and any keyword arguments as ints. V wants
// the variadic parameter last, so the keyword map comes just before it and is named.
@[vc_fn]
@[vc_kwargs: 'weights']
pub fn both(prefix string, weights map[string]int, items ...string) string {
	mut sum := 0
	for _, w in weights {
		sum += w
	}
	return '${prefix}:${items.join(",")}:${sum}'
}

// Config answers attribute lookups it has no field for: `cfg.anything` reads a setting
// by name, while `cfg.version` is still the ordinary field.
@[vc_class]
pub struct Config {
mut:
	@[vc_field] version int
}

@[vc_fn]
pub fn new_config() &Config {
	return &Config{
		version: 3
	}
}

// setting is the class's `__getattr__`: called only for names the class does not have.
@[vc_method]
@[vc_getattr]
pub fn (c &Config) setting(name string) !string {
	if name.starts_with('opt_') {
		return 'value of ${name}'
	}
	return error('no setting ${name}')
}

// RecordState holds a Record's dynamic attributes, collector-managed through `own_gc`.
struct RecordState {
mut:
	extra map[string]int
}

// Record stores assignments to names it has no field for: `r.anything = 3` goes to
// `put`, while `r.size` stays the ordinary field.
@[vc_class]
pub struct Record {
mut:
	@[vc_field] size int
	@[vc_handle] state vcraft.Owned
}

@[vc_fn]
pub fn new_record() &Record {
	return &Record{
		state: vcraft.own_gc(&RecordState{})
	}
}

// put is the class's `__setattr__` for the names it does not define. The name is
// borrowed from Python, so it is cloned before the map keeps it.
@[vc_method]
@[vc_setattr]
pub fn (mut r Record) put(name string, value int) ! {
	if name.starts_with('_') {
		return error('private name ${name}')
	}
	mut s := unsafe { &RecordState(r.state.get()) }
	s.extra[name.clone()] = value
	r.size = s.extra.len
}

// lookup is the matching `__getattr__`.
@[vc_method]
@[vc_getattr]
pub fn (r &Record) lookup(name string) !int {
	s := unsafe { &RecordState(r.state.get()) }
	return s.extra[name] or { return error('no ${name}') }
}

// Mood is a V enum: Python sees an `enum.IntEnum` named `Mood`.
pub enum Mood {
	calm
	happy = 5
}

// cheer_up returns the happier mood.
@[vc_fn]
pub fn cheer_up(m Mood) Mood {
	return if m == .calm { Mood.happy } else { m }
}

// apply_py calls a Python function with a V value, through `call_py`.
@[vc_fn]
pub fn apply_py(f vcraft.PyObj, x int) !int {
	arg := vcraft.to_py_int(x)
	r := vcraft.call_py(f, arg)
	arg.decref()
	if r.is_null() {
		return error('callback failed')
	}
	out := vcraft.from_py_int(r, 'result')!
	r.decref()
	return int(out)
}

// Note has fields V's collector manages -- strings, a list, a map -- so its state lives in
// a block the collector scans, and the parameters it stores are copied for it.
@[vc_class]
pub struct Note {
mut:
	@[vc_field] title string
	@[vc_field] tags  []string
	@[vc_field] views int
	words map[string]int
}

@[vc_fn]
pub fn new_note(title string) &Note {
	return &Note{
		title: title
	}
}

// rename stores its argument in the instance.
@[vc_method]
pub fn (mut n Note) rename(title string) {
	n.title = title
}

// learn counts the words of a text into a map the class keeps.
@[vc_method]
pub fn (mut n Note) learn(text string) int {
	for w in text.split(' ') {
		n.words[w.clone()]++
	}
	return n.words.len
}

// summary reads every field.
@[vc_method]
pub fn (n &Note) summary() string {
	return '${n.title}: ${n.tags.join(',')} (${n.views} views, ${n.words.len} words)'
}

// note_eq compares two notes by title: `==` on a boxed class.
@[vc_eq]
pub fn note_eq(a &Note, b &Note) bool {
	return a.title == b.title
}

// note_hash hashes a note by its title.
@[vc_hash]
pub fn note_hash(n &Note) int {
	return n.title.len
}

// note_title reads a Note passed as an argument: a `&T` parameter of a boxed class.
@[vc_fn]
pub fn note_title(n &Note) string {
	return n.title
}

// pick_note returns one of two notes: a `&T` result pointing into a boxed instance.
@[vc_fn]
pub fn pick_note(a &Note, b &Note, second bool) &Note {
	return if second { b } else { a }
}

// Draft is a subclass of a boxed class, which is boxed too.
@[vc_class]
@[vc_base(Note)]
pub struct Draft {
mut:
	@[vc_field] revision int
	@[vc_field] author   string
}

// Point3 is built from its fields: `@[vc_class: 'init']` generates the constructor, so
// `Point3(x=1.0, label='a')` works with no `new_point3` written.
@[vc_class: 'init']
pub struct Point3 {
mut:
	@[vc_field] x     f64
	@[vc_field] y     f64
	@[vc_field] z     f64
	@[vc_field] label string
	@[vc_field] tags  []string
}

// norm2 is the squared length.
@[vc_method]
pub fn (p &Point3) norm2() f64 {
	return p.x * p.x + p.y * p.y + p.z * p.z
}

// arrow_range is an int64 Arrow column 0..n.
@[vc_fn]
pub fn arrow_range(n int) vcraft.ArrowOut {
	mut xs := []i64{cap: n}
	for i in 0 .. n {
		xs << i64(i)
	}
	return vcraft.arrow_i64(xs)
}

// arrow_sum adds an int64 or float64 Arrow column, skipping nulls.
@[vc_fn]
pub fn arrow_sum(col vcraft.ArrowArray) !f64 {
	mut total := 0.0
	if col.format == 'l' {
		xs := col.i64s()!
		for i, x in xs {
			if !col.is_null(i) {
				total += f64(x)
			}
		}
		return total
	}
	xs := col.f64s()!
	for i, x in xs {
		if !col.is_null(i) {
			total += x
		}
	}
	return total
}

// arrow_names is a utf8 Arrow column from a list of strings.
@[vc_fn]
pub fn arrow_names(names []string) vcraft.ArrowOut {
	return vcraft.arrow_strings(names)
}

// arrow_upper upper-cases a utf8 Arrow column into a new one.
@[vc_fn]
pub fn arrow_upper(col vcraft.ArrowArray) !vcraft.ArrowOut {
	mut out := []string{cap: col.len}
	for i in 0 .. col.len {
		out << col.str_at(i)!.to_upper()
	}
	return vcraft.arrow_strings(out)
}

// par_poly evaluates a polynomial at each point, one chunk of the points per core.
@[vc_fn]
@[vc_nogil]
pub fn par_poly(xs []f64, rounds int) []f64 {
	mut out := []f64{len: xs.len}
	vcraft.par_range(xs.len, fn [xs, mut out, rounds] (start int, end int) {
		for i in start .. end {
			mut acc := 0.0
			for r in 0 .. rounds {
				acc = acc * 0.5 + xs[i] * f64(r % 7)
			}
			out[i] = acc
		}
	})
	return out
}

// sum_released adds up `xs` with the GIL released, through a closure over the list.
@[vc_fn]
pub fn sum_released(xs []f64) f64 {
	mut total := 0.0
	ptr := &total
	vcraft.released(fn [xs, ptr] () {
		mut acc := 0.0
		for x in xs {
			acc += x
		}
		unsafe {
			*ptr = acc
		}
	})
	return total
}

// par_fail panics in one of its chunks.
@[vc_fn]
pub fn par_fail(n int) int {
	vcraft.par_range(n, fn (start int, end int) {
		if start > 0 {
			panic('chunk starting at ${start} failed')
		}
	})
	return n
}

// Badge is built from its fields and inherits from Point3: `@[vc_class: 'init']` on a
// subclass takes the base's fields first.
@[vc_class: 'init']
@[vc_base(Point3)]
pub struct Badge {
mut:
	@[vc_field] rank int
	@[vc_field] motto string
}

// count_all takes only *args, so its glue reads no fixed parameter.
@[vc_fn]
pub fn count_all(xs ...int) int {
	return xs.len
}

// next_day moves a datetime forward a day: `time.Time` is Python's `datetime`.
@[vc_fn]
pub fn next_day(t time.Time) time.Time {
	return t.add_days(1)
}

// twice doubles a `timedelta`.
@[vc_fn]
pub fn twice(d time.Duration) time.Duration {
	return d * 2
}

// price_text sees a `decimal.Decimal` exactly, as its text.
@[vc_fn]
pub fn price_text(d vcraft.Decimal) vcraft.Decimal {
	return vcraft.decimal(d.text + '0')
}

// big_square squares a Python int of any size.
@[vc_fn]
pub fn big_square(n big.Integer) big.Integer {
	return n * n
}

// json_keys takes any JSON value and returns it with a `seen` key added to a dict.
@[vc_fn]
pub fn json_tag(v json2.Any) json2.Any {
	if v is map[string]json2.Any {
		mut m := v.clone()
		m['seen'] = json2.Any(true)
		return json2.Any(m)
	}
	return v
}

// log_twice writes to Python's logging from V.
@[vc_fn]
pub fn log_twice(msg string) {
	vcraft.log_info(msg)
	vcraft.log_warning(msg + '!')
}

// raise_os raises the OSError subclass an errno value stands for, with `context` as the
// part after the colon in its message.
@[vc_fn]
pub fn raise_os(code int, context string) !int {
	return vcraft.raise_errno(code, context)
}

// too_slow raises one of the OSError family by name.
@[vc_fn]
pub fn too_slow() !int {
	return vcraft.raise_domain(.timeout_error, 'too slow')
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

// ---- native state a class owns ------------------------------------------

// handle_releases counts how many handles have been released, so a test can see that
// dealloc ran the drop rather than trusting that it did.
__global handle_releases = 0

// handle_release_count reports how many handles have been released.
@[vc_fn]
pub fn handle_release_count() int {
	return handle_releases
}

// pointer_free releases an int allocation and counts it.
fn pointer_free(p voidptr) {
	handle_releases++
	vcraft.native_free(p)
}

// OwnedBox owns a native int. The field is `@[vc_handle]`, so the generated `tp_dealloc`
// releases it: the allocation's lifetime is the instance's, and no Python object is
// involved the way it is with a capsule.
@[vc_class]
pub struct OwnedBox {
mut:
	@[vc_handle] owned vcraft.Owned
	// value is the int the handle holds, copied out for the Python side.
	@[vc_field] value int
}

// new_owned_box allocates an int the instance owns.
@[vc_fn]
pub fn new_owned_box(value int) &OwnedBox {
	p := vcraft.native_alloc(usize(sizeof(int)))
	if p == unsafe { nil } {
		panic('memory allocation failure')
	}
	unsafe {
		*(&int(p)) = value
	}
	return &OwnedBox{
		owned: vcraft.own(p, pointer_free)
		value: value
	}
}

// owned_is_set reports whether the handle still owns its pointer.
@[vc_method]
pub fn (b &OwnedBox) owned_is_set() bool {
	return b.owned.is_set()
}

// release_now releases the handle before dealloc, which is what a caller does when the
// native resource has to go earlier than the object does.
@[vc_method]
pub fn (mut b OwnedBox) release_now() {
	b.owned.release()
}

// ---- an opaque pointer as a capsule -------------------------------------

// new_opaque_box allocates an int and returns it as an opaque handle.
//
// The `voidptr` result would otherwise be read as a borrowed `PyObject *`, so the wrapper
// wraps it in a capsule instead; `@[vc_opaque: 'name']` names the destructor, and without
// one the pointer would live as long as the process.
@[vc_fn]
@[vc_opaque: 'opaque_box_free']
pub fn new_opaque_box(value int) voidptr {
	p := vcraft.native_alloc(usize(sizeof(int)))
	if p == unsafe { nil } {
		panic('memory allocation failure')
	}
	unsafe {
		*(&int(p)) = value
	}
	return p
}

// opaque_box_free releases an opaque box when its capsule is collected.
fn opaque_box_free(capsule voidptr) {
	handle_releases++
	vcraft.native_free(vcraft.handle_data(capsule))
}

// opaque_box_value reads the int an opaque handle carries.
@[vc_fn]
pub fn opaque_box_value(handle voidptr) int {
	p := vcraft.handle_data(handle)
	if p == unsafe { nil } {
		return 0
	}
	return unsafe { *(&int(p)) }
}

// chunks splits `data` into `size`-byte slices.
@[vc_fn]
pub fn chunks(data []u8, size int) [][]u8 {
	mut out := [][]u8{}
	mut i := 0
	for i < data.len {
		end := if i + size < data.len { i + size } else { data.len }
		out << data[i..end]
		i += size
	}
	return out
}

// read_box reads the int an opaque handle carries.
//
// The handle arrives as a capsule and the generated glue unwraps it before the call, so
// the function never has to touch `handle_data` itself: `handle` is the pointer the
// capsule held, not the capsule.
@[vc_fn]
@[vc_opaque]
pub fn read_box(handle voidptr) int {
	if handle == unsafe { nil } {
		return 0
	}
	return unsafe { *(&int(handle)) }
}
