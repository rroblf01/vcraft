# Type reference

The type table, both directions. Anything not listed is a compile-time diagnostic naming
the file, line and column.

| V type | Python type | Direction and notes |
| --- | --- | --- |
| `bool` | `bool` | Any object in (truth test); `True`/`False` out |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int` | Range-checked in; overflow raises `OverflowError` |
| `u8`, `u16`, `u32`, `u64`, `usize` | `int` | Negative or overflow raises `OverflowError` |
| `f32`, `f64` | `float` | An `int` is accepted |
| `rune` | `int` | The code point |
| `string` | `str` | UTF-8 |
| `[]u8` | `bytes` | Bytes-like in without copying; a new `bytes` out |
| `[]T` | `list` | Any sequence in; a `list` out |
| `[N]T` | `list` | Exactly N items in; a `list` out |
| `?T` | `T` or `None` | `none` ↔ `None` |
| `map[K]T` (`K` scalar or `str`) | `dict` | Scalar/`str` keys; a new `dict` out |
| `(A, B, …)` (result) | `tuple` | Multi-value return only |
| `math.complex.Complex` | `complex` | |
| `voidptr` | any | Borrowed; the reference is yours |
| `vcraft.PyObj` (result) | any | Owned; the reference goes to the caller |
| `&T` (`T` a `@[vc_class]`) | `T` | Instance reference; accepts a subclass |
| an `enum` | that `enum.IntEnum` | Member in/out; a non-member raises `ValueError` |
| a plain `struct` | `dict` | Field names as keys |
| `void`, `!void` | `None` | |
| `!T` | `T` or raises | See [Errors and panics](../guide/errors.md) |

## Composite elements

A container element may itself be a container, an enum or a plain struct: `?[]int`,
`[][]int`, `map[string][]int`, `[]Color`, `[]Point` all cross. The element of `[]u8` is
special-cased to `bytes`; a `u8` element elsewhere has no reader.

## Fields

A `@[vc_class]` field follows the table but is limited to scalars and `@[vc_ref]`
references: a `string` or `[]T` in CPython-owned memory would be a pointer V's collector
cannot see. A plain `struct` field may be any type with a rule, checked recursively.
