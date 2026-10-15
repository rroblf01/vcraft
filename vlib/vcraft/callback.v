module vcraft

// Calling Python callables from V.
//
// The other direction of the boundary. A V function runs inside a trampoline that holds
// the GIL, so it can call back into Python: the callable arrives as a `voidptr` (from a
// `@[vc_raw]` parameter, or a `vcraft.PyObj` field) and the arguments are boxed with the
// usual `to_py_*` helpers.
//
// Re-entry is safe. The state chain is a per-thread stack that a trampoline restores on
// the way out, so a Python callable that calls back into a vcraft method sees its own
// state and leaves the caller's untouched. A Python exception raised by the callable is
// just a pending exception: `error_is_set` reports it and the trampoline returns null
// the same way it does for any other failure.

// call calls `callee` with the positional `args` and returns a new reference to the
// result, or the null object with a Python exception set.
//
// `args` are borrowed: the runtime takes its own reference to each, so the caller keeps
// whatever it held and a temporary it built can be released right after. Use `call_owned`
// to have the runtime release arguments it was given ownership of.
pub fn call(callee voidptr, args []voidptr) PyObj {
	unsafe {
		return steal(C.vpy_call(callee, args.data, isize(args.len)))
	}
}

// call_owned is `call` for arguments the caller built only for the call and does not
// keep: it releases each one after the call, on success or failure.
pub fn call_owned(callee voidptr, args []PyObj) PyObj {
	mut raw := []voidptr{cap: args.len}
	for a in args {
		raw << a.ptr
	}
	result := call(callee, raw)
	for a in args {
		a.decref()
	}
	return result
}

// getattr returns a new reference to `obj`'s attribute `name`, or the null object with a
// Python exception set (for example AttributeError). This is how a method is fetched to
// pass to `call`.
pub fn getattr(obj voidptr, name string) PyObj {
	namep := cstring(name)
	out := steal(C.PyObject_GetAttrString(obj, namep))
	free_cstring(namep)
	return out
}

// call_method calls `obj.name(...)` with the positional `args` (borrowed) and returns a
// new reference, or the null object with an exception set.
pub fn call_method(obj voidptr, name string, args []voidptr) PyObj {
	m := getattr(obj, name)
	if m.is_null() {
		return m
	}
	result := call(m.ptr, args)
	m.decref()
	return result
}
