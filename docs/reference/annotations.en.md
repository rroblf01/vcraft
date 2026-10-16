# Annotation reference

Every annotation the generator reacts to. Anything else in the `vc_` namespace is a
diagnostic, not a silent omission.

| Annotation | Applies to | Effect |
| --- | --- | --- |
| `@[vc_fn]` | `pub fn` | Exports the function as a module-level callable. `new_<class>` is a constructor. |
| `@[vc_class]` | `pub struct` | Creates a Python type backed by the V struct. |
| `@[vc_method]` | methods | Adds the method to the class of its receiver. |
| `@[vc_field]` | struct fields | Exposes the field as a read/write attribute. Scalars (or `@[vc_ref]`). |
| `@[vc_buffer]` | struct fields | A persistent native `[]T` of scalars, freed at dealloc. |
| `@[vc_buffer_typed]` | struct fields | With `@[vc_buffer]`: expose it as a typed `memoryview`. |
| `@[vc_property]` | methods | Registers the method as a Python `property`. |
| `@[vc_static]` | methods | Registers the method as a `staticmethod`. |
| `@[vc_classmethod]` | methods | Registers the method as a `classmethod`. |
| `@[vc_base]` | `pub struct` | Makes the class inherit the named one. |
| `@[vc_ref]` | struct fields | Exposes the field as a strong reference to another instance. |
| `@[vc_error]` | `pub struct` | Makes the struct usable as the error of a `!T` function. |
| `@[vc_len]` | methods | `__len__` (`len(instance)`, truthiness). No arguments, integer result. |
| `@[vc_getitem]` | methods | `__getitem__` (`instance[i]`). One integer argument. |
| `@[vc_contains]` | methods | `__contains__` (`x in instance`). One argument, bool result. |
| `@[vc_iter]` | methods | Makes the instance its own iterator (`__iter__`). |
| `@[vc_next]` | methods | One item per call (`__next__`). |
| `@[vc_eq]` | `pub fn` | `__eq__` / `__ne__`. |
| `@[vc_lt]`, `@[vc_le]`, `@[vc_gt]`, `@[vc_ge]` | `pub fn` | The matching ordering operator. |
| `@[vc_hash]` | `pub fn` | `__hash__`. |
| `@[vc_add]`, `@[vc_sub]`, `@[vc_mul]`, `@[vc_truediv]`, `@[vc_floordiv]`, `@[vc_mod]`, `@[vc_pow]` | `pub fn` | The matching arithmetic operator. |
| `@[vc_lshift]`, `@[vc_rshift]`, `@[vc_and]`, `@[vc_or]`, `@[vc_xor]` | `pub fn` | The matching bitwise operator. |
| `@[vc_radd]`, `@[vc_rsub]`, … | `pub fn` | The reflected form, reached when the instance is the right operand. |
| `@[vc_neg]`, `@[vc_pos]`, `@[vc_abs]`, `@[vc_invert]` | `pub fn` | The unary operator. |
| `@[vc_const]` | `pub const` | Exposes the constant as a module attribute (int, float, bool or string literal). |
| `@[vc_defaults]` | `pub fn`, methods | Default argument values: `@[vc_defaults: 'step=1, name="x"']`. |
| `@[vc_raw]` | `pub fn` | Skips marshalling; you receive and return `voidptr`. |
| `@[vc_nogil]` | `pub fn` | Runs the call with the GIL released. |
| `@[vc_memoryview]` | `pub fn`, methods | Returns a native slice as a writable `memoryview` (no copy). |

## Signatures

A few annotations expect a specific shape, and the generator reports the mismatch rather
than emitting glue that does not compile.

- **Comparison and ordering** (`@[vc_eq]`, `@[vc_lt]`, …) are free functions over two
  state pointers, because V allows one receiver per method and a comparison needs two
  operands. A method body loads the state with `vcraft.load_state`.
- **`@[vc_hash]`** takes one state pointer and returns an integer.
- **Numeric operators** are free functions `(self &T, operand) -> result`: the operand is a
  scalar (`int`, `u64`, `f64`, `bool`) or another `&T`, and the result is a number or a new
  `T` that vcraft allocates and fills. The name starts with the class's snake_case name.
- **`@[vc_len]`** takes no argument and returns an integer; **`@[vc_getitem]`** takes one
  integer; **`@[vc_contains]`** takes one argument and returns a bool.
- **`@[vc_iter]`** and **`@[vc_next]`** go together: an iterator that cannot produce items
  is a trap, and items without an iterator are unreachable.

## Names

Python names are the V names, verbatim. Doc comments become `__doc__`, the marshalled
signature becomes `__text_signature__`, and the same source writes a `.pyi` stub.
`@[vc_methods]` is the pre-1.0 spelling of `@[vc_method]` and still works, with a warning.
