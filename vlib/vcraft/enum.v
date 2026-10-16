module vcraft

// Generated Python enums.
//
// A V `enum` crosses as a generated `enum.IntEnum` subclass: the members keep their names
// and values, so a value reads back as the member rather than as a bare int, and an
// integer that is not a member is refused on the way in. The class is built once at exec
// and attached to the module under the enum's own name.

// import_module imports `name` and returns a new reference to the module, or the null
// object with an exception set.
pub fn import_module(name string) PyObj {
	namep := cstring(name)
	out := steal(C.vpy_import(namep))
	free_cstring(namep)
	return out
}

// int_enum builds an `enum.IntEnum` subclass named `name` whose members are `members`.
//
// `name` is the V enum's name, so `Color.red` on the Python side is the V `Color.red`,
// and the class shows up in the module as `Color`.
pub fn int_enum(name string, members map[string]i64) PyObj {
	enum_mod := import_module('enum')
	if enum_mod.is_null() {
		return enum_mod
	}
	cls := getattr(enum_mod.ptr, 'IntEnum')
	enum_mod.decref()
	if cls.is_null() {
		return cls
	}
	table := new_dict()
	if table.is_null() {
		cls.decref()
		return table
	}
	for member, value in members {
		dict_set_owned(table, to_py_string(member), to_py_int(value))
	}
	// `call_owned` releases the name and the table it was given; `cls` is the caller's.
	result := call_owned(cls.ptr, [to_py_string(name), table])
	cls.decref()
	return result
}

// enum_member returns the member of `cls` whose value is `value`, or the null object with
// an exception set. A V enum value is always a member, so the class call cannot fail for
// a value that came from V.
pub fn enum_member(cls voidptr, value i64) PyObj {
	return call_owned(cls, [to_py_int(value)])
}

// enum_value reads `obj` as a member of `cls` and returns its integer value, or an error
// with a Python exception set. Calling the class is what rejects an integer that is not a
// member, which a plain cast would accept.
pub fn enum_value(cls voidptr, obj PyObj, name string) !i64 {
	member := call(cls, [obj.ptr])
	if member.is_null() {
		return error('${name}: not a member')
	}
	out := from_py_int(member, name) or {
		member.decref()
		return error('${name}: not a member')
	}
	member.decref()
	return i64(out)
}
