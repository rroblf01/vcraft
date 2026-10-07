# vcraft_codegen

Turns annotated V declarations into the glue CPython needs, plus a `.pyi` stub.

```v
// Adds two integers and returns the sum.
@[vc_fn]
pub fn add(a int, b int) int {
	return a + b
}
```

becomes

```v
@[export: 'PyInit_hello_native']
fn vcraft_generated__pyinit() voidptr {
	mut m := vcraft.new_module('hello_native', 'Adds two integers and returns the sum.')
	m.add_function_owned('add', voidptr(vcraft_generated__wrap_add), vcraft.meth_fastcall,
		'add(a: int, b: int) -> int')
	return m.seal().ptr
}

fn vcraft_generated__wrap_add(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('add', 2, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	arg0 := vcraft.from_py_int_arg(args, 0, 'add', 'a') or { return unsafe { nil } }
	arg1 := vcraft.from_py_int_arg(args, 1, 'add', 'b') or { return unsafe { nil } }
	vcraft.reject_extra_args('add', 2, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	mut result := 0
	defer {
		if message := recover() {
			vcraft.raise_panic(message)
		}
	}
	result = add(arg0, arg1)
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}
```

The output is V, in the user's own module, and it is meant to be read. When
something goes wrong at three in the morning, this is what you read.

## Layout

| File         | Contents                                                     |
| ------------ | ------------------------------------------------------------ |
| `model.v`    | The annotation vocabulary and the model the scan produces    |
| `scan.v`     | Reading annotations and doc comments out of the source text  |
| `types.v`    | The type table: what each V type marshals to                 |
| `collect.v`  | Walking the parsed project into the model                    |
| `emit.v`     | Rendering the glue and the stub                              |
| `generate.v` | The entry point: read a project, return the files to write   |

## How the annotations are found

V keeps declaration attributes in the type checker, not in the parse tree, so a tool
that works on the tree cannot see them. V's own `v.astquery` documents the same
limitation and advises reading the source, which is what `scan.v` does.

Reading the text is not a workaround with a cost, it is better than the alternative
for a second reason: `v.astquery` also fails to attach a doc comment when an
annotation sits between the comment and the declaration, which is exactly the shape
vcraft asks for.

```v
// Adds two integers.
@[vc_fn]
pub fn add(a int, b int) int
```

So both the annotation block and the docstring are read in one pass upwards from the
declaration, and the module's `__doc__` and the Python `__doc__` come from the same
place as the stub a type checker reads.

## The vocabulary

| Annotation     | Applies to      | Effect                                                |
| -------------- | --------------- | ----------------------------------------------------- |
| `@[vc_fn]`     | `pub fn`        | Exports the function as a module-level callable        |
| `@[vc_raw]`    | `pub fn`        | No conversion: `voidptr` in, `voidptr` out            |
| `@[vc_gil]`    | `pub fn`        | Call with the GIL released                             |
| `@[vc_class]`  | `pub struct`    | Expose the struct as a Python type                     |
| `@[vc_methods]`| methods         | Add the method to its receiver's class                 |
| `@[vc_field]`  | struct fields   | Expose the field as an instance attribute              |
| `@[vc_property]` | methods       | Register the method as a Python `property`             |
| `@[vc_static]` | methods         | Register the method as a `staticmethod`                |

The names carry a `vc_` prefix rather than a namespace because **V rejects two
annotations that share one**. `@[vc.fn]` and `@[vc.raw]` on the same declaration is
`error: duplicate attribute 'vc'`, so the prefix has to be part of the name.

An unknown `vc_` annotation is a diagnostic, not a shrug. A silently ignored
annotation means a function quietly missing from the module, which is much worse
than a failed build.

## What the generator refuses

A type with no marshalling rule is a diagnostic naming the file, line and column:

```
src/lib.v:12:1: error: cannot expose `add`: type `map[string]int` of parameter
`lookup` has no marshalling rule
```

So is a `@[vc_methods]` method whose receiver is not a `@[vc_class]`, a class
declared twice, and a declaration whose signature cannot be read. The scan collects
every diagnostic and reports them all at once, so a project with five mistakes takes
one build to fix rather than five.

## Five things the first working version got wrong

Kept here because each one cost a build, and each is a property of V or of the C API
rather than an oversight.

**V has no `is` test for a Result.** The first version emitted

```v
outcome := greet(arg0)
if outcome is IError { ... }
```

which is `error: 'is' can only be used with sum type or interface values, not
'!string'`. Error propagation is the mechanism instead, and it hands `err` over
directly:

```v
result := greet(arg0) or {
	vcraft.raise_from_error(err)
	return unsafe { nil }
}
```

**A sequence parameter cannot be one generic helper.** `[]T` has to become a V slice
of `T`, and the obvious `from_py_seq[T]` does not compile, because V emits no forward
declaration for a generic called across modules. There is one non-generic reader per
element type instead: `from_py_int_seq_arg`, `from_py_f64_seq_arg`,
`from_py_str_seq_arg`, `from_py_uint_seq_arg`.

**`@[vc_raw]` mistypes its argument.** The declared parameter is `voidptr` and the
reader hands over a `PyObj`, and V's automatic referencing converts between the two
without complaint, producing C that passes a struct where a pointer belongs. The
conversion is now explicit with `from_py_voidptr`.

**A raw result is borrowed.** Returning the pointer as-is makes the call work and the
interpreter crash on exit, which is a memorable way to find a missing reference. The
wrapper takes it: `vcraft.borrow(result).new_ref().ptr`.

**Annotations cannot share a namespace.** Covered above.

## Tests

```console
$ ./scripts/build-example.sh hello hello_native
$ python3 tests/codegen/test_codegen.py
```

`tests/codegen/test_codegen.py` runs the real generator, checks the shape of the glue
it produced, then runs the real compiler and exercises the module that came out.
`examples/hello` is a working project with seven annotated functions covering
scalars, strings, a sequence, a void return, error propagation and the raw escape
hatch.

## Project layout

V 0.5.2 no longer treats `src/` as a module root by itself, so a project declares it
through `base_url`:

```toml
Module {
	name: 'hello_native'
	base_url: 'src'
	requires: ['vcraft']
}
```

Without that, `v -shared src/` fails with `the virtual 'src/' module directory is no
longer supported`. `vcraft new` writes it.
