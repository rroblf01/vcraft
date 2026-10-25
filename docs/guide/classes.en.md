# Classes and properties

A `@[vc_class]` struct becomes a Python type backed by the V struct. The state lives
inside the object (after the PyObject header), so construction pays one allocation and a
method follows no pointer.

## Fields

`@[vc_field]` exposes a field as a read/write attribute. Fields must be scalars (or an
instance reference, see below): a `string` or a `[]T` held in CPython-owned memory would be
a pointer V's collector cannot see. Strings belong behind methods, which marshal to and
from `str`.

```v
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
	@[vc_field] step  int
}
```

## Native state

A field that is not a scalar (a `string`, a `[]T`) cannot live in CPython-owned
memory: V's collector does not scan it. `@[vc_handle]` on a `vcraft.Owned` field owns
native state instead - a pointer together with the function that releases it, released by
the generated `tp_dealloc`. `release` is idempotent, which matters because `tp_dealloc`
also runs on instances whose constructor raised.

```v
@[vc_class]
pub struct Listener {
mut:
	@[vc_handle] socket vcraft.Owned
}
```

When Python itself has to see the handle, a capsule in a `@[vc_ref]` field does the same
job at the cost of a Python object per handle (see `vlib/vcraft/README.md`).

## Constructors


`new_<class>` is the constructor, run in `tp_new`. It may take arguments, bound with the
same marshalling rules as a method. An instance is made by calling the type:

```v
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{ step: 1 }
}
```

## Methods and properties

A method's receiver names its class. `@[vc_property]` makes it a read-only attribute;
`@[vc_static]` and `@[vc_classmethod]` are the two class-level forms.

```v
@[vc_method]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}

@[vc_method]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}
```

## Inheritance

`@[vc_base]` makes a class inherit another. The state is the base's struct followed by the
subclass's, so a base method reads the same bytes on a subclass instance and a chain is
published to CPython's collector.

## Instance references

A `&T` parameter or result passes the instance itself. A parameter gives the V function a
pointer into the instance's live state, so it reads and writes the same bytes a method
would; a result is handed back as the instance the pointer belongs to, matched by address
against the receiver and the `&T` arguments of the call.

```v
@[vc_method]
pub fn (c &Counter) self_ref() &Counter {
	return c
}
```

A `&T` result that points anywhere else raises `RuntimeError`: vcraft will not guess at an
object it does not own.

## Operators

`@[vc_eq]`, `@[vc_lt]` and the rest fill the comparison slots. The numeric operators
(`@[vc_add]`, `@[vc_mul]`, `@[vc_neg]`, …) fill CPython's number slots: an operator is a
free function whose name starts with the class's snake_case name and whose first parameter
is `&T`.

```v
@[vc_add]
pub fn counter_add(a &Counter, n int) Counter {
	return Counter{ value: a.value + n, step: a.step }
}
```

A scalar on the left (`2 + counter`) reaches the reflected `@[vc_radd]`-style function, or
the forward one for a commutative operator. See the
[annotation reference](../reference/annotations.md).
