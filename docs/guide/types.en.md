# Type marshalling

Every type that crosses the boundary has one rule, both ways. A type with no rule is a
compile-time diagnostic pointing at the exact file, line and column, never a runtime
surprise.

| V type | Python type | Notes |
| --- | --- | --- |
| `bool` | `bool` | Any object in, true/false out |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int` | Range-checked: out of range raises `OverflowError` |
| `u8`, `u16`, `u32`, `u64`, `usize` | `int` | Negative or out of range raises `OverflowError` |
| `f32`, `f64` | `float` | An `int` is accepted too |
| `rune` | `int` | The code point |
| `string` | `str` | UTF-8 |
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

## Zero-copy helpers

The marshalling rules above copy. Three helpers exist for the hot path where a copy is
not acceptable:

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
