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

// attr_base marks a class as inheriting another one. Its value is the base's name,
// which is why it is a name rather than a boolean like the rest.
pub const attr_base = 'vc_base'

// attr_error marks a struct as a V error type: a `!T` function's error carrying a Python
// exception class rather than a bare message.
pub const attr_error = 'vc_error'

// attr_ref marks a field as holding a strong reference to another instance. Its value
// is the class it accepts, empty when it accepts any vcraft instance, so it is a name
// where `@[vc_field]` is a boolean.
pub const attr_ref = 'vc_ref'

pub const attr_eq = 'vc_eq'

pub const attr_hash = 'vc_hash'

// known_attrs is every annotation the generator reacts to. Anything else in a
// `vc.` namespace is a typo and is reported rather than ignored, because a
// silently ignored annotation means a function quietly missing from the module.
pub const known_attrs = [
	attr_fn,
	attr_raw,
	attr_eq,
	attr_hash,
	attr_base,
	attr_ref,
	attr_error,
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
	// eq marks a method used as `tp_richcompare`'s equality. Exactly one per class.
	eq bool
	// hash marks a method used as `tp_hash`.
	hash bool
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
	// newstate_fn is the generated constructor of the whole state block. It is recursive:
	// a class with a base calls the base's newstate and assigns the result to its `base`
	// field, so a chain of any depth is built without knowing the depth in advance.
	newstate_fn string
	// dealloc is the generated `tp_dealloc`.
	dealloc string
	// repr is the generated `tp_repr`.
	repr string
	// base is the name of the class this one inherits, empty when it has none.
	base string
	// state_fields is every field the instance holds: this class's plus, when it has a
	// base, the base's. It is what the state block is laid out from.
	//
	// V has no struct inheritance, so a subclass names only its own fields and the
	// generated state is a struct holding the base followed by the subclass. A method
	// defined on the base therefore reads the same bytes it would on an instance of the
	// base, and one defined on the subclass sees its own fields.
	state_fields []Field
	// base_index is that class's position, resolved once every class is known. Negative
	// when there is no base or when the name did not resolve.
	base_index int = -1
	// eq_fn and hash_name are the user's methods marked `@[vc_eq]` and `@[vc_hash]`,
	// empty when the class declares neither.
	eq_fn     string
	hash_name string
	// richcompare and hash_fn are the generated `tp_richcompare` and `tp_hash`.
	richcompare string
	hash_fn string
	// key is the class name folded to snake_case, because V rejects an identifier
	// with uppercase letters in it.
	key string
	// origin, line and column place the declaration, for a diagnostic raised in a later
	// pass than the one that found it. A `@[vc_base]` naming a class that does not exist
	// can only be reported once every class is known, which is after the declaration has
	// been collected.
	origin string
	line   int
	column int
}

// Field is one exposed struct field.
// state_name is the name of the generated struct holding a subclass's state.
pub fn (c Class) state_name() string {
	return c.name + 'State'
}

// self_access is the path to the class's own struct inside the state block, with a
// trailing dot. Empty for a class with no base, `self.` for one that has.
pub fn (c Class) self_access() string {
	if c.base_index >= 0 {
		return 'self.'
	}
	return ''
}

// field_access is the expression that reaches a field from the state block.
//
// `self` for a class with a base, because its own fields live in the nested struct. A
// base's fields are reached the same way, so a method written against either class
// indexes the same struct.
pub fn (c Class) field_access(field string) string {
	if c.base_index >= 0 {
		return 'self.' + field
	}
	return field
}

// state_type is the type the state block is laid out from.
pub fn (c Class) state_type() string {
	if c.base_index >= 0 {
		return c.state_name()
	}
	return c.name
}

pub struct Field {
pub mut:
	name string
	doc  string
	// v_type is the declared field type, which decides the accessor.
	v_type string
	// setter is empty for a read-only field.
	setter string
	// ref marks a `@[vc_ref]` field, which holds a strong reference to another
	// instance rather than a value of its own.
	ref bool
	// ref_target is the class named by `@[vc_ref(Name)]`, empty when the field holds a
	// reference to any vcraft instance. Only a check: the field holds a `PyObj`, so
	// nothing in the layout depends on the target.
	ref_target string
	// path is the member path of this field within the *state block* of the class that
	// declares it, without the leading `state.`. Only set on the flattened list: a field
	// of the class itself is just its name, and one inherited from a base is reached
	// through the `base` half of the block, or through a further `self` for each
	// generation between the two.
	//
	// `state.<path>` is what a generated renderer reads. A field accessor does not use
	// it: an accessor is emitted once per declaring class and reads its own struct
	// directly, because the layout puts every generation at a fixed offset from the
	// start of the block.
	path string
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

// is_pyobj reports whether a V type is the runtime's own object reference.
//
// Both spellings, because V needs the qualified one in a module that imports vcraft and
// accepts the bare one in the runtime's own module. The generator compares the type as
// written rather than resolving it, so both have to be recognised here.
pub fn (f Field) is_pyobj() bool {
	return f.v_type == 'PyObj' || f.v_type == 'vcraft.PyObj'
}

// is_reference reports whether a field holds a strong reference to another instance.
//
// A reference field is a `PyObj`: a pointer plus a reference count, and nothing V's
// collector would recognise. That is what makes it safe to keep in memory CPython
// allocated, and it is also why the reference count has to be maintained by hand --
// `tp_traverse` reports it to the collector and `tp_clear` releases it.
pub fn (f Field) is_reference() bool {
	return f.ref
}

// ErrorType is a struct annotated `@[vc_error]`.
//
// V erases an error to `IError` by the time a wrapper sees it, so nothing in the error
// value can be read on the far side. What the generator can do is check the type is
// usable as an error and emit a raiser for it, which sets the pending Python exception
// from the struct's own field before the value is returned.
pub struct ErrorType {
pub mut:
	name string
	// exc_field is the field holding the Python exception class. Empty when the type
	// carries no class and names a builtin one through `code()` instead.
	exc_field string
	doc       string
	origin    string
	line      int
	// raiser is the generated function that turns a value of this type into an error with
	// its exception set.
	raiser string
}

// Project is everything the generator found.
// Operator is a `vc_eq` or `vc_hash` function seen before the class it belongs to.
//
// Held rather than resolved on the spot, because the class may be declared later in the
// same file or in a file that sorts after this one.
pub struct Operator {
pub mut:
	name   string
	// kind is `eq` or `hash`.
	kind   string
	origin string
	line   int
	column int
}

pub struct Project {
pub mut:
	// errors are the `@[vc_error]` types found, in declaration order.
	errors []ErrorType
	// module is the V module the glue will be compiled into. It is the user's own
	// module, so the generated file calls their functions directly with no module
	// prefix and no cross-module edge.
	module string
	// package is the Python package name, which is what `PyInit_` is named after.
	package     string
	funcs   []Func
	classes []Class
	// operators holds `vc_eq` and `vc_hash` functions seen before the class they belong
	// to. They are free functions, so they are dispatched from the `.fn` arm and the
	// class may not have been collected yet.
	operators []Operator
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
