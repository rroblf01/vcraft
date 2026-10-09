module vcraft_codegen

// The type table: what each V type marshals to, and how.
//
// It is the contract with the user. A type that is not in it becomes a compile time
// diagnostic naming the file, line and column, never a runtime surprise.

// Strategy is how a value crosses the boundary.
pub enum Strategy {
	// Void is a V function returning nothing, which becomes None.
	void
	// Int, Uint and Float go through the matching CPython accessor.
	int
	uint
	float
	// Bool accepts any object and uses Python's truth test.
	bool
	// Str and Bytes map onto Python str and bytes.
	str
	bytes
	// PyObj passes an arbitrary object through untouched. This is the `@[vc_raw]`
	// escape hatch and it costs nothing.
	pyobj
	// PyRef is a V value that is already a `PyObj`: the type of a `@[vc_ref]` field, and
	// what a function returns when it hands back an object rather than a `voidptr`.
	//
	// Distinct from PyObj because the two cross the boundary in opposite directions. A
	// `voidptr` is a raw borrowed pointer and the generated code passes it straight
	// through, while a `PyObj` is an owned reference and boxing one hands that ownership
	// to CPython rather than copying a pointer at it.
	pyref
	// Seq accepts any Python iterable and builds a V slice from it.
	seq
	// Optional is `?T` of a scalar or a string: `none` in V is `None` in Python, both ways.
	optional
	// Dict is `map[string]T` of a scalar or a string: a `dict` with `str` keys in, a new
	// `dict` out.
	dict
	// Tuple is a multi-value return, `(A, B)`, which Python receives as a `tuple`. V has
	// no tuple type for a parameter, so it exists only as a result.
	tuple
	// Fixed is a fixed-size array, `[N]T`: any sequence of exactly N items in, a `list`
	// out.
	fixed
	// Unsupported means the generator refuses to emit code for it.
	unsupported
}

// lookup classifies a V type as written in a signature.
//
// The leading `!` of a result type is stripped by the caller, so it never reaches
// here. What arrives is either a scalar, `[]T`, or something unrecognised.
pub fn lookup(v_type string) Strategy {
	base := v_type.trim_space()
	if base == 'void' {
		return .void
	}
	if base == 'voidptr' || base.len == 0 {
		return .pyobj
	}
	// `PyObj` unqualified, because a user's module imports vcraft and names the type
	// without a prefix wherever the annotation makes the type obvious. A `vcraft.PyObj`
	// is the same type written out.
	if base == 'PyObj' || base == 'vcraft.PyObj' {
		return .pyref
	}
	// The composite types are recognised by their shape before the scalar names, and
	// only over element types that are themselves plain values: anything else stays
	// unsupported, so it is a diagnostic rather than glue that does not compile.
	if base.starts_with('?') {
		return if is_plain_value(base[1..]) { Strategy.optional } else { Strategy.unsupported }
	}
	if base.starts_with('map[') {
		if base.starts_with('map[string]') && is_plain_value(base['map[string]'.len..]) {
			return .dict
		}
		return .unsupported
	}
	if base.starts_with('(') && base.ends_with(')') {
		parts := tuple_parts(base)
		return if parts.len >= 2 && parts.all(is_plain_value(it)) {
			Strategy.tuple
		} else {
			Strategy.unsupported
		}
	}
	if base.starts_with('[') && !base.starts_with('[]') {
		n, element := fixed_parts(base)
		return if n > 0 && is_plain_value(element) { Strategy.fixed } else { Strategy.unsupported }
	}
	return match base {
		'bool' { Strategy.bool }
		'int', 'i8', 'i16', 'i32', 'i64', 'isize', 'rune' { Strategy.int }
		'u8', 'u16', 'u32', 'u64', 'usize' { Strategy.uint }
		'f32', 'f64' { Strategy.float }
		'string' { Strategy.str }
		'[]u8' { Strategy.bytes }
		else {
			if base.starts_with('[]') {
				Strategy.seq
			} else {
				Strategy.unsupported
			}
		}
	}
}

// describe returns the type as it should appear in a Python signature.
pub fn describe(v_type string) string {
	return match lookup(v_type) {
		.void { 'None' }
		.bool { 'bool' }
		.int, .uint { 'int' }
		.float { 'float' }
		.str { 'str' }
		.bytes { 'bytes' }
		// `.pyref` needs its own arm: V compiled this match without it, and the missing
		// arm returned an unset string that crashed the generator inside `+`.
		.pyobj, .pyref { 'Any' }
		.seq { 'Sequence[Any]' }
		.optional { describe(v_type.trim_space()[1..]) + ' | None' }
		.dict { 'dict[str, ' + describe(v_type.trim_space()['map[string]'.len..]) + ']' }
		.tuple { 'tuple[' + tuple_parts(v_type.trim_space()).map(describe(it)).join(', ') + ']' }
		.fixed { 'list[' + describe(fixed_element(v_type)) + ']' }
		.unsupported { 'Any' }
	}
}

// split_result separates a declared return type into its value type and whether it
// was a result type at all.
//
//	!string  -> 'string', true
//	!void    -> '',      true
//	int      -> 'int',   false
//	string!  -> 'string', true
pub fn split_result(declared string) (string, bool) {
	text := declared.trim_space()
	if text.starts_with('!') {
		return text[1..].trim_space(), true
	}
	if text.ends_with('!') {
		return text[..text.len - 1].trim_space(), true
	}
	return text, false
}

// is_plain_value reports whether a type is a scalar or a string: the element types the
// composite strategies accept.
pub fn is_plain_value(v_type string) bool {
	return lookup(v_type) in [Strategy.bool, .int, .uint, .float, .str]
}

// tuple_parts splits a multi-value type, `(int, string)`, into its element types.
pub fn tuple_parts(v_type string) []string {
	inner := v_type.trim_space()
	if !inner.starts_with('(') || !inner.ends_with(')') {
		return []string{}
	}
	return inner[1..inner.len - 1].split(',').map(it.trim_space()).filter(it.len > 0)
}

// fixed_parts splits a fixed-size array type, `[3]int`, into its length and element
// type. The length is 0 when it is not a plain number, such as a constant's name.
pub fn fixed_parts(v_type string) (int, string) {
	t := v_type.trim_space()
	close := t.index(']') or { return 0, '' }
	size := t[1..close]
	if size.len == 0 || !size.bytes().all(it.is_digit()) {
		return 0, ''
	}
	return size.int(), t[close + 1..]
}

// fixed_element is the element type of a fixed-size array.
pub fn fixed_element(v_type string) string {
	_, element := fixed_parts(v_type)
	return element
}
