module vcraft

// Conversions for the standard-library types a V signature can name beyond the scalars:
// `time.Time` and `time.Duration` (Python's `datetime` and `timedelta`), `vcraft.Decimal`
// (Python's `decimal.Decimal`) and `big.Integer` (a Python `int` of any size), plus the
// bridge from V code to Python's `logging`.
//
// The runtime itself imports neither `time` nor `math.big`: these helpers trade in plain
// integers and strings, and the generated glue -- which imports those modules only when a
// signature uses them -- builds the V values. An extension that never names a date pays
// nothing for this file.

// datetime_mod and decimal_mod return the standard-library module, imported once per
// process and kept (in C: the runtime has no V globals). Borrowed; null with an exception
// set when the import failed.
fn datetime_mod() PyObj {
	return borrow(C.vpy_cached_module(0))
}

fn decimal_mod() PyObj {
	return borrow(C.vpy_cached_module(1))
}

// is_instance_named reports whether `o` is an instance of `module.cls`.
fn is_instance_named(o PyObj, module PyObj, cls string) bool {
	if module.is_null() {
		return false
	}
	typ := getattr(module.ptr, cls)
	if typ.is_null() {
		clear_error()
		return false
	}
	r := C.PyObject_IsInstance(o.ptr, typ.ptr)
	typ.decref()
	return r == 1
}

// int_attr reads an integer attribute.
fn int_attr(o PyObj, name string) !i64 {
	v := getattr(o.ptr, name)
	if v.is_null() {
		return error(name)
	}
	out := from_py_int(v, name) or {
		v.decref()
		return err
	}
	v.decref()
	return out
}

// datetime_parts reads a `datetime.datetime` as [year, month, day, hour, minute, second,
// microsecond]. An aware one is converted to UTC first, so the fields name one instant;
// a naive one is taken as written.
pub fn datetime_parts(o PyObj, name string) ![]int {
	dt := datetime_mod()
	if dt.is_null() || !is_instance_named(o, dt, 'datetime') {
		raise(.type_error, '${name}: expected datetime.datetime, got ${o.type_name()}')
		return error(name)
	}
	mut src := o
	mut owned := false
	tz := getattr(o.ptr, 'tzinfo')
	if !tz.is_null() && !is_none_ptr(tz.ptr) {
		timezone := getattr(dt.ptr, 'timezone')
		utc := getattr(timezone.ptr, 'utc')
		timezone.decref()
		converted := call_method(o.ptr, 'astimezone', [utc.ptr])
		utc.decref()
		if converted.is_null() {
			tz.decref()
			return error(name)
		}
		src = converted
		owned = true
	}
	tz.decref()
	mut out := []int{cap: 7}
	for field in ['year', 'month', 'day', 'hour', 'minute', 'second', 'microsecond'] {
		value := int_attr(src, field) or {
			if owned {
				src.decref()
			}
			return err
		}
		out << int(value)
	}
	if owned {
		src.decref()
	}
	return out
}

// to_py_datetime builds a naive `datetime.datetime` from its fields.
pub fn to_py_datetime(year int, month int, day int, hour int, minute int, second int, microsecond int) PyObj {
	dt := datetime_mod()
	if dt.is_null() {
		return dt
	}
	cls := getattr(dt.ptr, 'datetime')
	if cls.is_null() {
		return cls
	}
	out := call_owned(cls.ptr, [to_py_int(year), to_py_int(month), to_py_int(day),
		to_py_int(hour), to_py_int(minute), to_py_int(second), to_py_int(microsecond)])
	cls.decref()
	return out
}

// timedelta_microseconds reads a `datetime.timedelta` as a whole number of microseconds.
pub fn timedelta_microseconds(o PyObj, name string) !i64 {
	dt := datetime_mod()
	if dt.is_null() || !is_instance_named(o, dt, 'timedelta') {
		raise(.type_error, '${name}: expected datetime.timedelta, got ${o.type_name()}')
		return error(name)
	}
	days := int_attr(o, 'days')!
	seconds := int_attr(o, 'seconds')!
	micros := int_attr(o, 'microseconds')!
	return (days * 86400 + seconds) * 1_000_000 + micros
}

// to_py_timedelta builds a `datetime.timedelta` of `microseconds`.
pub fn to_py_timedelta(microseconds i64) PyObj {
	dt := datetime_mod()
	if dt.is_null() {
		return dt
	}
	cls := getattr(dt.ptr, 'timedelta')
	if cls.is_null() {
		return cls
	}
	out := call_kw(cls.ptr, []voidptr{}, {
		'microseconds': to_py_int(microseconds)
	})
	cls.decref()
	return out
}

// Decimal is a `decimal.Decimal` that crossed into V, kept as its exact text: V has no
// decimal type, and a float would round it. Parse it with whatever arithmetic the code
// uses, and build one with `vcraft.decimal('12.50')` to return.
pub struct Decimal {
pub:
	text string
}

// decimal makes a Decimal from its text, e.g. `vcraft.decimal('12.50')`.
pub fn decimal(text string) Decimal {
	return Decimal{
		text: text
	}
}

// str is the decimal's exact text.
pub fn (d Decimal) str() string {
	return d.text
}

// from_py_decimal reads a `decimal.Decimal` or an `int` as its exact text.
pub fn from_py_decimal(o PyObj, name string) !Decimal {
	dec := decimal_mod()
	if !o.type_is(long_type()) && (dec.is_null() || !is_instance_named(o, dec, 'Decimal')) {
		raise(.type_error, '${name}: expected decimal.Decimal, got ${o.type_name()}')
		return error(name)
	}
	text := steal(C.PyObject_Str(o.ptr))
	if text.is_null() {
		return error(name)
	}
	out := from_py_string(text, name) or {
		text.decref()
		return err
	}
	kept := out.clone()
	text.decref()
	return Decimal{
		text: kept
	}
}

// to_py_decimal builds a `decimal.Decimal` from a Decimal's text.
pub fn to_py_decimal(d Decimal) PyObj {
	dec := decimal_mod()
	if dec.is_null() {
		return dec
	}
	cls := getattr(dec.ptr, 'Decimal')
	if cls.is_null() {
		return cls
	}
	out := call_owned(cls.ptr, [to_py_string(d.text)])
	cls.decref()
	return out
}

// int_to_decimal_string reads a Python `int` of any size as its decimal digits, which
// `big.integer_from_string` parses.
pub fn int_to_decimal_string(o PyObj, name string) !string {
	if !o.type_is(long_type()) {
		raise(.type_error, '${name}: expected int, got ${o.type_name()}')
		return error(name)
	}
	text := steal(C.PyObject_Str(o.ptr))
	if text.is_null() {
		return error(name)
	}
	out := (from_py_string(text, name) or {
		text.decref()
		return err
	}).clone()
	text.decref()
	return out
}

// int_from_decimal_string builds a Python `int` from decimal digits, any size.
pub fn int_from_decimal_string(digits string) PyObj {
	p := cstring(digits)
	out := steal(C.PyLong_FromString(p, unsafe { nil }, 10))
	free_cstring(p)
	return out
}

// Logging.
//
// `vcraft.log_info('...')` and its siblings write to Python's `logging`, through the
// logger named after the extension module, so a V message lands wherever the
// application's logging configuration sends Python's own: handlers, levels, formatting.
// They may be called from any thread, with or without the GIL -- a `@[vc_nogil]` or
// `@[vc_async]` function included -- and take the GIL for the call.

pub const log_debug_level = 10
pub const log_info_level = 20
pub const log_warning_level = 30
pub const log_error_level = 40

// log writes `message` at a `logging` level number.
pub fn log(level int, message string) {
	state := gil_ensure()
	logger := steal(C.vpy_logger())
	if !logger.is_null() {
		lvl := to_py_int(level)
		msg := to_py_string(message)
		r := call_method(logger.ptr, 'log', [lvl.ptr, msg.ptr])
		if r.is_null() {
			clear_error()
		}
		r.decref()
		lvl.decref()
		msg.decref()
		logger.decref()
	} else {
		clear_error()
	}
	gil_release(state)
}

pub fn log_debug(message string) {
	log(log_debug_level, message)
}

pub fn log_info(message string) {
	log(log_info_level, message)
}

pub fn log_warning(message string) {
	log(log_warning_level, message)
}

pub fn log_error(message string) {
	log(log_error_level, message)
}

// set_logger_name names the logger `log` writes to; the generated module initialiser
// calls it with the module's name.
pub fn set_logger_name(name string) {
	p := cstring(name)
	C.vpy_set_logger_name(p)
	free_cstring(p)
}
