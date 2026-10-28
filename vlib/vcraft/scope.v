module vcraft

// Scope-based management of Python references.
//
// V has no destructors, so every `PyObj` a function creates has to be released
// by hand, and a forgotten `decref` is the usual leak. A scope collects the
// references a block creates and releases them all when the block exits, on
// every path including a panic.
//
// Usage:
//
//	vcraft.with_py_scope(fn [mut out] (mut scope PyScope) {
//		a := scope.track(vcraft.to_py_int(1))
//		b := scope.track(vcraft.to_py_int(2))
//		out = vcraft.to_py_int(a.ptr == b.ptr) // ...
//	})
//
// `track` returns its argument unchanged, so it can wrap a creation expression
// inline. A reference that has to outlive the scope (a result, a field) is
// taken out with `scope.keep(o)`, which removes it from the tracked set.

// PyScope collects Python references and releases them on scope exit.
pub struct PyScope {
mut:
	refs []PyObj
}

// track records `o` for release and returns it unchanged.
pub fn (mut s PyScope) track(o PyObj) PyObj {
	if !o.is_null() {
		s.refs << o
	}
	return o
}

// keep removes `o` from the tracked set so it survives the scope. Returns `o`.
pub fn (mut s PyScope) keep(o PyObj) PyObj {
	for i := s.refs.len - 1; i >= 0; i-- {
		if s.refs[i].ptr == o.ptr {
			s.refs.delete(i)
			break
		}
	}
	return o
}

// release releases every tracked reference. Safe to call more than once.
pub fn (mut s PyScope) release() {
	for o in s.refs {
		o.decref()
	}
	s.refs = []
}

// with_py_scope runs `f` with a fresh scope and releases it on exit, including
// on a panic. `f` receives the scope by mutable reference.
pub fn with_py_scope(f fn (mut PyScope)) {
	mut scope := PyScope{}
	defer {
		scope.release()
	}
	f(mut scope)
}
