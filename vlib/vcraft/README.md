# vcraft runtime

The V half of vcraft: the declarations and helpers that generated glue calls into.
This is the counterpart of PyO3, written in V.

```v
import vcraft

@[vc.fn]
pub fn add(a int, b int) int {
	return a + b
}
```

The code generator turns that into a trampoline that checks the arity, reads the
arguments, calls `add`, and boxes the result. Nothing in this module runs at import
time except what a module's own `PyInit_` asks for.

## Layout

| File              | Contents                                                        |
| ----------------- | --------------------------------------------------------------- |
| `cpython.c.v`     | The CPython declarations, the C struct mirrors, the constants   |
| `cstring.v`       | V string to C string, and the (pointer, length) pairs back      |
| `object.v`        | `PyObj`, the reference type                                      |
| `convert.v`       | `to_py_*` and `from_py_*`                                        |
| `args.v`          | Reading the positional arguments of a call                      |
| `errors.v`        | Exceptions, `error` translation, and the panic guard notes       |
| `module.v`        | Building the module object, and the layout self-check           |
| `c/shim.h`, `c/shim.c` | Accessors for CPython's data symbols                      |

## Seven constraints from the compiler, not from CPython

Each of these shaped the design, and each cost real debugging time. They are the
kind of thing that is invisible until it produces a wrong answer rather than an
error.

### 1. `#include <Python.h>` is mandatory

The V C backend emits **no prototypes** for `fn C.` declarations. Without the real
header in scope, gcc applies the C89 implicit-declaration rule, every CPython call
is treated as returning `int`, and the returned `PyObject *` is truncated from 64
bits to 32. The module loads perfectly and the interpreter segfaults on it.

Worse, V then reports a C compilation error and retries with a bootstrap of the V
compiler itself, which succeeds and hides the real diagnostic. `-new-compiler`
turns that retry off. `scripts/vcraft-v.sh` passes it, which is why the C errors in
this project are readable.

### 2. A `.c.v` file needs its own `module` line

Declarations in a sibling `.c.v` are only visible to the module its `module` line
names. Leave it out and the file parses without complaint while every struct and
function in it is invisible to the rest of the module.

### 3. CPython's data symbols need C accessors

`PyExc_TypeError` and friends are data, not functions, and V cannot name a C
global. `c/shim.c` has one accessor per singleton, and `c/shim.h` is required for
the same reason as point 1. The same applies to macros such as `PY_VERSION_HEX`.

### 4. Generic functions get no forward declaration across modules

A generic function called from another module produces C with an implicit
declaration and fails to compile. This is why there is no shared `guard[T]` for
panic recovery: the guard is inlined into each trampoline instead. It is four
lines, and inlining also removes a call per invocation.

### 5. `mut` receiver methods do not work across modules

Calling a method with a `mut` receiver on a struct imported from another module
generates C that passes the struct **by value** where the callee expects a
pointer:

```
error: incompatible type for argument 1 of 'sub__R__expect'
  sub__R__expect(r, 2);
```

This is why `args.v` is a set of plain functions and there is no reader object with
a `consumed` cursor, which would otherwise have been the natural design. The
generated glue keeps the call state in its own locals and passes the argument index
explicitly.

### 6. A module whose name ends in `_test` is a test file

V treats any file matching `*_test.v` as a test file: it is compiled with the test
harness and its module export is silently dropped. The build appears to succeed and
`import` then fails with "dynamic module does not define module export function".

 `vcraft new` must reject a project name ending in `_test`, and the generator should
 say so rather than let it produce an empty shared object.

### 7. The object header is 16 bytes with the GIL and 32 without it

Free-threaded CPython keeps a thread id, flags, a per-object lock and split
reference counts where the GIL build keeps one count, so `PyObject_HEAD` is twice
the size. Every struct mirrored from a header therefore has two shapes, selected
with `-d vcraft_free_threaded`, which the build passes when the interpreter is
free-threaded.

The failure is a misaligned mirror: `m_name` reads 16 bytes off, the module
imports on a GIL interpreter and segfaults on a free-threaded one inside
`PyUnicode_FromString`, called on what the code believes is the module name and
is really the `m_size` field. Nothing in the frame points at the mirror, which is
why `check_layout` runs on both generated entry points: a drifted mirror becomes
a named SystemError at import instead of a wild pointer.

Related: `$if` in struct-field position is silently ignored by this V version --
both branches vanish and only the remaining fields exist -- so the two shapes are
whole structs under a top-level `$if`, not conditional fields.

## Reference counting

`PyObj` is a plain struct, not a V reference type. If it were a reference, V would
assume it could collect the pointee, and CPython owns every object: one false
positive would be a use-after-free inside the interpreter.

A `PyObj` is a borrowed reference unless the doc comment says otherwise:

| Function            | Effect                                                      |
| ------------------- | ----------------------------------------------------------- |
| `borrow(p)`         | Wrap a pointer the caller does not own                      |
| `steal(p)`          | Adopt an existing new reference                             |
| `o.new_ref()`       | Return an owned reference to the same object                |
| `o.decref()`        | Release one reference; safe on the null pointer             |

## Integers are `int`, not `i64`

V 0.5.2 has a 64-bit `int` that is a **distinct type** from `i64`. A V programmer
writes `int`, so that is what the runtime uses and what the generator hands over as
a parameter type; a function declared with `i64` gets an explicit conversion at the
call site.

`from_py_int` rejects `bool` even though CPython would accept it, because `True`
becoming `1` is almost never what the caller meant.

## Panics

A V `panic` prints a message and calls `exit(1)`, which inside CPython would take
the interpreter down. V's Go-style recovery closes that hole, and the generated glue
inlines the guard:

```v
fn _vcraft_generated__wrap_div(a int, b int) int {
	defer {
		if message := recover() {
			vcraft.raise_runtime_error('panic in V code: ${message}')
		}
	}
	return divide(a, b)
}
```

The wrapper then checks `error_is_set` before returning, so a recovered panic is
reported rather than reaching Python as a half-written result. Panic state is
thread-local, which keeps this correct under free threading.

## Errors

A bare `error('...')` carries only a message, so every `!T` failure becomes a
RuntimeError. That hides real problems: `except ZeroDivisionError` around a call
into a V extension stops matching, because the code raises RuntimeError instead.

The specific exception cannot travel inside the error value. V 0.5.2 rejects a
`return` whose type is not `IError`, and a struct that implements `msg()` is not an
`IError`, so a custom error struct cannot be propagated at all:

```v
struct MyErr { mut: msg string }
fn (e &MyErr) msg() string { return e.msg }

fn boom() IError { return &MyErr{ msg: 'boom' } }   // cannot use `&MyErr` as `IError`
```

A struct literal is not a valid `match` pattern either, and a type assertion is not
allowed in an `if` guard, so neither `match err { ... }` nor `if e := err as
?DomainError` is available for recovering the type.

So the exception is set where the failure happens:

```v
pub fn divide(a f64, b f64) !f64 {
	if b == 0.0 {
		return vcraft.raise_domain(.zero_division_error, 'division by zero')
	}
	return a / b
}
```

and the wrapper leaves an already-set exception alone. That last part is what makes
it work: `raise_from_error` used to overwrite whatever `raise_domain` had set, which
turned every domain failure back into a RuntimeError and hid the bug the mechanism
was added to fix.

A message reaches CPython as a pointer and its length. `PyErr_SetString` wants a
NUL-terminated C string, and a V string has no terminator, so `set_error` used to copy
the message into a fresh buffer first: a malloc, a copy, a free, and a `strlen` inside
CPython, on every exception. `vpy_set_error_utf8` builds the `PyUnicode` from the length
and hands it to `PyErr_SetObject`, so none of that happens. Exception-heavy calls feel it:
`expect_positive` under a `try` went from behind PyO3 to ahead of it.

## Classes: three things that cost an afternoon each

A class is a heap type from `PyType_FromSpec` plus a block of memory holding the V
struct. Getting there turned up four problems worth writing down, because each one
produces a wrong answer rather than an error.

**`PyType_Spec` has no `doc`.** A type's docstring travels in the `Py_tp_doc` slot.
The obvious move is to add `doc` to the V mirror of the spec and set it there, and
that compiles cleanly, because the mirror has five fields either way and V emits no
layout check. It shifts `basicsize`, `flags` and `slots` by one pointer, and
`PyType_FromSpec` dereferences the shifted `slots` and segfaults. Read
`object.h` rather than trusting the shape you assumed.

**C `int` is 32 bits, V `int` is 64.** Every C `int` in a CPython struct mirror is
`i32`. With `int`, `PyTypeSpec.flags` and `.slots` land at the wrong offsets and
CPython reads a garbage pointer. `tp_basicsize` has the same hazard.

**`tp_new` receives the type, not an instance.** The first argument is the
`PyTypeObject *` the call was made on. An implementation that stores its state at
that address and returns it makes `Counter()` hand back the class object itself, and
writes the state over the type. The instance comes from `tp_alloc`, which is
`PyType_GenericAlloc`.

**V wraps a C callback whose parameters are `mut`.** A getset setter written as
`(self voidptr, mut value voidptr)` receives shifted arguments, so `value` arrives as
whatever the wrapper put there. Generated trampolines take plain parameters and copy
into a local when they need to mutate.

Two smaller ones: a getset setter returns `int`, so returning a null `voidptr`
reports *success* and leaves the exception set, which CPython only complains about
much later; and `PyType_Slot.slot` is an `int`, so slot ids go in as `i32` too.

Slot ids come from CPython's `typeslots.h` and are macros, so the runtime repeats the
numbers: `Py_tp_doc` 56, `Py_tp_dealloc` 52, `Py_tp_init` 60, `Py_tp_methods` 64,
`Py_tp_new` 65, `Py_tp_repr` 66, `Py_tp_getset` 73.

Those are the numbers CPython 3.14 happens to use, and nothing in a compiled
extension notices when they change: the type is built, the wrong slots are silently
left unset, and the symptom is a method that does not exist. So they are checked
against the headers rather than trusted:

```console
$ ./scripts/check-slot-ids.sh
Py_tp_doc    56 ok
Py_tp_new    65 ok
...
slot ids match CPython 3.14
```

The same applies to the struct mirrors: `sizeof(PyType_Spec)` is 32 bytes with five
members, and a sixth is not caught by the compiler.

## Comparisons are free functions, not methods

`@[vc_eq]` and `@[vc_hash]` are attached to free functions that take the state
pointers, not to methods. V allows exactly one receiver per method and rejects a second
parameter outright -- the parser reads `&Counter, other` as a second receiver type and
reports `unexpected name 'voidptr', expecting ','` -- so a comparison cannot even name
the other operand. The class is identified by the function's name: `counter_eq` belongs
to `Counter`.

Two things follow from that, and both cost an afternoon:

- **The operator may be declared before its class.** A free function is dispatched from
  the `.fn` arm of the scan, and the struct may be in a later file or later in the same
  one. It is collected into a pending list and attached once every class is known.
- **The dispatch must `continue`, not `return`.** The scan loops over the declarations of
  a file, and a `return` leaves the whole loop: the first `@[vc_eq]` in a file stops every
  declaration after it from being seen, including the class, whose operators then cannot
  be resolved because it was never collected. The symptom is a hash that stays identity
  and an `__eq__` that is never called, with no diagnostic anywhere.

`NotImplemented` has to be the singleton, not the exception class of the same name. The
class is truthy, so `==` reports a class rather than a bool, and every comparison ends in
a TypeError far from the cause. It also has to come through a C accessor: `Py_NotImplemented`
is a macro over `&_Py_NotImplementedStruct`, which V expands before the declaration is
resolved and the compiler then reports "the object called is not a function" from inside
`object.h`.

`PyObject_TypeCheck` is a `static inline` in `object.h`, not an exported symbol, and
under `Py_LIMITED_API` at 3.11 and above it is also a macro wrapping itself. It is
reimplemented in the shim over the exported `PyType_IsSubtype`, which says the same thing
once identity is added.

## Class state

The state lives inside the object, right after the PyObject header, so `tp_basicsize`
is the header plus the class's state struct and no separate allocation or pointer is
needed. `PyType_GenericAlloc` zeroes that memory, and `tp_free` releases the whole
object. Only scalars may live in the state. A V `string` is a pointer into V's heap,
and V's collector does not scan memory CPython allocated, so the string would be
reclaimed while Python still holds it. A class that needs strings marshals them
through a method.

## Persistent native buffers

A `@[vc_buffer]` field is the exception to "scalars only", and it is a narrow one: a
`[]T` of scalars whose backing is allocated with the CPython allocator and owned by hand.
The header of the slice still travels in the state, where V's collector cannot see it;
the backing it points at must not be in V's heap, or the pointer would look unreachable
and be reclaimed while Python held the object.

`vcraft.buffer_new_*` allocates that backing with a small header of its own: the count of
open memoryviews, then the capacity in bytes. The slice it returns is the only kind of
value such a field may hold, and `tp_dealloc` frees it with `buffer_free`, which knows
about the header and is a no-op on a nil pointer. Because the count is in the header,
`buffer_resize_*` can refuse with `BufferError` while a view is open: reallocating moves
the memory a live `Py_buffer` still points at.

The buffer protocol itself is two type slots, `Py_bf_getbuffer` and `Py_bf_releasebuffer`,
which `PyType_FromSpec` routes into `tp_as_buffer`. `bf_getbuffer` takes a reference on the
exporter and records it in the view; that reference, given back when the memoryview is
collected, is the whole reason `memoryview(instance)` is sound where
`PyMemoryView_FromMemory` is not -- the latter does not keep the owner alive. Only the
class's first own buffer gets the slots; a class that merely inherits one is covered by the
base through the type hierarchy.

By default the view is filled with `PyBuffer_FillInfo`, a 1-D byte view (`format "B"`,
`itemsize 1`). A `@[vc_buffer_typed]` field calls `buffer_fill_typed` instead, which fills
the `Py_buffer` by hand the way the exporter below does -- `itemsize` and `format` from the
element, one item per element -- through `vpy_buffer_fill_typed` in `c/shim.c`. Both take
the same reference on the exporter and are written to `view->obj` the same way.

### Exporting a buffer as a memoryview

`buffer_export_*` is the other direction, for a function that returns a slice rather than
storing one. It wraps a native-backed slice in a heap type, `vcraft._BufferExport`, whose
`bf_getbuffer` fills the view and whose finalizer frees the backing. The type is built once
with `PyType_FromSpec` in `c/shim.c` rather than as a static `PyTypeObject`, so it compiles
under the limited API, and the instance carries the data, the owner base and the element
kind as plain fields. `bf_getbuffer` fills the `Py_buffer` by hand instead of with
`PyBuffer_FillInfo`, because the format has to follow the element size (`b/h/i/q`, `f/d`,
`?`); the view is writable and takes a reference on the exporter.

There is no count of open views here, unlike the `@[vc_buffer]` path: the backing is owned
outright by the exporter, not shared with a V object, so the finalizer frees it once
through the same CPython allocator that `buffer_new_*` used. `buffer_export_owner` recovers
the base from the data pointer and the shim frees with `PyObject_Free`. The generator turns
`@[vc_memoryview]` on a slice-returning function into a call to
`buffer_export_<T>(result)`, whose `.ptr` is the `PyObject *` the trampoline returns.

## Native state a class owns

A `@[vc_handle]` field is a `vcraft.Owned`: a pointer together with the function that
releases it. The generated `tp_dealloc` calls `release` on it, so the allocation lives
exactly as long as the instance does, and the field is not a Python attribute.

```v
@[vc_class]
pub struct OwnedBox {
mut:
	@[vc_handle] owned vcraft.Owned
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

fn pointer_free(p voidptr) {
	vcraft.native_free(p)
}
```

The pair is the point, and there is a reason a `voidptr` field is not allowed to be one.
The state block lives in memory CPython allocated, and Boehm does not scan it: a bare
pointer there is a pointer nothing frees, and the object is left holding a dangling address
after the allocation goes. Naming the release next to the pointer is what makes the field
ownable, and `release` is idempotent, which matters because `tp_dealloc` also runs on an
instance whose constructor raised before it set the field. `@[vc_field]` on the same field
is refused: exposing a handle would hand Python a pointer whose owner is the class.

`Owned` is for state that stays native - a socket, a cursor, an arena, a coroutine a
transport is driving. When Python itself has to see the handle, a capsule in a `@[vc_ref]`
field does the same job at the cost of a Python object per handle; see Capsules.

A `voidptr` *result* is not a way to hand back a pointer. The type table reads `voidptr` as
`pyobj`, which means "the pointer to a Python object, passed through untouched" - the
borrowed `PyObject *` side of the fixed signature - so a function returning an `SSL_CTX *`
or a struct of pointers through one hands CPython a pointer to memory that is not an object,
and the first Python operation on the value follows it into a segfault.

`@[vc_opaque]` says that the result is the other thing: the wrapper wraps it in a capsule
instead of passing it through, and `@[vc_opaque: 'free_fn']` names the capsule's destructor,
which runs when Python collects the handle. A `voidptr` *parameter* is left alone - it stays
the borrowed object - because unwrapping one the caller handed over is a decision about the
callee's contract that an annotation on the result cannot make. A function that receives a
capsule calls `handle_data` on it, which is one line at the point of use and says which
parameter is a handle:

```v
// new_context loads what a connection needs and hands it over as an opaque handle.
@[vc_fn]
@[vc_opaque: 'context_free']
pub fn new_context(path string) voidptr {
	return load(path)
}

// context_free releases the handle when Python collects it.
fn context_free(capsule voidptr) {
	unload(vcraft.handle_data(capsule))
}
```

## Capsules

`new_handle` wraps an arbitrary native pointer in an anonymous `PyCapsule` with a
destructor, and `handle_data` recovers it. It is the escape hatch for state that is not a
plain slice, and it needs nothing from the generator: a `@[vc_raw]` function receives the
capsule as an opaque `voidptr` and calls `handle_data` itself. CPython calls the destructor
with the capsule object rather than the stored pointer, so the destructor has to call
`handle_data` to get its pointer back before freeing it.

`@[vc_opaque]` is the same capsule at the generator level: a function whose result is a
`voidptr` gets it wrapped on the way out, and each `voidptr` parameter of such a function
is unwrapped with `handle_data` on the way in. The annotation is what tells the generator
that the pointer is not a borrowed `PyObject *` - without it, a `voidptr` result is the
borrowed side of a fixed signature, and returning a real pointer through it hands CPython
something that is not an object.

A capsule is also how a class owns native state, because a field cannot hold a pointer the
collector would have to keep alive. Store the capsule in a `@[vc_ref]` field: the field
holds an owned reference, the generated `tp_dealloc` drops it, and the capsule's destructor
runs then, on whatever the pointer was. The `new_box`/`box_free` pair in the top-level
README is the whole idiom. What must not happen is the other shape - a bare `voidptr` field,
or a `@[vc_field]` one - because nothing in the object's memory is scanned by V's collector,
and an allocation behind such a field is freed under the class while the class still holds
the pointer to it.

## Calling into C: the declarations, the widths and the member names

V emits no prototype for a `C.` call, and an `#include` does not change that: each function
has to be declared, and the declaration is what decides how the call is compiled.

```v
#include <sys/socket.h>
#include <unistd.h>

fn C.accept4(fd int, addr voidptr, addrlen voidptr, flags int) int
fn C.recv(fd int, buf voidptr, len usize, flags int) isize
fn C.send(fd int, buf voidptr, len usize, flags int) isize
```

Two rules follow from that, and both cost an afternoon when they are missed. The width has
to be right - `recv` returns a `ssize_t`, and declaring it `int` truncates it silently on a
64-bit build - and a macro is not visible at all, so `MSG_NOSIGNAL`, `POLLIN` or a
`POLL*` flag has to be written out as its value with a comment saying which macro it is. An
`#include` of the header that defines the function is still needed for the types.

A C struct declared from V is matched to the *real* struct by name, so the fields have to
carry the C names, not the ones the shape suggests:

```v
struct C.iovec {
	iov_base voidptr
	iov_len  usize
}
```

`base`/`len` compile in V and fail in C with "struct iovec has no member named base". A
struct with a union in it needs `[packed]` and a member wide enough to hold the union -
`[packed] struct C.epoll_event { events u32 data u64 }` is 12 bytes and matches the kernel's
layout, which is what makes `epoll` reachable from V.

One V syntax trap belongs here too: `[]voidptr{a, b}` in code you write yourself is rejected
("array initializer elements must use square brackets"), so an argument array for
`vcraft.call` is built with `<<` into a `mut args := []voidptr{cap: n}`.

## Inherited state is published, not reachable from the receiver

A subclass's state is the base's state followed by the subclass's own struct, all in
the one object. V copies a receiver in before a method call and out after it, so a
method of a subclass is handed a copy of the subclass struct, and the base's bytes are
not in it. `&c` is therefore not the address of the instance's state, and there is no
way for a method to tell from the receiver whether it holds the whole state or half of
it.

So every generated trampoline publishes the state it loaded, plus one pointer per
generation above the class it belongs to, and a method asks for the level it wants:

```v
@[vc_method]
pub fn (mut c BoundedCounter) bump(by int) !int {
	mut base := unsafe { &Counter(vcraft.state_at(1)) }
	// ...
}
```

A level rather than a base pointer because the offsets are not uniform. Each generation's
state is its own base followed by its own struct, so where a generation's struct sits
depends on how many generations are above it: the immediate base of `BoundedCounter` is
at `state.base`, and the immediate base of a class whose base has a base of its own is at
`state.base.self`. The generator computes those addresses, which is the only place that
knows the layout.

The chain is a fixed array of eight, and a per-thread stack of frames saves and restores
it around each call: entering writes the new chain into the next frame and leaves the
parent frame below it untouched, so leaving is a decrement rather than a copy. A nested
call -- a method reaching another instance, or a property read from inside a method --
therefore leaves the outer trampoline pointing at its own state. The frame stack is in
native thread-local storage (`__thread`, not a `Py_tss_t` key, because there are two
lookups per trampoline), and the earlier version allocated a snapshot of the chain with
`PyMem_Malloc` on every call, which cost two allocator calls on every method of a module
that publishes the chain at all.

`fn inherited[T]() &T` would be the tidier spelling and does not compile from a user's
module, for constraint 4 above: no forward declaration is emitted for a generic. The cast
is what is left, and it costs the reader one `unsafe`.

## Instance references

A `&T` parameter and a `&T` result both cross the boundary as the instance
itself, and both lean on the layout above: the class's own struct sits exactly one
base-state into the object, so the offset is the immediate base's `sizeof_*`
helper, which the generator sums into the call rather than reading `tp_basicsize`
(which the limited API hides).

`from_py_instance` checks `is_instance_of` and returns `storage_of(obj)` plus that
offset, so a `&Base` parameter accepts a subclass instance and lands on the base
half of its state.

`instance_ref` is the harder direction. The V function returns a bare pointer and
CPython needs the object that owns it, so the pointer is matched by address
against the receiver and the `&T` arguments of the call -- the only instances a
result can legitimately point at -- and the one that matches is returned with a
new reference. A pointer that matches nothing raises `RuntimeError` rather than
being guessed at, because handing CPython an object it does not own corrupts the
interpreter. The match is an equality of `storage_of(candidate) + offset` against
the pointer, which is why the offset has to be right: one base too far would match
a different object, or nothing.

## Cycle collection

A type holding references to other objects needs three things from CPython: the
`Py_TPFLAGS_HAVE_GC` flag, a `tp_traverse` that reports what it holds, and a `tp_clear`
that lets it go. Two of them have a trap that costs an afternoon each.

**The type object is collectable too.** The flag marks the type, not just its instances,
so CPython calls `tp_traverse` and `tp_clear` on the type itself. The bytes after a type's
header are its dict, not V state, so a trampoline that reads them as one sends the
collector into whatever the dict points at. `is_type_object` tells the two apart and
hands the type case to CPython's own implementation of `type`.

**`PyObject_GC_UnTrack` assumes a collectable allocation.** It reads a header that only
exists on memory the collector allocated. Called on an instance of a class that holds no
references -- and so never got the flag -- it reads the first word of the payload as a
linked-list pointer, and the next collection walks into whatever that was. The guard is
inside the accessor, because every generated deallocator calls it and only some of those
classes are collectable.

Under the stable ABI the type object's own traverse has to come through
`PyType_GetSlot`: `PyTypeObject` is opaque there, so `PyType_Type.tp_traverse` cannot be
reached as a member at all.

## Reference counts on a `@[vc_ref]` field

A `PyObj` is deliberately not a V reference type -- V's collector would try to free
CPython's objects -- so the count is maintained by hand and every operation on it has to
say which direction it moves:

| Operation      | Direction                          |
| -------------- | ---------------------------------- |
| `retain`       | takes one on a borrowed pointer    |
| `set_ref`      | takes one on a setter's value      |
| `incref`       | takes one on a `PyObj` already held |
| `clear_ref`    | gives one back                     |

A property setter's value is *borrowed*, which is the one that is easy to get wrong:
storing the pointer without counting it leaves the field pointing at an object whose last
reference Python has already dropped, and the next allocation reuses that memory. The
symptom is an instance that appears to have a peer, whose peer then turns out to be a
different object that happens to sit at the same address.

## Errors carry the exception out of band, because V erases them

V's error interface is `msg()` and `code()`, and a struct implementing both can be returned
from a `!T` function -- verified, not assumed. But by the time a wrapper sees the value it
is an `IError`, and an `IError` has a message and nothing else. Anything else the error
carried is gone by then.

Three channels exist because of that, and all three go around the erasure rather than
through it:

| Channel                    | Carries                                    | Needs |
| -------------------------- | ------------------------------------------ | ----- |
| `code()` returning `PyExc`  | any builtin exception                      | nothing |
| `raise_custom`             | any Python exception class                 | nothing |
| a `PyObj` field + raiser   | any Python exception class, kept in the value | the generated raiser |

`PyExc.none` is not one of the builtin exceptions -- `pyexc_obj` resolves it to the null
pointer -- so `raise` maps it to a `RuntimeError` and `pyexc_from_code` starts at 1. This
is not defensive: `PyErr_SetString(NULL, msg)` does not check its first argument, it writes
through it, and the interpreter dies inside CPython on a line that mentions neither V nor
the code that asked for it.

## The GIL release pairs exactly once on every path

`allow_threads` and `end_allow_threads` are `PyEval_SaveThread` and
`PyEval_RestoreThread` through the shim, because both are macros V cannot spell. The
generated wrapper guards the deferred restore with a nil check: the fall-through path
restores and nulls the handle, so the deferred restore finds nothing to do, while a
panic unwinds straight into a restore of the handle that is still set. An unbalanced
pair leaves the GIL count wrong and crashes the next thread switch inside CPython --
found the hard way, as a segfault in `PyErr_Occurred` with nothing in the frame
pointing back at the missing re-acquire.

## Acquiring the GIL from a thread V created

`allow_threads` is the way out; `gil_ensure`/`gil_release` are the way in, and `with_gil`
pairs them around a block. A thread V made with `spawn`, or a callback from a C library,
holds no Python thread state at all: `vcraft.call`, `to_py_*` and every `PyObj` need the
GIL, and nothing in V can hand it over. `PyGILState_Ensure` is a no-op when the calling
thread already holds the GIL, so a function may call it defensively rather than knowing
which thread it is on:

```v
spawn fn (callee voidptr, results chan int) {
	vcraft.with_gil(fn [callee, results] () {
		results <- work_with_python(callee)
	})
}(callee, results)
```

The block is the whole point: the `defer` gives the GIL back on the way out, panic
included, which is what a hand-written pair does not do. Two things it does not change:
`@[vc_nogil]` code still may not touch Python, and a thread that holds the GIL and waits
for a thread that needs it deadlocks. Waiting has to release first:

```v
saved := vcraft.allow_threads()
answer := <-results
vcraft.end_allow_threads(saved)
```

That pair is also the reason `with_gil` exists rather than being sugar: a worker V starts
is only reachable if its caller steps out of the way of the GIL first.

## Acquiring and releasing the GIL on purpose

`allow_threads` and `end_allow_threads` are the way out, and `with_gil` and `released` are
the way in and out. A function that is not `@[vc_nogil]` holds the GIL for its whole call,
so a long V-only stretch - a poll, a parse, a compress, a syscall loop - blocks every other
Python thread. `released` is the RAII version of the manual pair, and it is the one that
gets the balance right when the block can panic: the restore runs in a `defer` registered
*after* the `recover` defer, so on a panic the restore fires first and the raise that
follows it already holds the GIL. An unbalanced pair leaves the GIL count wrong and
crashes the next thread switch inside CPython, which is how this was found.

```v
vcraft.released(fn () {
	// Pure V only: no Python calls, no `raise_domain`, no `PyObj`.
})
// The GIL is held here again. A call into Python that follows proves it.
```

The manual pair still has to be used when the release has to span something the block
form cannot - a `poll` with a 1 s timeout that returns without the GIL being restored,
or a `select` between several conditions. The rule for the manual form is the same as for
`released`: release and restore exactly once per path, restore before any Python call, and
never release inside a `@[vc_nogil]` function that is already released.

`with_gil` is the other direction, for a thread V created: it acquires the GIL for a
block and gives it back in a `defer`, panic included. A V thread holds no thread state
until one of the two is called.

## The state chain is per-thread because of `@[vc_nogil]`

With the GIL held, one global chain would do. A released call runs concurrently with a
held one, so two threads in two trampolines would publish into the same slots and each
would read the other's instance. The chain lives in `PyThread_tss_*` storage instead,
keyed once at import under the import lock.

## Buffers alias; the view is what owns the reference

`Py_buffer` is opaque under the limited API, so V never sees one: the shim allocates
it zeroed, acquires with `PyBUF_SIMPLE`, and hands back the pointer and length. The
`[]u8` aliases that memory, and the wrapper's deferred release drops the exporter's
reference on every path. A V slice cannot be built from a pointer by indexing --
`(&u8(p))[..n]` is rejected -- so the slice is assembled by writing `.data` directly,
which is the one field a slice exposes for exactly this.

Generated glue acquires a view for a `[]u8` *argument*. Hand-written V that gets a
bytes-like object back from a call - `vcraft.call` returning what an application built -
uses `bytes_view`, which is the object-shaped counterpart of `bytes_arg`: exact `bytes` is
aliased with no view at all, anything else goes through a view that pins the exporter, and
`release` gives it back. For an exact-`bytes` alias nothing but the caller keeps the
object alive, so a reference to it has to be held for as long as the slice is used; a
server that writes a body straight to a socket is the case it exists for.

## Iterators are two slots and a pair rule

`tp_iter` returns the instance itself after running the `@[vc_iter]` method for its
side effects; `@[vc_next]` produces one item per call and a V error ends it. The two
are required together, because each half alone compiles and then fails at the call
with nothing pointing at the missing annotation.

## The sequence slots are independent

`tp_iter`/`tp_iternext` are a pair, but `sq_length`, `sq_item` and `sq_contains` are not:
a class may fill any subset, and none of them needs another. `sq_length` returns a
`Py_ssize_t` (CPython raises the ValueError for a negative one itself), `sq_item` boxes a
method result like any other, and `sq_contains` returns `1`/`0`/`-1`. The last is the
awkward one: its argument readers signal failure by returning a null object, which an
`int`-returning function cannot do, so the read and the call happen in a per-class helper
that returns the Python bool and `consume_bool` maps it (`-1` for null, after releasing
the object).

## Calling back into Python

`vcraft.call(callee, args)` and `vcraft.call_method(obj, name, args)` run a Python
callable from inside a V function. The arguments are borrowed and the result is a new
reference the caller owns; `call_owned` releases arguments the caller built for the call.
`vpy_call` builds a tuple and calls `PyObject_CallObject`, the one stable-ABI entry point
whose argument count is dynamic. Re-entry is safe: the state chain is a per-thread stack a
trampoline restores on the way out, and a Python exception from the callback is just a
pending exception the trampoline returns null for.

Reading the arguments back is done with `from_py_int_arg(argv, i, func, name)` and its
`string`/`bytes` siblings: they take the trampoline's `argv` pointer and an index, with
the function name and argument name used in the error messages. Their `from_py_*_item`
counterparts read element `i` of a tuple or list that is already in hand, which is what a
function that receives a sequence from Python uses. Both are borrowed, so they do not
release the source.

## Running Python coroutines from V

`vcraft.run_coroutine(coro)` drives a coroutine to completion on the current thread and
returns its result, or the null object with a Python exception set. `vcraft.call_async`
is the composition: it calls the callable and drives the coroutine it returns.

```v
result := vcraft.run_coroutine(coro)
if result.is_null() {
    // the coroutine raised; the exception is pending
    return unsafe { nil }
}
```

The fast path is a single `send(None)`: most awaits in an extension are our own
receive/send, which complete without suspending, so the request finishes in ~1.8 us
instead of the 9.5 us that `loop.run_until_complete` costs. If the coroutine suspends
on real I/O it is driven the rest of the way through the loop.

The GIL is held for the whole call, exactly as for `call`. V can release it with
`released` if it has V-only work to do, but the coroutine itself is not paused while V
works: it has already finished (fast path) or has suspended on a future that V cannot
resume without re-entering the loop. Releasing the GIL *during* a Python await needs
the coroutine to be driven by a loop that is not this thread's, which is a different
feature (`call_async` level 2) and is not implemented yet.

`asyncio.events._set_running_loop` is private and is the only way to make
`asyncio.get_running_loop()` work while the coroutine is being stepped by hand. vcraft
is now the only place that depends on it: an extension that does not reimplement this
function does not depend on it at all.

## Tests


```console
$ ./scripts/build-runtime-tests.sh
$ python3 tests/runtime/test_runtime.py
```

`tests/runtime/vcraft_runtime_check.v` writes the glue by hand, exactly as the
generator will. It is what the generator is checked against, and it lets the runtime
be tested before the generator exists.
