# Annotations

The API of a vcraft extension is a V source file. You mark the declarations Python should
see with `@[vc_*]` annotations; the generator reads them from the source and writes the
glue, the type stubs and the module.

```v
module my_extension_native

import vcraft

// greet returns a greeting for `name`.
//
// The doc comment becomes the Python `__doc__`.
@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}

// Counter is a class. Fields are scalars and become read/write attributes;
// methods become methods; a property becomes a read-only attribute.
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
	@[vc_field] step  int
}

// new_counter is the constructor. An instance is made by calling the type.
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
```

## How the names work

Python names are taken from the V declaration, verbatim. A method's receiver declares the
class it belongs to, and `new_<class>` is the constructor. Doc comments become `__doc__`,
the marshalled signature becomes `__text_signature__`, and the same source produces a
`.pyi` stub, so `help()` and a type checker see the same thing.

## The vocabulary at a glance

| Annotation | Applies to | Effect |
| --- | --- | --- |
| `@[vc_fn]` | `pub fn` | Exports the function as a module-level callable |
| `@[vc_class]` | `pub struct` | Creates a Python type backed by the V struct |
| `@[vc_method]` | methods | Adds the method to the class of its receiver |
| `@[vc_field]` | struct fields | Exposes the field as an attribute |
| `@[vc_property]` | methods | Registers the method as a Python `property` |
| `@[vc_static]` | methods | Registers the method as a `staticmethod` |
| `@[vc_classmethod]` | methods | Registers the method as a `classmethod` |
| `@[vc_base]` | `pub struct` | Inherits the named class |
| `@[vc_ref]` | struct fields | A strong reference to another instance |
| `@[vc_weakref]` | `pub struct` | Allows `weakref.ref(instance)` on instances of the class |
| `@[vc_dict]` | `pub struct` | Gives instances an arbitrary-attribute `__dict__` |
| `@[vc_buffer]` | struct fields | A persistent native `[]T` of scalars |
| `@[vc_error]` | `pub struct` | A `!T` error type with a `msg()`/`code()` |
| `@[vc_len]` / `@[vc_getitem]` / `@[vc_setitem]` / `@[vc_contains]` | methods | `len()`, `obj[i]`, `obj[i] = v`, `x in obj` |
| `@[vc_mapping]` | `pub struct` | Enables the mapping protocol (`obj[key]`, `obj[key] = v`, `del obj[key]`, `len(obj)`) |
| `@[vc_map_getitem]` / `@[vc_map_setitem]` / `@[vc_map_delitem]` | methods | Mapping protocol handlers |
| `@[vc_iter]` / `@[vc_next]` | methods | `__iter__` / `__next__` |
| `@[vc_eq]` / `@[vc_lt]` … | `pub fn` | Comparison and ordering |
| `@[vc_hash]` | `pub fn` | `__hash__` |
| `@[vc_add]` … `@[vc_invert]` | `pub fn` | Arithmetic, bitwise and unary operators |
| `@[vc_const]` | `pub const` | A module-level constant |
| `@[vc_defaults]` | `pub fn`, methods | Default argument values |
| `@[vc_handle]` | struct fields | Native state the class owns: a pointer plus the function that releases it, freed at dealloc |
| `@[vc_opaque]` | `pub fn` | A `voidptr` result travels as a capsule, and each `voidptr` parameter is unwrapped from one |
| `@[vc_nogil]` | `pub fn` | Runs with the GIL released (methods included) |
| `@[vc_raw]` | `pub fn` | Skips marshalling; you handle `PyObject *` |
| `@[vc_from_py: 'fn']` | `pub fn` | Replaces the standard reader for every parameter with a custom converter |
| `@[vc_into_py: 'fn']` | `pub fn` | Replaces the standard boxing of the result with a custom converter |
| `@[vc_memoryview]` | `pub fn`, methods | Returns a native slice as a writable `memoryview` |

The full list, with the exact signatures each expects, is in the
[annotation reference](../reference/annotations.md).


## Zero-copy arguments and the syscalls pattern

`bytes_arg` is the runtime helper that makes a `[]u8` parameter alias the argument
without copying: an exact `bytes` costs nothing, anything else goes through a view that
pins the exporter, and the slice must not outlive the call. It is the counterpart of
`bytes_view` for results. The generated glue uses it for every `[]u8` parameter, so
hand-written V only needs it when it reads a bytes-like object that Python returned.

`@[vc_nogil]` applies to methods too, not just module functions: a method that only
touches V state can run with the GIL released, and the receiver is a pointer into the
instance's live state just like any other method. Use it together with `vcraft.released`
for the syscalls pattern - a `@[vc_nogil]` function that does the blocking call, and
V-only work wrapped in `released` around it - so a long operation does not stall every
other Python thread. The block passed to `released` must not call Python.

## Next

- [Type marshalling](types.md)
- [Classes and properties](classes.md)
- [Errors and panics](errors.md)
