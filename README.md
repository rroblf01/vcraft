# vcraft

**Native Python extensions written in V.**

[![PyPI](https://img.shields.io/pypi/v/vcraft.svg)](https://pypi.org/project/vcraft/)
[![Python versions](https://img.shields.io/pypi/pyversions/vcraft.svg)](https://pypi.org/project/vcraft/)
[![CI](https://github.com/rroblf01/vcraft/actions/workflows/ci.yml/badge.svg)](https://github.com/rroblf01/vcraft/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/rroblf01/vcraft/blob/main/LICENSE)

`vcraft` is to the [V language](https://vlang.io) what **PyO3 + maturin** is to Rust:
CPython bindings written in V, a code generator that turns annotated V declarations
into a Python API, and a build tool that compiles the result and writes a wheel you
can upload to PyPI. There is no Rust, no C++ and no zlib anywhere in the pipeline.

```v
// src/my_extension.v
module my_extension

// Adds two integers and returns the result.
@[vc_fn]
pub fn add(a int, b int) int {
	return a + b
}
```

```python
>>> import my_extension as m
>>> m.add(2, 3)
5
>>> help(m.add)
add(a: int, b: int) -> int
    Adds two integers and returns the result.
```

## Highlights

- **One annotation per declaration.** `@[vc_fn]`, `@[vc_class]`, `@[vc_method]`,
  `@[vc_field]` and friends become functions, classes, methods and properties, with
  docstrings and a generated `.pyi` stub for type checkers.
- **Fast calls.** The generated glue calls your V functions with their real types
  through `METH_FASTCALL`: no boxing layer, no reflection. Call overhead is on par
  with or below PyO3 in the [benchmarks](#performance).
- **Real Python semantics.** V errors become exceptions (custom exception classes
  included), panics are caught instead of killing the interpreter, classes support
  inheritance, equality, hashing, iteration and garbage-collected reference cycles.
- **Zero-copy and GIL-free.** `[]u8` and `[]string` parameters alias Python's buffers,
  `@[vc_nogil]` releases the GIL around a call, and free-threaded CPython (3.13t,
  3.14t) is supported.
- **Wheels without the toolchain zoo.** `vcraft build` writes the wheel itself
  (DEFLATE, ZIP, RECORD, tags) for regular, abi3 and free-threaded builds,
  manylinux and musllinux, and refuses version combinations that would only fail
  after install.
- **CI included.** `vcraft generate-ci` writes a GitHub Actions matrix that builds,
  installs and imports every wheel, using published manylinux/musllinux images and a
  reusable action.

## Quick start

**1. Install vcraft** (Linux x86_64 or macOS arm64, Python 3.11+):

```console
$ pip install vcraft
$ vcraft --version
```

**2. Install the V compiler.** `pip` ships the tool, not the toolchain, the same way
maturin needs Rust. vcraft needs a V newer than the 0.5.2 release, so it builds the
commit it is tested with into its own cache (about five minutes, once; needs git,
make and a C compiler):

```console
$ vcraft toolchain install
$ vcraft toolchain          # which compiler vcraft uses, and whether it is the pinned one
```

vcraft finds it there by itself. `VCRAFT_V=/path/to/v` uses another V instead.

You also need a C compiler (gcc or clang) and the CPython headers, which most Python
installs already include.

**3. Create, develop and build a project:**

```console
$ vcraft new my_extension
$ cd my_extension
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop                      # build and install into the active venv
$ python -c "import my_extension_native as m; print(m.greet('world'))"
Hello, world!
$ vcraft build --release              # dist/my_extension-0.1.0-cp314-cp314-<platform>.whl
```

**4. Ship it.** `vcraft generate-ci` writes a GitHub Actions workflow that builds a
wheel per supported Python and platform, installs and imports each one, and is ready
to publish to PyPI. See [Continuous integration](#continuous-integration).

## Table of contents

- [Why](#why)
- [How it works](#how-it-works)
- [The annotation vocabulary](#the-annotation-vocabulary)
- [Type marshalling](#type-marshalling)
- [Keyword arguments and defaults](#keyword-arguments-and-defaults)
- [Classes and properties](#classes-and-properties)
- [Errors and panics](#errors-and-panics)
- [The command line](#the-command-line)
- [Wheels](#wheels)
- [Generated project layout](#generated-project-layout)
- [Continuous integration](#continuous-integration)
- [Configuration](#configuration)
- [Performance](#performance)
- [Project status](#project-status)
- [Stability](#stability)
- [Development](#development)
- [Design notes](#design-notes)
- [License](#license)

---

## Why

V compiles to fast native code through a tiny C backend and has no runtime dependencies of its own. That makes it a good fit for native Python extensions, but there has been no equivalent of PyO3: writing to the CPython C API from V means hand-declaring every foreign function, hand-writing the module initialiser, and hand-rolling the wheel.

`vcraft` removes all three chores.

|                    | Rust ecosystem     | vcraft                          |
| ------------------ | ------------------ | ------------------------------- |
| Native bindings    | PyO3               | `vlib/vcraft` (written in V)    |
| Binding generation | `#[pyfunction]`    | `@[vc_fn]`                      |
| Class bindings     | `#[pyclass]`       | `@[vc_class]`                   |
| Error translation  | `Result<T, E>`     | `!T` / `error` / `recover()`    |
| GIL handling       | `Python::detach`   | `@[vc_nogil]`                     |
| Build tool         | maturin            | `vcraft build`                  |
| Local install      | `maturin develop`  | `vcraft develop`                |
| CI                 | `maturin-action`   | `vcraft-action@v1`              |
| Dependency install | `cargo add`        | `v import`                      |

---

## How it works

A CPython extension module is nothing more than a shared library that exports a
single symbol, `PyInit_<name>`. V can already produce exactly that:

```
v -shared -o my_extension/_core.cpython-314-x86_64-linux-gnu.so src/
```

Three properties of V's `-shared` mode make this work cleanly:

1. **Symbol control.** `-shared` compiles with `-fvisibility=hidden` and
   `-Wl,--exclude-libs,ALL`, so only declarations carrying an `@[export: '...']`
   attribute appear in the dynamic symbol table. `PyInit_my_extension` is
   exported; nothing else is.
2. **Automatic lifecycle.** V emits `_vinit_caller` and `_vcleanup_caller` as ELF
   constructors and destructors, so the V runtime and its garbage collector are
   initialised when CPython `dlopen`s the module and torn down when it is unloaded.
   No manual init hook is needed.
3. **No link against `libpython`.** Extension modules leave the `Py*` symbols
   undefined; the dynamic linker resolves them against the already-loaded
   `libpython` in the global scope. This is how every CPython extension works, and
   it is why a wheel built for one CPython minor version stays tied to it.

On top of that, `vcraft` adds a code generator. It parses your V sources,
discovers the annotated declarations, and emits the glue that CPython needs:

```
src/lib.v  ──vcraft codegen──▶  src/_vcraft_generated.v
                                          │
                                          ▼
                         v -shared  ──▶  my_extension/
                                            ├── __init__.py
                                            ├── helpers.py
                                            ├── _stubs.pyi
                                            └── _core.cpython-314-x86_64-linux-gnu.so
                                          │
                                          ▼
                              dist/my_extension-0.1.0-cp314-cp314-linux_x86_64.whl
```

The generated glue is a normal V file. It calls your functions with their real V
types, so a call from Python becomes a direct C call with no intermediate
marshalling layer and no boxing.

---

## The annotation vocabulary

Annotations are read from your source text. V keeps declaration attributes in the
type checker rather than in the parse tree, so `vcraft` reads the `@[...]` block
that immediately precedes each declaration. Any name works; these are the ones
`vcraft` recognises.

| Annotation      | Applies to      | Effect                                                     |
| --------------- | --------------- | ---------------------------------------------------------- |
| `@[vc_fn]`      | `pub fn`        | Exports the function as a module-level Python callable      |
| `@[vc_class]`   | `pub struct`    | Creates a Python type backed by the V struct                |
| `@[vc_method]` | methods         | Adds the method to the class of its receiver                |
| `@[vc_field]`   | struct fields   | Exposes the field as an attribute of the instance           |
| `@[vc_property]`| methods         | Registers the method as a Python `property`                 |
| `@[vc_base]`    | `pub struct`    | Makes the class inherit the named one                       |
| `@[vc_ref]`     | struct fields   | Exposes the field as a strong reference to another instance  |
| `@[vc_error]`   | `pub struct`    | Makes the struct usable as the error of a `!T` function      |
| `@[vc_static]`  | methods         | Registers the method as a `staticmethod`                    |
| `@[vc_defaults]`| `pub fn`, methods | Default values: `@[vc_defaults: 'step=1, name="x"']`     |
| `@[vc_raw]`     | `pub fn`        | Skips marshalling; you receive and return `voidptr` yourself |
| `@[vc_nogil]`     | `pub fn`        | Runs the call with the GIL released                         |
| `@[vc_iter]`    | methods         | Makes the instance its own iterator (`__iter__`)            |
| `@[vc_next]`    | methods         | Produces one item per call (`__next__`)                     |

Names are taken from the V declaration, verbatim. Doc comments become `__doc__`, the
marshalled signature becomes `__text_signature__`, and the same source also produces
a `.pyi` stub, so `help()` and a type checker see the same thing.

The prefix is part of the name rather than a namespace because V rejects two
annotations sharing one: `@[vc.fn]` and `@[vc.raw]` on the same declaration is
`duplicate attribute 'vc'`.

---

## Type marshalling

Values are converted with direct CPython calls whenever a fast path exists — for
example a V `int` becomes `PyLong_AsLongLong`, not a round trip through a
generic value tree.

| V                                     | Python                       | Notes                                              |
| ------------------------------------- | ---------------------------- | -------------------------------------------------- |
| `bool`                                | `bool`                       | Any object in, by its truth value                  |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int`                    | Range-checked: out of range raises OverflowError    |
| `u8`, `u16`, `u32`, `u64`, `usize`    | `int`                        | Negative or out of range raises OverflowError      |
| `f32`, `f64`                          | `float`                      | An `int` is accepted too                           |
| `rune`                                | `int`                        | The code point                                     |
| `string`                              | `str`                        | UTF-8                                              |
| `[]u8`                                | `bytes`                      | Any bytes-like object in, without copying it       |
| `[]T` of the types above, or `string` | `list`                       | Any sequence in (a list, a tuple); a list out      |
| `[N]T` of the types above             | `list`                       | Any sequence of exactly N items in; a list out     |
| `?T` of the types above               | `T` or `None`                | `none` is `None`, both ways                        |
| `map[string]T` of the types above     | `dict`                       | `str` keys; a new dict out                         |
| `(A, B, ...)`, as a result            | `tuple`                      | A multi-value return                               |
| `voidptr`                             | any object                   | Borrowed; you own the reference                    |
| `vcraft.PyObj` (result)               | any object                   | Owned; the reference goes to the caller            |
| `void`, `!void`                       | `None`                       |                                                    |
| `!T`                                  | `T`, or raises               | See [Errors and panics](#errors-and-panics)        |

Fields of a `@[vc_class]` struct and method parameters follow the same table.
Enums, plain structs, V function types, maps with non-string keys, nested
composites (`?[]int`, `map[string][]int`) and class instances (`&T`) as parameters or
results of plain functions are not supported yet; they are on the
[roadmap](ROADMAP.md). A `@[vc_class]` is constructed from Python
with its class, through `new_<class>` when one is declared.

Anything not in this table is a compile-time diagnostic pointing at the exact
file, line and column, not a runtime surprise.

---

## Keyword arguments and defaults

Every parameter can be passed by position or by name, as in a Python function. A `?T`
parameter may be left out and arrives as `none`; any other parameter gets a default
from `@[vc_defaults]`, since V has no default arguments of its own:

```v
// Formats a count, with an optional step and label.
@[vc_fn]
@[vc_defaults: 'step=1, label="item"']
pub fn describe(count int, step int, label string, unit ?string) string {
	suffix := unit or { '' }
	return '${label}: ${count * step}${suffix}'
}
```

```python
>>> m.describe(3)
'item: 3'
>>> m.describe(3, label="box", unit="kg")
'box: 3kg'
>>> m.describe()
TypeError: describe() missing required argument: 'count'
```

Defaults are literals of the parameter's type (a number, `true`/`false`, or a quoted
string), for bool, integer, float and string parameters; anything else is a
diagnostic. A call that passes every parameter by position costs what it did before
keywords existed: one comparison.

---

## Classes and properties

```v
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

// new_counter builds a Counter. It takes no arguments; the convention is that
// `new_<Class>` is the constructor, and an instance is made by calling the type.
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

// is_zero reports whether the value is still zero.
@[vc_method]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}
```

```python
>>> c = m.Counter()
>>> repr(c)
'Counter(value: 0, step: 1)'
>>> c.increment(), c.increment()
(1, 2)
>>> c.step = 5
>>> c.increment()
7
>>> c.is_zero
False
>>> c.value = 100
>>> c
Counter(value: 100, step: 5)
```

A class becomes a CPython heap type created with `PyType_FromSpec`. The state lives
in a block CPython allocates, methods and accessors work on that block in place, and
`tp_dealloc` frees the block.

An `@[vc_eq]` and an `@[vc_hash]` function fill the type's comparison and hash slots.
They are free functions rather than methods, because V allows exactly one receiver per
method and a comparison needs both operands:

<!-- readme-test: continue -->
```v
@[vc_eq]
pub fn counter_eq(a voidptr, b voidptr) bool {
	mut x := Counter{}
	mut y := Counter{}
	vcraft.load_state(a, voidptr(&x), sizeof(Counter))
	vcraft.load_state(b, voidptr(&y), sizeof(Counter))
	return x.value == y.value && x.step == y.step
}

@[vc_hash]
pub fn counter_hash(self voidptr) int {
	mut c := Counter{}
	vcraft.load_state(self, voidptr(&c), sizeof(Counter))
	return c.value * 31 + c.step
}
```

```python
>>> a, b = m.Counter(), m.Counter()
>>> a == b, {a, b}
(True, {Counter(value: 0, step: 1)})
```

The two go together. Python's dicts assume that two objects which compare equal hash the
same, so a value comparison with an identity hash misses every lookup in a set or a dict
key without reporting anything. Only `==` and `!=` reach the function; the ordering
operators return `NotImplemented`, which is what lets Python try the other operand's
reflected method before failing with an error that names the type. Comparing against
another type is `False` rather than a `TypeError`, which is what `NotImplemented` buys.

An `@[vc_field]` becomes a read/write attribute. Assigning the wrong type raises
`TypeError`, and deleting one raises `AttributeError`: both come for free from
registering a setter, rather than from a hand-written check per field. An
`@[vc_property]` method becomes a read-only property, and a plain `@[vc_method]`
method takes arguments like any other exposed function.

The constructor runs in `tp_new` and takes no arguments, so `Counter(1)` is a
`TypeError`. That is deliberate: there is no implied `__init__` signature to keep
in sync with a V constructor that could change shape. Give the constructor
parameters and you would have to keep two signatures aligned by hand.

Docstrings reach `__doc__` on the type, its methods, its properties and its fields.

### Inheritance

`@[vc_base(Name)]` makes a class inherit another. Declaration order does not
matter: a subclass may be written before its base, or in a file that sorts
earlier, and the generator orders the classes itself.

<!-- readme-test: continue -->
```v
@[vc_class]
@[vc_base(Counter)]
pub struct BoundedCounter {
mut:
	@[vc_field] limit int
}

// bump adds `by`, refusing to pass the limit.
//
// The receiver is `BoundedCounter`, which names only `limit`: V has no struct
// inheritance, so `c.value` does not compile here. `vcraft.state_at(1)` is the
// base's own struct inside the live state of the instance the method is running
// on.
@[vc_method]
pub fn (mut c BoundedCounter) bump(by int) !int {
	mut base := unsafe { &Counter(vcraft.state_at(1)) }
	if base.value + by > c.limit {
		return vcraft.raise_domain(.value_error, 'the counter would pass its limit')
	}
	base.value += by
	return base.value
}
```

What Python sees is ordinary single inheritance: one base, the base's fields,
methods and properties on the subclass, the subclass's own alongside them,
`isinstance` in both directions behaving as it should, and a Python subclass on
top of it working too.

Two details are worth knowing.

`state_at` takes a level, not a name. Level 1 is the immediate base, level 2 the
one above it, and so on, so a chain three deep can reach its root from the
grandchild. It is a level rather than a base because the offsets are not uniform:
each generation's state is its own base followed by its own struct, so where a
generation's struct sits depends on how many generations are above it. The
generator computes the address and publishes it; a method asks for the level it
wants. Eight levels is the cap, and a deeper chain is reported as an error rather
than silently truncated.

The pointer is only valid while the method runs. It points into the state block
the trampoline holds, which the trampoline writes back when the method returns.
There is nowhere to put it on the receiver: `&c` is a copy of the subclass struct
and does not contain the base's bytes, so a method cannot tell from it whether it
is holding the whole state or half of it.

```pycon
>>> b = BoundedCounter()
>>> b.value, b.step, b.limit
(0, 1, 0)
>>> b.limit = 10
>>> b.bump(4)
4
>>> b.increment()          # a method of the base
5
>>> repr(b)
'BoundedCounter(value: 5, step: 1, limit: 10)'
>>> isinstance(b, Counter)
True
```

### Reference fields and cycles

`@[vc_ref(Name)]` exposes a field as a strong reference to another instance. The field
is declared `vcraft.PyObj`, because that is what it holds: a pointer and a reference
count, and nothing V's collector would recognise.

```v
@[vc_class]
pub struct Node {
mut:
	@[vc_field] label int
	@[vc_ref(Node)] peer vcraft.PyObj
}

// link makes two nodes point at each other.
//
// `retain`, not `steal`: a function parameter is borrowed, and the field has to keep the
// object alive on its own.
@[vc_method]
pub fn (mut n Node) link(other voidptr) {
	n.peer = vcraft.retain(other)
}
```

A class holding references is created with `Py_TPFLAGS_HAVE_GC` and gets `tp_traverse`
and `tp_clear`, so a cycle of instances is collected rather than leaked. Two details are
load-bearing and neither is obvious.

`Py_TPFLAGS_HAVE_GC` makes the *type object itself* collectable, so CPython calls
`tp_traverse` and `tp_clear` on the type as well as on its instances. A type's bytes after
the header are its dict, not a state block, so both trampolines check whether they were
handed a type and hand that case to CPython before reading anything.

`PyObject_GC_UnTrack` reads a collector header that only exists on a collectable
allocation, so the deallocator's untrack is guarded on the flag. A class with no reference
fields does not set it, and untracking its instances unconditionally crashes several
collections later, inside `PyObject_GC_UnTrack`, with nothing in the frame pointing back.

`__repr__` is guarded with `Py_ReprEnter` for the same reason a cycle needs collecting in
the first place: two nodes that point at each other would otherwise recurse until the C
stack ran out, and the segfault would name neither.

The reference count is maintained by hand, because a `PyObj` is deliberately not a V
reference type. `retain` takes a reference of your own on a borrowed pointer, which is
what a method parameter is; `set_ref` counts one when Python assigns through the property;
`clear_ref` gives it back in `tp_clear` and `tp_dealloc`. A property setter's value is
borrowed, so the field counts its own rather than adopting CPython's.

Weak references are not supported yet: that needs a `tp_weaklistoffset` inside the
instance and registration in `tp_traverse`.

### Custom error types

`@[vc_error]` marks a struct as the error of a `!T` function. V requires `msg()` and
`code()`, and the generator reports the annotation on a struct that has not got both rather
than letting it fail at the V compiler with a message about an interface.

There are three ways for such an error to name its Python exception, and they are not
equivalent.

**`code()` is the exception.** The enum's own numbering is the channel, so nothing else is
needed:

```v
@[vc_error]
pub struct ConfigError {
pub:
	detail string
	line   int
}

pub fn (e ConfigError) msg() string {
	return 'line ${e.line}: ${e.detail}'
}

// The code *is* the exception: `PyExc.value_error` is 2.
pub fn (e ConfigError) code() int {
	return int(vcraft.PyExc(.value_error))
}

@[vc_fn]
pub fn load(text string) !string {
	// ...
	return ConfigError{ detail: 'not a name=value line', line: 1 }
}
```

A code outside the enum is an ordinary error code rather than an exception choice, and
those are common, so anything unrecognised becomes a `RuntimeError`. `code() == 0`, which
is every anonymous `error('...')`, is a `RuntimeError` too: `0` is `PyExc.none`, whose
object is the null pointer, and `PyErr_SetString` writes through it rather than checking.

**`raise_custom` sets an arbitrary class.** For an exception vcraft has no name for,
including one the caller defined in Python:

```v
@[vc_fn]
pub fn parse(text string, missing voidptr) !int {
	if text.len == 0 || !text.bytes().all(it.is_digit()) {
		return vcraft.raise_custom(missing, 'not a number')
	}
	return text.int()
}
```

**A `PyObj` field plus the generated raiser.** To keep the class in the error value rather
than passing it around, one `PyObj` field and the raiser the generator emits:

```v
@[vc_error]
pub struct Rejected {
pub:
	exc    vcraft.PyObj
	detail string
}

pub fn (e Rejected) msg() string { return e.detail }
pub fn (e Rejected) code() int { return 0 }

// generated:
//   fn vcraft_generated__raise_rejected(e Rejected) IError {
//       return vcraft.raise_custom(e.exc.ptr, e.msg())
//   }

@[vc_fn]
pub fn checked(value int, exc voidptr) !int {
	if value < 0 {
		return vcraft_generated__raise_rejected(Rejected{
			exc:    vcraft.borrow(exc)
			detail: 'value must not be negative'
		})
	}
	return value * 2
}
```

Two `PyObj` fields are reported rather than guessed at, since there is no way to tell which
one is the class.

What none of these can do is carry the choice *inside* the error and have the wrapper read
it there: V erases an error to `IError` by the time the wrapper sees it, and an `IError`
has a message and nothing else. That is why `raise_domain` sets the exception at the point
of failure, and why the raiser exists.



### Buffers without copying

A `[]u8` parameter accepts anything bytes-like through the buffer protocol:

```v
// checksum adds every byte it is given.
//
// `bytes`, `bytearray`, `memoryview`: nothing is copied on the way in.
@[vc_fn]
pub fn checksum(data []u8) int {
	mut total := 0
	for b in data {
		total = (total + int(b)) & 0xffffff
	}
	return total
}
```

The wrapper acquires a view, aliases it as a V slice for exactly the call, and
releases it on the way out -- including the error paths, which is why the release
is deferred rather than written after the call. The slice must not outlive the
call: the release drops the exporter's reference, and a stored slice would point
at memory nobody owns. Returns copy the other way, because an immutable Python
`bytes` cannot alias V memory.

### Iterators

`@[vc_iter]` and `@[vc_next]` always come as a pair: an iterator that cannot produce
items fails at the first `next()`, and items without an iterator are unreachable,
so a half pair is reported rather than emitted.

```v
@[vc_class]
pub struct Countdown {
mut:
	@[vc_field] current int
	@[vc_field] start int
}

// rewind resets the countdown, so the same instance can be iterated twice.
@[vc_method]
@[vc_iter]
pub fn (mut c Countdown) rewind() {
	c.current = c.start
}

// next yields the current value and steps down, refusing past zero.
@[vc_method]
@[vc_next]
pub fn (mut c Countdown) advance() !int {
	if c.current <= 0 {
		return vcraft.raise_domain(.stop_iteration, 'no more values')
	}
	c.current--
	return c.current + 1
}
```

```pycon
>>> c = Countdown()
>>> c.start = 3
>>> c.current = 3
>>> list(c)
[3, 2, 1]
```

The instance is its own iterator: `@[vc_iter]` runs for its side effects and the
slot returns the instance itself. `@[vc_next]` produces one item per call, and a V
error ends the iteration -- cleanly for `StopIteration`, loudly for anything else,
which is CPython's own contract for the slot rather than something vcraft
invented.

---

## Errors and panics

A `!T` return becomes a Python exception:

```v
// Greet someone by name.
@[vc_fn]
pub fn greet(name string) !string {
	if name.len == 0 {
		return error('name must not be empty')
	}
	return 'Hello, ${name}!'
}
```

```python
>>> m.greet('')
RuntimeError: name must not be empty
```

A bare `error('...')` carries nothing but a message, so it becomes a
`RuntimeError`. That is right often enough to hide the problem: Python code that
divides by zero expects `ZeroDivisionError`, and an `except ZeroDivisionError`
around a call into a V extension silently stops matching. So a failure that means a
particular exception says so:

```v
// Divides two floats, refusing a zero divisor.
@[vc_fn]
pub fn divide(a f64, b f64) !f64 {
	if b == 0.0 {
		return vcraft.raise_domain(.zero_division_error, 'division by zero')
	}
	return a / b
}
```

```python
>>> m.divide(1.0, 0.0)
ZeroDivisionError: division by zero
```

The exception is chosen where the failure happens rather than in the wrapper,
because V gives a wrapper nothing to choose from: every error arrives as an
`IError` holding a message, and a bare message does not say whether it was a
`ValueError` or a `ZeroDivisionError`. `raise_domain` sets the Python exception and
returns an error, and the wrapper's `error_is_set` check stops the value from
reaching Python as a result. A wrapper never overwrites an exception that is already
set, so the choice survives.

A custom V error struct cannot carry the choice. V 0.5.2 rejects a value whose type
is not `IError`, and a struct that implements `msg()` is not one, so the exception
travels out of band through the pending Python exception instead of inside the error
value.

Argument marshalling failures are separate and never reach your code: a wrong
argument type is a `TypeError` and the wrong number of arguments is a `TypeError`,
both naming the parameter.

### Panics

A V `panic` prints a message and calls `exit(1)`, which inside CPython would take
the whole interpreter down with it. V 0.5 has Go-style recovery, so every generated
wrapper installs a frame:

<!-- readme-test: skip -->
```v
fn _vcraft_generated__wrap_first_char(text string) string {
	defer {
		if message := recover() {
			vcraft.raise_runtime_error('panic in V code: ${message}')
		}
	}
	return first_char(text)
}
```

```python
>>> m.first_char('')
RuntimeError: panic in V code: substr(0, 1) out of bounds (len=0) s=
>>> m.add(2, 3)          # the interpreter is still fine
5
```

A recovered panic is raised rather than reaching Python as a half-written result,
which is what the wrapper's `error_is_set` check after the call is for. Panic state
is thread-local in V, so this stays correct under free threading. A method works on
the instance in place, as a PyO3 method does, so one that panics halfway keeps the
fields it had already written.

The guard is inlined per trampoline rather than shared through a helper. V emits no
forward declaration for a generic function called across modules, so a shared
wrapper fails to compile with an implicit-declaration error.

`@[vc_nogil]` marks a function as pure V with no Python interaction. The GIL is
released around the call, so long-running V code runs in parallel the way
`py.allow_threads` does in PyO3:

```v
// spin burns time in pure V, so threads can prove the GIL is really released.
//
// Nothing in here touches Python, raises, or allocates in a way the collector would
// need the interpreter for.
@[vc_fn]
@[vc_nogil]
pub fn spin(iterations int) int {
	mut total := 0
	for i in 0 .. iterations {
		total = (total + i * 7) & 0x7fffffff
	}
	return total
}
```

```pycon
>>> import threading
>>> threads = [threading.Thread(target=lambda: spin(3000000)) for _ in range(4)]
>>> [t.start() for t in threads]
>>> [t.join() for t in threads]  # each burns its own core
```

The annotation is a promise, not a hint, and the generator cannot verify purity. No
Python calls, no `raise_domain`, no touching a `PyObj` while released:
`raise_domain` sets a Python exception, which without the GIL corrupts the
interpreter state rather than reporting anything. A `!T` function fails with a plain
`error(...)` instead, and the wrapper turns it into an exception after it holds the
GIL again. `@[vc_nogil]` on a `@[vc_raw]` function is refused outright: raw means the
function handles `PyObject *` itself, which is the opposite of pure.

The pairing is exact on every path -- success, `!T` failure, and panic -- because an
unbalanced release corrupts the GIL count and crashes the next thread switch inside
CPython rather than anywhere near the call. And the per-thread state chain (see [reference fields and cycles](#reference-fields-and-cycles)) is what keeps two threads in two
trampolines from publishing into each other's slots: with the GIL held one global
would do, and without it each thread needs its own.

---

## The command line

```
vcraft new <name>            scaffold a V project ready for Python
vcraft build [options]       build a distributable wheel
vcraft develop [options]     build and install an editable pointer by default
vcraft develop --copy        install a plain extension copy instead
vcraft sdist                 build a source distribution
vcraft generate-ci           emit a GitHub Actions workflow into .github/workflows/
vcraft publish               upload the built distributions to PyPI
vcraft info                  show what vcraft resolved for this project
vcraft clean                 remove build output
vcraft version               print the version

build options:
  --release                    compile with -prod
  --abi3 <version>             one wheel usable from CPython <version> onwards (3.11+)
  --interpreter <path>         build against a specific interpreter
  --out-dir <dir>              output directory (default: dist/)
  --platform <tag>             override the platform tag
  --target <name>              cross-compile for a target, e.g. linux-aarch64-gnu
  --manylinux <version>        claim a manylinux policy, e.g. 2_17
  --musllinux <version>        claim a musllinux policy, e.g. 1_2
  --cc <compiler>              C compiler for V to invoke
  --cflags <flags>             extra flags for the C compiler
  --ldflags <flags>            extra flags for the C linker
  --dry-run                    print the build plan without building
  --free-threading             build against a free-threaded interpreter (3.13t+)
  --strip                      strip symbols
  --skip-audit                 do not validate the resulting wheel
  --jobs <n>                   compiler parallelism
  --editable                   point the environment at this build instead of copying
  --copy                       install a copy, which is the opposite of --editable
```

`vcraft` never writes to a system location and never installs anything outside
the project. The V runtime module is located relative to the `vcraft` binary
itself and passed to the compiler with `-path`, so `VMODULES` is left untouched.

A project from scratch, end to end:

```console
$ ./scripts/build-vcraft.sh
$ vcraft new mypkg
$ cd mypkg && vcraft develop
$ python -c "import mypkg_native as m; print(m.greet('world'))"
Hello, world!
```

Packaging configuration lives in `vcraft.toml`, not in `v.mod`. `v.mod` is V's
manifest and names the V module; a wheel also needs a distribution name, a version,
a licence and a `Requires-Python`, and none of those are V's business.

See [`vlib/vcraft_project/README.md`](vlib/vcraft_project/README.md) for the TOML
subset that is parsed, and for the compiler constraints that shaped it.

---

## Wheels

```console
$ vcraft build --release
$ pip install dist/my_extension-0.1.0-cp314-cp314-linux_x86_64.whl
```

A wheel is written from scratch in V: DEFLATE, the ZIP container, `METADATA`, `WHEEL`,
`RECORD` with SHA-256, the compatibility tag, and the file name.

zlib is not linked. It is on most build hosts but not all, and linking it makes the
extension depend on a shared library the manylinux and musllinux images have to agree
on. About 250 lines of fixed-Huffman DEFLATE is cheaper than that or than vendoring
zlib, and the output is read by every unzip. A `.so` compresses to roughly 43%.

`RECORD` carries base64 digests with the URL-safe alphabet and no padding, because pip
compares the string. A hex digest installs and then fails verification on every file.

The details that are easy to get wrong are written up in
[`vlib/vcraft_wheel/README.md`](vlib/vcraft_wheel/README.md). The shortest version:

- The distribution name is **escaped**, a run of `-_.` becoming `_`. The version is
  escaped too, but only its dashes: `-` becomes `_` and `.` stays `.`. Writing `0-1-0`
  looks equivalent because PEP 440 agrees it is the same version, but the installer
  splits the file name on `-` and pip rejects it with "wrong number of parts".
- The `.dist-info` directory is named after the distribution, never the module. pip
  checks this before opening the archive.
- The extension goes at the archive root. A directory named after the module is a
  namespace package, and Python resolves one without opening the files inside it, so
  the wheel installs and then imports as an empty module with `__file__` of `None`.

Hand-written Python under a project's `python/` directory is packaged under the same
relative names; `embed-pyc = true` ships sourceless `.pyc` files instead. `vcraft
develop` is editable by default: it installs a `.pth` pointing at the build output and
the project's Python sources, plus distribution metadata, while `develop --copy`
installs a plain extension copy. `pip install -e .` uses the generated PEP 660 backend.
Editable wheels point at the local build tree and are refused by `vcraft publish`.

### Cross-compilation targets

`--target` names the machine a wheel is built for rather than the one building it.
The canonical form is `<os>-<arch>-<libc>` -- `linux-aarch64-gnu`,
`linux-x86_64-musl`, `macos-arm64`, `windows-amd64` -- and Rust-style triples
like `aarch64-unknown-linux-gnu` are accepted as aliases. There is deliberately
no `universal2`: a fat binary needs two architectures linked together and one
build makes one, so the tag always names the architecture actually built. A Linux
policy is claimed separately and explicitly, because the tag is a statement about
the libc the binary was linked against:

```console
$ vcraft build --target linux-aarch64-gnu --manylinux 2_17
$ vcraft build --target linux-x86_64-musl --musllinux 1_2 --cc x86_64-linux-musl-gcc
```

A target without a policy keeps the plain `linux_<arch>` tag: claiming manylinux is
a statement a build that has not verified its libc must not make. Naming the host's
own target changes nothing -- the wheel is byte-identical to a default build, which
is checked -- and a `--platform` that disagrees with the target is refused rather
than warned about, because the wheel would lie about what it contains.

`--dry-run` prints the resolved OS, architecture, tag, extension suffix and compiler
invocation without touching a toolchain. Planning is pure; compiling is not, so a
target whose cross compiler is not installed verifies this far and fails with the
compiler's name when asked to build for real. Foreign execution -- actually running
an aarch64 or musl wheel -- happens in CI, where the images carry the toolchains.

## Generated project layout

What `vcraft new my_extension` writes:

```
my_extension/
├── vcraft.toml                 packaging configuration (see Configuration)
├── v.mod                       Module { name: 'my_extension' }
├── pyproject.toml              names the PEP 517/660 build backend
├── vcraft_build.py             the backend, emitted by the vcraft that wrote it
├── README.md  .gitignore
└── src/
    └── my_extension_native.v   your code
```

A build adds `src/_vcraft_generated.v` and `python/<module>/_stubs.pyi`, both
generated and git-ignored, and writes wheels to `dist/`. `vcraft generate-ci` adds
`.github/workflows/build.yml`.

Python and V coexist: pure-V packages get a generated `__init__.py` that
re-exports the extension, while mixed packages can put whatever Python they like
next to it. Both land in the same wheel.

---

## Continuous integration

`vcraft generate-ci` writes `.github/workflows/build.yml` for your project:

```console
$ vcraft generate-ci
```

The matrix is derived from `vcraft.toml`:

- **Regular builds:** one wheel per supported CPython from the project's
  `minimum-version` up, for manylinux x86_64 and aarch64 and for macOS arm64.
- **`abi3`:** one wheel per platform covers every CPython from the floor up, plus
  musllinux x86_64 and aarch64.
- **`free-threading`:** 3.13t and 3.14t wheels for Linux and macOS.

Linux wheels are built inside published images that already carry V and vcraft,
`ghcr.io/rroblf01/vcraft-manylinux` (derived from PyPA's `manylinux_2_28`) and
`ghcr.io/rroblf01/vcraft-musllinux` (Alpine), each on a native runner for its
architecture. Every wheel is then installed and imported in the image or
interpreter it was built for before the job passes, so a wheel that would fail on a
user's machine fails in CI instead. See [`docker/README.md`](docker/README.md) for
how the images are built.

The build step uses the vcraft action, which mirrors `maturin-action`. On a runner
it installs vcraft from PyPI and a cached V compiler; with `container:` it runs
inside one of the images instead. Linux and macOS runners are supported; Windows
runners are refused with a clear error.

```yaml
- uses: rroblf01/vcraft/actions/vcraft-action@v1
  with:
    vcraft-version: v0.2.0
    args: build --release
```

vcraft is also a PEP 517 build backend (`pip install .` works), so other
wheel-building tools can drive it, but only the workflow above is tested.

---

## Configuration

Packaging configuration lives in `vcraft.toml` at the project root. `vcraft new`
writes one; `pyproject.toml` only names the build backend.

```toml
[package]
name = "my-extension"
version = "0.1.0"
module = "my_extension"
description = "A Python extension written in V."
license = "MIT"
requires-python = ">=3.11"
readme = "README.md"         # the PyPI project page, rendered as Markdown
keywords = ["fast", "parsing"]
classifiers = ["Programming Language :: Other", "Programming Language :: Python :: 3"]
dependencies = []

[build]
minimum-version = "3.11"     # oldest CPython the CI matrix builds a wheel for
abi3 = "3.11"                # optional: one stable-ABI wheel for 3.11 and newer
free-threading = false       # true: build for a free-threaded CPython (3.13t+)
strip = false
embed-pyc = false
gc-free-space-divisor = 2    # Boehm heap growth: 1 favours speed, 2 memory

[urls]
Source = "https://github.com/me/my-extension"
Issues = "https://github.com/me/my-extension/issues"
```

Before 1.0 the build keys were top-level keys and classifiers were `[[classifier]]`
tables; both are still read throughout 1.x, with a warning saying what to change.

The keys of `[build]`:

| Key               | Default   | Meaning                                                        |
| ----------------- | --------- | -------------------------------------------------------------- |
| `minimum-version` | `"3.11"`  | Oldest CPython `vcraft generate-ci` builds a wheel for          |
| `abi3`            | unset     | Stable-ABI floor for a single portable wheel, `3.11` or newer   |
| `free-threading`  | `false`   | Build for a free-threaded interpreter and declare it GIL-free   |
| `strip`           | `false`   | Strip the extension                                             |
| `embed-pyc`       | `false`   | Ship sourceless `.pyc` files instead of the project's `.py`     |
| `gc-free-space-divisor` | `2` | Boehm heap growth divisor; `1` trades memory for speed       |

In `[package]`, `readme` names the file PyPI shows as the project page (`.md` is
rendered as Markdown, `.rst` as reStructuredText); `vcraft new` writes a
`README.md` and points at it. Classifiers must be ones PyPI knows, or it rejects
the upload: V has none of its own, so use `Programming Language :: Other`. Each
entry of `[urls]` becomes a link in the PyPI sidebar.

`vcraft build` refuses the combinations that would compile and then fail later: an
interpreter older than 3.11, an `abi3` floor below 3.11 or above the interpreter
building it, `abi3` together with `free-threading` (free-threaded CPython has no
stable ABI), and `free-threading` on anything older than 3.13.

---

## Performance

Same thirteen functions implemented with PyO3, vcraft and zig-maturin, plus pure
Python, measured on Python 3.13, macOS arm64. Time per call, lower is better:

| workload | PyO3 | vcraft | pure Python |
|---|---|---|---|
| `add(1, 2)`: call overhead | 28 ns | **23 ns** | 16 ns |
| `greet(name)`: str in, new str out | 54 ns | **34 ns** | 33 ns |
| `fib(25)`: pure compute | 120.2 µs | **119.4 µs** | 5.19 ms |
| `sum_floats(100k)`: list[float] in | 456.6 µs | **133.9 µs** | 778.0 µs |
| `Counter()`: object construction | 37 ns | **34 ns** | 38 ns |
| `c.add(1)`: method call | 28 ns | **22 ns** | 26 ns |
| `count_primes(1e6)`: compute + native alloc | **2.01 ms** | 3.76 ms | 41.60 ms |

The vcraft wheel is the smallest of the three and its clean release build the
fastest. Methodology, every workload, memory use and import time are in
[`benchmark/README.md`](benchmark/README.md) and
[`benchmark/results.md`](benchmark/results.md).

---

## Project status

**Alpha.** The feature set above works and is tested, but until 1.0 a minor release
may change the annotation vocabulary, the `vcraft.toml` keys or the CLI; every
change is listed in the [changelog](CHANGELOG.md).

What is tested on every commit:

- CPython 3.11, 3.12, 3.13 and 3.14 on Linux x86_64, and 3.11 and 3.14 on macOS
  arm64, with the full suite: runtime, code generator, wheel writer, packaging and
  the CLI end to end.
- Free-threaded CPython 3.13t and 3.14t on Linux and 3.14t on macOS, importing with
  the GIL disabled and calling from several threads.

Known limitations:

- **Windows is not supported.** vcraft quotes its compiler arguments for a POSIX
  shell, and the action refuses Windows runners.
- **V has to be built from source** at the pinned commit until V publishes a release
  newer than 0.5.2.
- **aarch64 Linux** wheels and images are built on native runners but are not part
  of the per-commit test matrix.
- Extensions use single-phase initialisation, so a module is shared by all
  subinterpreters.

## Stability

vcraft follows [Semantic Versioning](https://semver.org/). From 1.0, the annotations,
the `vcraft.toml` keys, the CLI commands and options, and the Python behaviour of the
conversions in the type table are the public surface:

- A **minor** release (1.1, 1.2...) only adds to it: new annotations, keys, options and
  types.
- A name that is replaced keeps working for the rest of 1.x, and every use of it draws
  a warning naming its replacement. It is removed in **2.0**, never before.
- Generated glue, the runtime's V API under `vlib/vcraft`, and the wheel's internals
  are not part of the surface: they change whenever the generator needs them to.

Upgrading a 0.x project: [MIGRATING.md](MIGRATING.md). Reporting a vulnerability:
[SECURITY.md](SECURITY.md).

Renamed in 1.0, still accepted with a warning: `@[vc_gil]` (now `@[vc_nogil]`),
`@[vc_methods]` (now `@[vc_method]`), top-level build keys in `vcraft.toml` (now in
`[build]`) and `[[classifier]]` tables (now `classifiers = [...]`).

## Requirements

- Python 3.11 to 3.14, or 3.13t/3.14t for free-threaded builds
- Linux (glibc or musl) or macOS
- A V compiler at the pinned commit: `vcraft toolchain install` builds it
- gcc or clang, and the CPython development headers
- Docker, only to build manylinux or musllinux wheels locally

---

## Development

```console
$ git clone https://github.com/rroblf01/vcraft && cd vcraft
$ ./scripts/build-vcraft.sh            # builds bin/vcraft
```

Each test suite is a standalone, standard-library-only script that builds what it
needs:

```console
$ python3 tests/project/check_toml.py     # vcraft.toml parser
$ python3 tests/packaging/test_pack.py    # the PyPI wheel of vcraft itself
$ python3 tests/wheel/test_wheel.py       # wheel writer, checked with zipfile and pip
$ python3 tests/runtime/test_runtime.py   # the CPython runtime
$ python3 tests/codegen/test_codegen.py   # code generator, end to end
$ python3 tests/memory/test_leaks.py      # no leaked objects, references or memory
$ python3 tests/fuzz/test_fuzz.py         # hostile arguments: no crash, the right exception
$ python3 tests/docs/test_readme.py       # every V example in this README builds
$ scripts/run-sanitized.sh python3 tests/fuzz/test_fuzz.py   # the same under ASan and UBSan (Linux)
$ python3 tests/cli/test_cli.py           # the CLI against real projects and venvs
```

They run against whichever `python3` is first on `PATH`. Inside this repository,
invoke V only through `scripts/vcraft-v.sh`: a bare `v` answers a failed C compile
by bootstrapping the whole compiler, a multi-gigabyte, multi-minute detour, and the
wrapper turns that off and bounds the build's memory.

Releases are cut by pushing tags; see the release workflows in
[`.github/workflows`](.github/workflows).

---

## Design notes

A few decisions worth knowing about, and why they were made.

**The generated glue is V, not a foreign language.** Since the generated file is
compiled by V alongside your code, it can call your functions with their real
types. There is no tagged union, no serialisation step and no reflection at
runtime, so the cost of a call is a C call plus the conversions you asked for.

**The CPython headers are included, never re-declared.** V does not emit
prototypes for `fn C.` declarations, so any module that binds to CPython must
`#include <Python.h>` rather than rely on V to declare them. See finding 1 in
[`examples/probe/README.md`](examples/probe/README.md).

**`METH_FASTCALL` is the default calling convention.** It is the cheapest way
CPython can pass positional arguments, and it lets the generated wrapper read the
arguments as a borrowed pointer array. Functions with parameters are registered
as `METH_FASTCALL | METH_KEYWORDS`: a call that passes every parameter by position uses
the array as it is, and only a call with keywords or left-out parameters is bound into
per-parameter slots first.

**Annotations come from the source text.** V's parse tree does not keep
declaration attributes; they live in the type checker. V's own `v.astquery`
module documents the same limitation and advises reading the source. `vcraft`
therefore parses declarations with `v.astquery` and then reads the `@[...]` block
immediately above each one. It works on files that do not compile, which keeps
error messages about broken annotations useful.

**C struct mirrors use `voidptr` and `mut:`.** V's ownership rules would demand
initialisers for reference-typed fields, and a zero-initialised literal has to be
able to produce C's all-zero sentinels such as the `PyMethodDef` terminator.
Describing pointers as `voidptr` inside a `mut:` section sidesteps both.

**CPython data symbols get C accessors.** `PyExc_TypeError` and friends are
data, not functions, and V cannot name a C global. The runtime ships a small C
file of accessors with a header, pulled in with `#flag @VMODROOT/c/...`.

**The V garbage collector runs inside CPython.** V uses Boehm–Demers–Weiser by
default. It is statically linked into the extension, it does not replace the C
allocator, so it never interferes with CPython's own memory management, and V
0.5.2 already calls `GC_allow_register_threads()` during initialisation, which is
precisely the case of a host-created thread entering V code.

**Extension modules are process-scoped.** `PyInit_` is the single-phase
initialisation API, so a module loaded in one interpreter is shared by all of
them. Subinterpreter support would need the multi-phase API; the generated
glue is structured so that switch is a contained change.

**The runtime API is stateless.** `vcraft/args.v` is a set of plain functions and
the generated glue keeps the call state in its own locals, passing argument indices
explicitly. The obvious design, a reader object with a `consumed` cursor, cannot be
compiled at all: see constraint 5 above.

**Nothing is installed system-wide.** `vcraft` builds into the project's `build/`
and installs into the active virtualenv. The V runtime module ships with `vcraft`
and is passed to the compiler with `-path`, so `VMODULES` is never touched.

**A module name ending in `_test` is rejected.** V would treat the file as a test
file and silently drop its module export. `vcraft new` says so instead of producing
an empty shared object.


### Compiler constraints

Building the first extension uncovered seven V compiler behaviours that produce a
wrong answer rather than an error. They shaped the runtime and are written up in full
in [`vlib/vcraft/README.md`](vlib/vcraft/README.md):

1. The V C backend emits no prototypes for `fn C.` declarations, so a module that
   binds to CPython **must** `#include <Python.h>`. Without it gcc applies the
   implicit `int` return rule, truncates the returned `PyObject *` to 32 bits,
   and the interpreter segfaults on a module that loaded cleanly.
2. A sibling `.c.v` file only exports its declarations to the module named by its
   own `module` line.
3. CPython's builtin exception types are data symbols, so each one needs a small C
   accessor, with a header.
4. A generic function called across modules gets no forward declaration and does
   not compile, so the panic guard is inlined per trampoline instead of shared.
5. A `mut` receiver method on a struct from another module generates C that
   passes the struct by value where a pointer is expected. That rules out a reader
   object with a cursor, and is why the argument helpers take an explicit index.
6. A file matching `*_test.v` is compiled as a V test file and its module export is
   silently dropped.
7. The object header is 16 bytes with the GIL and 32 without it, so every struct
   mirrored from a header has two shapes. The wrong one imports on a GIL
   interpreter and segfaults on a free-threaded one with nothing pointing at the
   mirror.

---

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Ricardo Robles Fernández
