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

// attr_nogil releases the GIL around a call. It was spelled `vc_gil` before 1.0, which
// read as the opposite; that name is still accepted, with a warning.
pub const attr_nogil = 'vc_nogil'

pub const attr_class = 'vc_class'

// attr_methods exposes one method. It was spelled `vc_methods` before 1.0, after
// PyO3's `#[pymethods]`, which annotates a whole impl block that V does not have; that
// name is still accepted, with a warning.
pub const attr_methods = 'vc_method'

pub const attr_field = 'vc_field'

// attr_buffer marks a field as a persistent native buffer: a `[]T` of scalars whose
// backing lives for the object's lifetime, is not copied per call, and is freed by the
// generated `tp_dealloc`. Unlike `@[vc_field]` it is not exposed as a Python attribute;
// it is reachable through `memoryview(instance)` (the first one) and through methods.
pub const attr_buffer = 'vc_buffer'

// attr_buffer_typed is `@[vc_buffer]`'s opt-in: `memoryview(instance)` reports a typed
// view -- format and itemsize from the element type, one item per element -- instead of
// the default 1-D byte view. It is a separate annotation so the change is deliberate.
pub const attr_buffer_typed = 'vc_buffer_typed'

// attr_memoryview marks a function or method whose `[]T` result is handed to Python as a
// writable `memoryview` with no copy, instead of being boxed as a list or a `bytes`. The
// slice must be native-backed (`buffer_new_*`), because the view takes ownership of it.
pub const attr_memoryview = 'vc_memoryview'

// attr_opaque marks a function whose `voidptr` result is an opaque native pointer rather
// than a borrowed `PyObject`. The wrapper hands it to Python in a capsule, which is the
// only way a pointer Python does not own can travel safely; an unannotated `voidptr`
// result is a `PyObject *` and returning anything else through it crashes the interpreter.
// `@[vc_opaque: 'free_fn']` names the capsule's destructor.
pub const attr_opaque = 'vc_opaque'

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

// attr_handle marks a field as native state the class owns: a `vcraft.Owned`, a pointer
// and the function that releases it. The generated `tp_dealloc` calls `release` on it, so
// the allocation's lifetime is the instance's. It is not exposed to Python.
pub const attr_handle = 'vc_handle'

// attr_defaults gives parameters default values: `@[vc_defaults: 'step=1, name="x"']`.
// V has no default arguments of its own, so they are declared on the function.
pub const attr_defaults = 'vc_defaults'

pub const attr_eq = 'vc_eq'

// The ordering operators. Each is a free function `(a voidptr, b voidptr) bool`, like
// `@[vc_eq]`, because V allows one receiver per method and an operator needs two
// operands. They fill `tp_richcompare`'s `<`, `<=`, `>` and `>=`.
pub const attr_lt = 'vc_lt'

pub const attr_le = 'vc_le'

pub const attr_gt = 'vc_gt'

pub const attr_ge = 'vc_ge'

// The numeric operators. Like `@[vc_eq]`, each is a free function whose name starts
// with the class's snake_case name, because V allows one receiver per method and a
// binary operator has two operands. The forward annotation fills the `nb_*` slot the
// runtime names; `@[vc_radd]` and the rest are the reflected forms CPython reaches when
// the instance is the *right* operand (`2 + counter`), and the four unary ones take no
// second operand.
pub const attr_add = 'vc_add'

pub const attr_radd = 'vc_radd'

pub const attr_sub = 'vc_sub'

pub const attr_rsub = 'vc_rsub'

pub const attr_mul = 'vc_mul'

pub const attr_rmul = 'vc_rmul'

pub const attr_truediv = 'vc_truediv'

pub const attr_rtruediv = 'vc_rtruediv'

pub const attr_floordiv = 'vc_floordiv'

pub const attr_rfloordiv = 'vc_rfloordiv'

pub const attr_mod = 'vc_mod'

pub const attr_rmod = 'vc_rmod'

pub const attr_pow = 'vc_pow'

pub const attr_rpow = 'vc_rpow'

pub const attr_lshift = 'vc_lshift'

pub const attr_rlshift = 'vc_rlshift'

pub const attr_rshift = 'vc_rshift'

pub const attr_rrshift = 'vc_rrshift'

pub const attr_and = 'vc_and'

pub const attr_rand = 'vc_rand'

pub const attr_or = 'vc_or'

pub const attr_ror = 'vc_ror'

pub const attr_xor = 'vc_xor'

pub const attr_rxor = 'vc_rxor'

pub const attr_neg = 'vc_neg'

pub const attr_pos = 'vc_pos'

pub const attr_abs = 'vc_abs'

pub const attr_invert = 'vc_invert'

// attr_len marks a method as `__len__`: no parameters, an integer result, installed as
// `sq_length`. It makes `len(instance)` and `bool(instance)` work.
pub const attr_len = 'vc_len'

// attr_getitem marks a method as `__getitem__`: one integer parameter, installed as
// `sq_item`. It makes `instance[i]` work.
pub const attr_getitem = 'vc_getitem'

// attr_setitem marks a method as `__setitem__`: an integer index plus a value,
// installed as `sq_ass_item`. It makes `instance[i] = value` work.
pub const attr_setitem = 'vc_setitem'

// attr_contains marks a method as `__contains__`: one parameter, a bool result,
// installed as `sq_contains`. It makes `x in instance` work.
pub const attr_contains = 'vc_contains'

// attr_classmethod marks a `fn Class.name(...)` as a Python `classmethod`. It is like
// `@[vc_static]` but CPython passes the class rather than NULL, so a subclass calling it
// sees the subclass.
pub const attr_classmethod = 'vc_classmethod'

// attr_const marks a `pub const NAME = value` as a module-level Python attribute. The
// value must be an int, a float, a bool or a string.
pub const attr_const = 'vc_const'

// attr_iter marks a method as the class's `__iter__`: the instance is its own iterator,
// so the slot returns the instance itself after running the method for its side effects.
pub const attr_iter = 'vc_iter'

// attr_next marks a method as the class's `__next__`: each call returns the next item,
// and a V error ends the iteration -- cleanly for `StopIteration`, loudly otherwise.
pub const attr_next = 'vc_next'

pub const attr_hash = 'vc_hash'

// known_attrs is every annotation the generator reacts to. Anything else in a
// `vc.` namespace is a typo and is reported rather than ignored, because a
// silently ignored annotation means a function quietly missing from the module.
// deprecated_attrs maps a name from before 1.0 to the one that replaced it. Both
// work throughout 1.x; the old one draws a warning and goes in 2.0.
pub const deprecated_attrs = {
	'vc_gil':     'vc_nogil'
	'vc_methods': 'vc_method'
}

// canonical_attr is the current name of an annotation, given either spelling.
pub fn canonical_attr(name string) string {
	return deprecated_attrs[name] or { name }
}

pub const known_attrs = [
	attr_fn,
	attr_defaults,
	attr_raw,
	attr_eq,
	attr_hash,
	attr_lt,
	attr_le,
	attr_gt,
	attr_ge,
	attr_add,
	attr_radd,
	attr_sub,
	attr_rsub,
	attr_mul,
	attr_rmul,
	attr_truediv,
	attr_rtruediv,
	attr_floordiv,
	attr_rfloordiv,
	attr_mod,
	attr_rmod,
	attr_pow,
	attr_rpow,
	attr_lshift,
	attr_rlshift,
	attr_rshift,
	attr_rrshift,
	attr_and,
	attr_rand,
	attr_or,
	attr_ror,
	attr_xor,
	attr_rxor,
	attr_neg,
	attr_pos,
	attr_abs,
	attr_invert,
	attr_len,
	attr_getitem,
	attr_setitem,
	attr_contains,
	attr_classmethod,
	attr_const,
	attr_iter,
	attr_next,
	attr_base,
	attr_ref,
	attr_error,
	attr_nogil,
	attr_class,
	attr_methods,
	attr_field,
	attr_buffer,
	attr_buffer_typed,
	attr_handle,
	attr_opaque,
	attr_memoryview,
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
	// default is the value from `@[vc_defaults]` as written there, e.g. `1` or `"x"`,
	// or empty when the parameter has none. Validated against the type before any
	// glue is written.
	default string
	// instance_target is the class name when the parameter is `&T` and `T` resolved to a
	// class: the wrapper checks the argument is an instance of it and hands the V
	// function a pointer into that instance's state. Empty for every other parameter.
	instance_target string
	// instance_handle is the V expression for the target class's type object, and
	// instance_offset is where its struct starts in the state block. Both are filled in
	// with instance_target.
	instance_handle string
	instance_offset string
}

// optional reports whether a caller may leave the parameter out: it has a default, or
// it is `?T`, which defaults to None.
pub fn (p Param) optional() bool {
	return p.default.len > 0 || p.v_type.trim_space().starts_with('?')
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
	// opaque marks a function whose `voidptr` result is a native pointer, not a borrowed
	// `PyObject`: the wrapper hands it to Python in a capsule.
	opaque bool
	// opaque_destructor is the V function `@[vc_opaque: 'name']` names as the capsule's
	// destructor, empty when the pointer outlives the capsule (a process-wide context).
	opaque_destructor string
	// export_buffer marks a function whose `[]T` result is returned as a zero-copy
	// `memoryview` over native-backed memory, rather than boxed as a list. The slice's
	// backing must come from `buffer_new_*`: the view takes ownership of it.
	export_buffer bool
	// unknown_defaults are names in `@[vc_defaults]` that are not parameters, kept for
	// a diagnostic once the declaration's position is known.
	unknown_defaults []string
	// property marks a method exposed as a Python property rather than a call.
	property bool
	// static marks a method that takes no receiver.
	static bool
	// static_receiver names the class a `@[vc_static]` method belongs to. The V function
	// is `Receiver.name` and its trampoline gets NULL as `self`, so the call target and
	// the Python name have to be carried separately.
	static_receiver string
	// eq marks a method used as `tp_richcompare`'s equality. Exactly one per class.
	eq bool
	// hash marks a method used as `tp_hash`.
	hash bool
	// is_iter marks a method used as `tp_iter`. Exactly one per class, paired with one
	// `is_next`: an iterator that cannot produce items is a trap, and items without an
	// iterator are unreachable.
	is_iter bool
	// is_next marks a method used as `tp_iternext`.
	is_next bool
	// is_len, is_getitem and is_contains mark a method used as `sq_length`, `sq_item`
	// and `sq_contains`: `len(instance)`, `instance[i]` and `x in instance`.
	is_len      bool
	is_getitem  bool
	is_setitem  bool
	is_contains bool
	// classmethod marks a `fn Class.name(...)` registered with `METH_CLASS`, so CPython
	// passes the class rather than NULL and a subclass sees itself.
	classmethod bool
	// instance_result is the class name when the function returns `&T` and `T` resolved
	// to a class: the wrapper hands Python the instance the pointer points into. Empty
	// for every other result. instance_result_handle and instance_result_offset are its
	// type object and struct offset, filled in with instance_result.
	instance_result        string
	instance_result_handle string
	instance_result_offset string
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
	// ctor_params is the constructor's parameters. They travel through the same
	// marshalling rules as a method's, read in `tp_new` from the tuple and dict CPython
	// passes there, so a class can be sized at construction: `new_tableau(2 * n + 1)`.
	ctor_params []Param
	// ctor_has_defaults is true when any constructor parameter carries `@[vc_defaults]`,
	// which only matters for the generated signature's rendering.
	ctor_has_defaults bool
	// ctor_opaque is true when the constructor is `@[vc_opaque]`: every `voidptr`
	// parameter is unwrapped from a capsule before the call.
	ctor_opaque bool
	// base_ctor_count is how many of `newstate_params` belong to the base: `newstate`
	// forwards that many to the base's own state constructor. Zero for a class with no
	// base, or one whose base takes no arguments.
	base_ctor_count int
	// newstate_params is the full parameter list of the generated state constructor: the
	// base's parameters followed by the class's own. It is the Python signature of
	// `new_<class>`, because `tp_new` binds every one of them and `newstate` splits them
	// again, handing the base's to the base's constructor.
	newstate_params []Param
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
	// lt_fn, le_fn, gt_fn and ge_fn are the user's `@[vc_lt]`, `@[vc_le]`, `@[vc_gt]`
	// and `@[vc_ge]` functions, empty when the class declares none.
	lt_fn string
	le_fn string
	gt_fn string
	ge_fn string
	// richcompare and hash_fn are the generated `tp_richcompare` and `tp_hash`.
	richcompare string
	hash_fn string
	// iter_fn and next_fn are the generated `tp_iter` and `tp_iternext`, empty when the
	// class declares no `@[vc_iter]` and `@[vc_next]` pair.
	iter_fn string
	next_fn string
	// len_fn, item_fn and contains_fn are the generated `sq_length`, `sq_item` and
	// `sq_contains`, empty when the class declares no `@[vc_len]`, `@[vc_getitem]` or
	// `@[vc_contains]`.
	len_fn string
	item_fn string
	setitem_fn string
	contains_fn string
	// numeric maps a numeric operator's key (see numeric_slots, e.g. `add` or `radd`) to
	// the user's function, so the trampoline knows the name to call and the operand and
	// result types to marshal.
	numeric map[string]Func
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
	// buffer marks a `@[vc_buffer]` field: a `[]T` of scalars whose backing vcraft frees
	// at dealloc and that the first such field also exposes through the buffer protocol.
	buffer bool
	// buffer_typed is `@[vc_buffer_typed]`: the buffer protocol reports a typed view
	// instead of the default byte view.
	buffer_typed bool
	// handle marks a `@[vc_handle]` field: a `vcraft.Owned` whose pointer vcraft releases
	// at dealloc, for native state the collector cannot follow into the object.
	handle bool
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
	return is_scalar_type(f.v_type)
}

// is_scalar_type reports whether a type name is one of the scalar types safe to hold in
// CPython-owned memory, or as the element of a native buffer.
pub fn is_scalar_type(v_type string) bool {
	return match v_type.trim_space() {
		'bool', 'int', 'i8', 'i16', 'i32', 'i64', 'isize' { true }
		'u8', 'u16', 'u32', 'u64', 'usize' { true }
		'f32', 'f64' { true }
		else { false }
	}
}

// is_buffer reports whether a field is a `@[vc_buffer]` native slice.
pub fn (f Field) is_buffer() bool {
	return f.buffer
}

// buffer_kind is the element family of a buffer scalar, numbered as the runtime's
// `buffer_export_kind_*` constants are: the family says signed, unsigned, float or bool,
// and the element's width picks the format character within it.
pub fn buffer_kind(v_type string) int {
	return match v_type.trim_space() {
		'bool' { 3 }
		'f32', 'f64' { 2 }
		'i8', 'i16', 'i32', 'i64', 'isize', 'int' { 1 }
		else { 0 }
	}
}

// buffer_element is the element type of a `@[vc_buffer]` slice, which decides the runtime
// allocation helper the user calls and the byte width `bf_getbuffer` reports.
pub fn (f Field) buffer_element() string {
	return element_type(f.v_type)
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

// NumericSlot is one numeric operator: the annotation suffix and the map key, the
// runtime `slot_nb_*` constant the trampoline is installed under, the operand count, and
// whether a commutative operator can answer the reflected call with its forward
// function.
pub struct NumericSlot {
pub:
	name        string
	nb          string
	arity       int
	commutative bool
}

// numeric_slots is every numeric operator, in the order the trampolines are emitted so
// the generated file does not depend on map iteration order.
pub const numeric_slots = [
	NumericSlot{ name: 'add', nb: 'slot_nb_add', arity: 2, commutative: true },
	NumericSlot{ name: 'sub', nb: 'slot_nb_subtract', arity: 2, commutative: false },
	NumericSlot{ name: 'mul', nb: 'slot_nb_multiply', arity: 2, commutative: true },
	NumericSlot{ name: 'truediv', nb: 'slot_nb_true_divide', arity: 2, commutative: false },
	NumericSlot{ name: 'floordiv', nb: 'slot_nb_floor_divide', arity: 2, commutative: false },
	NumericSlot{ name: 'mod', nb: 'slot_nb_remainder', arity: 2, commutative: false },
	NumericSlot{ name: 'pow', nb: 'slot_nb_power', arity: 2, commutative: false },
	NumericSlot{ name: 'lshift', nb: 'slot_nb_lshift', arity: 2, commutative: false },
	NumericSlot{ name: 'rshift', nb: 'slot_nb_rshift', arity: 2, commutative: false },
	NumericSlot{ name: 'and', nb: 'slot_nb_and', arity: 2, commutative: true },
	NumericSlot{ name: 'or', nb: 'slot_nb_or', arity: 2, commutative: true },
	NumericSlot{ name: 'xor', nb: 'slot_nb_xor', arity: 2, commutative: true },
	NumericSlot{ name: 'neg', nb: 'slot_nb_negative', arity: 1, commutative: false },
	NumericSlot{ name: 'pos', nb: 'slot_nb_positive', arity: 1, commutative: false },
	NumericSlot{ name: 'abs', nb: 'slot_nb_absolute', arity: 1, commutative: false },
	NumericSlot{ name: 'invert', nb: 'slot_nb_invert', arity: 1, commutative: false },
]

// numeric_operand_types are the scalar types a numeric operator's operand and result may
// be. Each is a width the converters produce and consume exactly, so the generated call
// needs no cast; a narrower `i64` or `f32` is refused rather than silently miscompiled.
pub const numeric_operand_types = ['int', 'u64', 'f64', 'bool', 'PyObj', 'vcraft.PyObj']

// numeric_slot returns the table entry for an annotation suffix, or none when the suffix
// is not a numeric operator.
pub fn numeric_slot(name string) ?NumericSlot {
	for s in numeric_slots {
		if s.name == name {
			return s
		}
	}
	return none
}

// Project is everything the generator found.
// Operator is a `vc_eq` or `vc_hash` function seen before the class it belongs to.
//
// Held rather than resolved on the spot, because the class may be declared later in the
// same file or in a file that sorts after this one.
pub struct Operator {
pub mut:
	name   string
	// kind is `eq` or `hash`, an ordering name, or a numeric slot key.
	kind   string
	origin string
	line   int
	column int
	// handler is the built function, kept for the numeric operators so their operand and
	// result types are known when the trampoline is emitted. Empty for the others, whose
	// calling convention is fixed.
	handler Func
}

// Const is a `pub const NAME = value` annotated `@[vc_const]`, exposed as a module-level
// Python attribute.
pub struct Const {
pub mut:
	name string
	// value is the literal as written, and kind is `int`, `float`, `bool` or `str`.
	// Nothing else can cross: a const is read at generation time, not at run time, so
	// the value has to be a literal the generator can box itself.
	value  string
	kind   string
	origin string
	line   int
	column int
}

// EnumMember is one member of a V `enum`: its name and integer value.
pub struct EnumMember {
pub:
	name  string
	value i64
}

// EnumInfo is a V `enum` a project declares. It crosses as a generated `enum.IntEnum`
// subclass attached to the module under `name`.
pub struct EnumInfo {
pub:
	name    string
	key     string
	members []EnumMember
}

// StructField is one field of a plain V `struct`: its name and type.
pub struct StructField {
pub:
	name   string
	v_type string
}

// StructInfo is a plain V `struct` a project declares. It crosses as a Python `dict` of
// its fields, keyed by their names.
pub struct StructInfo {
pub:
	name   string
	key    string
	fields []StructField
}

// known_enums is every enum the current project declares, keyed by the name as written in
// a signature. `lookup` consults it, so an enum name classifies as `.enum_type` rather
// than as an unknown struct. Cleared at the start of a run. `known_structs` is the same
// for plain structs.
__global (
	known_enums   map[string]EnumInfo   = map[string]EnumInfo{}
	known_structs map[string]StructInfo = map[string]StructInfo{}
)

// reset_type_registry clears the enum and struct registries before a project is
// collected.
pub fn reset_type_registry() {
	known_enums = map[string]EnumInfo{}
	known_structs = map[string]StructInfo{}
}

// is_enum reports whether `v_type` names an enum the project declares.
pub fn is_enum(v_type string) bool {
	return v_type.trim_space() in known_enums
}

// enum_info returns the registry entry for an enum type name.
pub fn enum_info(v_type string) ?EnumInfo {
	t := v_type.trim_space()
	if t in known_enums {
		return known_enums[t]
	}
	return none
}

// is_struct reports whether `v_type` names a plain struct the project declares.
pub fn is_struct(v_type string) bool {
	return v_type.trim_space() in known_structs
}

// struct_info returns the registry entry for a plain struct type name.
pub fn struct_info(v_type string) ?StructInfo {
	t := v_type.trim_space()
	if t in known_structs {
		return known_structs[t]
	}
	return none
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
	// consts are the `@[vc_const]` module-level constants, in declaration order.
	consts []Const
	// enums are the V `enum` declarations, in declaration order, each exposed as an
	// `enum.IntEnum` subclass.
	enums []EnumInfo
	// structs are the plain V `struct` declarations, in declaration order, each crossing
	// as a Python `dict`.
	structs []StructInfo
	// diagnostics are problems found while scanning. They do not stop generation;
	// the emitter reports them all at once so a project with five mistakes takes
	// one build to fix rather than five.
	diagnostics []Diagnostic
	// uses_state_at is whether any source file calls `vcraft.state_at`, the only reader
	// of the state chain. Without one, nothing can observe the chain, so the
	// trampolines skip publishing it.
	uses_state_at bool
	// needs_converters is set when a parameter is a map or a nested composite, which
	// needs the recursive converter helpers. They are emitted into the generated file
	// rather than the runtime because V gives a generic called from another module no
	// forward declaration, so `convert_seq`/`convert_dict` have to live in the same
	// module as their caller.
	needs_converters bool
	// uses_state_at_zero is whether any source file calls `state_at(0)`, the one level a
	// class with no base has to publish. `state_at(level>=1)` reaches an ancestor, so it
	// is only meaningful inside a subclass, and every generation above a class is
	// published by that class's own trampolines. So a class with no base publishes
	// nothing unless `state_at(0)` is used somewhere, in which case the conservative
	// fallback is to publish in every class again (a helper called from a base-less
	// class could reach `state_at(0)` unseen).
	uses_state_at_zero bool
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
