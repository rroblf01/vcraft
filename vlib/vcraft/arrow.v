module vcraft

// Arrow columns, both ways, through the Arrow PyCapsule interface that pyarrow, polars,
// pandas and DuckDB implement. The C half is `c/arrow.c`.
//
// A `vcraft.ArrowArray` parameter takes any Arrow column -- a pyarrow array, a polars
// Series, a chunked array -- and reads it in place where the protocol allows:
//
//	@[vc_fn]
//	pub fn mean(col vcraft.ArrowArray) !f64 {
//		xs := col.f64s()!
//		...
//	}
//
// A `vcraft.ArrowOut` result is a column Python receives as an object `pyarrow.array()` or
// `polars.Series()` takes without a copy: `vcraft.arrow_f64(values)`, `arrow_i64`,
// `arrow_i32`, `arrow_strings`.

fn C.vpy_arrow_view_new() voidptr
fn C.vpy_arrow_view_delete(v voidptr)
fn C.vpy_arrow_view(obj voidptr, out voidptr) int
fn C.vpy_arrow_format(v voidptr) &char
fn C.vpy_arrow_length(v voidptr) i64
fn C.vpy_arrow_null_count(v voidptr) i64
fn C.vpy_arrow_offset(v voidptr) i64
fn C.vpy_arrow_validity(v voidptr) voidptr
fn C.vpy_arrow_values(v voidptr) voidptr
fn C.vpy_arrow_data(v voidptr) voidptr
fn C.vpy_arrow_column(format &char, length i64, n_buffers int, b0 voidptr, b1 voidptr, b2 voidptr) voidptr
fn C.vpy_arrow_malloc(n usize) voidptr

// ArrowArray is a borrowed view of one Arrow column, valid for the call. `format` is the
// Arrow format string: `g` float64, `f` float32, `l` int64, `i` int32, `s` int16, `c`
// int8 (capitals for unsigned), `u` utf8 strings.
pub struct ArrowArray {
pub:
	format     string
	len        int
	null_count int
	offset     int
	validity   voidptr
	values     voidptr
	data       voidptr
	view       voidptr
}

// arrow_arg reads positional argument `i` as an Arrow column. Used by the generated
// wrapper, which defers `release`.
pub fn arrow_arg(argv voidptr, i int, func string, name string) !ArrowArray {
	obj := arg_at(argv, i)
	if obj.is_null() {
		raise(.type_error, '${func}() missing required argument: ${name}')
		return error('missing ${name}')
	}
	return arrow_of(obj)
}

// arrow_of views any object implementing the Arrow PyCapsule interface. Release it.
pub fn arrow_of(obj PyObj) !ArrowArray {
	view := C.vpy_arrow_view_new()
	if view == unsafe { nil } {
		raise(.memory_error, 'cannot view an Arrow column')
		return error('arrow')
	}
	if C.vpy_arrow_view(obj.ptr, view) != 0 {
		C.vpy_arrow_view_delete(view)
		return error('arrow')
	}
	return ArrowArray{
		format:     unsafe { cstring_to_vstring(C.vpy_arrow_format(view)) }
		len:        int(C.vpy_arrow_length(view))
		null_count: int(C.vpy_arrow_null_count(view))
		offset:     int(C.vpy_arrow_offset(view))
		validity:   C.vpy_arrow_validity(view)
		values:     C.vpy_arrow_values(view)
		data:       C.vpy_arrow_data(view)
		view:       view
	}
}

// release lets go of the column; the generated glue calls it after the function.
pub fn (a ArrowArray) release() {
	C.vpy_arrow_view_delete(a.view)
}

// is_null reports whether element `i` is null.
pub fn (a ArrowArray) is_null(i int) bool {
	if a.validity == unsafe { nil } || a.null_count == 0 {
		return false
	}
	bit := a.offset + i
	unsafe {
		return ((&u8(a.validity))[bit >> 3] >> u8(bit & 7)) & 1 == 0
	}
}

fn (a ArrowArray) typed(want string, what string) ! {
	if a.format != want {
		raise(.type_error, 'expected an Arrow ${what} column, got format `${a.format}`')
		return error(what)
	}
}

// f64s aliases a float64 column as a V slice, without copying. A null reads as whatever
// the slot holds (Arrow leaves it unspecified); check `is_null` where nulls matter.
pub fn (a ArrowArray) f64s() ![]f64 {
	a.typed('g', 'float64')!
	mut out := []f64{}
	unsafe {
		out.data = &u8(a.values) + a.offset * int(sizeof(f64))
		out.len = a.len
		out.cap = a.len
	}
	return out
}

// f32s aliases a float32 column.
pub fn (a ArrowArray) f32s() ![]f32 {
	a.typed('f', 'float32')!
	mut out := []f32{}
	unsafe {
		out.data = &u8(a.values) + a.offset * int(sizeof(f32))
		out.len = a.len
		out.cap = a.len
	}
	return out
}

// i64s aliases an int64 column.
pub fn (a ArrowArray) i64s() ![]i64 {
	a.typed('l', 'int64')!
	mut out := []i64{}
	unsafe {
		out.data = &u8(a.values) + a.offset * int(sizeof(i64))
		out.len = a.len
		out.cap = a.len
	}
	return out
}

// i32s aliases an int32 column.
pub fn (a ArrowArray) i32s() ![]i32 {
	a.typed('i', 'int32')!
	mut out := []i32{}
	unsafe {
		out.data = &u8(a.values) + a.offset * int(sizeof(i32))
		out.len = a.len
		out.cap = a.len
	}
	return out
}

// str_at is element `i` of a utf8 column, borrowed from the column for the call.
pub fn (a ArrowArray) str_at(i int) !string {
	a.typed('u', 'utf8')!
	if i < 0 || i >= a.len {
		raise(.index_error, 'Arrow column index ${i} out of range for length ${a.len}')
		return error('index')
	}
	unsafe {
		off := &i32(a.values)
		start := off[a.offset + i]
		end := off[a.offset + i + 1]
		return tos(&u8(a.data) + start, end - start)
	}
}

// ArrowOut is a column built in V, returned to Python as an object implementing the Arrow
// PyCapsule interface (`__arrow_c_array__`), which pyarrow and polars take without a copy.
pub struct ArrowOut {
pub:
	obj PyObj
}

fn arrow_values_copy(src voidptr, bytes usize) voidptr {
	block := C.vpy_arrow_malloc(bytes)
	if block != unsafe { nil } && bytes > 0 {
		unsafe { vmemcpy(block, src, int(bytes)) }
	}
	return block
}

// arrow_f64 makes a float64 Arrow column from `values`.
pub fn arrow_f64(values []f64) ArrowOut {
	b := arrow_values_copy(values.data, usize(values.len) * sizeof(f64))
	return ArrowOut{steal(C.vpy_arrow_column(c'g', values.len, 2, unsafe { nil }, b, unsafe { nil }))}
}

// arrow_i64 makes an int64 Arrow column.
pub fn arrow_i64(values []i64) ArrowOut {
	b := arrow_values_copy(values.data, usize(values.len) * sizeof(i64))
	return ArrowOut{steal(C.vpy_arrow_column(c'l', values.len, 2, unsafe { nil }, b, unsafe { nil }))}
}

// arrow_i32 makes an int32 Arrow column.
pub fn arrow_i32(values []i32) ArrowOut {
	b := arrow_values_copy(values.data, usize(values.len) * sizeof(i32))
	return ArrowOut{steal(C.vpy_arrow_column(c'i', values.len, 2, unsafe { nil }, b, unsafe { nil }))}
}

// arrow_strings makes a utf8 Arrow column.
pub fn arrow_strings(values []string) ArrowOut {
	mut total := 0
	for s in values {
		total += s.len
	}
	offsets := &i32(C.vpy_arrow_malloc(usize(values.len + 1) * sizeof(i32)))
	data := &u8(C.vpy_arrow_malloc(usize(total)))
	mut at := 0
	for i, s in values {
		unsafe {
			offsets[i] = i32(at)
			if s.len > 0 {
				vmemcpy(&data[at], s.str, s.len)
			}
		}
		at += s.len
	}
	unsafe {
		offsets[values.len] = i32(at)
	}
	return ArrowOut{steal(C.vpy_arrow_column(c'u', values.len, 3, unsafe { nil }, offsets, data))}
}

// arrow_export hands an ArrowOut to Python.
pub fn arrow_export(o ArrowOut) PyObj {
	return o.obj
}
