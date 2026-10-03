module vcraft

// Python types backed by V structs.
//
// An instance is a CPython object whose `tp_basicsize` leaves room for one
// pointer past the PyObject header. That pointer addresses a block of memory
// CPython owns, holding a copy of the V struct. Methods copy the value out, call
// the user's V method, and copy it back.
//
// ## Why the state is a copy, and why it is copied into CPython memory
//
// Two facts about V decide this, and both were established by experiment:
//
//   - `&Counter{}` compiles to `memdup`, so a heap struct lives in Boehm's heap and
//     V has no matching free: `c.free()` on it emits nothing at all. Ownership
//     there belongs to the collector.
//   - Boehm does not scan memory that CPython allocated. A PyObject is allocated
//     by pymalloc, so anything reachable only through one is invisible to the
//     collector.
//
// Neither allocator alone works for a struct that CPython holds a pointer to. A
// Boehm block would be collected while Python still uses it; a PyObject block would
// hide V's own references from the collector. So the block is allocated and freed
// with `PyObject_Malloc`, and the V value is copied into it. The V temporary the
// user's constructor produced stays GC-owned and is reclaimed normally.
//
// ## What that costs
//
// A `@[vc_class]` struct may hold scalar fields only. A `string` or `[]T` copied into
// CPython memory would be a Boehm pointer that nothing keeps alive, and the crash
// it produces would be far from the code that caused it. The code generator reports
// that case rather than generating it. Strings belong behind methods, which already
// marshal to and from Python str.

// TypeObject wraps a heap type created by `PyType_FromSpec`.
pub struct TypeObject {
pub:
	obj PyObj
}

// instance_basicsize is the `tp_basicsize` for a class: the PyObject header plus
// room for the storage pointer.
pub fn instance_basicsize() int {
	return int(C.vpy_size_PyObject()) + int(sizeof(voidptr))
}

// type_flags is what a vcraft heap type asks for: CPython's own default set plus
// Py_TPFLAGS_BASETYPE, so a Python class may subclass it.
pub fn type_flags() u32 {
	return C.vpy_tpflags_default() | tpflags_basetype
}

// type_alloc creates an instance of `typ`.
//
// `tp_new` receives the *type*, not an instance, so the instance has to be
// allocated here. Getting this wrong writes the state over the type object and
// makes `Class()` return the class itself.
pub fn type_alloc(typ voidptr) voidptr {
	unsafe {
		return C.PyType_GenericAlloc(typ, 0)
	}
}

// no_memory raises MemoryError and returns the null pointer, which is what a
// `tp_new` must do when it cannot allocate.
//
// It lives here because generated code in a user module cannot call `C.` functions.
pub fn no_memory() voidptr {
	unsafe {
		C.PyErr_NoMemory()
	}
	return unsafe { nil }
}

// instance_alloc reserves the state block for a fresh instance.
pub fn instance_alloc(size usize) voidptr {
	return C.vpy_instance_alloc(size)
}

// instance_free releases it. Called from `tp_dealloc`.
pub fn instance_free(p voidptr) {
	if p != unsafe { nil } {
		C.vpy_instance_free(p)
	}
}

// storage_of returns the address of the state pointer that follows the PyObject
// header of `obj`.
pub fn storage_of(obj voidptr) voidptr {
	unsafe {
		return voidptr(&u8(obj) + C.vpy_size_PyObject())
	}
}

// instance_storage returns the state block of an instance, or the null pointer when
// the object has none, which is the case for a subclass that was never initialised.
pub fn instance_storage(obj voidptr) voidptr {
	unsafe {
		slot := &voidptr(storage_of(obj))
		return slot[0]
	}
}

// instance_set_storage records the state block on an instance.
pub fn instance_set_storage(obj voidptr, storage voidptr) {
	unsafe {
		slot := &voidptr(storage_of(obj))
		slot[0] = storage
	}
}

// load_state and store_state move a V value between the state block and a local.
//
// They take a raw size rather than being generic. A generic helper would be the
// obvious signature, and it does not compile when called from generated code in
// another module: V emits no forward declaration for a generic, so the call fails
// with an implicit declaration. The generated code names the type once, as
// `sizeof(Counter)`, and these stay plain functions.
//
// The copy is the point. It puts the V value back under V's own rules, where the
// collector and the ownership checker can see it, for the duration of the call.
pub fn load_state(storage voidptr, dest voidptr, size usize) {
	if storage == unsafe { nil } {
		return
	}
	unsafe {
		C.vpy_memcpy(dest, storage, size)
	}
}

// noop is the value of a setter that has nothing to store.
pub fn noop() voidptr {
	unsafe {
		return nil
	}
}

// The state block of the running trampoline, and one pointer per generation above it.
//
// A method's receiver is the class's own struct, copied in before the call and out after
// it. For a subclass that struct does *not* contain the base's half of the state: the
// state of a class with a base is the base's whole state followed by its own struct, so
// the receiver reaches its own half and nothing else. Without these pointers a method of a
// subclass has no way at all to read an inherited field, because `&c` is not the address
// of the instance's state.
//
// A chain is a list rather than a single "base" pointer because the offsets are not
// uniform. The root of a chain is always at the start of the block, but the immediate base
// of a class whose base is itself derived sits after that base's own base, and so on down.
// The generator knows the chain, so it publishes each generation's own struct by address
// and a method asks for the level it wants.
//
// Eight levels is the cap. Nothing in V suggests a deeper chain is common, and a fixed
// array keeps the save and restore a copy rather than an allocation on every call.
pub const state_chain_max = 8

__global (
	// Initialised inside `unsafe` because it is an array of references, and V insists on
	// that for a fixed array. The values are nil, so nothing is actually unchecked here.
	g_vc_chain = unsafe { [state_chain_max]voidptr{} }
)

// enter_state publishes `block` as level 0 of the running trampoline's state and returns
// the chain it replaced, so the caller can put it back.
//
// The whole chain is saved rather than just the block: a nested call -- a method reaching
// another instance, or a property read from inside a method -- would otherwise leave the
// outer trampoline's levels pointing at the inner one's instance. There is no thread-local
// storage here, and an extension module's Python calls hold the GIL, so one chain is
// enough.
pub fn enter_state(block voidptr) [state_chain_max]voidptr {
	previous := unsafe { g_vc_chain }
	unsafe {
		g_vc_chain = [state_chain_max]voidptr{}
		g_vc_chain[0] = block
	}
	return previous
}

// publish_base records the own struct of one generation of the chain.
//
// Level 1 is the immediate base, level 2 the one above it, and so on. The generator emits
// one call per generation with the address it computes from the state struct, so nothing
// here has to know the layout.
pub fn publish_base(level int, ptr voidptr) {
	if level < 1 || level >= state_chain_max {
		return
	}
	unsafe {
		g_vc_chain[level] = ptr
	}
}

// leave_state restores the chain saved by `enter_state`.
pub fn leave_state(previous [state_chain_max]voidptr) {
	unsafe {
		g_vc_chain = previous
	}
}

// A method of a subclass reaches an inherited field with a cast on `state_at`:
//
//	@[vc_methods]
//	pub fn (mut c BoundedCounter) bump(by int) !int {
//		mut base := unsafe { &Counter(vcraft.state_at(1)) }
//		if base.value + by > c.limit {
//			return vcraft.raise_domain(.value_error, 'the counter would pass its limit')
//		}
//		base.value += by
//		return base.value
//	}
//
// A pointer rather than a copy, and that is the whole point. V hands the method a copy of
// the subclass struct, and the base's bytes are not in it, so a copy taken here would be
// written to and then thrown away. This points into the state block the trampoline holds,
// which the trampoline writes back when the method returns.
//
// The cast rather than a generic on purpose. `fn inherited[T]() &T` is the obvious
// spelling and it does not compile from a user's module: V emits no forward declaration for
// a generic, so the call fails with "unknown function: vcraft.inherited[Counter]".
//
// Written to a local rather than assigned through, because V cannot assign through a call
// result: `vcraft.state_at(1).value = 1` is rejected, `base.value = 1` on the local is not.
//
// The pointer is only good for the duration of the call. Outside a trampoline the level is
// nil and dereferencing it is a segfault, which is why this is not a method on the receiver:
// there would be no way to tell from `&c` whether the receiver is the whole state or just
// the subclass's half of it.
//
// state_at returns the address of one generation of the running trampoline's state, nil if
// that level is not there.
//
// Level 0 is the whole block, 1 the immediate base's own struct, 2 the next one up. Nil
// outside a trampoline and for a level deeper than the class's chain, so a method of a
// class with no base that asks gets nil rather than a wild pointer. Dereferencing nil is
// still the caller's mistake to make, and no spelling of this API can be both zero-cost
// and checked.
pub fn state_at(level int) voidptr {
	if level < 0 || level >= state_chain_max {
		return unsafe { nil }
	}
	unsafe {
		return g_vc_chain[level]
	}
}

// set_state copies a Python value into a single field of the state block.
//
// `size` is the size of that field, so a field is addressed the same way a V struct
// member is: by the address of the member, not by an offset computed here.
pub fn set_state(member voidptr, value voidptr, size usize) {
	if value == unsafe { nil } {
		unsafe {
			C.vpy_memcpy(member, nil, size)
		}
		return
	}
	unsafe {
		C.vpy_memcpy(member, value, size)
	}
}

// store_state copies a V value into the state block.
pub fn store_state(value voidptr, storage voidptr, size usize) {
	if storage == unsafe { nil } {
		return
	}
	unsafe {
		C.vpy_memcpy(storage, value, size)
	}
}

// class_dealloc releases the state block and then the object, and returns whatever
// the base deallocator returned.
//
// The order matters: the block may hold the only reference to something, so it goes
// first. Calling the base deallocator last is what CPython requires of a subtype.
// This lives in the runtime because `Py_TYPE` is a macro, which generated code in a
// user module cannot use.
pub fn class_dealloc(self voidptr) voidptr {
	instance_free(instance_storage(self))
	C.vpy_type_free(self)
	return unsafe { nil }
}

// type_from_spec creates a heap type. `slots` must be a null-slot-terminated
// PyType_Slot array owned by the caller for as long as the type lives, which the
// generated code arranges by making it a module-level table.
pub fn type_from_spec(name string, basicsize int, slots voidptr) PyObj {
	namep := cstring(name)
	unsafe {
		spec := &PyTypeSpec{
			name:      namep
			basicsize: basicsize
			itemsize:  0
			flags:     type_flags()
			slots:     slots
		}
		return steal(C.PyType_FromSpec(voidptr(spec)))
	}
}

// new_type creates a heap type whose only job is to hold V state.
//
// The slots are the whole contract: `tp_new` allocates and stores the state,
// `tp_init` runs the user's constructor, `tp_dealloc` releases the block, and
// `tp_repr` prints it. Any other behaviour comes from the method and getset tables
// the generated code registers.
//
// `doc` becomes `__doc__` on the type. It may be empty, in which case CPython leaves
// the attribute absent rather than set to an empty string.
// `bases` is the tuple a type inherits from, or nil for none. It is passed as the
// address of a one-element or n-element tuple object, which is what `Py_tp_bases` takes.
//
// The slot exists under the stable ABI and is how a type without multi-phase
// initialisation declares a base. A single base is enough for a V class, and V's
// embedding has no use for more than one: a second base would need its state laid out
// after the first's, and vcraft's layout is one block of V values.
//
// `bases` is required rather than defaulting to nil because V allows only a constant as
// a default value, and `unsafe { nil }` is an expression.
pub fn new_type(name string, doc string, new_ voidptr, init voidptr, dealloc voidptr,
	methods voidptr, getsets voidptr, repr voidptr, richcompare voidptr, hash voidptr,
	bases voidptr) PyObj {
	// The instance size is the larger of this class's own header plus its storage
	// pointer, and whatever its base already needs. A subclass that is smaller than its
	// base is rejected by CPython with "tp_basicsize ... too small for base", and the
	// number it compares against is the base's, not a constant.
	mut basicsize := instance_basicsize()
	mut slots := [PyTypeSlot{
		slot:  slot_new
		value: new_
	}, PyTypeSlot{
		slot:  slot_init
		value: init
	}, PyTypeSlot{
		slot:  slot_dealloc
		value: dealloc
	}]
	if methods != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_methods
			value: methods
		}
	}
	if getsets != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_getset
			value: getsets
		}
	}
	if repr != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_repr
			value: repr
		}
	}
	if richcompare != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_richcompare
			value: richcompare
		}
	}
	// `tp_hash` is only meaningful alongside `tp_richcompare`. A type that compares by
	// value and then hashes by identity breaks the invariant Python's dicts rely on, and
	// the symptom is a dict that cannot look up a key it already holds.
	if hash != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_hash
			value: hash
		}
	}
	// The base tuple has to outlive this call: CPython reads it and keeps a reference to
	// the base types, and the tuple itself is only borrowed for the call. The caller
	// makes it a module global for exactly this reason.
	if bases != unsafe { nil } {
		slots << PyTypeSlot{
			slot:  slot_bases
			value: bases
		}
	}
	// The docstring is a slot, not a member of PyType_Spec. An empty one is left out
	// so CPython keeps `__doc__` absent instead of setting it to "".
	if doc.len > 0 {
		slots << PyTypeSlot{
			slot:  slot_doc
			value: cstring(doc)
		}
	}
	slots << PyTypeSlot{}
	namep := cstring(name)
	unsafe {
		spec := &PyTypeSpec{
			name:      namep
			basicsize: i32(basicsize)
			itemsize:  0
			flags:     type_flags()
			slots:     voidptr(&slots[0])
		}
		return steal(C.PyType_FromSpec(voidptr(spec)))
	}
}

// The comparison operators CPython's `PyObject_RichCompare` passes as the third
// argument of a `tp_richcompare`.
pub const op_lt = i32(0)

pub const op_le = i32(1)

pub const op_eq = i32(2)

pub const op_ne = i32(3)

pub const op_gt = i32(4)

pub const op_ge = i32(5)

// richcompare_not_implemented is the value to return for an operator a class does not
// implement.
//
// Returning `NotImplemented` rather than `False` is what lets Python try the reflected
// operation on the other operand, and then fall back to identity comparison. A class
// that returns `False` for every operator is `!=` everything and `==` nothing, which
// makes `x in a_list` surprising in a way that is hard to trace back here.
pub fn richcompare_not_implemented() voidptr {
	// The `NotImplemented` *singleton*, not the exception class of the same name.
	// Returning the class is a very quiet mistake: it is a type object, so it is truthy,
	// so `==` reports a class rather than a bool, and every comparison involving the
	// class ends in a TypeError far from here.
	return C.vpy_not_implemented()
}

// identity_richcompare is the default `tp_richcompare`: `==` and `!=` by identity, and
// `NotImplemented` for the ordering operators.
//
// Identity rather than `False` for `==` is what makes a plain class usable as a dict
// key and comparable to itself, which is what every other object does. `NotImplemented`
// for `<` is what lets a class that defines `__lt__` still be ordered against one that
// does not: Python falls back to the other operand's reflected method, and then to its
// default, which is an error naming the type rather than a wrong `False`.
pub fn identity_richcompare(self voidptr, other voidptr, op int) voidptr {
	if op != op_eq && op != op_ne {
		return richcompare_not_implemented()
	}
	same := C.Py_Is(self, other) != 0
	match op {
		op_eq { return bool_object(same) }
		else { return bool_object(!same) }
	}
}

// identity_hash is the default `tp_hash`: the object's own address.
//
// The id-based hash that goes with identity comparison. It is what a class without a
// value comparison gets, and it is stable for the life of the object because the object
// does not move while Python holds it.
pub fn identity_hash(self voidptr) isize {
	unsafe {
		return isize(C.vpy_hash(self))
	}
}

// bool_object returns a new reference to `True` or `False`.
fn bool_object(value bool) voidptr {
	return to_py_bool(value).ptr
}

// is_instance_of reports whether an object is an instance of a type.
//
// `PyObject_TypeCheck` rather than a pointer comparison, because a subclass instance is
// also an instance of its base. A comparison method that returned `NotImplemented` for a
// subclass would make `base() == sub()` false, which is the opposite of what Python does
// for a type that does not override `__eq__`.
pub fn is_instance_of(obj voidptr, typ voidptr) bool {
	unsafe {
		return C.vpy_type_check(obj, typ) != 0
	}
}

// hash_from_int folds a V integer into `Py_hash_t`.
//
// The truncation to the platform's `Py_hash_t` is the format's own: Python specifies the
// hash as a signed integer of platform width and does not require a value that fits in a
// 64-bit one. Collisions are handled by the dict, so a truncated hash costs a comparison
// rather than correctness.
pub fn hash_from_int(value int) isize {
	// The mask is applied with a modulo rather than a bitwise `&`. V translates `&` on
	// integers to C's bitwise and, which is fine, but the whole expression is emitted
	// from generated code and a stray `&` there lands in a context where C reads it as
	// an address-of. A modulo has no such reading.
	mut out := isize(value)
	bits := hash_mask()
	if bits < 64 {
		out = out % (isize(1) << bits)
	}
	if value < 0 {
		return -out
	}
	return out
}

// hash_mask returns the width of `Py_hash_t` on this platform.
//
// A C `long`, so 64 bits where the platform uses `ssize_t` and 32 where it does not. It
// is asked of the interpreter rather than assumed, because the answer decides whether a
// hash above 2^31 keeps its top bits.
fn hash_mask() isize {
	unsafe {
		return isize(C.vpy_hash_bits())
	}
}

// base_tuple packs one type into a tuple, which is what `Py_tp_bases` takes.
//
// A tuple rather than the type itself, and the difference is not cosmetic: the slot
// stores the tuple and CPython takes a new reference to the base from it, so a type
// passed directly would be read as the first element of a tuple that does not exist.
pub fn base_tuple(types []PyObj) voidptr {
	unsafe {
		return C.PyTuple_New(isize(types.len))
	}
}

// tuple_of_one builds the one-element tuple a single-base class declares.
//
// A class inherits from exactly one V class. V's embedding lays out an instance as one
// block of V values, so a second base would have to be placed after the first's, and
// there is no way to express that through `@[vc_base]` without the user writing the
// offsets by hand.
pub fn tuple_of_one(t PyObj) PyObj {
	unsafe {
		tuple := C.PyTuple_New(1)
		if tuple == nil {
			return PyObj{}
		}
		// Stolen into the tuple, which is what makes the caller keep its own reference.
		// A new reference, because `PyTuple_SET_ITEM` steals what it is given and the
		// caller keeps using its own handle afterwards.
		C.PyTuple_SET_ITEM(tuple, 0, t.new_ref().ptr)
		// Returned as a `PyObj` rather than a bare pointer because the caller stores it in
		// a global and a global has to own its handle.
		return PyObj{
			ptr: tuple
		}
	}
}
