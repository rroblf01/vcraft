# Type marshalling

Every type that crosses the boundary has one rule, both ways. A type with no rule is a
compile-time diagnostic pointing at the exact file, line and column, never a runtime
surprise.

| V type | Python type | Notes |
| --- | --- | --- |
| `bool` | `bool` | Any object in, true/false out |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int` | Range-checked: out of range raises `OverflowError`; `bool` and `int` subclasses (an `IntEnum`) are accepted, as in Python |
| `u8`, `u16`, `u32`, `u64`, `usize` | `int` | Negative or out of range raises `OverflowError` |
| `f32`, `f64` | `float` | An `int` is accepted too |
| `rune` | `int` | The code point |
| `string` | `str` | UTF-8; borrowed in, valid for the call |
| `[]u8` | `bytes` | Any bytes-like object in, without copying it |
| `[]T` | `list` | Any sequence in (a list, a tuple); a list out |
| `[N]T` | `list` | Any sequence of exactly N items in; a list out |
| `?T` | `T` or `None` | `none` is `None`, both ways |
| `map[K]T`, `K` a scalar or `string` | `dict` | Scalar or `str` keys; a new dict out |
| `(A, B, …)`, as a result | `tuple` | A multi-value return |
| `voidptr` | any object | Borrowed; you own the reference |
| `vcraft.PyObj` (result) | any object | Owned; the reference goes to the caller |
| `&T`, where `T` is a `@[vc_class]` | `T` | An instance reference; accepts a subclass |
| an `enum` the project declares | that `enum.IntEnum` | Members keep their names and values |
| a plain `struct` the project declares | `dict` | Field names as keys |
| `void`, `!void` | `None` | |
| `!T` | `T`, or raises | See [Errors and panics](errors.md) |


## Arrow columns

| V | Python | Notes |
| --- | --- | --- |
| `vcraft.ArrowArray` (parameter) | any object with `__arrow_c_array__` or `__arrow_c_stream__` | pyarrow arrays read in place; polars Series and chunked arrays copied once; numbers and strings (`utf8`, `large_utf8`, `utf8_view`) |
| `vcraft.ArrowOut` (result) | an object with `__arrow_c_array__` | `pyarrow.array(x)` and `polars.Series(x)` adopt it without a copy; build it with `vcraft.arrow_f64/i64/i32/strings` |

## Scalar width

A narrow integer is range-checked on the way in: `t_i8(128)` raises `OverflowError`, and
so does a field assigned out of range. That is the difference between a marshalling rule
and a cast.

## Composites nest

A container nests, both ways, so `?[]int`, `[][]int`, `map[string][]int` and a struct
field of any of them cross as nested `list`/`dict`/`None`. A returned container is boxed
element by element; a parameter reads through the same rules.

## Enums

A V `enum` the project declares becomes an `enum.IntEnum` of the same name, attached to
the module. A value reads back as the member, and an integer that is not a member raises
`ValueError` on the way in. Member values are read from the source, so an explicit `= n`
is honoured.

## Plain structs

A `struct` that is not `@[vc_class]` becomes a `dict` of its fields. A field is boxed by
its own rule and read back by name, so a missing key is a `KeyError` and a wrong field
type a `TypeError`. A field with no rule, at any depth, is a diagnostic.

## Instance references

A `&T` where `T` is a `@[vc_class]` passes the instance itself, not a copy: a parameter
hands the V function a pointer into the instance's live state, and a result is matched back
to the instance it points into. See [Classes and properties](classes.md).

## Structs, struct sequences and sumtypes

A plain `struct` crosses out as a `dict`. In, it also accepts a namedtuple or any tuple of
its fields in order, and an object that stores them as attributes (a dataclass, a
`SimpleNamespace`). `@[vc_structseq]` on the struct makes it cross out as a struct sequence
-- a tuple with named fields, like `os.stat_result` -- which is cheaper than a dict and is
typed as a `NamedTuple` in the stub.

A sumtype (`type Shape = int | string | Point`) crosses as the variant it holds and is read
by trying the variants: a `bool` only for a real `bool`, integers before floats, then the
declared order. The stub types it as a union.

## Dates, decimals, big integers and JSON

`time.Time` is a `datetime.datetime` (naive both ways; an aware one is converted to UTC
on the way in) and `time.Duration` a `datetime.timedelta`. `vcraft.Decimal` is a
`decimal.Decimal` kept exactly as its text. `big.Integer` is a Python `int` of any size.
`json2.Any` takes any JSON-shaped value -- None, bool, int, float, str, lists and str-keyed
dicts -- recursively, both ways. The glue imports `time`, `math.big` or `json2` only when a
signature uses them.

## NumPy and N-dimensional arrays

`vcraft.NdArray` as a parameter takes any buffer exporter (a NumPy array, `array.array`,
`memoryview`) without copying and without depending on NumPy, with its `kind`, `shape`,
`strides`, `readonly` and `c_contiguous`. `f64s()`, `f32s()`, `i64s()`, `i32s()` and
`u8s()` alias a C-contiguous array as a V slice; `at_f64(i, j)` follows the strides of
any other. `vcraft.NdOut` as a result (`vcraft.nd_out_f64(shape)`) is returned as an
N-dimensional `memoryview` that `numpy.asarray` wraps without a copy.

## Borrowed strings

A `str` is not copied on the way in. A `string` parameter, the items of a `[]string`, the
keys and values of a `map[string]T` and the value a property setter or `__setitem__`
receives all point into the `str` object's own UTF-8 buffer. They are valid for the call,
including while `@[vc_nogil]` has the GIL released, because the caller holds the `str`.
Anything kept past the call - in a map, a struct field, a global, a channel - has to be
copied with `.clone()` first, or it points at memory Python frees once the `str` goes.
Under `@[vc_nogil]`, the items of a list another thread mutates during the call can also
go away mid-call.

## Zero-copy helpers

The other rules above copy numbers and build new containers. Three helpers exist for the
hot path where a copy of a buffer is not acceptable:

- `vcraft.bytes_arg` (for a `[]u8` parameter) aliases the argument without copying: exact
  `bytes` costs nothing, anything else goes through a view whose reference pins the
  exporter. The slice must not outlive the call.
- `vcraft.bytes_view` does the same for a bytes-like value Python *returned* from a call.
  An exact `bytes` is aliased (the caller keeps the object alive for as long as the
  slice is used); anything else goes through a view that pins the exporter. `release`
  gives it back.
- `vcraft.to_py_bytes_slice` is the other direction and copies, because Python `bytes`
  owns immutable storage. A zero-copy return to Python is `@[vc_memoryview]`, which hands
  the native-backed slice over as a writable `memoryview`.

## Scope-based reference management

`vcraft.with_py_scope(fn (mut scope vcraft.PyScope) {})` runs a block with a fresh scope
that tracks every `PyObj` passed to `scope.track(o)` and releases them all when the block
exits, on every path including a panic. `scope.keep(o)` removes a reference from the
tracked set so it survives the scope. Use it for a function that builds several temporary
Python objects and returns one of them.

## GIL helpers

- `vcraft.with_gil(fn () {})` acquires the GIL for a block and gives it back on every
  path, panic included. Use it inside a V thread created with `spawn` before touching
  Python.
- `vcraft.released(fn () {})` is the mirror image: it runs a block with the GIL *released*,
  for V-only work, and re-acquires it in a `defer`. The block must not call Python.
  Note that releasing the GIL lets other threads run the same block concurrently, so a
  `mut` field they both touch is a data race: the GIL protects Python objects, not V
  memory. Guard shared V state with a mutex, or keep the mutation under `with_gil`.
- `vcraft.gil_ensure()` / `vcraft.gil_release(state)` are the manual pair, for the cases
  the block forms cannot cover (a `poll` with a timeout, a choice between conditions).

## Calling Python coroutines

`vcraft.run_coroutine(coro)` and `vcraft.call_async(callee, args)` drive a Python coroutine
to completion on the current thread. The fast path is a single `send(None)` (~1.8 us); the
loop is only entered when the coroutine suspends. The GIL stays held for the whole call, so
V can release it with `released` around V-only work, but the coroutine itself is not paused
while V works. See `examples/async_callback` for the canonical use.
