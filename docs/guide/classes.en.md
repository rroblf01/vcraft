# Classes and properties

A `@[vc_class]` struct becomes a Python type backed by the V struct. The state lives
inside the object (after the PyObject header), so construction pays one allocation and a
method follows no pointer.

## Fields

`@[vc_field]` exposes a field as a read/write attribute, of any type vcraft converts:
scalars, `string`, lists, maps, structs. A class with only scalar fields keeps its state
inside the object. One with a field V's collector manages -- a `string`, a `[]T`, a map,
exposed or not -- keeps it in a block the collector scans, which the object points at and
frees at dealloc, so the string cannot be reclaimed while Python holds the instance. A
string a constructor, a `mut` method or a setter stores is copied for it, since what
Python passes is borrowed for the call.

```v
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
	@[vc_field] step  int
}
```


### Constructors from the fields

`@[vc_class: 'init']` generates the constructor from the exposed fields, as a dataclass
does: `Point3(1.0, label='origin')`, each field optional with its zero value as default
(`0`, `0.0`, `False`, `''`, `[]`, `{}`). A class that writes its own `new_*` keeps it.

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

State the collector manages - a V struct with maps, arrays, a mutex or a channel - goes
in the same kind of field through `vcraft.own_gc`, which registers the pointer as a
collector root until the instance is released. Each instance owns its own, so a process
can hold any number of them:

```v
@[vc_class]
pub struct Server {
mut:
	@[vc_handle] hub vcraft.Owned
}

@[vc_fn]
pub fn new_server() &Server {
	return &Server{
		hub: vcraft.own_gc(&Hub{})
	}
}
```

The state is read back with `unsafe { &Hub(s.hub.get()) }`.

When Python itself has to see the handle, a capsule in a `@[vc_ref]` field does the same
job at the cost of a Python object per handle (see `vlib/vcraft/README.md`).

## Pickling and copying

An instance whose whole state is exposed attributes pickles and copies (`pickle`,
`copy.copy`, `copy.deepcopy`): the generated `__reduce__` saves the attributes, and the
module's `_vcraft_rebuild` assigns them back through the setters without running the
constructor. A Python subclass's own attributes come along. A class with a native buffer,
a handle or a field Python cannot see refuses with a `TypeError` naming it.

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
