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
| `@[vc_nogil]`    | `pub fn`        | Call with the GIL released                             |
| `@[vc_memoryview]`| `pub fn`, methods | Return a native slice as a writable `memoryview`     |
| `@[vc_class]`  | `pub struct`    | Expose the struct as a Python type                     |
| `@[vc_method]`| methods         | Add the method to its receiver's class                 |
| `@[vc_field]`  | struct fields   | Expose the field as an instance attribute              |
| `@[vc_buffer]` | struct fields   | A persistent native `[]T` of scalars, freed at dealloc  |
| `@[vc_property]` | methods       | Register the method as a Python `property`             |
| `@[vc_static]` | methods         | Register the method as a `staticmethod`                |
| `@[vc_classmethod]` | methods    | Register the method as a `classmethod` (`METH_CLASS`)   |
| `@[vc_len]`    | methods         | Fill `sq_length` (`__len__`)                            |
| `@[vc_getitem]`| methods         | Fill `sq_item` (`__getitem__`)                          |
| `@[vc_contains]`| methods        | Fill `sq_contains` (`__contains__`)                     |
| `@[vc_eq]`     | `pub fn`        | Fill `tp_richcompare`'s `==`/`!=`                       |
| `@[vc_lt]`, `@[vc_le]`, `@[vc_gt]`, `@[vc_ge]` | `pub fn` | Fill the matching ordering operator in `tp_richcompare` |
| `@[vc_add]`, `@[vc_sub]`, `@[vc_mul]`, `@[vc_truediv]`, `@[vc_floordiv]`, `@[vc_mod]`, `@[vc_pow]`, `@[vc_lshift]`, `@[vc_rshift]`, `@[vc_and]`, `@[vc_or]`, `@[vc_xor]` | `pub fn` | Fill the matching `nb_*` number slot |
| `@[vc_radd]`, `@[vc_rsub]`, … | `pub fn` | The reflected form of a binary operator |
| `@[vc_neg]`, `@[vc_pos]`, `@[vc_abs]`, `@[vc_invert]` | `pub fn` | Fill the matching unary `nb_*` slot |
| `@[vc_hash]`   | `pub fn`        | Fill `tp_hash`                                          |
| `@[vc_const]`  | `pub const`     | Expose the literal as a module attribute                |

## Protocols, classmethods and constants

`@[vc_len]`, `@[vc_getitem]` and `@[vc_contains]` are methods that fill the `sq_*` slots
(`link_sequences` names the trampolines, `emit_class_sequences` writes them). They are
independent — a class may define any subset — and unlike `@[vc_iter]`/`@[vc_next]` none
needs another. `__contains__` is the awkward one to emit: its slot returns an `int`, and
the argument readers' error paths return a null object, so the work happens in a small
per-class helper that returns the Python bool and a one-line slot maps it with
`vcraft.consume_bool` (null is `-1`, `True` is `1`, `False` is `0`).

The four ordering operators share `tp_richcompare` with `@[vc_eq]`. Like `@[vc_eq]` they
are free functions over two state pointers, so `assign_operator` matches the class by the
function's name prefix and the emitter dispatches on CPython's operator id; an operator a
class does not define returns `NotImplemented`, which lets Python try the reflected side.

The numeric operators fill the `nb_*` slots (`emit_class_numeric` writes the trampolines,
`numeric_slots_expr` names them in the spec). They differ from the comparison operators in
two ways. Their operand and result types decide how the trampoline marshals, so
`assign_numeric` keeps each built function rather than a name. And CPython calls the *same*
slot with the operands swapped when the instance is the right operand (`2 + counter`), so
the trampoline inspects both `left` and `right` and picks the reflected function, with a
commutative operator falling back to its forward one. A result that is the class itself is
copied into a freshly allocated instance, the same path `tp_new` takes.

`@[vc_classmethod]` is collected on V's `.fn` path (V reports `fn Class.name` as
`Class@static@name`) and differs from `@[vc_static]` only in the method flag:
`vcraft.meth_class` makes CPython pass the class as `self`.

`@[vc_const]` is a `pub const` whose value is read from the source line at generation
time, so it has to be a literal (`const_kind` classifies int, float, bool and str); the
boxed value is attached in `exec` with `add_object_owned`, which steals the reference.

The names carry a `vc_` prefix rather than a namespace because **V rejects two
annotations that share one**. `@[vc.fn]` and `@[vc.raw]` on the same declaration is
`error: duplicate attribute 'vc'`, so the prefix has to be part of the name.

An unknown `vc_` annotation is a diagnostic, not a shrug. A silently ignored
annotation means a function quietly missing from the module, which is much worse
than a failed build.

## Constructors and native buffers

`new_<Class>` is the class's `tp_new`. When it declares parameters, `tp_new` binds the
positional tuple and the keyword dict CPython passes there with `vcraft.bind_new_args`,
reads each parameter exactly as a method reads a vectorcall argument, and passes them to
the constructor.

A subclass's state is built base first, so its `tp_new` binds the base's parameters too
and `newstate` forwards them: `Class.newstate_params` is the base's list followed by the
class's own, and `base_ctor_count` says where the split is. `newstate` hands the leading
`base_ctor_count` to the base's state constructor and the rest to the class's `new_*`
function, which therefore declares only the class's own parameters. Both sets travel in
the one Python signature the subclass binds, so a name shared by the base and the
subclass is a diagnostic.

`tp_new` is written for the common positional call. Its argument slots are a fixed array
on the stack (`mut bound := unsafe { [N]voidptr{} }`, which V lowers to `void* bound[N]`),
not a `[]voidptr{len: ...}` slice the collector has to allocate, and the parameter-name
and optional arrays are module-level globals (`emit_bind_globals`, the same ones a
function uses) rather than literals rebuilt on every construction. A base-less class's
`newstate` returns the constructor's value directly, so the state is not zeroed and copied
twice.

A field annotation is read from the field's own line; V also accepts one on the line
above, where it would be silently ignored. `collect_fields` warns for a stray
`@[vc_field]`/`@[vc_ref]`/`@[vc_buffer]` there and names the field.

A `@[vc_buffer]` field is a `[]T` of scalars. The generator emits its free into the same
`tp_dealloc` that releases the reference fields, installs the buffer protocol over the
class's first such field (its own, not an inherited one), and prints its length in the
repr rather than its contents. The backing belongs to the runtime's `buffer_new_*`
helpers: only their values may be stored in such a field.

`@[vc_buffer_typed]`, written beside `@[vc_buffer]` and only accepted with it, makes that
buffer's `memoryview(instance)` a typed view (`emit_class_buffer_slots` calls the
runtime's `buffer_fill_typed` with the element's `buffer_kind` and width) instead of the
default byte view. The two annotations share one `@[...]` block with a `;`, which
`parse_attr_names` splits on along with `,` and `:`.

`@[vc_memoryview]` is the return-side counterpart: a modifier on a `@[vc_fn]` or
`@[vc_method]` whose result is a slice of scalars. The generator emits
`vcraft.buffer_export_<T>(result)` instead of boxing the elements, so the caller gets a
`memoryview` over the same memory and the stub and signature say `memoryview`. It is
refused on `@[vc_raw]`, and on a result that is not a `.seq` or `.bytes` of a buffer
scalar.

## Instance references

A parameter or result typed `&T`, where `T` is a `@[vc_class]`, is resolved by
`link_instances`, which runs after `link_bases` has ordered the classes and before the
`new_*` functions are dropped from `p.funcs` (so a constructor parameter can be a `&T`
too). `link_instance_params` sets `instance_target`, `instance_handle` and
`instance_offset` on the `Param`; `link_instance_result` sets the matching fields on the
`Func`. A `&T` whose `T` is not a class is a diagnostic here, not in `validate`:
`validate` leaves a `&T` alone because whether it names a class cannot be known until
every class has been collected.

`instance_layout` gives the offset as the immediate base's generated `sizeof_*`, not the
sum of every ancestor: the state nests (`CState { base BState; self C }`), so a class's
own struct sits exactly one base-state into the object, whatever class the instance
really is.

`param_reader` reads a `&T` with `vcraft.from_py_instance`, keeping the borrowed object
in `arg<i>_obj` so a result of the same call can be resolved against it;
`instance_result_expr` builds the candidate list from the receiver and those objects and
calls `vcraft.instance_ref`. A plain function (no receiver) whose result is `&T` with no
`&T` parameter has nothing to resolve against and is refused.

## What the generator refuses

A type with no marshalling rule is a diagnostic naming the file, line and column:

```
src/lib.v:12:1: error: cannot expose `add`: type `map[string]int` of parameter
`lookup` has no marshalling rule
```

So is a `@[vc_method]` method whose receiver is not a `@[vc_class]`, a class
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
