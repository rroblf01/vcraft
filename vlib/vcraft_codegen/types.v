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
	// PyObj passes an arbitrary object through untouched. This is the `@[vc.raw]`
	// escape hatch and it costs nothing.
	pyobj
	// Seq accepts any Python iterable and builds a V slice from it.
	seq
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
		.pyobj { 'Any' }
		.seq { 'Sequence[Any]' }
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
