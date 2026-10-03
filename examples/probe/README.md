# Gate 0 probe

A CPython extension module compiled by the V compiler, built and tested by hand.

This exists to prove the assumption the whole project rests on: that
`v -shared` can produce a shared library CPython will load as a native
extension module. Everything else in vcraft is ordinary engineering on top of it.

## Build and test

Nothing is installed. The script uses the `v` already on `PATH` and the CPython
headers that ship with the interpreter.

```console
$ ./scripts/build-probe.sh
$ python3 examples/probe/test_probe.py
```

```
module definition
  ok   module imports
  ok   module __doc__
  ok   extension file name
METH_NOARGS
  ok   answer() == 42
  ok   answer.__doc__
  ok   is a builtin
METH_FASTCALL and argument marshalling
  ok   add(2, 3) == 5
  ok   add(-5, 5) == 0
  ok   add(int, int) docstring
error propagation
  ok   TypeError for 'takes exactly 2'
  ok   TypeError for 'takes exactly 2'
  ok   TypeError for 'cannot be interpreted as'
  ok   TypeError for 'cannot be interpreted as'
dynamic symbol table
  ok   PyInit_probe is exported
  ok   nothing else from the module leaks

gate 0 passed
```

## What it demonstrates

| Capability | How |
| --- | --- |
| Extension module | `@[export: 'PyInit_probe']` on a V function |
| Module creation | `PyModule_Create2` with a runtime-built `PyModuleDef` |
| No-argument builtins | `METH_NOARGS` |
| Argument passing | `METH_FASTCALL`, the convention vcraft generates |
| Error propagation | CPython's own `TypeError` reaches the caller |
| Docstrings | module `m_doc` and per-function `ml_doc` |
| Encapsulation | only `PyInit_probe` and `_v_interface_exports` are exported |

## Three things this cost us to learn

They are load-bearing for the runtime, so they are written down here.

### 1. `#include <Python.h>` is mandatory, not optional

**The V C backend does not emit prototypes for `fn C.` declarations.** Without
the real header in scope, gcc treats a call to `PyModule_Create2` as returning
`int`, because that is the C89 implicit-declaration rule. The returned
`PyObject *` is 64 bits wide but the compiler reads 32, so the module pointer is
truncated and CPython segfaults as soon as it dereferences it.

The failure is nasty to diagnose: V reports a C compilation error, falls back to
the compatibility compiler, that compiler tolerates the implicit declaration,
and the result is a shared object that loads cleanly and then crashes the
interpreter. The generated C contains a bare call with no declaration at all:

```c
return PyModule_Create2((void*)(def), probe__py_api_version);
```

So `vlib/vcraft/cpython.c.v` starts with the include, and so must any module that
binds to CPython.

### 2. A `.c.v` file needs its `module` line

Declarations in a sibling `.c.v` file are only visible to the module that names
it. Drop the `module probe` line and the struct and function declarations
silently vanish: the `.c.v` itself parses without complaint, and the errors show
up in the other file as `unknown struct` and `unknown function`.

### 3. C data symbols need a companion header

CPython publishes its builtin exception types as data, not functions:

```c
PyAPI_DATA(PyTypeObject *) PyExc_TypeError;
```

V cannot name a C global, so the runtime needs an accessor for each one it
needs, in a small C file pulled in with `#flag @VMODROOT/c/shim.c`. Because of
point 1, that C file needs a header too, or the same implicit-declaration
truncation applies to the accessor itself. `src/c/shim.h` and `src/c/shim.c` are
the pattern the runtime will generalise.

## Layout

```
examples/probe/
├── src/
│   ├── v.mod
│   ├── probe.v          the module and the PyInit_ export
│   ├── probe.c.v        the CPython declarations and struct mirrors
│   └── c/
│       ├── shim.h       prototypes for the accessors
│       └── shim.c       accessors for CPython data symbols
└── test_probe.py        stdlib-only checks
```

The struct mirrors use `voidptr` for every pointer-like member and keep their
fields in a `mut:` section. V's ownership rules would otherwise demand
initialisers for reference-typed fields, and a zero-initialised literal has to
be able to produce C's all-zero `PyMethodDef` terminator.
