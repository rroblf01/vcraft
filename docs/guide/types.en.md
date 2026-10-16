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
