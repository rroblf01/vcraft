module vcraft_codegen

// The model the generator builds from a project, and emits from.
//
// It is deliberately small: one function per exported declaration, with the
// parameter list already split into the parts the emitter needs. Nothing here
// knows about CPython.

// Annotation names the generator acts on. They live under a `vc_` prefix so that
// a project's own annotations cannot collide with them.
pub const attr_fn = 'vc_fn'

pub const attr_raw = 'vc_raw'

pub const attr_nogil = 'vc_gil'

pub const attr_class = 'vc_class'

pub const attr_methods = 'vc_methods'

pub const attr_field = 'vc_field'

pub const attr_property = 'vc_property'

pub const attr_static = 'vc_static'

// known_attrs is every annotation the generator reacts to. Anything else in a
// `vc.` namespace is a typo and is reported rather than ignored, because a
// silently ignored annotation means a function quietly missing from the module.
pub const known_attrs = [
	attr_fn,
	attr_raw,
	attr_nogil,
	attr_class,
	attr_methods,
	attr_field,
	attr_property,
	attr_static,
]

// Param is one declared parameter.
pub struct Param {
pub mut:
	name string
	// v_type is the type as written, which for a parameter is never a result
	// type and so needs no splitting.
	v_type string
}

// Func is one function the generator will export. It is filled in piecewise as the
// scan learns more about it, so its fields are mutable.
pub struct Func {
pub mut:
	name string
	// v_ret is the declared return type, already split so that `!string` yields
	// `string` and `!void` yields an empty result.
	v_ret string
	// returns_result is true when the declared return type was `!T`, which is
	// what makes the generated wrapper translate a failure into a Python
	// exception.
	returns_result bool
	params        []Param
	// doc is the doc comment, already stripped of its `//` markers. It becomes
	// the Python `__doc__`.
	doc string
	// raw marks a function the generated wrapper must not marshal at all: it
	// takes and returns `voidptr` and sees the real PyObject pointers.
	raw bool
	// nogil marks a pure V function the wrapper may call with the GIL released.
	nogil bool
	// property marks a method exposed as a Python property rather than a call.
	property bool
	// static marks a method that takes no receiver.
	static bool
	// mangled is the C-level V name of the trampoline, unique within the module.
	trampoline string
	// origin, line and column place the declaration, for a diagnostic raised in a
	// later pass than the one that found it.
	origin string
	line   int
	column int
}

// Class is one struct the generator will expose as a Python type.
pub struct Class {
pub mut:
	name string
	doc  string
	// qualified is the name the type is created under, which is the V module name
	// plus the class name, so that two modules may each declare a `Point`.
	qualified string
	// storage is the C name of the generated size constant.
	storage string
	fields  []Field
	methods []Func
	// ctor_fn is the user's `new_*` function, run by `tp_new`. Empty when the class
	// has none, in which case instances can only be built from V.
	ctor_fn string
	// ctor is the generated `tp_new` trampoline.
	ctor string
	// ctype is the local the generated `PyInit` holds the heap type in.
	ctype string
	// size_fn is the generated helper reporting the struct's size in bytes.
	size_fn string
	// dealloc is the generated `tp_dealloc`.
	dealloc string
	// repr is the generated `tp_repr`.
	repr string
	// key is the class name folded to snake_case, because V rejects an identifier
	// with uppercase letters in it.
	key string
}

// Field is one exposed struct field.
pub struct Field {
pub mut:
	name string
	doc  string
	// v_type is the declared field type, which decides the accessor.
	v_type string
	// setter is empty for a read-only field.
	setter string
}

// is_scalar reports whether a field type is safe to hold in CPython-owned memory.
//
// Only scalars are. A `string` copied there would be a Boehm pointer that nothing
// keeps alive, because Boehm does not scan memory CPython allocated.
pub fn (f Field) is_scalar() bool {
	return match f.v_type {
		'bool', 'int', 'i8', 'i16', 'i32', 'i64', 'isize' { true }
		'u8', 'u16', 'u32', 'u64', 'usize' { true }
		'f32', 'f64' { true }
		else { false }
	}
}

// Project is everything the generator found.
pub struct Project {
pub mut:
	// module is the V module the glue will be compiled into. It is the user's own
	// module, so the generated file calls their functions directly with no module
	// prefix and no cross-module edge.
	module string
	// package is the Python package name, which is what `PyInit_` is named after.
	package     string
	funcs       []Func
	classes     []Class
	// diagnostics are problems found while scanning. They do not stop generation;
	// the emitter reports them all at once so a project with five mistakes takes
	// one build to fix rather than five.
	diagnostics []Diagnostic
}

// Diagnostic is one problem, anchored to a source position.
pub struct Diagnostic {
pub:
	file    string
	line    int
	column  int
	message string
}

// error renders a diagnostic the way a compiler would.
pub fn (d Diagnostic) error() string {
	return '${d.file}:${d.line}:${d.column}: ${d.message}'
}

// has_errors reports whether any diagnostic is fatal. Warnings are not, so the
// field is kept separate from the message rather than encoded in it.
pub fn (p Project) has_errors() bool {
	return p.diagnostics.any(it.message.starts_with('error'))
}
