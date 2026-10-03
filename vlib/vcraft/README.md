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

## Six constraints from the compiler, not from CPython

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

## Class state

The state block is allocated with `PyObject_Malloc` and freed in `tp_dealloc`. Only
scalars may live in it. A V `string` is a pointer into V's heap, and V's collector
does not scan memory CPython allocated, so the string would be reclaimed while
Python still holds it. A class that needs strings marshals them through a method.

## Tests

```console
$ ./scripts/build-runtime-tests.sh
$ python3 tests/runtime/test_runtime.py
```

`tests/runtime/vcraft_runtime_check.v` writes the glue by hand, exactly as the
generator will. It is what the generator is checked against, and it lets the runtime
be tested before the generator exists.
