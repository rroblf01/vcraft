# Runtime API

The `vcraft` module every extension imports: conversions, errors, classes, buffers,
callbacks, Arrow and NumPy views, parallel loops, logging. Generated from the doc comments
in `vlib/vcraft` by `scripts/gen-runtime-docs.py`; CI checks it is current.

Functions the generated glue calls are listed too; the ones a project's own code reaches
for are described in the guide pages (errors, classes, types).

## `args.v`

```v
pub fn arg_at(argv voidptr, i int) PyObj
```

arg_at returns the i-th positional argument as a borrowed reference.

It does not bounds-check: the glue calls `require_nargs` first, which raises if
the call is short, so every index it goes on to read is known to be present. A
check per argument would be redundant work on the hot path.

```v
pub fn require_nargs(name string, expected int, given int)
```

arg_count is the number of positional arguments CPython passed. The glue knows
it from the METH_FASTCALL `nargs` parameter, so it is passed in rather than
derived here.

```v
pub fn wrong_nargs(name string, expected int, given int)
```

wrong_nargs raises the TypeError for a call with the wrong number of positional
arguments. The generated glue compares `nargs` itself and only calls this when
the count is wrong, so the success path pays for one comparison.

```v
pub fn reject_extra_args(name string, expected int, given int)
```

reject_extra_args reports a call that passed more arguments than the V function
accepts. Called after the last parameter.

```v
pub fn bind_args(args voidptr, nargs isize, kwnames voidptr, out voidptr, names []string, optional []bool, func string) bool
```

bind_args places the arguments of a METH_FASTCALL | METH_KEYWORDS call in one slot
per parameter, in declaration order, so the readers can take them by index as they
take a positional call's.

`args` holds `nargs` positional values followed by one value per name in `kwnames`, a
tuple of str or null. `out` has `names.len` slots, zeroed by the caller: a slot left
null is a parameter the caller left out, which only an optional one may be. Raises
TypeError, and returns false, for what Python itself refuses: too many positional
arguments, an unknown or repeated keyword, or a missing required parameter.

```v
pub struct CallSplit
```

CallSplit is a call to a function with `*args` or `**kwargs` taken apart: one slot per
fixed parameter (filled only when the caller passed keywords, as `bind_args` does), the
positional arguments past them, and the keywords no fixed parameter takes. Every object
is borrowed from the call.

```v
pub fn split_call(args voidptr, nargs isize, kwnames voidptr, names []string, optional []bool, var_pos bool, var_kw bool, func string) !CallSplit
```

split_call binds a call to a function whose V parameters end with a variadic `...T`
(`var_pos`) and/or a `map[string]T` collecting the remaining keywords (`var_kw`).
`names` and `optional` describe the fixed parameters only. It raises the TypeError
Python would -- too many positional arguments without `*args`, an unknown keyword
without `**kwargs`, a repeated one, a missing required one -- and fails.

```v
pub fn unexpected_kwarg(name string, keyword string)
```

unexpected_kwarg reports an unknown keyword argument.

```v
pub fn arg_present(argv voidptr, nargs isize, kwnames voidptr, i int) bool
```

arg_present reports whether the value for parameter `i` was passed.

With keywords, `argv` is the slot array `bind_args` filled and a parameter left out is
a null slot. A positional-only call has no slot array: `argv` is the argument pointer
array itself and the parameter is present when `i` is before the count. This is what
lets a call that omits trailing parameters read each one without a slot array.

```v
pub fn missing_arg(func string, name string)
```

missing_arg raises the TypeError for a required parameter that was not passed.

The generated glue calls this on the positional path, where `bind_args` -- which raises
the same message for the keyword path -- has not run.

```v
pub fn bind_new_args(args voidptr, kwds voidptr, out voidptr, names []string, optional []bool, func string) bool
```

bind_new_args places the arguments of a `tp_new` call in one slot per parameter, in
declaration order, so the constructor's readers can take them by index exactly as a
method's readers take a METH_FASTCALL call's.

`tp_new` receives the positional arguments as a tuple and the keywords as a dict,
which is not the vectorcall layout `bind_args` reads. Everything else is the same:
`out` has one slot per parameter, zeroed by the caller, a null slot is a parameter the
caller left out (only an optional one may be), and a Python-refused call raises
TypeError and returns false.

```v
pub fn required_arg(argv voidptr, i int, func string, name string) !PyObj
```

required_arg returns positional argument `i`, raising TypeError when it is missing.
The narrow scalar parameters read it through this and then convert it with the
matching `*_from_py_*` narrower.

```v
pub fn from_py_int_arg(argv voidptr, i int, func string, name string) !int
```

from_py_int_arg reads positional argument `i` as an int.

```v
pub fn from_py_uint_arg(argv voidptr, i int, func string, name string) !u64
```

from_py_uint_arg reads positional argument `i` as a u64.

```v
pub fn from_py_f64_arg(argv voidptr, i int, func string, name string) !f64
```

from_py_f64_arg reads positional argument `i` as a float.

```v
pub fn from_py_string_arg(argv voidptr, i int, func string, name string) !string
```

from_py_string_arg reads positional argument `i` as a str.

```v
pub fn from_py_bytes_arg(argv voidptr, i int, func string, name string) !string
```

from_py_bytes_arg reads positional argument `i` as bytes.

```v
pub fn from_py_bool_arg(argv voidptr, i int, func string, name string) !bool
```

from_py_bool_arg reads positional argument `i` as a bool.

```v
pub fn require_arg(argv voidptr, i int, func string, name string) PyObj
```

require_arg returns positional argument `i` as an opaque object, raising if the
call was short. This is the `@[vc.raw]` path, where no type check applies.

```v
pub fn require_voidptr_arg(argv voidptr, i int, func string, name string) voidptr
```

require_voidptr_arg reads a required argument as an opaque handle.

The `voidptr` counterpart of `require_arg`, and used for every parameter typed
`voidptr` or `PyObj` in the generated glue. Handing a `PyObj` to a `voidptr` parameter
happens to work because V dereferences the single-field struct for it, but it warns,
it is documented as going away, and a `PyObj` is one field only by accident.

```v
pub fn seq_arg(argv voidptr, i int, func string, name string) !PyObj
```

seq_arg reads positional argument `i` as a validated sequence, handing the object to a
caller that converts the elements itself. It is what a nested `[]T` parameter needs:
the per-type readers below convert as they read, which only works for a scalar element.

```v
pub fn require_sequence(obj PyObj, name string) !
```

require_sequence raises TypeError unless `obj` is a list or a tuple.

A nested reader calls it before it reads a length: `PyObject_Length` on, say, an int
returns -1 with an error set, and building a slice with that length is a negative
capacity, which panics V rather than raising.

```v
pub fn from_py_int_seq_arg(argv voidptr, i int, func string, name string) ![]int
```

from_py_int_seq_arg reads positional argument `i` as a sequence of ints.

The leading items that are exact ints are converted in one pass in C; whatever is
left, from the first item that is anything else, goes through the general reader,
which raises the usual error for the item that is wrong.

```v
pub fn read_int_fixed(argv voidptr, i int, func string, name string, out voidptr, n int, wide bool) !
```

read_int_fixed reads positional argument `i` straight into a fixed-size array of
`int` or `i64` at `out`, which holds exactly `n` of them, `wide` when an element is
64 bits.

The general `[N]T` path reads the argument into a heap slice and copies it out, an
allocation per call for what is a few machine words on the stack. This writes the
array in place, with the same checks and the same errors: a list or a tuple, exactly
`n` items (ValueError otherwise), each an int in range.

```v
pub fn from_py_i64_seq_arg(argv voidptr, i int, func string, name string) ![]i64
```

from_py_i64_seq_arg reads positional argument `i` as a sequence of i64.

```v
pub fn from_py_f64_seq_arg(argv voidptr, i int, func string, name string) ![]f64
```

from_py_f64_seq_arg reads positional argument `i` as a sequence of floats.

Exact floats and ints convert in one pass in C, the rest one at a time, as in
`from_py_int_seq_arg`.

```v
pub fn from_py_str_seq_arg(argv voidptr, i int, func string, name string) ![]string
```

from_py_str_seq_arg reads positional argument `i` as a sequence of strings.

Each item aliases its str object's buffer instead of copying it (see
`from_py_str_borrowed`): a 10k-item list costs no per-item allocation, only
the join or whatever the function builds from them. The slice must not
outlive the call, because nothing pins the strs past it.

```v
pub fn from_py_uint_seq_arg(argv voidptr, i int, func string, name string) ![]u64
```

from_py_uint_seq_arg reads positional argument `i` as a sequence of unsigned
integers.

```v
pub fn from_py_i8_seq_arg(argv voidptr, i int, func string, name string) ![]i8
```

from_py_i8_seq_arg reads positional argument `i` as a sequence of i8.

```v
pub fn from_py_i16_seq_arg(argv voidptr, i int, func string, name string) ![]i16
```

from_py_i16_seq_arg reads positional argument `i` as a sequence of i16.

```v
pub fn from_py_i32_seq_arg(argv voidptr, i int, func string, name string) ![]i32
```

from_py_i32_seq_arg reads positional argument `i` as a sequence of i32.

```v
pub fn from_py_isize_seq_arg(argv voidptr, i int, func string, name string) ![]isize
```

from_py_isize_seq_arg reads positional argument `i` as a sequence of isize.

```v
pub fn from_py_rune_seq_arg(argv voidptr, i int, func string, name string) ![]rune
```

from_py_rune_seq_arg reads positional argument `i` as a sequence of runes.

```v
pub fn from_py_u16_seq_arg(argv voidptr, i int, func string, name string) ![]u16
```

from_py_u16_seq_arg reads positional argument `i` as a sequence of u16.

```v
pub fn from_py_u32_seq_arg(argv voidptr, i int, func string, name string) ![]u32
```

from_py_u32_seq_arg reads positional argument `i` as a sequence of u32.

```v
pub fn from_py_usize_seq_arg(argv voidptr, i int, func string, name string) ![]usize
```

from_py_usize_seq_arg reads positional argument `i` as a sequence of usize.

```v
pub fn from_py_f32_seq_arg(argv voidptr, i int, func string, name string) ![]f32
```

from_py_f32_seq_arg reads positional argument `i` as a sequence of f32.

```v
pub fn from_py_bool_seq_arg(argv voidptr, i int, func string, name string) ![]bool
```

from_py_bool_seq_arg reads positional argument `i` as a sequence of bools.

## `arrow.v`

```v
pub struct ArrowArray
```

ArrowArray is a borrowed view of one Arrow column, valid for the call. `format` is the
Arrow format string: `g` float64, `f` float32, `l` int64, `i` int32, `s` int16, `c`
int8 (capitals for unsigned), `u` utf8 strings.

```v
pub fn arrow_arg(argv voidptr, i int, func string, name string) !ArrowArray
```

arrow_arg reads positional argument `i` as an Arrow column. Used by the generated
wrapper, which defers `release`.

```v
pub fn arrow_of(obj PyObj) !ArrowArray
```

arrow_of views any object implementing the Arrow PyCapsule interface. Release it.

```v
pub fn (a ArrowArray) release()
```

release lets go of the column; the generated glue calls it after the function.

```v
pub fn (a ArrowArray) is_null(i int) bool
```

is_null reports whether element `i` is null.

```v
pub fn (a ArrowArray) f64s() ![]f64
```

f64s aliases a float64 column as a V slice, without copying. A null reads as whatever
the slot holds (Arrow leaves it unspecified); check `is_null` where nulls matter.

```v
pub fn (a ArrowArray) f32s() ![]f32
```

f32s aliases a float32 column.

```v
pub fn (a ArrowArray) i64s() ![]i64
```

i64s aliases an int64 column.

```v
pub fn (a ArrowArray) i32s() ![]i32
```

i32s aliases an int32 column.

```v
pub fn (a ArrowArray) str_at(i int) !string
```

str_at is element `i` of a utf8 column, borrowed from the column for the call.

```v
pub struct ArrowOut
```

ArrowOut is a column built in V, returned to Python as an object implementing the Arrow
PyCapsule interface (`__arrow_c_array__`), which pyarrow and polars take without a copy.

```v
pub fn arrow_f64(values []f64) ArrowOut
```

arrow_f64 makes a float64 Arrow column from `values`.

```v
pub fn arrow_i64(values []i64) ArrowOut
```

arrow_i64 makes an int64 Arrow column.

```v
pub fn arrow_i32(values []i32) ArrowOut
```

arrow_i32 makes an int32 Arrow column.

```v
pub fn arrow_strings(values []string) ArrowOut
```

arrow_strings makes a utf8 Arrow column.

```v
pub fn arrow_export(o ArrowOut) PyObj
```

arrow_export hands an ArrowOut to Python.

## `async.v`

```v
pub struct AsyncCall
```

AsyncCall is what the worker thread needs to settle one call: the loop and the future,
each an owned reference that `async_settle` releases.

```v
pub fn async_begin() !AsyncCall
```

async_begin returns the running event loop and a new future on it. Called on the
calling thread, with the GIL; outside a running loop it raises RuntimeError, as
`asyncio.get_running_loop()` does.

```v
pub fn async_succeed(call AsyncCall, value PyObj)
```

async_succeed settles the call with `value`, whose reference it takes. The caller holds
the GIL.

```v
pub fn async_fail(call AsyncCall, err IError)
```

async_fail settles the call with the exception `err` stands for, chosen the way a
synchronous call's would be. Takes the GIL itself.

```v
pub fn async_panic(call AsyncCall, message string)
```

async_panic settles the call with the RuntimeError a recovered panic becomes. Takes the
GIL itself: the panic happened in V code running without it.

## `buffer.v`

```v
pub fn buffer_view(argv voidptr, i int, func string, name string) !voidptr
```

buffer_view acquires a buffer-protocol view of positional argument `i`.

Fails with the `TypeError` CPython sets itself when the argument is not bytes-like,
and with a `TypeError` naming the missing argument when there is none. The view is
released with `buffer_release`, and acquiring without releasing leaks the view and
the reference it holds on the exporter.

```v
pub fn buffer_view_of(obj PyObj, name string) !voidptr
```

buffer_view_of acquires a buffer-protocol view of any object, which is what `buffer_view`
does for a positional argument.

It is the shape a hand-written extension needs for an object that did not arrive as an
argument: a value that came back from a call. The view holds a reference on the exporter,
so `buffer_release` is what lets the exporter go. Fails with the `TypeError` CPython sets
itself when the object is not bytes-like.

```v
pub fn buffer_bytes(view voidptr) []u8
```

buffer_bytes aliases a view's bytes as a V slice, without copying.

The slice and the view share the exporter's memory. See the module comment for why
the slice must not outlive the call.

The header is built field by field from an empty literal: allocating `len`
first and then overwriting `data` would abandon a GC block of the argument's
size on every call, which is exactly the garbage a zero-copy path exists to
avoid.

```v
pub fn buffer_release(view voidptr)
```

buffer_release releases a view acquired with `buffer_view`.

Safe on every path, including a view whose acquisition failed and a null view,
because the view is zeroed on allocation. The generated wrapper defers this, so a
call that fails or panics still gives the reference back.

```v
pub struct BytesArg
```

BytesArg is a `[]u8` argument together with whatever keeps it alive for the
call: a buffer view, or nothing for exact `bytes`. `bytes` is immutable and
the argument itself keeps the object alive, so aliasing it needs no view and
pays no acquisition. The generated wrapper holds one, defers `release`, and
reads `data`.

```v
pub fn bytes_arg(argv voidptr, i int, func string, name string) !BytesArg
```

bytes_arg reads positional argument `i` as bytes without copying.

Exact `bytes` aliases the object directly. Anything else bytes-like goes
through `buffer_view`, whose reference pins the exporter. Missing and
non-bytes-like arguments fail exactly as `buffer_view` reports them, so the
slow path stays the single place that shapes those errors.

```v
pub fn (b BytesArg) release()
```

release gives the view back, or nothing for exact `bytes`.

```v
pub fn bytes_view(obj PyObj, name string) !BytesArg
```

bytes_view reads any bytes-like object as a borrowed `[]u8`, without copying.

`bytes_arg` is the argument-shaped version of this and indexes into a vectorcall tuple;
this is the one for a value that came back from a call, which is just an object. Exact
`bytes` is aliased directly -- no view, no acquisition -- and anything else bytes-like
goes through a buffer view, whose reference pins the exporter. `bytes_of`, in cstring.v,
is the lower-level exact-`bytes` pointer+length with no view at all.

The slice aliases memory the caller does not own, so two rules are absolute. For an
exact `bytes` alias nothing but the caller keeps the object alive, so a reference to it
must be held for as long as the slice is used; a view, by contrast, holds its own. And
`release` has to run on every path, success or failure.

Hand-written V is the audience: a `[]u8` parameter already crosses without copying, but
a large buffer that Python built and handed back (`await request.body()`, a cached
response) otherwise costs a copy into a V `string` and another into a `[]u8` before the
server can write it. Generated glue never needs this.

```v
pub fn to_py_bytes_slice(value []u8) PyObj
```

to_py_bytes_slice boxes a V slice as Python bytes, copying it.

Copying because Python `bytes` are immutable and own their storage: there is no
aliasing a V slice into them. For reads the other direction costs nothing; for
writes this is the price of the type.

```v
pub fn native_alloc(nbytes usize) voidptr
```

native_alloc allocates `nbytes` of CPython-owned memory, released with `native_free`.

The block has no header and no view count; it is the raw allocator, for the capsule
escape hatch and anything that is not a `@[vc_buffer]` slice.

```v
pub fn native_free(p voidptr)
```

native_free releases a block allocated with `native_alloc`.

```v
pub fn checksum_bytes(data []u8) u64
```

checksum_bytes sums the bytes of a buffer in C, faster than a V loop.

```v
pub fn sum_i64(data []i64) i64
```

sum_i64 sums a slice of i64 in C.

```v
pub fn sum_f64(data []f64) f64
```

sum_f64 sums a slice of f64 in C.

```v
pub fn buffer_free(p voidptr)
```

buffer_free releases a native buffer. Safe on a nil pointer, which is what an
unallocated or zero-length field holds, and on a buffer with views open: the view count
is for refusing resizes, not frees.

```v
pub fn buffer_views(p voidptr) int
```

buffer_views reports how many memoryviews of a native buffer are open, zero for nil.

```v
pub fn buffer_views_incr(p voidptr)
```

buffer_views_incr is called by a generated `bf_getbuffer` after a successful fill.

```v
pub fn buffer_views_decr(p voidptr)
```

buffer_views_decr is called by a generated `bf_releasebuffer`.

```v
pub fn buffer_fill(view voidptr, exporter voidptr, data voidptr, len_bytes isize, readonly int, flags int) int
```

buffer_fill wraps one contiguous run of bytes in a `Py_buffer`.

`exporter` is the object the view keeps alive: `PyBuffer_FillInfo` takes a reference on
it and `PyBuffer_Release` gives it back, which is the whole reason the memoryview is
sound where `PyMemoryView_FromMemory` is not. Returns CPython's status.

```v
pub fn buffer_fill_typed(view voidptr, exporter voidptr, data voidptr, len_bytes isize, itemsize isize, kind int, readonly int, flags int) int
```

buffer_fill_typed wraps a run of bytes in a typed `Py_buffer`, for a class whose
`@[vc_buffer_typed]` field implements the buffer protocol. `itemsize` is the element's
width and `kind` its family (0 unsigned, 1 signed, 2 float, 3 bool), so the view
reports one item per element with the matching format instead of a byte view.
`PyBuffer_FillInfo`, which only expresses a byte view, backs `buffer_fill` instead.
Returns CPython's status.

```v
pub fn new_handle(value voidptr, destructor voidptr) PyObj
```

new_handle wraps a native pointer in a Python capsule.

The general escape hatch for state that is not a plain slice: a handle from a C library,
a struct full of pointers, anything a class would be overkill for. The capsule owns the
pointer and calls `destructor` when the capsule is collected. CPython passes the
destructor the *capsule object*, not the stored pointer, so the destructor calls
`handle_data(capsule)` to recover it. The capsule is anonymous, so `handle_data` needs
no name that would have to outlive the capsule.

```v
pub fn handle_data(obj voidptr) voidptr
```

handle_data returns the pointer a capsule holds, or nil when `obj` is not one (with a
Python exception set, as `PyCapsule_GetPointer` does).

```v
pub fn buffer_new_bool(n int) []bool
```

buffer_new_bool allocates a native-backed `[]bool` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_bool(s []bool, n int) ![]bool
```

buffer_resize_bool reallocates a native-backed `[]bool`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_int(n int) []int
```

buffer_new_int allocates a native-backed `[]int` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_int(s []int, n int) ![]int
```

buffer_resize_int reallocates a native-backed `[]int`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_i8(n int) []i8
```

buffer_new_i8 allocates a native-backed `[]i8` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_i8(s []i8, n int) ![]i8
```

buffer_resize_i8 reallocates a native-backed `[]i8`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_i16(n int) []i16
```

buffer_new_i16 allocates a native-backed `[]i16` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_i16(s []i16, n int) ![]i16
```

buffer_resize_i16 reallocates a native-backed `[]i16`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_i32(n int) []i32
```

buffer_new_i32 allocates a native-backed `[]i32` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_i32(s []i32, n int) ![]i32
```

buffer_resize_i32 reallocates a native-backed `[]i32`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_i64(n int) []i64
```

buffer_new_i64 allocates a native-backed `[]i64` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_i64(s []i64, n int) ![]i64
```

buffer_resize_i64 reallocates a native-backed `[]i64`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_isize(n int) []isize
```

buffer_new_isize allocates a native-backed `[]isize` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_isize(s []isize, n int) ![]isize
```

buffer_resize_isize reallocates a native-backed `[]isize`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_u8(n int) []u8
```

buffer_new_u8 allocates a native-backed `[]u8` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_u8(s []u8, n int) ![]u8
```

buffer_resize_u8 reallocates a native-backed `[]u8`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_u16(n int) []u16
```

buffer_new_u16 allocates a native-backed `[]u16` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_u16(s []u16, n int) ![]u16
```

buffer_resize_u16 reallocates a native-backed `[]u16`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_u32(n int) []u32
```

buffer_new_u32 allocates a native-backed `[]u32` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_u32(s []u32, n int) ![]u32
```

buffer_resize_u32 reallocates a native-backed `[]u32`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_u64(n int) []u64
```

buffer_new_u64 allocates a native-backed `[]u64` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_u64(s []u64, n int) ![]u64
```

buffer_resize_u64 reallocates a native-backed `[]u64`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_usize(n int) []usize
```

buffer_new_usize allocates a native-backed `[]usize` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_usize(s []usize, n int) ![]usize
```

buffer_resize_usize reallocates a native-backed `[]usize`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_f32(n int) []f32
```

buffer_new_f32 allocates a native-backed `[]f32` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_f32(s []f32, n int) ![]f32
```

buffer_resize_f32 reallocates a native-backed `[]f32`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_new_f64(n int) []f64
```

buffer_new_f64 allocates a native-backed `[]f64` of `n` elements, zero-initialised.

```v
pub fn buffer_resize_f64(s []f64, n int) ![]f64
```

buffer_resize_f64 reallocates a native-backed `[]f64`, or raises BufferError while a
memoryview of it is open. The address may move, so the result must be stored back.

```v
pub fn buffer_export_bool(s []bool) PyObj
```

buffer_export_bool exports a `[]bool` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_int(s []int) PyObj
```

buffer_export_int exports a `[]int` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_i8(s []i8) PyObj
```

buffer_export_i8 exports a `[]i8` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_i16(s []i16) PyObj
```

buffer_export_i16 exports a `[]i16` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_i32(s []i32) PyObj
```

buffer_export_i32 exports a `[]i32` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_i64(s []i64) PyObj
```

buffer_export_i64 exports a `[]i64` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_isize(s []isize) PyObj
```

buffer_export_isize exports a `[]isize` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_u8(s []u8) PyObj
```

buffer_export_u8 exports a `[]u8` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_u16(s []u16) PyObj
```

buffer_export_u16 exports a `[]u16` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_u32(s []u32) PyObj
```

buffer_export_u32 exports a `[]u32` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_u64(s []u64) PyObj
```

buffer_export_u64 exports a `[]u64` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_usize(s []usize) PyObj
```

buffer_export_usize exports a `[]usize` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_f32(s []f32) PyObj
```

buffer_export_f32 exports a `[]f32` as a writable memoryview, transferring ownership.

```v
pub fn buffer_export_f64(s []f64) PyObj
```

buffer_export_f64 exports a `[]f64` as a writable memoryview, transferring ownership.

## `callback.v`

```v
pub fn call(callee voidptr, args []voidptr) PyObj
```

call calls `callee` with the positional `args` and returns a new reference to the
result, or the null object with a Python exception set.

`args` are borrowed: the runtime takes its own reference to each, so the caller keeps
whatever it held and a temporary it built can be released right after. Use `call_owned`
to have the runtime release arguments it was given ownership of.

```v
pub fn call_py(f PyObj, args ...PyObj) PyObj
```

call_py calls the Python callable `f` with `args`, all of them `PyObj` -- the form to
reach for first: no `voidptr`, no `.ptr`, no slice literal to get the element type of
right. The arguments are borrowed, as with `call`; the result is a new reference, or
the null object with an exception set.

r := vcraft.call_py(f, vcraft.to_py_string(word))

```v
pub fn call_method_py(obj PyObj, name string, args ...PyObj) PyObj
```

call_method_py calls `obj.name(*args)` with `PyObj` arguments, borrowed; see `call_py`.

```v
pub fn call_owned(callee voidptr, args []PyObj) PyObj
```

call_owned is `call` for arguments the caller built only for the call and does not
keep: it releases each one after the call, on success or failure.

```v
pub fn call_kw(callee voidptr, args []voidptr, kwargs map[string]PyObj) PyObj
```

call_kw calls `callee` with positional `args` (borrowed) and keyword `kwargs`,
returning a new reference to the result, or the null object with an exception set.

`kwargs` maps keyword names to borrowed values; the runtime builds the dict and
releases its own references to them, so the caller keeps whatever it held.

```v
pub fn call_method_kw(obj voidptr, name string, args []voidptr, kwargs map[string]PyObj) PyObj
```

call_method_kw calls `obj.name(...)` with positional `args` and keyword `kwargs`.

```v
pub fn getattr(obj voidptr, name string) PyObj
```

getattr returns a new reference to `obj`'s attribute `name`, or the null object with a
Python exception set (for example AttributeError). This is how a method is fetched to
pass to `call`.

```v
pub fn setattr(obj voidptr, name string, value PyObj) int
```

setattr sets `obj.name = value`, stealing the caller's reference to `value`.
It returns 0 on success and -1 with a Python exception set on failure.

```v
pub fn hasattr(obj voidptr, name string) bool
```

hasattr reports whether `obj` has an attribute `name`, without raising.

```v
pub fn vpy_get_dict(self voidptr, closure voidptr) PyObj
```

vpy_get_dict and vpy_set_dict are the managed-dict accessors exposed to generated
code. They are thin shims over PyObject_GenericGetDict/SetDict.

```v
pub fn vpy_set_dict(self voidptr, value PyObj, closure voidptr) int
```

```v
pub fn enable_mapping(typ voidptr, mp_length voidptr, mp_subscript voidptr, mp_ass_subscript voidptr)
```

vpy_enable_mapping attaches a mapping protocol to a heap type.

```v
pub fn call_method(obj voidptr, name string, args []voidptr) PyObj
```

call_method calls `obj.name(...)` with the positional `args` (borrowed) and returns a
new reference, or the null object with an exception set.

## `class.v`

```v
pub struct TypeObject
```

TypeObject wraps a heap type created by `PyType_FromSpec`.

```v
pub fn object_header_size() int
```

object_header_size is the size of the PyObject header: 16 bytes with the GIL, 32
on a free-threaded build, where the header carries an extra word.

```v
pub fn instance_basicsize(state_size int, weakref bool, dict bool) int
```

instance_basicsize is the `tp_basicsize` for a class whose state struct is
`state_size` bytes: the PyObject header plus the state itself, which lives inside
the object rather than behind a pointer.

A subclass's state starts with its base's, so its `state_size` is larger and its
`tp_basicsize` is larger with it -- which is what CPython's "tp_basicsize ... too
small for base" check wants.

```v
pub fn type_flags(gc bool, weakref bool, dict bool) u32
```

type_flags is what a vcraft heap type asks for: CPython's own default set plus
Py_TPFLAGS_BASETYPE, so a Python class may subclass it.

`gc` adds `Py_TPFLAGS_HAVE_GC`, which is what makes the collector look at the
instances at all. A class with no reference field leaves it off: the flag costs a
little on every collection and buys nothing for a type that cannot be in a cycle.

```v
pub fn type_alloc(typ voidptr) voidptr
```

type_alloc creates an instance of `typ`.

`tp_new` receives the *type*, not an instance, so the instance has to be
allocated here. Getting this wrong writes the state over the type object and
makes `Class()` return the class itself.

An instance of a boxed class (see `boxed_storage`) gets its zeroed state block here, so
every way an instance comes to exist -- `tp_new`, unpickling, a result built from V, a
Python subclass -- has one before any field is read or written. A module with no boxed
class pays one comparison.

```v
pub fn no_memory() voidptr
```

no_memory raises MemoryError and returns the null pointer, which is what a
`tp_new` must do when it cannot allocate.

It lives here because generated code in a user module cannot call `C.` functions.

```v
pub fn storage_of(obj voidptr) voidptr
```

storage_of returns the address of the state that follows the PyObject header of
`obj`. That memory is part of the object, so it needs no separate allocation and
no pointer to reach it.

```v
pub fn instance_storage(obj voidptr) voidptr
```

instance_storage returns the state of an instance.

The state lives inside the object, so the address is always valid: an instance a
Python subclass produced without running a vcraft constructor still has its state
bytes, zeroed by `PyType_GenericAlloc`. There is no null case to report.

```v
pub fn mark_boxed_type(typ voidptr, size usize)
```

mark_boxed_type registers a type whose instances are boxed, for the readers of `&T`
arguments and results that only have the type to go by.

```v
pub fn boxed_storage(obj voidptr) voidptr
```

boxed_storage returns the state block of an instance of a boxed class.

```v
pub fn box_new(obj voidptr, size usize)
```

box_new gives a fresh instance of a boxed class its zeroed state block, once.

```v
pub fn box_free(obj voidptr)
```

box_free releases an instance's state block, at dealloc.

```v
pub fn instance_fail(obj voidptr) voidptr
```

instance_fail releases an instance whose constructor failed, and returns the null
pointer a `tp_new` must return.

`tp_new` owns the object `tp_alloc` handed it: returning nil without a decref leaks
the object, because CPython only propagates the nil. Decref runs the generated
`tp_dealloc`, which releases any reference or buffer the constructor had already
stored. The state is a valid V value at this point -- `PyType_GenericAlloc` zeroed
it and only a fully built state is ever copied in -- so the dealloc is safe even
when the failure was a panic before the copy.

```v
pub fn load_state(storage voidptr, dest voidptr, size usize)
```

load_state and store_state move a V value between the state block and a local.

They take a raw size rather than being generic. A generic helper would be the
obvious signature, and it does not compile when called from generated code in
another module: V emits no forward declaration for a generic, so the call fails
with an implicit declaration. The generated code names the type once, as
`sizeof(Counter)`, and these stay plain functions.

The copy is the point. It puts the V value back under V's own rules, where the
collector and the ownership checker can see it, for the duration of the call.

```v
pub fn noop() voidptr
```

noop is the value of a setter that has nothing to store.

```v
pub const state_chain_max = 8
```

The state block of the running trampoline, and one pointer per generation above it.

A method's receiver is the class's own struct, copied in before the call and out
after it. For a subclass that struct does *not* contain the base's half of the state:
the state is the base followed by the subclass, so the receiver reaches the subclass's
half and nothing else. Without these pointers a method of a subclass has no way at all
to read an inherited field, because `&c` is not the address of the instance's state.

A chain is a list rather than a single "base" pointer because the offsets are not
uniform. The root of a chain is always at the start of the block, but the immediate base
of a class whose base is itself derived sits after that base's own base, and so on down.
The generator knows the chain, so it publishes each generation's own struct by address
and a method asks for the level it wants.

Eight levels is the cap. Nothing in V suggests a deeper chain is common, and a fixed
array keeps the save and restore a copy rather than an allocation on every call.

One chain per thread rather than one for the process. Every trampoline used to publish
into a single global, which is correct exactly as long as the GIL serialises the
trampolines -- and a `@[vc_nogil]` call runs without it, so two threads in two
trampolines would publish into the same slots and each would read the other's
instance. The chain lives in thread-local storage instead, keyed once at import.

```v
pub fn init_state()
```

init_state creates the thread-local key the state chain lives in.

Called from the generated module initialiser, which runs once per import under the
import lock. Everything after that -- every trampoline of every thread -- assumes the
key exists.

```v
pub fn enter_state(block voidptr) voidptr
```

enter_state publishes `block` as level 0 of the calling thread's chain and returns
the chain it replaced, so the caller can put it back.

The whole chain is saved rather than just the block: a nested call -- a method reaching
another instance, or a property read from inside a method -- would otherwise leave the
outer trampoline's levels pointing at the inner one's instance. There is no
thread-local storage here beyond the chain itself, and an extension module's Python
calls hold the GIL, so one chain per thread is enough.

```v
pub fn publish_base(level int, ptr voidptr)
```

publish_base records the own struct of one generation of the chain.

Level 1 is the immediate base, level 2 the one above it, and so on. The generator emits
one call per generation with the address it computes from the state struct, so nothing
here has to know the layout.

```v
pub fn leave_state(previous voidptr)
```

leave_state restores the chain saved by `enter_state`.

```v
pub fn state_at(level int) voidptr
```

A method of a subclass reaches an inherited field with a cast on `state_at`:

@[vc_method]
pub fn (mut c BoundedCounter) bump(by int) !int {
mut base := unsafe { &Counter(vcraft.state_at(1)) }
if base.value + by > c.limit {
return vcraft.raise_domain(.value_error, 'the counter would pass its limit')
}
base.value += by
return base.value
}

A pointer rather than a copy, and that is the whole point. V hands the method a copy of
the subclass struct, and the base's bytes are not in it, so a copy taken here would be
written to and then thrown away. This points into the state block the trampoline holds,
which the trampoline writes back when the method returns.

The cast rather than a generic on purpose. `fn inherited[T]() &T` is the obvious
spelling and it does not compile from a user's module: V emits no forward declaration for
a generic, so the call fails with "unknown function: vcraft.inherited[Counter]".

Written to a local rather than assigned through, because V cannot assign through a call
result: `vcraft.state_at(1).value = 1` is rejected, `base.value = 1` on the local is not.

The pointer is only good for the duration of the call. Outside a trampoline the level is
nil and dereferencing it is a segfault, which is why this is not a method on the receiver:
there would be no way to tell from `&c` whether the receiver is the whole state or just
the subclass's half of it.

state_at returns the address of one generation of the running trampoline's state, nil if
that level is not there.

```v
pub fn set_state(member voidptr, value voidptr, size usize)
```

set_state copies a Python value into a single field of the state block.

`size` is the size of that field, so a field is addressed the same way a V struct
member is: by the address of the member, not by an offset computed here.

```v
pub fn store_state(value voidptr, storage voidptr, size usize)
```

store_state copies a V value into the state block.

```v
pub fn class_dealloc(self voidptr) voidptr
```

class_dealloc releases the state block and then the object, and returns whatever
the base deallocator returned.

The order matters: the block may hold the only reference to something, so it goes
first. Calling the base deallocator last is what CPython requires of a subtype.
This lives in the runtime because `Py_TYPE` is a macro, which generated code in a
user module cannot use.

```v
pub fn traverse_ref(field voidptr, visit voidptr, arg voidptr) int
```

traverse_ref hands one reference field to the collector's visit function.

The address is passed rather than the object so the generated code can hand over the
address of a struct member without naming its type, which it cannot do: the field is
declared in the user's V struct and the trampoline is emitted into their module.

`Py_VISIT` in C returns early on a non-zero visit, and so does this, because that is
the whole contract of `tp_traverse`: a non-zero return means an error and the
collector abandons the traversal.

```v
pub fn visit_ref(obj voidptr, visit voidptr, arg voidptr) int
```

visit_ref hands one object to the collector's visit function.

Used where the object is already in hand rather than in a field: `tp_clear` releases
what `tp_traverse` reported, and both need the same treatment of a null object.

```v
pub fn is_type_object(self voidptr) bool
```

is_type_object reports whether `self` is a type rather than one of its instances.

A heap type with `Py_TPFLAGS_HAVE_GC` is on the collector's list itself, so CPython
calls `tp_traverse` and `tp_clear` on the type as well as on what it makes. A generated
trampoline has to tell the two apart before it reads its state block: the type object's
bytes after the header are its own dict pointer, not a state block, and reading them as
one sends the collector into whatever the dict points at.

```v
pub fn traverse_type(self voidptr, visit voidptr, arg voidptr) int
```

traverse_type visits the type object's own references, through CPython's own
implementation of `type`.

The type's dict, bases and MRO are not in the state block and vcraft did not create
them, so they are CPython's to report.

```v
pub fn clear_type(self voidptr)
```

clear_type releases the type object's own references.

Reached during finalisation. Without it the collector would run the generated clear on
a type object and read its dict pointer as a state block.

```v
pub fn set_ref(field voidptr, obj voidptr)
```

set_ref replaces a reference field, taking a reference of its own on the new object.

The incoming object is *borrowed*. A property setter is handed its value the way
`PyObject_SetAttr` hands it, which is borrowed: CPython keeps its own reference for as
long as the assignment is in progress and releases it afterwards, so a setter that
stored the pointer without counting it would leave the field pointing at an object
whose last reference has already gone. The symptom is an instance that appears to have
a peer, whose peer is then reused by the next allocation.

So the field counts one reference and gives it back in `clear_ref`, which is what
`tp_clear` and `tp_dealloc` call. The old object is released only after the new one is
counted, so assigning an object to a field that already points at it neither leaks nor
releases it twice.

The field is written through its address rather than assigned, because assigning needs
the field itself to be `mut` and the state block is a copy.

```v
pub fn ref_target_ok(obj voidptr, typ voidptr) bool
```

ref_target reports whether an object may be stored in a reference field.

`typ` is the class the field accepts, or nil to accept any vcraft instance. The null
object is always accepted, because None is how a reference field says "unset", and a
field that could not be emptied could not express that.

A vcraft instance is recognised by its type having been built here rather than by a
marker: every heap type vcraft creates carries `tp_new` from this runtime, so an
arbitrary Python object has no such slot value. That is a heuristic, and the honest
alternative -- a per-type registry -- costs a lookup on every assignment to catch a
case that cannot arise in a well-typed program.

```v
pub fn none_or_null(obj voidptr) voidptr
```

none_or_null turns Python's None into a null reference and leaves anything else alone.

A `@[vc_ref]` field stores a pointer, so None has to become null rather than be stored
as a reference to the singleton: a field that "is None" and a field that was never set
are the same state, and the getter prints None for both.

```v
pub fn is_none_ptr(obj voidptr) bool
```

is_none_ptr reports whether a pointer is the `None` singleton.

```v
pub fn type_name_of(obj voidptr) string
```

type_name_of reports the name of an object's type, for an error message.

Takes a raw pointer because that is what a CPython callback hands over, and the
`PyObj` methods would want a caller's reference rather than a borrowed one.

```v
pub fn repr_enter(self voidptr) bool
```

repr_enter marks `self` as being rendered and reports whether it already was.

A reference field can point at an object that points back, so `repr` can arrive at the
same instance twice on one stack. CPython's own containers guard against that with this
pair: the first caller gets 0 and renders, the second gets non-zero and prints `...`.

Without it the recursion runs until the C stack is exhausted, and the symptom is a
segfault inside the interpreter rather than anything mentioning the cycle.

```v
pub fn repr_leave(self voidptr)
```

repr_leave undoes `repr_enter`, and must be called on every path that entered.

A `defer` rather than a statement at the end, because a repr that raises part way
through would otherwise leave the instance marked as already-rendered for good, and
every later repr of it would print `...`.

```v
pub fn repr_ref(obj voidptr) string
```

repr_ref renders a reference field for `__repr__`.

`None` for an unset field rather than `0x7f...`, matching what a Python attribute
holding nothing prints.

```v
pub fn clear_ref(field voidptr)
```

clear_ref releases a reference field and leaves it null.

`tp_clear` breaks the cycle: it drops the references the instance holds, so a cycle
becomes a chain of objects with no path back to the collector's roots and is freed on
the next pass. Setting the field to null rather than leaving it is what stops a
resurrected or re-entered `tp_clear` from releasing the same reference twice.

```v
pub fn type_from_spec(name string, basicsize int, slots voidptr) PyObj
```

type_from_spec creates a heap type. `slots` must be a null-slot-terminated
PyType_Slot array owned by the caller for as long as the type lives, which the
generated code arranges by making it a module-level table.

```v
pub fn new_type(name string, state_size int, doc string, new_ voidptr, init voidptr, dealloc voidptr, methods voidptr, getsets voidptr, repr voidptr, str_fn voidptr, call voidptr, descr_get voidptr, descr_set voidptr, richcompare voidptr, hash voidptr, bases voidptr, traverse voidptr, clear voidptr, iter_fn voidptr, next_fn voidptr, getbuffer voidptr, releasebuffer voidptr, len_fn voidptr, item_fn voidptr, setitem_fn voidptr, contains_fn voidptr, map_getitem_fn voidptr, map_ass_subscript_fn voidptr, concat_fn voidptr, repeat_fn voidptr, weakref bool, dict bool, number_slots []PyTypeSlot) PyObj
```

new_type creates a heap type whose only job is to hold V state.

The slots are the whole contract: `tp_new` allocates the object and fills its
inline state, `tp_init` runs the user's constructor, `tp_dealloc` releases whatever
the state holds, and `tp_repr` prints it. Any other behaviour comes from the method
and getset tables the generated code registers.

`state_size` is `sizeof` the class's state struct, which the type's `tp_basicsize`
is the PyObject header plus: the state is laid out inside the object.

`doc` becomes `__doc__` on the type. It may be empty, in which case CPython leaves
the attribute absent rather than set to an empty string.
`bases` is the tuple a type inherits from, or nil for none. It is passed as the
address of a one-element or n-element tuple object, which is what `Py_tp_bases` takes.

The slot exists under the stable ABI and is how a type without multi-phase
initialisation declares a base. A single base is enough for a V class, and V's
embedding has no use for more than one: a second base would need its state laid out
after the first's, and vcraft's layout is one block of V values.

`bases`, `traverse` and `clear` are required rather than defaulting to nil because V
allows only a constant as a default value, and `unsafe { nil }` is an expression.
Callers that have nothing to pass write `unsafe { nil }`.

```v
pub const op_lt = i32(0)
```

The comparison operators CPython's `PyObject_RichCompare` passes as the third
argument of a `tp_richcompare`.

```v
pub const op_le = i32(1)
```

```v
pub const op_eq = i32(2)
```

```v
pub const op_ne = i32(3)
```

```v
pub const op_gt = i32(4)
```

```v
pub const op_ge = i32(5)
```

```v
pub fn richcompare_not_implemented() voidptr
```

richcompare_not_implemented is the value to return for an operator a class does not
implement.

Returning `NotImplemented` rather than `False` is what lets Python try the reflected
operation on the other operand, and then fall back to identity comparison. A class
that returns `False` for every operator is `!=` everything and `==` nothing, which
makes `x in a_list` surprising in a way that is hard to trace back here.

```v
pub fn identity_richcompare(self voidptr, other voidptr, op int) voidptr
```

identity_richcompare is the default `tp_richcompare`: `==` and `!=` by identity, and
`NotImplemented` for the ordering operators.

Identity rather than `False` for `==` is what makes a plain class usable as a dict
key and comparable to itself, which is what every other object does. `NotImplemented`
for `<` is what lets a class that defines `__lt__` still be ordered against one that
does not: Python falls back to the other operand's reflected method, and then to its
default, which is an error naming the type rather than a wrong `False`.

```v
pub fn identity_hash(self voidptr) isize
```

identity_hash is the default `tp_hash`: the object's own address.

The id-based hash that goes with identity comparison. It is what a class without a
value comparison gets, and it is stable for the life of the object because the object
does not move while Python holds it.

```v
pub fn is_instance_of(obj voidptr, typ voidptr) bool
```

is_instance_of reports whether an object is an instance of a type.

`PyObject_TypeCheck` rather than a pointer comparison, because a subclass instance is
also an instance of its base. A comparison method that returned `NotImplemented` for a
subclass would make `base() == sub()` false, which is the opposite of what Python does
for a type that does not override `__eq__`.

```v
pub fn is_none(obj voidptr) bool
```

is_none reports whether an object is the `None` singleton.

The ternary `nb_power` slot receives the optional third argument of `pow(a, b, m)`
as `None` when it was not given, which is the only case a numeric operator handles;
a real modulus is left to CPython's own error.

```v
pub fn number_slot(id i32, f voidptr) PyTypeSlot
```

number_slot builds one `PyType_Slot` for the number protocol, so generated code can
assemble the `nb_*` slots a class needs without naming the CPython struct.

```v
pub fn from_py_instance(obj voidptr, target voidptr, target_name string, offset usize, func string, name string) voidptr
```

from_py_instance reads an argument that must be an instance of `target` and returns a
pointer to the start of the target's own struct inside the object's state.

`offset` is where that struct sits in the state block: the sum of the sizes of the
target's ancestors' structs, computed by the generator from the same layout it emitted.
An instance of the target or of any subclass shares that layout, so a `&Base` parameter
accepts a subclass instance and reads the same bytes a `Base` method would.

```v
pub fn instance_ref(ptr voidptr, target voidptr, target_name string, offset usize, candidates []voidptr, func string) voidptr
```

instance_ref turns a `&T` result back into the instance that owns the memory it points
into.

A `&T` is only a pointer; CPython needs the object. The pointer is matched by address
against the receiver and the `&T` arguments of the call, which are the only instances a
result can legitimately point at, and the match is checked to be an instance of `target`
so an unrelated object that merely shares the address cannot be handed back. A result
that points anywhere else -- a global, or memory the function allocated -- is reported
rather than guessed at, because handing CPython an object it does not own corrupts the
interpreter.

```v
pub fn hash_from_int(value int) isize
```

hash_from_int folds a V integer into `Py_hash_t`.

The truncation to the platform's `Py_hash_t` is the format's own: Python specifies the
hash as a signed integer of platform width and does not require a value that fits in a
64-bit one. Collisions are handled by the dict, so a truncated hash costs a comparison
rather than correctness.

```v
pub fn base_tuple(types []PyObj) voidptr
```

base_tuple packs one type into a tuple, which is what `Py_tp_bases` takes.

A tuple rather than the type itself, and the difference is not cosmetic: the slot
stores the tuple and CPython takes a new reference to the base from it, so a type
passed directly would be read as the first element of a tuple that does not exist.

```v
pub fn tuple_of_one(t PyObj) PyObj
```

tuple_of_one builds the one-element tuple a single-base class declares.

A class inherits from exactly one V class. V's embedding lays out an instance as one
block of V values, so a second base would have to be placed after the first's, and
there is no way to express that through `@[vc_base]` without the user writing the
offsets by hand.

```v
pub fn reduce_by_fields(self voidptr, rebuild voidptr, names []string) PyObj
```

reduce_by_fields is a `__reduce__` for an instance whose state is the attributes
`names`: `(rebuild, (type(self), {name: value}, self.__dict__ or None))`.

```v
pub fn rebuild_fields(cls voidptr, fields voidptr, extra voidptr) PyObj
```

rebuild_fields is the other half: an instance of `cls` made without its constructor,
with every attribute in `fields` assigned and `extra` merged into its `__dict__`.
The caller has checked that `cls` is one of the module's classes.

```v
pub fn is_class_of(cls voidptr, typ voidptr) bool
```

is_class_of reports whether `cls` is `typ` or a subclass of it, without raising for a
`cls` that is not a class at all.

```v
pub fn generic_getattr(self voidptr, name voidptr) PyObj
```

generic_getattr is the ordinary attribute lookup (`object.__getattribute__`), which a
`@[vc_getattr]` class runs before falling back to its V method.

```v
pub fn generic_setattr(self voidptr, name voidptr, value voidptr) int
```

generic_setattr is the ordinary attribute assignment (`object.__setattr__`), which a
`@[vc_setattr]` class keeps for the names it defines and for deletions.

```v
pub fn type_defines(self voidptr, name voidptr) bool
```

type_defines reports whether the type of `self` (or a base) has an attribute `name`:
a field, property or method, which assignment must reach the ordinary way.

```v
pub fn critical_begin(cs voidptr, obj voidptr)
```

critical_begin holds `obj`'s critical section in the 32 bytes at `cs` (a free-threaded
interpreter only; a no-op with the GIL). The generated glue wraps every method with a
`mut` receiver in it, so concurrent calls into one instance do not interleave.

```v
pub fn critical_end(cs voidptr)
```

critical_end releases what `critical_begin` took.

```v
pub fn attribute_error_pending() bool
```

attribute_error_pending reports whether the pending exception is an AttributeError.

```v
pub fn raise_attribute_miss(err IError, type_name string, attr string)
```

raise_attribute_miss reports what a `@[vc_getattr]` method's error means: the exception
it chose, or for a plain `error(...)` the AttributeError Python would raise for a
missing attribute, naming the type and the attribute.

```v
pub fn set_match_args(typ PyObj, names []string)
```

set_match_args sets a class's `__match_args__`, the field order `case Point(x, y):`
destructures by. A failure leaves the class without it, which only costs positional
patterns, so it is cleared rather than reported.

## `convert.v`

```v
pub fn from_py_int_item(obj PyObj, i int, name string) !i64
```

from_py_int reads a Python int.

Any int is accepted, subclasses included -- `bool` (`True` is 1), an `IntEnum` member
-- as Python's own `int` parameters and PyO3 accept them, and as the stub's `int`
tells a type checker. A float or a str is refused with the type it got.
from_py_int_item reads element `i` of a list or a tuple as an int.

The `from_py_*_arg` readers ask for a positional argument by index; this one asks for
an element of a value that is already in hand, which is what a function that receives a
tuple or a list from Python does. The element is borrowed, so it is not released here.

```v
pub fn from_py_str_item(obj PyObj, i int, name string) !string
```

from_py_str_item reads element `i` of a list or a tuple as a str.

```v
pub fn from_py_bytes_item(obj PyObj, i int, name string) !string
```

from_py_bytes_item reads element `i` of a list or a tuple as bytes.

```v
pub fn from_py_int(obj PyObj, name string) !i64
```

```v
pub fn from_py_uint(obj PyObj, name string) !u64
```

from_py_uint reads a Python int into a u64. PyLong_AsUnsignedLongLong already
raises OverflowError for a negative input, so the range check comes for free.

```v
pub fn from_py_f64(obj PyObj, name string) !f64
```

from_py_f64 reads a Python float. An int is accepted and widened, which is what
Python does for a float parameter.

```v
pub fn from_py_complex(obj PyObj, name string) !complex.Complex
```

from_py_complex reads a Python complex into a V `math.complex.Complex`.

A real number is accepted too, with no imaginary part, matching Python's own coercion
of a real where a complex is expected: `scale(2)` works next to `scale(2+1j)`.

```v
pub fn from_py_bool(obj PyObj) bool
```

from_py_bool reads any object as Python's `bool()` would.

```v
pub fn i8_from_py_int(obj PyObj, name string) !i8
```

i8_from_py_int reads a Python int into an i8.

```v
pub fn i16_from_py_int(obj PyObj, name string) !i16
```

i16_from_py_int reads a Python int into an i16.

```v
pub fn i32_from_py_int(obj PyObj, name string) !i32
```

i32_from_py_int reads a Python int into an i32.

```v
pub fn isize_from_py_int(obj PyObj, name string) !isize
```

isize_from_py_int reads a Python int into an isize.

```v
pub fn rune_from_py_int(obj PyObj, name string) !rune
```

rune_from_py_int reads a Python int into a rune.

```v
pub fn u8_from_py_uint(obj PyObj, name string) !u8
```

u8_from_py_uint reads a Python int into a u8.

```v
pub fn u16_from_py_uint(obj PyObj, name string) !u16
```

u16_from_py_uint reads a Python int into an u16.

```v
pub fn u32_from_py_uint(obj PyObj, name string) !u32
```

u32_from_py_uint reads a Python int into a u32.

```v
pub fn usize_from_py_uint(obj PyObj, name string) !usize
```

usize_from_py_uint reads a Python int into a usize.

```v
pub fn f32_from_py_f64(obj PyObj, name string) !f32
```

f32_from_py_f64 reads a Python float or int into an f32, with the same
acceptance as `from_py_f64`. Any f64 converts; one far outside the f32
range becomes an infinity, as a V `f32()` cast does.

```v
pub fn from_py_string(obj PyObj, name string) !string
```

from_py_string reads a Python str. bytes is rejected: CPython separates the
two on purpose, and silently decoding one as the other hides bugs.

```v
pub fn from_py_str_borrowed(obj PyObj, name string) !string
```

from_py_str_borrowed reads a Python str without copying it: the V string
aliases the str object's UTF-8 buffer for exactly the call.

Same checks and errors as `from_py_string`; only the copy is skipped. The
argument keeps the str alive for the call's duration, so the alias must not
outlive the call -- the same documented contract as `buffer_bytes`, and for
the same reason: V's collector cannot see CPython's memory. Safe against
mutation rather than lifetime only because `str` is immutable: nothing can
change the aliased bytes under the reader, which a `bytearray` alias cannot
promise.

```v
pub fn from_py_bytes_borrowed(obj PyObj, name string) !string
```

from_py_bytes_borrowed is the borrowed form of `from_py_bytes`: the V string aliases
the bytes object's buffer for exactly the call. `from_py_bytes` already borrows,
so this is the same operation under a name that pairs with `from_py_str_borrowed`;
it exists so a reader can state the aliasing contract at the call site.

```v
pub fn from_py_bytes(obj PyObj, name string) !string
```

from_py_bytes reads a Python bytes object into a V string holding the same
bytes. The result aliases CPython's buffer, so a caller that needs it to
outlive the source object must copy it.

```v
pub fn from_py_voidptr(obj PyObj) voidptr
```

from_py_voidptr adopts any object as an opaque handle. There is no type check
on purpose: this is the escape hatch that lets a V function take a PyObject *
directly.

```v
pub fn from_py_list(obj PyObj, name string) ![]PyObj
```

from_py_list reads a list or a tuple into a `[]PyObj` of borrowed references.

The elements are borrowed, so the caller does not release them; they stay
alive as long as the source object does. This is the counterpart of
`to_py_obj_list` and is what a function that has to walk a composite Python
value (a decoder, a query result) uses.

```v
pub fn from_py_dict(obj PyObj, name string) !(map[string]PyObj)
```

from_py_dict reads a dict into a `map[string]PyObj` of borrowed references.

A key that is not a str raises TypeError. The values are borrowed.

```v
pub fn to_py_int(value i64) PyObj
```

to_py_int boxes a V integer.

It takes an i64 so that every signed width boxes through it: V widens an `int`,
an `i32` or an `i16` implicitly, but refuses to narrow an `i64`, so an `int`
parameter made every generated `i64` getter a compile error.

```v
pub fn to_py_uint(value u64) PyObj
```

to_py_uint boxes a V u64.

```v
pub fn to_py_f64(value f64) PyObj
```

to_py_f64 boxes a V float.

```v
pub fn to_py_complex(value complex.Complex) PyObj
```

to_py_complex boxes a V `math.complex.Complex` as a Python complex.

```v
pub fn zero_complex() complex.Complex
```

zero_complex is the zero value of `math.complex.Complex`, as a call so generated code
can default a result local without naming the type (and so without importing the
module in the glue file).

```v
pub fn to_py_string(value string) PyObj
```

to_py_string boxes a V string as a Python str, decoding it as UTF-8.

```v
pub fn to_py_bytes(value string) PyObj
```

to_py_bytes boxes a V string as Python bytes, with no decoding.

```v
pub fn to_py_bool(value bool) PyObj
```

to_py_bool boxes a V bool.

```v
pub fn to_py_list[T](items []T, box fn (T) PyObj) PyObj
```

to_py_list boxes a V slice as a Python list, calling `box` on each element.

The element conversion is a function because the element type is only known to
the code generator, so it passes the boxing rule in rather than this module
hard-coding one.

The list is created at its final length and each slot filled once. Appending to an
empty list instead regrows it as it goes, and costs a third more for a large one.
`PyList_SetItem` steals the element's reference, so nothing is released here on
success; a failed box releases the half-built list and returns a null object with
the exception already set.

```v
pub fn to_py_obj_list(items []PyObj) PyObj
```

to_py_obj_list boxes a `[]PyObj` as a Python list without a per-element boxing
call. Every element is already a `PyObject *`, so there is nothing to convert;
this is the path a function that has built a list of Python objects by hand
(a JSON decoder, a query result) takes, and it skips the closure indirection
`to_py_list` pays for every element.

```v
pub fn to_py_dict[K, V](m map[K]V, key_box fn (K) PyObj, val_box fn (V) PyObj) PyObj
```

to_py_dict boxes a map as a new `dict`, with one boxing rule for the keys and one for
the values, so a value that is itself a composite boxes through the same call.

The map is a parameter here rather than the parameter of an immediately called
function literal, which is how this used to be emitted: V mis-parses a function
literal whose parameter type is `map[K][]V`, reading the value's slice as the whole
parameter, and the generated file failed to compile. Passing the map to a generic
helper sidesteps it.

```v
pub fn to_py_obj_dict(m map[string]PyObj) PyObj
```

to_py_obj_dict boxes a `map[string]PyObj` as a Python dict without per-element
boxing calls, since the keys and values are already `PyObject *`.

```v
pub fn to_py_i64_list(items []i64) PyObj
```

to_py_i64_list, to_py_int_list and to_py_f64_list box a slice of plain numbers as a
list in one pass in C, with no function call per element. The generated glue uses
them for those element types and `to_py_list` for the rest.

```v
pub fn to_py_int_fixed(ptr voidptr, n int, wide bool) PyObj
```

to_py_int_fixed boxes a fixed-size array of `int` or `i64` as a list, read straight
from its storage: `n` elements at `ptr`, `wide` when an element is 64 bits. The general
path slices the array first, which allocates a slice header per call.

```v
pub fn to_py_int_list(items []int) PyObj
```

```v
pub fn to_py_f64_list(items []f64) PyObj
```

```v
pub fn to_py_str_list(items []string) PyObj
```

to_py_str_list boxes a `[]string` as a Python list of str in one pass, without a call per
element. The generated glue used to call `to_py_list` with `to_py_string` as the boxer,
which worked and cost a V function call and the closure's indirection for every element.

```v
pub fn to_py_bytes_list(items [][]u8) PyObj
```

to_py_bytes_list boxes a `[][]u8` as a Python list of bytes in one pass.

```v
pub fn sequence_element_box(value voidptr) PyObj
```

to_py_object is the default boxing rule for a `[]voidptr` sequence: each element
is already a PyObject pointer, and it is passed through with its own reference
kept by the list.

```v
pub fn to_py_none() PyObj
```

to_py_none is the result of a V function returning nothing.

```v
pub fn to_py_voidptr(p voidptr) PyObj
```

to_py_voidptr boxes an opaque pointer back into a Python object without
touching its reference count, which is only correct for a pointer the caller
already owns a reference to.

```v
pub fn unbox_int(value voidptr, name string) !int
```

unbox_int, unbox_uint, unbox_f64 and unbox_bool convert a value a field setter was
handed into the V type the field holds.

A setter receives a `PyObject *`. That object is a `PyLong` or a `PyFloat` with
CPython's own layout, so the value has to be converted rather than copied: memcpy'ing
the bytes would read the interpreter's internals as if they were a V value.

The object is borrowed. CPython owns the argument for the duration of the call, so
taking a reference would leak one per assignment.

```v
pub fn unbox_uint(value voidptr, name string) !u64
```

```v
pub fn unbox_f64(value voidptr, name string) !f64
```

```v
pub fn unbox_bool(value voidptr) !bool
```

```v
pub fn repr_int(value i64) string
```

repr_int, repr_uint, repr_f64, repr_bool and repr_string render a V value the way
Python's own repr would, so an instance's repr reads like a Python one.

```v
pub fn repr_uint(value u64) string
```

```v
pub fn repr_f64(value f64) string
```

```v
pub fn repr_bool(value bool) string
```

```v
pub fn repr_string(value string) string
```

```v
pub fn dict_items(obj PyObj, name string) ![]PyObj
```

dict_items reads a `dict` into its keys and values, alternating: key, value, key, ...

The references are borrowed from the dict, which the caller holds for the call, so
nothing here is released. Anything that is not a `dict` (or a subclass) is a
TypeError naming the parameter, like the scalar readers.

```v
pub fn dict_get(obj PyObj, key string, name string) !PyObj
```

dict_get returns a borrowed reference to `obj[key]`, or an error with a Python
exception set when `obj` is not a dict or the key is missing. It is what a plain-struct
reader uses to pull one field out of the dict that crossed.

```v
pub fn struct_field(obj PyObj, key string, index int, count int, name string) !PyObj
```

struct_field reads field `key`, the `index`-th of `count`, from whatever was passed for
a plain V struct: a dict by key, a tuple of `count` items by position (a namedtuple, a
struct sequence), any other object by attribute (a dataclass, a SimpleNamespace). The
reference is borrowed and stays valid while the source object does; see
`vpy_struct_field` for why an attribute computed on access is refused.

```v
pub fn structseq_type(name string, fields []string, doc string) PyObj
```

structseq_type creates the struct sequence type a `@[vc_structseq]` struct crosses as:
a tuple subclass with a named field per struct field, the kind `os.stat_result` is.
`name` is qualified (`module.Point`), which is what its repr and pickle use.

```v
pub fn structseq_new(typ PyObj) PyObj
```

structseq_new and structseq_set build a struct sequence field by field (`set` takes
the value's reference). `structseq_done` returns the sequence, or null when a field
failed to box and left its exception pending.

```v
pub fn structseq_set(seq PyObj, i int, value PyObj)
```

```v
pub fn structseq_done(seq PyObj) PyObj
```

```v
pub fn structseq_pack(typ PyObj, items []PyObj) PyObj
```

structseq_pack builds an instance of a struct sequence type from boxed values, whose
references it takes. A value that failed to box makes the result null, with the
exception it set still pending.

```v
pub fn new_dict() PyObj
```

new_dict returns a new empty `dict`, owned by the caller.

```v
pub fn dict_set_owned(d PyObj, key PyObj, value PyObj)
```

dict_set_owned stores `value` under `key` and releases the caller's references to
both: the dict takes its own. A key or value that failed to box (null, with the
exception set) is skipped, and the exception stays for the trampoline to report.

```v
pub fn dict_set_key(d PyObj, key PyObj, value PyObj)
```

dict_set_key stores `value` under a key the caller keeps (a module-level interned
string), releasing only the caller's reference to the value.

```v
pub fn interned(name string) PyObj
```

interned returns an interned `str` for a name the module keeps for its whole life:
a struct's field names, built once rather than on every boxing.

```v
pub fn tuple_of(items []PyObj) PyObj
```

tuple_of builds a `tuple` from owned items; the tuple steals each reference.

```v
pub fn new_set() PyObj
```

new_set returns a new empty `set`, owned by the caller.

```v
pub fn set_add_owned(s PyObj, item PyObj) int
```

set_add_owned adds `item` to `s`, stealing the caller's reference. Returns 0 on
success and -1 with an exception set on failure (for example a TypeError for an
unhashable item).

```v
pub fn to_py_set(items []PyObj) PyObj
```

to_py_set boxes a `[]PyObj` as a Python set, transferring ownership of each
element.

```v
pub fn from_py_set(obj PyObj, name string) ![]PyObj
```

from_py_set reads a set into a `[]PyObj` of borrowed references.

```v
pub fn list_new() PyObj
```

list_new returns a new empty list, owned by the caller.

```v
pub fn list_append_owned(list PyObj, item PyObj) int
```

list_append_owned appends `item` to `list`, transferring ownership: the list
takes its own reference and the caller's is released. A failed append leaves
the exception set and releases `item`.

```v
pub fn list_set_owned(list PyObj, i int, item PyObj)
```

list_set_owned stores `item` at index `i` of `list` (which must already have
room), stealing the caller's reference.

## `coroutine.v`

```v
pub fn run_coroutine(coro PyObj) PyObj
```

run_coroutine drives a coroutine to completion on the current thread and returns its
result, or the null object with a Python exception set.

```v
pub fn call_async(callee voidptr, args []voidptr) PyObj
```

call_async calls `callee` with positional `args` and drives the coroutine it returns.

## `cpython.c.v`

```v
pub fn gc_enter()
```

gc_enter makes the calling thread known to V's collector; see `vpy_gc_enter` in
`c/gc_preinit.h`. The generated glue calls it first thing in every function, so an
extension can be called from any Python thread.

```v
pub fn python_api_version() int
```

PYTHON_API_VERSION, surfaced as a function because V cannot read a C macro.

```v
pub fn version_hex() u64
```

Py_GetVersion, the hex value such as 0x030E00A0 for CPython 3.14.

```v
pub fn version_string() string
```

The interpreter version string, for example "3.14.7 (main, ...)".

```v
pub fn version_major_minor() (int, int)
```

major.minor of the running interpreter, derived from version_hex.

```v
pub const meth_noargs = 0x0004
```

METH_NOARGS

```v
pub const meth_o = 0x0008
```

METH_O

```v
pub const meth_fastcall = 0x0080
```

METH_FASTCALL

```v
pub const meth_fastcall_keywords = meth_fastcall | 0x0002
```

METH_FASTCALL | METH_KEYWORDS

```v
pub const meth_static = 0x0020
```

METH_STATIC makes a `PyMethodDef` entry a static method: CPython passes NULL as the
receiver, so the trampoline gets no instance. `@[vc_static]` is its only user.

```v
pub const meth_class = 0x0010
```

meth_class is CPython's METH_CLASS: the trampoline is a classmethod, so CPython passes
the class (the subclass on a subclass call) rather than NULL.

```v
pub const slot_doc = i32(56)
```

Type slot identifiers, from CPython's typeslots.h. A slot id is a macro, so the
runtime repeats the numbers and `check_layout` would catch a future change only
by name, not by value. They are part of the stable ABI.

```v
pub const slot_dealloc = i32(52)
```

```v
pub const slot_init = i32(60)
```

```v
pub const slot_methods = i32(64)
```

```v
pub const slot_new = i32(65)
```

```v
pub const slot_repr = i32(66)
```

```v
pub const slot_descr_get = i32(54)
```

```v
pub const slot_descr_set = i32(55)
```

```v
pub const slot_nb_bool = i32(9)
```

```v
pub const slot_getattro = i32(58)
```

slot_getattro is `Py_tp_getattro`, filled by `@[vc_getattr]`.

```v
pub const slot_setattro = i32(69)
```

slot_setattro is `Py_tp_setattro`, filled by `@[vc_setattr]`.

```v
pub const slot_str = i32(70)
```

```v
pub const slot_call = i32(50)
```

```v
pub const slot_traverse = i32(71)
```

```v
pub const slot_bases = i32(49)
```

```v
pub const slot_clear = i32(51)
```

```v
pub const slot_iter = i32(62)
```

```v
pub const slot_iternext = i32(63)
```

```v
pub const slot_hash = i32(59)
```

```v
pub const slot_richcompare = i32(67)
```

```v
pub const slot_sq_length = i32(45)
```

The sequence protocol: `__len__`, `__getitem__` and `__contains__` are `sq_*` slots
rather than `tp_*`, so `len()`, `obj[i]` and `x in obj` reach them.

```v
pub const slot_sq_item = i32(44)
```

```v
pub const slot_sq_contains = i32(41)
```

```v
pub const slot_sq_ass_item = i32(39)
```

```v
pub const slot_sq_concat = i32(40)
```

```v
pub const slot_sq_repeat = i32(46)
```

```v
pub const slot_mp_length = i32(4)
```

```v
pub const slot_mp_subscript = i32(5)
```

```v
pub const slot_mp_ass_subscript = i32(3)
```

```v
pub const slot_nb_add = i32(7)
```

The number protocol. `nb_*` slots are what `+`, `-`, `*`, `&`, `|` and the unary
operators reach; the ids are the `PyType_Slot` ones, which sit below the `Py_sq_*`
and `Py_tp_*` ranges. They have not moved across 3.11-3.15 and the codegen suite
compares them with the installed headers through scripts/check-slot-ids.sh.

```v
pub const slot_nb_subtract = i32(36)
```

```v
pub const slot_nb_multiply = i32(29)
```

```v
pub const slot_nb_remainder = i32(34)
```

```v
pub const slot_nb_power = i32(33)
```

```v
pub const slot_nb_negative = i32(30)
```

```v
pub const slot_nb_positive = i32(32)
```

```v
pub const slot_nb_absolute = i32(6)
```

```v
pub const slot_nb_invert = i32(27)
```

```v
pub const slot_nb_lshift = i32(28)
```

```v
pub const slot_nb_rshift = i32(35)
```

```v
pub const slot_nb_and = i32(8)
```

```v
pub const slot_nb_xor = i32(38)
```

```v
pub const slot_nb_or = i32(31)
```

```v
pub const slot_nb_floor_divide = i32(12)
```

```v
pub const slot_nb_true_divide = i32(37)
```

```v
pub const slot_members = i32(72)
```

```v
pub const slot_getset = i32(73)
```

```v
pub const tpflags_basetype = u32(1 << 10)
```

Py_TPFLAGS_BASETYPE, required before a Python class may be subclassed.

```v
pub const tpflags_have_gc = u32(1 << 14)
```

Py_TPFLAGS_HAVE_GC, required on any type whose instances hold references to other
objects. CPython refuses a type that claims it and leaves tp_traverse null, and it
never collects a type that does not claim it, so an instance in a cycle would leak
rather than be collected.

```v
pub struct PyMethodDef
```

Every C `int` here is `i32`, never V's `int`. V's `int` is 64 bits and C's is 32,
which for `PyTypeSpec` moves `flags` and `slots` to the wrong offsets and makes
CPython read a garbage pointer. Most of the other mirrors happen to line up
anyway; none of them are worth relying on.

```v
pub struct PyModuleDefBase
```

```v
pub struct PyModuleDefBase
```

```v
pub struct PyModuleDefSlot
```

PyModuleDef_Slot is one entry of a multi-phase module's slot table. The two members
are the slot id and the function that implements it, both from the stable ABI.

Present under `Py_LIMITED_API` as well as without it, so the same mirror serves a
build of either kind.

```v
pub struct PyModuleDef
```

```v
pub struct PyTypeSlot
```

```v
pub struct PyTypeSpec
```

There is no `doc` member. CPython's PyType_Spec is exactly five fields, and a
mirror that adds one does not merely lose `__doc__`: `basicsize`, `flags` and
`slots` all shift and CPython reads a garbage pointer. A type's docstring travels
in the `Py_tp_doc` slot instead.

```v
pub struct PyGetSetDef
```

PyGetSetDef is a property descriptor. A nil `set` makes it read only, which is
what a V method marked as a property produces.

```v
pub struct Arena
```

```v
pub fn arena_new() Arena
```

```v
pub fn (a Arena) alloc(size int) voidptr
```

```v
pub fn (mut a Arena) free()
```

```v
pub fn to_py_int_list_fast(ptr &i64, n int) PyObj
```

```v
pub fn to_py_f64_list_fast(ptr &f64, n int) PyObj
```

```v
pub fn to_py_bytes_fast(ptr &u8, n int) PyObj
```

```v
pub fn to_py_memoryview(ptr voidptr, n int) PyObj
```

## `cstring.v`

```v
pub fn cstring(s string) voidptr
```

cstring allocates a NUL-terminated copy of `s` on the C heap.

The copy outlives the V value it came from and is released with
`free_cstring`, so it stays valid for as long as the callee needs it without
involving V's allocator or its ownership rules. V uses the same technique
where it needs a terminator, see `string.replace`.

A compile-time literal can be passed to CPython directly, as `c'name'`, and
then nothing needs freeing.

```v
pub fn free_cstring(p voidptr)
```

free_cstring releases a buffer returned by `cstring`.

```v
pub fn with_cstring[T](s string, f fn (voidptr) T) T
```

with_cstring runs `f` with a NUL-terminated copy of `s` and frees it
afterwards, so the allocation never leaks on an early return.

```v
pub fn from_utf8(ptr voidptr, len int) string
```

from_utf8 turns the (pointer, length) pair that PyUnicode_AsUTF8AndSize and
PyBytes_AsStringAndSize return into a V string. It reads exactly `len` bytes,
so embedded NULs survive the round trip.

```v
pub fn utf8_of(obj PyObj) (voidptr, int)
```

utf8_of returns the UTF-8 bytes and length of a Python str. The pointer is
owned by the str object, so the caller must keep `obj` alive while using it.

```v
pub fn bytes_of(obj PyObj) (voidptr, int)
```

bytes_of returns the buffer and length of a Python bytes object. The pointer
is owned by the object. On failure CPython sets the exception and the
pointer comes back null.

## `enum.v`

```v
pub fn import_module(name string) PyObj
```

import_module imports `name` and returns a new reference to the module, or the null
object with an exception set.

```v
pub fn int_enum(name string, members map[string]i64) PyObj
```

int_enum builds an `enum.IntEnum` subclass named `name` whose members are `members`.

`name` is the V enum's name, so `Color.red` on the Python side is the V `Color.red`,
and the class shows up in the module as `Color`.

```v
pub fn int_enum_in(module string, name string, members map[string]i64) PyObj
```

int_enum_in is `int_enum` for a class that lives in module `module`: its `__module__`
names that module, which is what pickle and `repr` look the class up by. Without it the
functional `IntEnum(...)` API guesses from the calling frame and, called from C, lands
on `_frozen_importlib`, so a member could not be pickled.

```v
pub fn enum_member(cls voidptr, value i64) PyObj
```

enum_member returns the member of `cls` whose value is `value`, or the null object with
an exception set. A V enum value is always a member, so the class call cannot fail for
a value that came from V.

```v
pub fn enum_value(cls voidptr, obj PyObj, name string) !i64
```

enum_value reads `obj` as a member of `cls` and returns its integer value, or an error
with a Python exception set. Calling the class is what rejects an integer that is not a
member, which a plain cast would accept.

## `errors.v`

```v
pub struct VError
```

VError carries a V error value across the boundary so it can be turned into a
Python exception with the original message intact.

```v
pub fn (e VError) str() string
```

Error gives VError the `Error` interface.

```v
pub fn error_is_set() bool
```

error_is_set reports whether a Python exception is pending. A wrapper that
has just called into V checks this before returning a result, so a failure
never leaves a stale value where the caller expects an object.

```v
pub fn clear_error()
```

clear_error discards a pending exception. Used when a wrapper replaces a
CPython-level failure with a more specific V error.

```v
pub fn set_error(exc PyObj, message string)
```

set_error raises `exc` with `message` as its text.

The message goes across as a pointer and its length rather than as a NUL-terminated
copy: a V string has no terminator, so `PyErr_SetString` would need one built first,
and every error the runtime reports would pay a malloc, a copy and a free for it.

```v
pub fn fetch_error() (PyObj, PyObj, PyObj)
```

fetch_error takes the pending exception out of CPython and returns its type,
value and traceback. It returns null objects when nothing was pending.

```v
pub fn restore_error(t PyObj, v PyObj, tb PyObj)
```

restore_error puts an exception triple back, as PyErr_Restore does. Steals all
three references.

```v
pub fn pending_error_text() string
```

error_text renders the pending exception the way Python's traceback would show
it, for embedding into a V error message.

```v
pub enum PyExc
```

```v
pub fn pyexc_obj(kind PyExc) PyObj
```

pyexc_obj resolves an enum member to the CPython exception type.

```v
pub fn raise(kind PyExc, message string)
```

raise raises one of the builtin exceptions.

`.none` is not one of them -- `pyexc_obj` resolves it to the null pointer -- so it
becomes a RuntimeError rather than being passed on. `PyErr_SetString` does not check for
a null type: it writes through it, and the crash lands inside CPython on a line that
mentions neither V nor the code that asked for it.

```v
pub fn raise_type_error(message string)
```

raise_type_error reports a value of the wrong Python type.

```v
pub fn raise_attribute_error(message string)
```

raise_attribute_error reports a missing or undeletable attribute.

```v
pub fn raise_value_error(message string)
```

raise_value_error reports a value of the right type but an unusable value.

```v
pub fn raise_runtime_error(message string)
```

raise_runtime_error reports a failure with no more specific mapping.

```v
pub fn raise_panic_at(message string, file string, line int, func string)
```

raise_panic_at is `raise_panic` plus a traceback frame naming the V function's source
file and line, which the generated glue passes. See `vpy_add_v_frame`.

```v
pub fn raise_panic(message string)
```

```v
pub fn raise_domain(kind PyExc, message string) IError
```

raise_domain raises the Python exception a domain failure maps to, and returns an
error carrying the same message.

This is how a `!T` function reports a specific exception:

if b == 0.0 {
return vcraft.raise_domain(.zero_division_error, 'division by zero')
}

The exception is set here rather than in the wrapper because V gives a wrapper no
way to tell a ZeroDivisionError from a ValueError: both arrive as an IError with a
message and nothing else. Once set, the wrapper's `error_is_set` check stops the
value from reaching Python as a result, and the exception set here is the one
Python sees.

A custom V error struct cannot be returned from a `!T` function in V 0.5.2: the
compiler rejects a value whose type is not IError, and a struct that implements
`msg()` is not one. That is why the choice travels out of band, through the
pending Python exception, instead of inside the error value.

`StopIteration` is the one exception that is not set here. It is how an iterator
ends, so an iteration of n items raised it once per loop, and building the exception
object cost more than the rest of a short iteration put together. The error carries
the exception in its `code()` instead: the `tp_iternext` trampoline ends the iteration
on it without any exception (CPython's own contract for the slot, and what `for`,
`list()` and `next()` all accept), and every other trampoline hands it to
`raise_from_error`, which raises `StopIteration` with this message exactly as before.

```v
pub fn ends_iteration(err IError) bool
```

ends_iteration reports whether an error that reached a `tp_iternext` trampoline is the
end of the iteration rather than a failure: an iterator's `StopIteration` that no
Python exception has overtaken. See `raise_domain`.

```v
pub fn set_error_object(exc voidptr, message string)
```

set_error_object sets an arbitrary Python exception class with a message.

`exc` is the class, not an instance: CPython instantiates it. That is what
`PyErr_SetObject` takes and what lets a V error name an exception the user defined in
Python, which no `PyExc` member can.

The reference is borrowed. CPython stores the class on the exception it builds, which
increments it, so there is nothing for the caller to release.

```v
pub fn raise_errno(code int, context string) IError
```

raise_errno raises the `OSError` an errno value stands for, and returns an error
carrying `context`.

CPython picks the subclass from the number, as it does for its own system calls:
ECONNREFUSED is a `ConnectionRefusedError`, ENOENT a `FileNotFoundError`, EACCES a
`PermissionError`, and `str(exc)` is `[Errno 111] Connection refused: 'context'`.
`exc.errno` and `exc.strerror` are set, so Python code can match on either. An empty
`context` leaves the filename part out.

if C.bind(fd, addr, len) != 0 {
return vcraft.raise_last_errno('bind ${host}:${port}')
}

```v
pub fn raise_last_errno(context string) IError
```

raise_last_errno is `raise_errno` with the calling thread's `errno`, read before anything
else can change it: the call to make right after a failed C call.

```v
pub fn raise_custom(exc voidptr, message string) IError
```

raise_custom raises an arbitrary Python exception class and returns an error carrying
the same message.

The counterpart of `raise_domain` for an exception vcraft has no name for:

pub fn parse(text string) !int {
if !is_digits(text) {
return vcraft.raise_custom(python_error_class('BadNumber'), 'not a number')
}
...
}

The class is borrowed and the error value cannot carry it, for the same reason
`raise_domain` sets the exception here rather than inside it: V erases an error to
`IError` by the time the wrapper sees it, and everything but the message is gone.

```v
pub fn pyexc_from_code(code int) PyExc
```

pyexc_from_code turns an error's `code()` back into the exception it names.

The inverse of the enum's own numbering, which is what lets a custom V error type
choose its exception with no wrapper code at all:

@[vc_error]
pub struct ConfigError {
pub:
message string
}

pub fn (e ConfigError) msg() string { return e.message }

// The code *is* the exception: `PyExc.value_error` is 2.
pub fn (e ConfigError) code() int { return int(vcraft.PyExc(.value_error)) }

A code outside the enum is not an exception choice at all -- it is an ordinary error
code, and those are common -- so it falls back to `.runtime_error` rather than being
read as one.

```v
pub fn raise_from_error(err IError)
```

raise_from_error turns a V error value into a Python exception.

IError is V's builtin error interface, so this accepts any error a `!T` function can
produce: the anonymous ones `error('...')` creates, and any struct implementing `msg()`
and `code()`.

Three ways an error can name its exception, in the order they are consulted:

- An exception already set. `raise_domain` and `raise_custom` set one at the point of
failure, and it wins: replacing it would undo the choice the V code made.
- A `code()` that is one of the `PyExc` values. This is how a custom error type
carries a builtin exception with no help from the generator.
- Otherwise a RuntimeError, because a bare message says nothing about which exception
was meant.

## `gil.v`

```v
pub fn allow_threads() voidptr
```

allow_threads releases the GIL and returns the state to restore.

The state is the thread's own, saved by CPython. It travels as an opaque pointer
because restoring anything else corrupts the interpreter, and a void pointer gives
the generated code nothing to mistake for something else.

```v
pub fn end_allow_threads(state voidptr)
```

end_allow_threads restores the state a matching `allow_threads` returned.

Exactly once per release. The generated wrapper guards the deferred call with a nil
check so a fall-through restore and a panic-unwind restore cannot both fire.

```v
pub fn gil_ensure() int
```

gil_ensure acquires the GIL for a thread that does not hold it, and returns the state to
give back with `gil_release`.

The other direction from `allow_threads`, and the one that makes a V-owned thread
possible. A thread V created with `spawn` holds no Python thread state: calling into
Python from it - `vcraft.call`, `to_py_*`, a `PyObj` - needs the GIL, and nothing in V
can hand it over. `PyGILState_Ensure` is a no-op when the calling thread already holds
the GIL, so a function may call it defensively rather than asserting which thread it is
on.

The state is CPython's own enum and travels as an int, because V has no name for it and
a `[faulty]` void pointer would invite someone to invent one.

```v
pub fn gil_release(state int)
```

gil_release gives back the state `gil_ensure` returned. Exactly once per acquisition.

```v
pub fn with_gil(f fn ())
```

with_gil runs `f` holding the GIL, acquiring it for the duration when the calling thread
does not already have it.

This is the shape a V-created thread wants: everything Python-touching goes inside the
block, and the defer gives the GIL back on the way out, panic included. It does not make
`@[vc_nogil]` safe to call Python from - a released call still may not touch Python -
it is the way back in.

`f` is released when this returns (see `release_closure`): pass a closure literal.

```v
pub fn released(f fn ())
```

released runs `f` with the GIL released, and re-acquires it on every path, panic included.

The mirror image of `with_gil`: a function that is not `@[vc_nogil]` holds the GIL for its
whole call, so a long V-only stretch - a poll, a parse, a compress, a syscall loop - blocks
every other Python thread. `released` is the RAII version of the `allow_threads`/
`end_allow_threads` pair the README describes, and it is the only way to get the pair
balanced when the block can panic: the restore runs in a `defer` registered *after* the
`recover` defer, so on a panic the restore fires first and the raise that follows it
already holds the GIL. An unbalanced pair leaves the GIL count wrong and crashes the
next thread switch inside CPython, which is how this was found.

`f` runs released, so it may not touch Python, may not call `allow_threads` or
`end_allow_threads`, and may not raise a V error: all three go through the interpreter.
Anything that has to cross the boundary goes before `released` or after it.

`f` is released when this returns (see `release_closure`): pass a closure literal.

## `handle.v`

```v
pub struct Owned
```

Owned is a native pointer together with the function that releases it.

Both halves are scalars, so one of these is safe to hold in the state block of a class:
nothing in it needs the collector to follow it. The drop function is `fn (voidptr)`
rather than a method so a class can own something it has no type for.

```v
pub fn own(ptr voidptr, drop fn (voidptr)) Owned
```

own pairs a pointer with the function that releases it.

Ownership transfers: whatever `ptr` came from is released when the instance holding
this is deallocated, or when `release` is called on it directly.

```v
pub fn own_gc(ptr voidptr) Owned
```

own_gc keeps a V allocation alive for as long as the instance holding it.

`own` is for memory the collector does not manage. V state built with `&T{...}` -- a
struct with maps, arrays, a mutex, a channel -- is the collector's, and a pointer to it
kept only in an instance is a pointer the collector cannot see: the state block lives
in CPython's memory, which it does not scan, so the struct would be freed while the
instance still used it. `own_gc` registers the pointer as a collector root, and
`release` (run by the generated `tp_dealloc`) drops the root again, after which the
collector reclaims the struct like any other garbage.

```v
@[vc_class]
pub struct Server {
mut:
@[vc_handle]
hub vcraft.Owned
}

pub fn new_server() &Server {
return &Server{
hub: vcraft.own_gc(&Hub{})
}
}

fn (s &Server) state() &Hub {
return unsafe { &Hub(s.hub.get()) }
}
```

Each instance owns its own state, so a process can hold any number of them, which a
module-level global cannot give.

```v
pub fn (mut o Owned) release()
```

release calls the drop function, once.

Safe to call twice, and safe on the zero value of the struct: a field of a class that
was never constructed holds no pointer, and `tp_dealloc` runs on such an instance every
time a constructor raises. The pointer is cleared before the drop runs, so a drop that
panics cannot leave a handle that would release the same address again.

```v
pub fn (o Owned) get() voidptr
```

get returns the pointer, for the code that knows what it is.

V has no generic cast to a named type here, so a caller writes the cast itself:
`unsafe { &net.TcpListener(handle.get()) }`.

```v
pub fn (o Owned) is_set() bool
```

is_set reports whether the handle still owns something.

## `module.v`

```v
pub struct Module
```

Module is a Python module under construction. After `seal` it is a finished
module with a new reference the caller owns.

```v
pub fn new_module(name string, docstring string) Module
```

new_module starts a module definition. Nothing is handed to CPython yet, so
functions may still be added. `name` and `docstring` are copied into buffers
that live as long as the module does.

```v
pub fn (m Module) install_functions(module voidptr) !
```

install_functions copies the method table into the module.

Single-phase initialisation does this itself, inside `PyModule_Create2`. Multi-phase
initialisation does not: the module is created empty and filled by `Py_mod_exec`, so
the table has to be installed by hand or every function is missing.

`PyModule_AddFunctions` is the stable-ABI call that does it, and it is what makes one
generated source serve both APIs: the loop here runs under `Py_mod_exec` on an abi3
build and is never reached on a normal one, where `seal` has already done the work.

```v
pub fn (mut m Module) add_function(name voidptr, trampoline voidptr, flags int, docstring voidptr)
```

add_function appends a function to the table.

`name` and `docstring` are pointers the module keeps for its lifetime, so pass
a string literal as `voidptr(c'name')` or the result of `cstring`. An empty
docstring becomes a null pointer, which is how CPython spells "no docstring".

This must be called before `seal`.

```v
pub fn (mut m Module) add_function_owned(name string, trampoline voidptr, flags int, docstring string)
```

add_function_owned is `add_function` for names and docstrings that are V
strings. It allocates the buffers once and never frees them, which matches the
lifetime of a module that lives until the process exits.

```v
pub fn (mut m Module) seal() PyObj
```

seal finishes construction: it terminates the method table, creates the module
and returns it with a new reference that the caller owns.

Two paths, because CPython has two module initialisation APIs and only one of them is
in the limited API.

`PyModule_Create2` is single-phase: it takes a `PyModuleDef` whose fields are filled
in here and hands back a finished module. That is the cheaper path and it is what a
normal build uses, but the struct it needs is a concrete type the stable ABI hides,
so an abi3 build cannot call it at all.

Under `Py_LIMITED_API` the module declares a `Py_mod_exec` slot instead, and the
interpreter calls it to populate the module. That is multi-phase initialisation, and
it is the only form available to an abi3 extension.

```v
pub fn (mut m Module) set_exec(fn_ptr voidptr)
```

set_exec records the callback the interpreter invokes through `Py_mod_exec`.

An abi3 build cannot populate the module from `pyinit`, because `pyinit` returns a
definition rather than a module and the interpreter calls back afterwards. The
callback is a plain function pointer rather than a V method value, since CPython
calls it with one argument and no receiver.

```v
pub fn (m Module) add_object(name string, value PyObj)
```

add_object installs an attribute on a finished module, stealing a reference to
`value`. This is how classes, constants and submodules are attached.

```v
pub fn add_object_ref_on(module voidptr, name string, value PyObj)
```

add_object_ref_on installs an attribute on a finished module without stealing the
reference, which is the safer choice when the caller keeps using the value.

It takes the module as a `voidptr` rather than a `Module`, because by the time anything
is attached the module is already sealed: under multi-phase initialisation the caller
is the interpreter's `Py_mod_exec` callback, which receives the module as a plain
pointer and never sees the `Module` at all.

```v
pub fn add_object_owned(module voidptr, name string, value PyObj)
```

add_object_owned installs an attribute on a sealed module, stealing the reference.

The counterpart of `add_object_ref_on` for a value built only to be attached, such as a
`@[vc_const]`: the caller holds the only reference and does not keep it.

```v
pub fn (m Module) add_object_ref(name string, value PyObj)
```

add_object_ref installs an attribute without stealing.

```v
pub fn (m Module) set_docstring(docstring string)
```

set_docstring replaces the module docstring after construction.

```v
pub fn check_layout() !
```

check_layout compares the V mirrors of CPython's structs against the sizes the
C compiler agrees with, and reports a mismatch as a Python SystemError.

This is cheap insurance. If a mirror ever drifts from the CPython headers,
every later symptom would be a wild pointer dereference inside the
interpreter, which is close to impossible to diagnose. Checking once at import
turns that into a message naming the struct.

It also catches the mistake that motivated it: V's `int` is 64 bits while C's
`int` is 32, so the two are the same width nowhere and must never be assumed
interchangeable in a layout.

## `ndarray.v`

```v
pub struct NdArray
```

NdArray is a borrowed view of an N-dimensional buffer, valid for the call.

```v
pub fn nd_arg(argv voidptr, i int, func string, name string) !NdArray
```

nd_arg reads positional argument `i` as an N-dimensional view. Used by the generated
wrapper for a `vcraft.NdArray` parameter, which defers `release`.

```v
pub fn nd_of(obj PyObj, name string) !NdArray
```

nd_of views any object that exports a buffer. Release it with `release`.

```v
pub fn (a NdArray) release()
```

release gives the view back. The generated wrapper defers it; hand-written code calls it
once it is done with the array and every slice taken from it.

```v
pub fn (a NdArray) ndim() int
```

ndim is the number of dimensions.

```v
pub fn (a NdArray) f64s() ![]f64
```

f64s aliases a C-contiguous float64 array as a `[]f64` in row-major order, without
copying. Valid for the call; write through it only when `readonly` is false.

```v
pub fn (a NdArray) f32s() ![]f32
```

f32s is `f64s` for a float32 array.

```v
pub fn (a NdArray) i64s() ![]i64
```

i64s is `f64s` for an int64 array.

```v
pub fn (a NdArray) i32s() ![]i32
```

i32s is `f64s` for an int32 array.

```v
pub fn (a NdArray) u8s() ![]u8
```

u8s is `f64s` for a uint8 array.

```v
pub fn (a NdArray) offset(idx []int) int
```

offset is the byte offset of the element at `idx`, following the strides, so it works
for a transposed or sliced array too. It panics on an index out of range.

```v
pub fn (a NdArray) at_f64(idx ...int) f64
```

at_f64 reads the float64 element at `idx`, whatever the layout.

```v
pub fn (a NdArray) at_i64(idx ...int) i64
```

at_i64 reads the int64 element at `idx`, whatever the layout.

```v
pub fn (a NdArray) set_f64(value f64, idx ...int) !
```

set_f64 writes the float64 element at `idx`, refusing a read-only array.

```v
pub struct NdOut
```

NdOut is a native N-dimensional buffer a function returns: Python receives it as a
`memoryview` with this shape, which `numpy.asarray` wraps without copying.

```v
pub fn nd_out_f64(shape []int) NdOut
```

nd_out_f64 allocates a zeroed float64 result of `shape`.

```v
pub fn nd_out_f32(shape []int) NdOut
```

nd_out_f32 allocates a zeroed float32 result of `shape`.

```v
pub fn nd_out_i64(shape []int) NdOut
```

nd_out_i64 allocates a zeroed int64 result of `shape`.

```v
pub fn nd_out_i32(shape []int) NdOut
```

nd_out_i32 allocates a zeroed int32 result of `shape`.

```v
pub fn nd_out_u8(shape []int) NdOut
```

nd_out_u8 allocates a zeroed uint8 result of `shape`.

```v
pub fn (o NdOut) f64s() []f64
```

f64s is the result's storage as a `[]f64`, row-major, to fill before returning it.

```v
pub fn (o NdOut) f32s() []f32
```

f32s is `f64s` for a float32 result.

```v
pub fn (o NdOut) i64s() []i64
```

i64s is `f64s` for an int64 result.

```v
pub fn (o NdOut) i32s() []i32
```

i32s is `f64s` for an int32 result.

```v
pub fn (o NdOut) u8s() []u8
```

u8s is `f64s` for a uint8 result.

```v
pub fn nd_export(o NdOut) PyObj
```

nd_export hands a result to Python as an N-dimensional memoryview that owns the buffer.
The flat view is cast to bytes and then to the element format with the shape, because a
memoryview cannot be reshaped between two non-byte formats directly.

## `object.v`

```v
pub struct PyObj
```

PyObj is a reference to a CPython object.

Reference counting is explicit, following the C API rather than V's ownership
rules. A PyObj value is a *borrowed* reference unless a function's doc comment
says otherwise, which is how a CPython caller reads. The two functions that
move ownership say so in their names:

- `new_ref` returns a reference the caller owns and must release with
`decref`.
- `steal` adopts a reference that is already new, typically the return value
of a CPython constructor such as PyLong_FromLongLong.

This is deliberately not a V reference type. If it were, V would assume it
could collect the pointee, and CPython owns every object. A false positive
would be a use-after-free inside the interpreter.

```v
pub const null = PyObj{}
```

null is the null pointer. CPython spells it NULL; it is never a valid object,
so it doubles as "no result" when a function reports failure by returning it.

```v
pub fn borrow(p voidptr) PyObj
```

borrow wraps a pointer the caller does not own. The count does not change.

```v
pub fn steal(p voidptr) PyObj
```

steal adopts an existing new reference, so the caller must eventually release
it with `decref`.

```v
pub fn (o PyObj) new_ref() PyObj
```

new_ref returns an owned reference to the same object.

```v
pub fn (o PyObj) decref()
```

decref releases one reference. Calling it on the null pointer is harmless,
which matches Py_DECREF.

```v
pub fn incref(o PyObj) PyObj
```

incref returns an owned reference to the same object.

The free-function spelling of `new_ref`. A method on an imported type does not resolve
from a user's module -- V reports "unknown method or field" for it -- so anything a
generated file or a user's own code needs has to be reachable as a plain function.
The name follows the C API this runtime is a mirror of.

```v
pub fn retain(p voidptr) PyObj
```

retain turns a borrowed pointer into an owned reference.

The one to reach for when a value crosses into storage that has to keep it alive: a
`@[vc_ref]` field, or anything else that outlives the call it came from. A V function
parameter arrives borrowed -- CPython owns the reference, and the callee does not get
one -- so storing one without retaining it leaves a field pointing at an object whose
last reference Python has already dropped.

@[vc_method]
pub fn (mut n Node) link(other voidptr) {
n.peer = vcraft.retain(other)
}

`retain` and `steal` are opposites that read alike. `steal` adopts a reference that is
already new, which is what CPython hands a property setter; `retain` takes one of its
own. Mixing them up leaks or double-frees, the same as in C.

```v
pub fn is_null(o PyObj) bool
```

is_null reports whether the reference is the null pointer.

The free-function spelling of the method, for the same reason as `incref`.

```v
pub fn (o PyObj) is_null() bool
```

```v
pub fn (o PyObj) is_none() bool
```

is_none reports whether the reference is None.

```v
pub fn (o PyObj) is(other PyObj) bool
```

is compares by identity, which is what Python's `is` does.

```v
pub fn (o PyObj) call(args []voidptr) PyObj
```

call invokes the object as a callable with the positional `args` (borrowed) and
returns a new reference, or the null object with an exception set.

```v
pub fn (o PyObj) call_kw(args []voidptr, kwargs map[string]PyObj) PyObj
```

call_kw invokes the object as a callable with positional `args` (borrowed) and
keyword `kwargs`, returning a new reference.

```v
pub fn (o PyObj) call_method_kw(name string, args []voidptr, kwargs map[string]PyObj) PyObj
```

call_method_kw invokes `o.name(...)` with positional `args` and keyword `kwargs`.

```v
pub fn (o PyObj) iter() PyObj
```

iter returns a new reference to an iterator over `o`, or null with an exception set.

```v
pub fn (o PyObj) next() PyObj
```

next returns the next item from the iterator `o`, or null with an exception set
(StopIteration when exhausted).

```v
pub fn (o PyObj) contains(item PyObj) bool
```

contains reports whether `item in o`, without raising on a False result. An
error (for example an unhashable item) leaves a Python exception set.

```v
pub fn (o PyObj) del_attr(name string) int
```

del_attr deletes `o.name`, returning 0 on success and -1 with an exception set.

```v
pub fn (o PyObj) call_method(name string, args []voidptr) PyObj
```

call_method invokes `o.name(...)` with the positional `args` (borrowed).

```v
pub fn (o PyObj) getitem(key PyObj) PyObj
```

getitem returns `o[key]` as a new reference.

```v
pub fn (o PyObj) setitem(key PyObj, value PyObj) int
```

setitem stores `value` under `key`, stealing the caller's reference to `value`.
Returns 0 on success and -1 with an exception set on failure.

```v
pub fn (o PyObj) getattr(name string) PyObj
```

getattr returns `o.name` as a new reference (or null with an exception set).

```v
pub fn (o PyObj) setattr(name string, value PyObj) int
```

setattr sets `o.name = value`, stealing the caller's reference to `value`.

```v
pub fn (o PyObj) hasattr(name string) bool
```

hasattr reports whether `o` has an attribute `name`, without raising.

```v
pub fn consume_bool(obj voidptr) int
```

consume_bool maps an owned bool object to `sq_contains`'s int result and releases it:
1 for a true object, 0 for a false one, and -1 for null, which is the error the caller
already set. The object is consumed, so the reference is not leaked.

```v
pub fn (o PyObj) is_true() bool
```

is_true reports the truth value of the object, as Python's `bool()` would.

```v
pub fn (o PyObj) type() PyObj
```

type returns the type of the object as a new reference.

```v
pub fn (o PyObj) type_is(wanted PyObj) bool
```

type_is reports whether the object is an instance of `wanted` or of a class
deriving from it.

```v
pub fn (o PyObj) type_obj() PyObj
```

type_obj returns a new reference to the object's type.

```v
pub fn (o PyObj) type_name() string
```

type_name returns the name of the object's type, for error messages.

```v
pub fn (o PyObj) hash_value() isize
```

hash_value returns the Python hash of the object, or -1 with an error set.

```v
pub fn (o PyObj) len() isize
```

len returns the length of a sized object, or -1 with an error set.

```v
pub fn (o PyObj) item(i int) PyObj
```

item returns the i-th element of a list or a tuple as a borrowed reference, which
is what PyList_GetItem and PyTuple_GetItem both hand back. It raises IndexError on
an out-of-range index and TypeError for any other kind of object.

It used PySequence_GetItem, whose reference is a new one, and every caller treated
it as borrowed, so each element read kept a reference nothing released.

```v
pub fn (o PyObj) append(value PyObj) int
```

append adds a value to a list, stealing a reference to it.

```v
pub fn (o PyObj) repr() string
```

repr renders the object the way Python's `repr` would.

```v
pub fn (o PyObj) str() string
```

str renders the object the way Python's `str` would.

```v
pub fn (o PyObj) to_vstring() string
```

to_vstring converts a Python str into a V string. CPython caches the UTF-8
form on the str object, so this does not transcode and the result shares
memory with the object, which keeps the receiver alive through the call.

```v
pub fn (o PyObj) get_attr(name string) PyObj
```

get_attr looks an attribute up by name, returning a borrowed reference. It
leaves a Python exception set when the attribute is missing.

```v
pub fn (o PyObj) set_attr(name string, value PyObj) int
```

set_attr sets an attribute by name, stealing a reference to `value`.

```v
pub fn py_none() PyObj
```

none is Python's None singleton.

```v
pub fn not_implemented() PyObj
```

not_implemented is Python's NotImplemented singleton.

```v
pub fn bool_obj(value bool) PyObj
```

bool_obj returns True or False.

```v
pub fn bool_type() PyObj
```

The CPython singletons the runtime type-checks against. Exposed so the code
generator can compare against them without repeating the shim calls.

```v
pub fn long_type() PyObj
```

```v
pub fn float_type() PyObj
```

```v
pub fn str_type() PyObj
```

```v
pub fn bytes_type() PyObj
```

```v
pub fn tuple_type() PyObj
```

```v
pub fn list_type() PyObj
```

```v
pub fn set_type() PyObj
```

```v
pub fn dict_type() PyObj
```

```v
pub fn module_type() PyObj
```

## `parallel.v`

```v
pub fn par_range(n int, body fn (start int, end int))
```

par_range runs `body` over `0 .. n` in one chunk per core.

```v
pub fn par_range_with(n int, workers int, body fn (start int, end int))
```

par_range_with is `par_range` with an explicit number of workers; 0 means one per core.
A small `n` uses fewer threads, and a single worker runs on the calling thread.

## `scope.v`

```v
pub struct PyScope
```

PyScope collects Python references and releases them on scope exit.

```v
pub fn (mut s PyScope) track(o PyObj) PyObj
```

track records `o` for release and returns it unchanged.

```v
pub fn (mut s PyScope) keep(o PyObj) PyObj
```

keep removes `o` from the tracked set so it survives the scope. Returns `o`.

```v
pub fn (mut s PyScope) release()
```

release releases every tracked reference. Safe to call more than once.

```v
pub fn with_py_scope(f fn (mut PyScope))
```

with_py_scope runs `f` with a fresh scope and releases it on exit, including
on a panic. `f` receives the scope by mutable reference.

`f` is released when this returns (see `release_closure`): pass a closure literal.

## `temporal.v`

```v
pub fn datetime_parts(o PyObj, name string) ![]int
```

datetime_parts reads a `datetime.datetime` as [year, month, day, hour, minute, second,
microsecond]. An aware one is converted to UTC first, so the fields name one instant;
a naive one is taken as written.

```v
pub fn to_py_datetime(year int, month int, day int, hour int, minute int, second int, microsecond int) PyObj
```

to_py_datetime builds a naive `datetime.datetime` from its fields.

```v
pub fn timedelta_microseconds(o PyObj, name string) !i64
```

timedelta_microseconds reads a `datetime.timedelta` as a whole number of microseconds.

```v
pub fn to_py_timedelta(microseconds i64) PyObj
```

to_py_timedelta builds a `datetime.timedelta` of `microseconds`.

```v
pub struct Decimal
```

Decimal is a `decimal.Decimal` that crossed into V, kept as its exact text: V has no
decimal type, and a float would round it. Parse it with whatever arithmetic the code
uses, and build one with `vcraft.decimal('12.50')` to return.

```v
pub fn decimal(text string) Decimal
```

decimal makes a Decimal from its text, e.g. `vcraft.decimal('12.50')`.

```v
pub fn (d Decimal) str() string
```

str is the decimal's exact text.

```v
pub fn from_py_decimal(o PyObj, name string) !Decimal
```

from_py_decimal reads a `decimal.Decimal` or an `int` as its exact text.

```v
pub fn to_py_decimal(d Decimal) PyObj
```

to_py_decimal builds a `decimal.Decimal` from a Decimal's text.

```v
pub fn int_to_decimal_string(o PyObj, name string) !string
```

int_to_decimal_string reads a Python `int` of any size as its decimal digits, which
`big.integer_from_string` parses.

```v
pub fn int_from_decimal_string(digits string) PyObj
```

int_from_decimal_string builds a Python `int` from decimal digits, any size.

```v
pub const log_debug_level = 10
```

```v
pub const log_info_level = 20
```

```v
pub const log_warning_level = 30
```

```v
pub const log_error_level = 40
```

```v
pub fn log(level int, message string)
```

log writes `message` at a `logging` level number.

```v
pub fn log_debug(message string)
```

```v
pub fn log_info(message string)
```

```v
pub fn log_warning(message string)
```

```v
pub fn log_error(message string)
```

```v
pub fn set_logger_name(name string)
```

set_logger_name names the logger `log` writes to; the generated module initialiser
calls it with the module's name.
