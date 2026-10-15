// Accessors for CPython symbols that are data rather than functions.
//
// V cannot name a C global, so every CPython singleton the runtime needs gets a
// one-line accessor here. This file is compiled into the extension by the
// `#flag @VMODROOT/c/shim.c` directive in vlib/vcraft/cpython.c.v.
//
// Every accessor that would touch a concrete object struct has a `Py_LIMITED_API`
// variant. Under the stable ABI CPython hides `PyTypeObject` and friends behind
// incomplete typedefs and turns the `Py*_GET_SIZE` family into macros that are not
// exported, so the code below has to go through functions instead. `vcraft build
// --abi3` defines `vcraft_limited_api`, which is what selects these branches.

#include "shim.h"

#include <string.h>

int vpy_python_api_version(void) {
	return PYTHON_API_VERSION;
}

// vpy_type_name_into writes the unqualified type name of `o` into `buf` and returns its
// length, or -1 with an exception set. `PyType_GetName` reads the name directly (stable
// ABI since 3.11, vcraft's floor) and `PyUnicode_AsUTF8` returns the cached UTF-8 form,
// so a caller that names the actual type on a failure path allocates nothing.
int vpy_type_name_into(PyObject *o, char *buf, size_t n) {
	if (o == NULL || buf == NULL || n == 0) {
		return -1;
	}
	PyObject *name = PyType_GetName(Py_TYPE(o));
	if (name == NULL) {
		return -1;
	}
	Py_ssize_t len = 0;
	const char *utf8 = PyUnicode_AsUTF8AndSize(name, &len);
	if (utf8 == NULL) {
		Py_DECREF(name);
		return -1;
	}
	if ((size_t)len >= n) {
		len = (Py_ssize_t)(n - 1);
	}
	memcpy(buf, utf8, (size_t)len);
	buf[len] = '\0';
	Py_DECREF(name);
	return (int)len;
}

unsigned long vpy_version_hex(void) {
	return PY_VERSION_HEX;
}

const char *vpy_version_string(void) {
	return Py_GetVersion();
}

Py_ssize_t vpy_ssize_size(void) {
	return (Py_ssize_t)sizeof(Py_ssize_t);
}

int vpy_int_size(void) {
	return (int)sizeof(int);
}

Py_ssize_t vpy_size_PyModuleDef(void) {
	// `sizeof` is valid under `Py_LIMITED_API` even for a struct the ABI does not
	// expose: the headers still define the type, they just do not let a caller reach
	// its fields. An earlier version of this file answered 0 here "because the struct
	// is hidden", and the runtime used that to compute `tp_basicsize`, which came out
	// as 8 instead of 16 and made every class fail with "tp_basicsize ... too small for
	// base 'object'". A guard that guesses is worse than no guard.
	return (Py_ssize_t)sizeof(PyModuleDef);
}

Py_ssize_t vpy_size_PyMethodDef(void) {
	return (Py_ssize_t)sizeof(PyMethodDef);
}

Py_ssize_t vpy_size_PyObject(void) {
	return (Py_ssize_t)sizeof(PyObject);
}

// The interpreter's own Py_TPFLAGS_DEFAULT, which is a union whose contents depend
// on how CPython was built. Asking beats hard-coding a bitmask.
unsigned int vpy_tpflags_default(void) {
	return (unsigned int)Py_TPFLAGS_DEFAULT;
}

#ifdef vcraft_limited_api

// Under the stable ABI there is no `PyTypeObject` to read a field out of and no
// exported `Py*_GET_SIZE`. Everything below goes through a function CPython does
// export, which is the whole point of the limited API.

void *vpy_memcpy(void *dst, const void *src, size_t n) {
	// `memcpy` is a C library function rather than a CPython one, so the limited API
	// does not hide it. The header that declares it is the reason for the guard above.
	return memcpy(dst, src, n);
}

void *vpy_type_ptr(PyObject *self) {
	return (void *)Py_TYPE(self);
}

// vpy_is_limited_api reports which CPython API this object was compiled against.
//
// A run-time answer rather than a compile-time one because V's `$if` cannot see a
// `-cflags` define. The two module-creation paths both compile either way; only one of
// them links against an abi3 build.
int vpy_is_limited_api(void) {
#ifdef vcraft_limited_api
	return 1;
#else
	return 0;
#endif
}

// vpy_call_exec invokes the generated `Py_mod_exec` callback.
//
// The return value is CPython's: 0 for success, -1 with an exception set. vcraft
// returns it rather than checking, because only the generated code knows whether the
// classes it tried to attach actually were.
int vpy_call_exec(void *fn_ptr, void *module) {
	int (*exec_fn)(PyObject *) = (int (*)(PyObject *))fn_ptr;
	return exec_fn((PyObject *)module);
}

// vpy_hash returns an object's default hash.
//
// `PyObject_Hash` is not in the limited API, and under `Py_LIMITED_API` a type's
// `tp_hash` has to be filled with a function that reaches the hash through whatever the
// stable ABI offers. There is nothing it offers here, so an abi3 build reports -1,
// which CPython reads as "hash failed" -- the correct answer for a type whose hash is
// identity, since an address-based hash cannot be computed without the concrete object
// header.
Py_hash_t vpy_hash(PyObject *self) {
	// The address, shifted right by four bits: the low bits of a pointer are always
	// zero, so folding them in would halve the hash's range for nothing.
	//
	// `_Py_HashPointer` is not available under `Py_LIMITED_API`, so the shift is done
	// here rather than through it. An abi3 build that used the helper would fail to
	// compile on an implicit declaration.
	return (Py_hash_t)((size_t)self >> 4);
}

// vpy_hash_bits reports the width of `Py_hash_t`, which is a `long` and therefore
// platform dependent: 64 bits where `long` is 64, 32 where it is not.
long vpy_hash_bits(void) {
	return (long)sizeof(Py_hash_t) * 8;
}

// vpy_type_check reports whether an object is an instance of a type, subclasses
// included.
//
// Written here rather than called because `PyObject_TypeCheck` is a `static inline` in
// object.h, not an exported symbol. Under `Py_LIMITED_API` at 3.11 and above it is
// additionally a macro wrapping itself, which V expands before the declaration is ever
// resolved and the compiler then reports `expected declaration specifiers ... before
// '(' token` from inside Python's own header. `PyType_IsSubtype` is exported and says
// the same thing once identity is added.
// vpy_not_implemented returns the `NotImplemented` singleton.
//
// Through an accessor because `Py_NotImplemented` is a macro over `&_Py_NotImplementedStruct`,
// and V expands it before the declaration is resolved: the compiler then reports "the
// object called is not a function nor a pointer to function" from inside object.h.
PyObject *vpy_not_implemented(void) {
	Py_INCREF(Py_NotImplemented);
	return Py_NotImplemented;
}

int vpy_type_check(PyObject *o, PyTypeObject *type) {
	if (o == NULL || type == NULL) {
		return 0;
	}
	if ((PyObject *)type == (PyObject *)o) {
		return 1;
	}
	return PyType_IsSubtype(Py_TYPE(o), type);
}

Py_ssize_t vpy_tuple_size(PyObject *self) {
	if (self == NULL) {
		return 0;
	}
	return PyTuple_Size(self);
}

Py_ssize_t vpy_ob_size(PyObject *self) {
	// `Py_SIZE` is a macro over a struct field. The function that answers the same
	// question for an arbitrary object does not exist, so the size of a non-container
	// is reported as zero, which is what the runtime uses it for anyway: deciding
	// whether a sequence argument is a tuple or a list.
	(void)self;
	return 0;
}

void vpy_type_free(PyObject *self) {
	Py_DECREF(self);
}

#else

void *vpy_memcpy(void *dst, const void *src, size_t n) {
	return memcpy(dst, src, n);
}

void *vpy_type_ptr(PyObject *self) {
	return (void *)Py_TYPE(self);
}

// vpy_is_limited_api reports which CPython API this object was compiled against.
//
// A run-time answer rather than a compile-time one because V's `$if` cannot see a
// `-cflags` define. The two module-creation paths both compile either way; only one of
// them links against an abi3 build.
int vpy_is_limited_api(void) {
#ifdef vcraft_limited_api
	return 1;
#else
	return 0;
#endif
}

// vpy_call_exec invokes the generated `Py_mod_exec` callback.
//
// The return value is CPython's: 0 for success, -1 with an exception set. vcraft
// returns it rather than checking, because only the generated code knows whether the
// classes it tried to attach actually were.
int vpy_call_exec(void *fn_ptr, void *module) {
	int (*exec_fn)(PyObject *) = (int (*)(PyObject *))fn_ptr;
	return exec_fn((PyObject *)module);
}

// vpy_hash returns an object's default hash.
//
// `PyObject_Hash` is not in the limited API, and under `Py_LIMITED_API` a type's
// `tp_hash` has to be filled with a function that reaches the hash through whatever the
// stable ABI offers. There is nothing it offers here, so an abi3 build reports -1,
// which CPython reads as "hash failed" -- the correct answer for a type whose hash is
// identity, since an address-based hash cannot be computed without the concrete object
// header.
Py_hash_t vpy_hash(PyObject *self) {
	// The address, shifted right by four bits: the low bits of a pointer are always
	// zero, so folding them in would halve the hash's range for nothing.
	//
	// `_Py_HashPointer` is not available under `Py_LIMITED_API`, so the shift is done
	// here rather than through it. An abi3 build that used the helper would fail to
	// compile on an implicit declaration.
	return (Py_hash_t)((size_t)self >> 4);
}

// vpy_hash_bits reports the width of `Py_hash_t`, which is a `long` and therefore
// platform dependent: 64 bits where `long` is 64, 32 where it is not.
long vpy_hash_bits(void) {
	return (long)sizeof(Py_hash_t) * 8;
}

// vpy_type_check reports whether an object is an instance of a type, subclasses
// included.
//
// Written here rather than called because `PyObject_TypeCheck` is a `static inline` in
// object.h, not an exported symbol. Under `Py_LIMITED_API` at 3.11 and above it is
// additionally a macro wrapping itself, which V expands before the declaration is ever
// resolved and the compiler then reports `expected declaration specifiers ... before
// '(' token` from inside Python's own header. `PyType_IsSubtype` is exported and says
// the same thing once identity is added.
// vpy_not_implemented returns the `NotImplemented` singleton.
//
// Through an accessor because `Py_NotImplemented` is a macro over `&_Py_NotImplementedStruct`,
// and V expands it before the declaration is resolved: the compiler then reports "the
// object called is not a function nor a pointer to function" from inside object.h.
PyObject *vpy_not_implemented(void) {
	Py_INCREF(Py_NotImplemented);
	return Py_NotImplemented;
}

int vpy_type_check(PyObject *o, PyTypeObject *type) {
	if (o == NULL || type == NULL) {
		return 0;
	}
	if ((PyObject *)type == (PyObject *)o) {
		return 1;
	}
	return PyType_IsSubtype(Py_TYPE(o), type);
}

Py_ssize_t vpy_tuple_size(PyObject *self) {
	if (self == NULL) {
		return 0;
	}
	return PyTuple_GET_SIZE(self);
}

Py_ssize_t vpy_ob_size(PyObject *self) {
	return (Py_ssize_t)Py_SIZE(self);
}

void vpy_type_free(PyObject *self) {
	Py_TYPE(self)->tp_free(self);
}

#endif

void *vpy_instance_alloc(size_t n) {
	return PyObject_Malloc(n);
}

void vpy_instance_free(void *p) {
	PyObject_Free(p);
}

// vpy_visit calls CPython's visit function on one object.
//
// The visit function is a `visitproc`, which V cannot name, so it arrives as a void
// pointer and is cast back here. The cast is the one thing this file does that C's type
// system would otherwise check, and it is safe because the only caller is the generated
// `tp_traverse`, which receives its arguments from CPython.
int vpy_visit(void *obj, void *visit, void *arg) {
	if (obj == NULL) {
		// Nothing to visit. Not an error: a reference field may legitimately be unset,
		// and CPython's own types treat a null slot as nothing to report.
		return 0;
	}
	visitproc fn = (visitproc)visit;
	return fn((PyObject *)obj, arg);
}

// vpy_traverse_ref visits one reference held in an instance's state block.
//
// `ref` is the address of the field, not its value, so the generated code can hand over
// the address of the member without knowing its type. A null field is skipped rather
// than reported as an error, matching what CPython's own containers do.
int vpy_traverse_ref(void *ref, void *visit, void *arg) {
	if (ref == NULL) {
		return 0;
	}
	PyObject *obj = *(PyObject **)ref;
	if (obj == NULL) {
		return 0;
	}
	visitproc fn = (visitproc)visit;
	return fn(obj, arg);
}

// vpy_is_type_object reports whether `self` is a type rather than an instance of one.
int vpy_is_type_object(void *self) {
	if (self == NULL) {
		return 0;
	}
	return PyType_Check((PyObject *)self);
}

// vpy_type_traverse visits the type object's own references.
//
// Through `PyType_GetSlot` rather than `PyType_Type.tp_traverse`, because under the
// limited API `PyTypeObject` is opaque and the member cannot be reached at all. The slot
// id is the same one the generated type uses, so both agree.
int vpy_type_traverse(void *self, void *visit, void *arg) {
	traverseproc fn = (traverseproc)PyType_GetSlot((PyTypeObject *)&PyType_Type,
	                                               Py_tp_traverse);
	if (fn == NULL) {
		return 0;
	}
	return fn((PyObject *)self, (visitproc)visit, arg);
}

// vpy_type_clear releases the type object's own references.
//
// Reached during finalisation, when the collector clears everything before the
// interpreter tears down. Same reason as `vpy_type_traverse` for using the slot.
void vpy_type_clear(void *self) {
	inquiry fn = (inquiry)PyType_GetSlot((PyTypeObject *)&PyType_Type, Py_tp_clear);
	if (fn == NULL) {
		return;
	}
	fn((PyObject *)self);
}

#define VPY_STATE_LEVELS 8

// How many trampolines may be nested before publishing falls back to a heap snapshot.
// A method calling another, a property read inside a method, a slot that re-enters --
// the depth is small in practice, and 16 is past any real nesting. Deeper nesting is
// still correct: the fallback allocates its own snapshot per level, so a chain past the
// cap only pays allocator calls.
#define VPY_STATE_FRAMES 16

// vpy_state_stack is the per-thread state chain stack.
//
// `frames[i]` is the chain while nesting level `i` runs, and `depth` is how many levels
// are active. Entering writes the new chain into the next frame and leaves the parent
// frame below it untouched, so leaving is a decrement rather than a copy back. That is
// what takes the per-call `PyMem_Malloc` off every trampoline: it used to allocate a
// snapshot of the chain on entry and free it on exit, which cost two allocator calls on
// every method, accessor and property of a module that publishes the chain at all.
typedef struct {
	int depth;
	void *frames[VPY_STATE_FRAMES][VPY_STATE_LEVELS];
} vpy_state_stack;

// The calling thread's state stack, in native thread-local storage.
//
// A `__thread` pointer rather than a `Py_tss_t` key: the key costs a
// `PyThread_tss_get` on every `vpy_stack` call, and there are two per trampoline
// (enter and leave), which is most of what the stack was meant to save. Native TLS
// reads the same per-thread value with no function call. The extension is
// process-scoped, so one stack per OS thread is the whole requirement.
static __thread vpy_state_stack *vpy_state_tls = NULL;

// vpy_state_init is kept for the generated module initialiser to call.
//
// The stack is created lazily on first use now, so there is nothing to key at import;
// the hook stays so the generated code needs no conditional.
void vpy_state_init(void) {
}

// vpy_stack returns the calling thread's state stack, creating it zeroed on first use.
//
// The block is never freed, which keeps about 1 KiB per thread that ever ran a
// trampoline. CPython offers no hook to free native thread-local storage at thread
// exit, and neither does C, so the alternative would be a global registry with a lock
// on every call.
static vpy_state_stack *vpy_stack(void) {
	if (vpy_state_tls == NULL) {
		vpy_state_tls = (vpy_state_stack *)PyMem_Calloc(1, sizeof(vpy_state_stack));
	}
	return vpy_state_tls;
}

// vpy_active_chain returns the chain of the trampoline that is running, or NULL outside
// one. `vpy_publish_state` and `vpy_state_at` report nothing when it is NULL.
static void **vpy_active_chain(vpy_state_stack *stack) {
	if (stack == NULL || stack->depth <= 0) {
		return NULL;
	}
	return stack->frames[stack->depth - 1];
}

// vpy_enter_state publishes `block` as level 0 of the calling thread's chain and returns
// a token for `vpy_leave_state`. The token is the frame it filled, which is how a leave
// tells a frame from the heap fallback below.
//
// The parent frame is not copied: it sits below the new one and is restored simply by
// dropping the depth on leave. A trampoline that never calls back into Python between
// the two sees exactly what it published, whatever other threads do.
void *vpy_enter_state(void *block) {
	vpy_state_stack *stack = vpy_stack();
	void **chain;
	void *previous;
	int level;
	if (stack == NULL) {
		return NULL;
	}
	if (stack->depth >= VPY_STATE_FRAMES) {
		// Deeper than the fixed stack: fall back to the heap snapshot the frames
		// replaced, so an unusually deep nesting still works. The pointer is outside
		// the frames array, which is how `vpy_leave_state` tells the two apart. Nesting
		// two levels past the cap would alias, which 32-deep re-entry does not reach.
		chain = vpy_active_chain(stack);
		previous = PyMem_Malloc(VPY_STATE_LEVELS * sizeof(void *));
		if (previous == NULL) {
			return NULL;
		}
		if (chain != NULL) {
			memcpy(previous, chain, VPY_STATE_LEVELS * sizeof(void *));
			memset(chain, 0, VPY_STATE_LEVELS * sizeof(void *));
			chain[0] = block;
		} else {
			memset(previous, 0, VPY_STATE_LEVELS * sizeof(void *));
		}
		return previous;
	}
	chain = stack->frames[stack->depth];
	chain[0] = block;
	for (level = 1; level < VPY_STATE_LEVELS; level++) {
		chain[level] = NULL;
	}
	previous = (void *)chain;
	stack->depth++;
	return previous;
}

// vpy_leave_state restores the chain `vpy_enter_state` returned.
//
// A frame token is inside the stack, so leaving is the decrement: the parent frame is
// still there. A token outside it is the heap fallback and is copied back and freed.
void vpy_leave_state(void *previous) {
	vpy_state_stack *stack = vpy_stack();
	void *begin;
	void *end;
	if (previous == NULL || stack == NULL) {
		return;
	}
	begin = (void *)&stack->frames[0][0];
	end = (void *)&stack->frames[VPY_STATE_FRAMES][0];
	if ((uintptr_t)previous >= (uintptr_t)begin && (uintptr_t)previous < (uintptr_t)end) {
		if (stack->depth > 0) {
			stack->depth--;
		}
		return;
	}
	{
		void **chain = vpy_active_chain(stack);
		if (chain != NULL) {
			memcpy(chain, previous, VPY_STATE_LEVELS * sizeof(void *));
		}
		PyMem_Free(previous);
	}
}

// vpy_publish_state records one generation of the chain: level 1 is the immediate
// base, level 2 the one above it, and so on. Out-of-range levels are ignored rather
// than reported, because the generator emits exactly the levels the chain has.
void vpy_publish_state(int level, void *ptr) {
	void **chain = vpy_active_chain(vpy_stack());
	if (chain == NULL || level < 1 || level >= VPY_STATE_LEVELS) {
		return;
	}
	chain[level] = ptr;
}

// vpy_state_at returns one generation of the calling thread's chain, or null when the
// level is not there. Null outside a trampoline and past the end of the class's chain,
// so a method asking for a generation above its own gets null rather than a pointer
// into another thread's call.
void *vpy_state_at(int level) {
	void **chain = vpy_active_chain(vpy_stack());
	if (chain == NULL || level < 0 || level >= VPY_STATE_LEVELS) {
		return NULL;
	}
	return chain[level];
}

// vpy_gc_untrack removes an instance from the collector's list.
//
// The first step of any `tp_dealloc` for a type with `Py_TPFLAGS_HAVE_GC`. Skipping it
// leaves a freed object on the collector's list, and the next collection walks into it.
//
// Guarded on the flag, and the guard is not optional. `PyObject_GC_UnTrack` reads the
// collector's header out of the object, which only exists on a type allocated as
// collectable. Called on an instance of a class with no reference fields it reads the
// first word of the payload as a linked-list pointer and the next collection walks into
// whatever that was: the segfault lands in `PyObject_GC_UnTrack`, several collections
// later, with nothing in the frame to connect it to the class that lacked the flag.
void vpy_gc_untrack(void *self) {
	PyTypeObject *type = Py_TYPE((PyObject *)self);
	if (type != NULL && PyType_HasFeature(type, Py_TPFLAGS_HAVE_GC)) {
		PyObject_GC_UnTrack((PyObject *)self);
	}
}

// vpy_gc_track puts an instance back on the collector's list.
//
// Needed when `tp_dealloc` resurrects an object, which a class whose `__del__`-like
// behaviour re-adds a reference can do. vcraft does not resurrect, and this exists so
// the pair is available rather than because something calls it. Guarded for the same
// reason as `vpy_gc_untrack`.
void vpy_gc_track(void *self) {
	PyTypeObject *type = Py_TYPE((PyObject *)self);
	if (type != NULL && PyType_HasFeature(type, Py_TPFLAGS_HAVE_GC)) {
		PyObject_GC_Track((PyObject *)self);
	}
}

// vpy_allow_threads releases the GIL and returns the thread state to restore.
//
// The state is opaque to the caller on purpose: restoring anything but the state this
// returned corrupts the interpreter's thread bookkeeping, and a void pointer gives the
// caller nothing to mistake for something else.
void *vpy_allow_threads(void) {
	return (void *)PyEval_SaveThread();
}

// vpy_end_allow_threads restores the thread state a matching `vpy_allow_threads`
// returned, which re-acquires the GIL.
//
// Paired exactly once per release. Restoring twice, or restoring a state from another
// release, leaves the GIL count wrong and the next thread switch crashes inside
// CPython rather than anywhere near the call that unbalanced it.
void vpy_end_allow_threads(void *state) {
	PyEval_RestoreThread((PyThreadState *)state);
}

// vpy_mod_gil_not_used returns the `Py_MOD_GIL_NOT_USED` slot value.
//
// Through an accessor because it is a macro, and because it only exists where the
// headers know about free threading. Compiles everywhere -- on a GIL build it is
// just `(void *)1` -- and is only ever passed to `PyUnstable_Module_SetGIL`.
void *vpy_mod_gil_not_used(void) {
#ifdef Py_MOD_GIL_NOT_USED
	return Py_MOD_GIL_NOT_USED;
#else
	// The value is `(void *)1` in every version that defines the macro. It is absent
	// from the headers before 3.13 and hidden behind the limited API below a 3.13
	// floor, and both still compile this file. Testing the macro itself rather than
	// the API level is what keeps a 3.11 or 3.12 full-API build compiling.
	return (void *)1;
#endif
}

// vpy_module_set_gil declares whether a module needs the GIL.
//
// Single-phase modules cannot carry slots -- `PyModule_Create2` refuses a definition
// with any -- so this is the only way to declare them GIL-free. Returns CPython's
// status, so the caller decides what a failure means.
//
// `PyUnstable_Module_SetGIL` is only declared when the headers know about free
// threading, so on a GIL build this is a stub that reports failure. That branch never
// runs: the V side calls it only under `$if vcraft_free_threaded`, which the build
// passes exactly when the interpreter is free-threaded. A stub rather than `#ifdef`-
// ing the function away, because a missing symbol fails the link with a message
// about `vpy_module_set_gil` instead of failing the compile with one about
// `PyUnstable_Module_SetGIL`.
int vpy_module_set_gil(void *module, void *gil) {
#ifdef Py_GIL_DISABLED
	return PyUnstable_Module_SetGIL((PyObject *)module, gil);
#else
	(void)module;
	(void)gil;
	return -1;
#endif
}

// vpy_module_def_head fills the head of a module definition from a static one.
//
// `PyModuleDef_HEAD_INIT` is the only thing that sets `_Py_STATICALLY_ALLOCATED_FLAG`
// in `ob_flags`, and CPython 3.15's `PyModuleDef_Init` rejects a free-threaded module
// whose head lacks it ("invalid PyModuleDef, extension possibly compiled for
// non-free-threaded Python"). A definition the runtime builds field by field starts
// zeroed, so the head is copied from a real static definition first. A no-op on a GIL
// build, where the flag is not checked; the V side calls it only under
// `$if vcraft_free_threaded`.
void vpy_module_def_head(void *dst, size_t n) {
#if defined(Py_GIL_DISABLED)
	static const PyModuleDef head = {
		PyModuleDef_HEAD_INIT, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL
	};
	if (n > sizeof(head)) {
		n = sizeof(head);
	}
	memcpy(dst, &head, n);
#else
	(void)dst;
	(void)n;
#endif
}

// vpy_buffer_new allocates a view for one buffer acquisition.
//
// Zeroed, because `PyBuffer_Release` on a view whose acquisition failed must find
// nothing to release rather than a half-written pointer. The zeroing is the contract
// that makes releasing unconditionally safe.
void *vpy_buffer_new(void) {
	return PyMem_Calloc(1, sizeof(Py_buffer));
}

// vpy_buffer_get acquires a simple view of an object's buffer.
//
// Returns 0 on success and -1 with a Python exception set on failure, which is
// CPython's own convention: a `TypeError` naming that a bytes-like object was
// required. The caller releases the view when it is done, on every path, including
// the error paths after it.
int vpy_buffer_get(void *obj, void *view) {
	if (obj == NULL || view == NULL) {
		return -1;
	}
	return PyObject_GetBuffer((PyObject *)obj, (Py_buffer *)view, PyBUF_SIMPLE);
}

// vpy_buffer_ptr returns the address of the viewed bytes.
void *vpy_buffer_ptr(void *view) {
	if (view == NULL) {
		return NULL;
	}
	return ((Py_buffer *)view)->buf;
}

// vpy_buffer_len returns how many bytes the view holds.
long vpy_buffer_len(void *view) {
	if (view == NULL) {
		return 0;
	}
	return (long)((Py_buffer *)view)->len;
}

// vpy_buffer_release releases a view and frees it.
//
// Safe on a view whose acquisition failed, because the view is zeroed on allocation
// and `PyBuffer_Release` finds a null object in it. Safe on null itself, because a
// reader that never acquired has nothing to give back.
void vpy_buffer_release(void *view) {
	if (view == NULL) {
		return;
	}
	PyBuffer_Release((Py_buffer *)view);
	PyMem_Free(view);
}

// vpy_is_exact_bytes reports whether obj is exactly bytes, not a subclass.
//
// Only exact bytes take the no-view fast path: bytes is immutable, so its buffer
// cannot move for the duration of the call, and the argument itself keeps the
// object alive. Everything else -- bytearray, memoryview, exotic exporters --
// goes through a view, which also pins the exporter with a reference.
int vpy_is_exact_bytes(void *obj) {
	if (obj == NULL) {
		return 0;
	}
	return Py_TYPE((PyObject *)obj) == &PyBytes_Type;
}

PyObject *vpy_none(void) {
	return Py_None;
}

PyObject *vpy_notimplemented(void) {
	return Py_NotImplemented;
}

PyObject *vpy_bool_type(void) {
	return (PyObject *)&PyBool_Type;
}

PyObject *vpy_long_type(void) {
	return (PyObject *)&PyLong_Type;
}

PyObject *vpy_float_type(void) {
	return (PyObject *)&PyFloat_Type;
}

PyObject *vpy_str_type(void) {
	return (PyObject *)&PyUnicode_Type;
}

PyObject *vpy_bytes_type(void) {
	return (PyObject *)&PyBytes_Type;
}

PyObject *vpy_tuple_type(void) {
	return (PyObject *)&PyTuple_Type;
}

PyObject *vpy_list_type(void) {
	return (PyObject *)&PyList_Type;
}

PyObject *vpy_dict_type(void) {
	return (PyObject *)&PyDict_Type;
}

PyObject *vpy_module_type(void) {
	return (PyObject *)&PyModule_Type;
}

PyObject *vpy_exc_type_error(void) {
	return PyExc_TypeError;
}

PyObject *vpy_exc_value_error(void) {
	return PyExc_ValueError;
}

PyObject *vpy_exc_runtime_error(void) {
	return PyExc_RuntimeError;
}

PyObject *vpy_exc_not_implemented_error(void) {
	return PyExc_NotImplementedError;
}

PyObject *vpy_exc_attribute_error(void) {
	return PyExc_AttributeError;
}

PyObject *vpy_exc_index_error(void) {
	return PyExc_IndexError;
}

PyObject *vpy_exc_key_error(void) {
	return PyExc_KeyError;
}

PyObject *vpy_exc_stop_iteration(void) {
	return PyExc_StopIteration;
}

PyObject *vpy_exc_memory_error(void) {
	return PyExc_MemoryError;
}

PyObject *vpy_exc_system_error(void) {
	return PyExc_SystemError;
}

PyObject *vpy_exc_zero_division_error(void) {
	return PyExc_ZeroDivisionError;
}

PyObject *vpy_exc_arithmetic_error(void) {
	return PyExc_ArithmeticError;
}

PyObject *vpy_exc_buffer_error(void) {
	return PyExc_BufferError;
}

// vpy_is_complex reports whether an object is a Python complex.
//
// By type name rather than by `PyComplex_Check`, which is a macro over
// `PyObject_TypeCheck` and does not compile under `Py_LIMITED_API`: at 3.11 and above it
// wraps itself and V's preprocessor output trips the C compiler, the same problem
// `vpy_type_check` was written to sidestep. `PyType_GetName` is stable ABI, so the same
// code serves an abi3 and a full build.
int vpy_is_complex(void *o) {
#ifdef Py_LIMITED_API
	// Under the limited API `PyComplex_Type` is hidden and `PyComplex_Check` is a macro
	// that trips the compiler (see `vpy_type_check`), so the type is recognised by name.
	if (o == NULL) {
		return 0;
	}
	char buf[32];
	int n = vpy_type_name_into((PyObject *)o, buf, sizeof(buf));
	if (n < 0) {
		// A type with no name is not a complex, and the pending error is not the
		// caller's: the reader falls through to the float path, which reports the type
		// it got.
		PyErr_Clear();
		return 0;
	}
	return strcmp(buf, "complex") == 0;
#else
	// A full build can use the macro: two loads against the name probe's allocation and
	// string comparison, on the hot path of every complex conversion.
	return o != NULL && PyComplex_Check((PyObject *)o);
#endif
}

// The buffer-protocol slot ids, read from the headers.
//
// PEP 820 renumbered these in CPython 3.15: `Py_bf_getbuffer` was 1 and is 88, and the
// old number survives only as an alias for a limited-API build below 3.15. V cannot read
// a macro, so the value is asked for here and the build it was compiled with decides it.
int vpy_slot_bf_getbuffer(void) {
	return Py_bf_getbuffer;
}

int vpy_slot_bf_releasebuffer(void) {
	return Py_bf_releasebuffer;
}

// The multi-phase module slot ids, for the same reason: PEP 820 renumbers them too, and
// an abi3 build whose floor is 3.15 reads the new values.
int vpy_slot_mod_exec(void) {
	return Py_mod_exec;
}

int vpy_slot_mod_create(void) {
	return Py_mod_create;
}

PyObject *vpy_exc_overflow_error(void) {
	return PyExc_OverflowError;
}

// vpy_exact_long_as_i64 is the fast path for reading an integer argument.
//
// It covers the case nearly every call is: an exact `int` that fits in 64 bits. One
// pointer comparison decides it, where the general reader asks `PyType_IsSubtype`
// twice (once to refuse `bool`, once to accept `int`) and then consults the error
// indicator. Returns 1 with the value stored, or 0 with nothing stored and no Python
// error left set, in which case the caller takes the general path: a subclass, a
// `bool`, another type and an overflow all end up there, with their usual messages.
int vpy_exact_long_as_i64(PyObject *o, long long *out) {
	if (o == NULL || !PyLong_CheckExact(o)) {
		return 0;
	}
	int overflow = 0;
	long long value = PyLong_AsLongLongAndOverflow(o, &overflow);
	if (overflow != 0) {
		return 0;
	}
	if (value == -1 && PyErr_Occurred()) {
		PyErr_Clear();
		return 0;
	}
	*out = value;
	return 1;
}

// vpy_is_instance reports whether `o` is an instance of `type` or of a subclass.
//
// `PyObject_Type` would answer the same question with a new reference to the type,
// which the caller then has to release; reading `Py_TYPE` borrows it.
int vpy_is_instance(PyObject *o, PyObject *type) {
	if (o == NULL || type == NULL) {
		return 0;
	}
	return PyType_IsSubtype(Py_TYPE(o), (PyTypeObject *)type);
}

// vpy_seq_item returns item `i` of a list or a tuple as a borrowed reference.
//
// `PySequence_GetItem` answers for any sequence, but with a new reference, and the
// runtime's sequence readers treated it as borrowed: every element read kept one
// reference that was never released, so the elements of a temporary list were never
// freed. A list or a tuple, the only sequences a `[]T` parameter accepts, hands out
// borrowed references of its own.
PyObject *vpy_seq_item(PyObject *o, Py_ssize_t i) {
	if (PyList_Check(o)) {
		return PyList_GetItem(o, i);
	}
	if (PyTuple_Check(o)) {
		return PyTuple_GetItem(o, i);
	}
	PyErr_SetString(PyExc_TypeError, "expected a list or a tuple");
	return NULL;
}

// vpy_seq_at reads item `i` of a list or a tuple whose length the caller has checked.
static PyObject *vpy_seq_at(PyObject *o, int is_list, Py_ssize_t i) {
#ifdef Py_LIMITED_API
	return is_list ? PyList_GetItem(o, i) : PyTuple_GetItem(o, i);
#else
	return is_list ? PyList_GET_ITEM(o, i) : PyTuple_GET_ITEM(o, i);
#endif
}

// vpy_seq_fill_f64 converts the leading items of a list or a tuple of exact floats
// and ints into `out`, which holds `n` doubles, `n` being the sequence's length.
//
// It returns how many it converted. It stops at the first item that is anything
// else, without raising, and the caller converts the rest one at a time with the
// general reader, which raises the usual error for whichever item is wrong. One pass
// in C with no Python error state consulted is what makes the common case cheap.
Py_ssize_t vpy_seq_fill_f64(PyObject *o, double *out, Py_ssize_t n) {
	int is_list = PyList_Check(o);
	for (Py_ssize_t i = 0; i < n; i++) {
		PyObject *item = vpy_seq_at(o, is_list, i);
		if (item != NULL && PyFloat_CheckExact(item)) {
#ifdef Py_LIMITED_API
			out[i] = PyFloat_AsDouble(item);
#else
			out[i] = PyFloat_AS_DOUBLE(item);
#endif
			continue;
		}
		long long value;
		if (vpy_exact_long_as_i64(item, &value)) {
			out[i] = (double)value;
			continue;
		}
		return i;
	}
	return n;
}

// vpy_seq_fill_i64 is `vpy_seq_fill_f64` for exact ints that fit in 64 bits.
Py_ssize_t vpy_seq_fill_i64(PyObject *o, long long *out, Py_ssize_t n) {
	int is_list = PyList_Check(o);
	for (Py_ssize_t i = 0; i < n; i++) {
		if (!vpy_exact_long_as_i64(vpy_seq_at(o, is_list, i), &out[i])) {
			return i;
		}
	}
	return n;
}

// vpy_list_from_i64 builds a list of ints from `n` 64-bit integers.
//
// The generic `to_py_list` boxes each element through a function pointer and stores
// it with `PyList_SetItem`, which checks its arguments every time. For the element
// types that are plain numbers the whole loop runs here instead. Returns a new
// reference, or NULL with an exception set.
PyObject *vpy_list_from_i64(const long long *items, Py_ssize_t n) {
	PyObject *list = PyList_New(n);
	if (list == NULL) {
		return NULL;
	}
	for (Py_ssize_t i = 0; i < n; i++) {
		PyObject *value = PyLong_FromLongLong(items[i]);
		if (value == NULL) {
			Py_DECREF(list);
			return NULL;
		}
#ifdef Py_LIMITED_API
		PyList_SetItem(list, i, value);
#else
		PyList_SET_ITEM(list, i, value);
#endif
	}
	return list;
}

// vpy_list_from_f64 is `vpy_list_from_i64` for doubles.
PyObject *vpy_list_from_f64(const double *items, Py_ssize_t n) {
	PyObject *list = PyList_New(n);
	if (list == NULL) {
		return NULL;
	}
	for (Py_ssize_t i = 0; i < n; i++) {
		PyObject *value = PyFloat_FromDouble(items[i]);
		if (value == NULL) {
			Py_DECREF(list);
			return NULL;
		}
#ifdef Py_LIMITED_API
		PyList_SetItem(list, i, value);
#else
		PyList_SET_ITEM(list, i, value);
#endif
	}
	return list;
}
