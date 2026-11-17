module vcraft

// Native state a class owns.
//
// A `@[vc_class]` field annotated `@[vc_handle]` holds an `Owned`: a pointer and the
// function that releases it. The generated `tp_dealloc` calls `release` on it, so the
// lifetime of the allocation is the lifetime of the instance and nothing else has to be
// remembered at a call site.
//
// This is the shape the state rule pushes you towards. A `voidptr` field would be a
// pointer V's collector cannot see (the state block lives in CPython-allocated memory, and
// Boehm does not scan that), so a bare pointer there is freed by nobody and the object
// holds a dangling address after the mid-game. Naming the release alongside the pointer is
// what makes the field ownable: there is no guessing at what a freed handle wanted.
//
// A capsule in a `@[vc_ref]` field does the same job when the state has to be visible to
// Python - `new_handle`/`handle_data` - and it costs a Python object per handle. This is
// for state that stays native: a socket, a cursor, an arena, a running coroutine.
//
// ```v
// @[vc_class]
// pub struct Listener {
// mut:
// 	@[vc_handle]
// 	socket vcraft.Owned
// }
//
// pub fn new_listener(fd int) &Listener {
// 	return &Listener{
// 		socket: vcraft.own(voidptr(fd), close_fd)
// 	}
// }
//
// fn close_fd(p voidptr) {
// 	C.close(int(p))
// }
// ```

// Owned is a native pointer together with the function that releases it.
//
// Both halves are scalars, so one of these is safe to hold in the state block of a class:
// nothing in it needs the collector to follow it. The drop function is `fn (voidptr)`
// rather than a method so a class can own something it has no type for.
pub struct Owned {
pub mut:
	ptr  voidptr
	drop fn (voidptr) = unsafe { nil }
	// root is the collector root that keeps a V allocation alive while the instance
	// holds it (see `own_gc`); null for a pointer `own` was given.
	root voidptr
}

// own pairs a pointer with the function that releases it.
//
// Ownership transfers: whatever `ptr` came from is released when the instance holding
// this is deallocated, or when `release` is called on it directly.
pub fn own(ptr voidptr, drop fn (voidptr)) Owned {
	return Owned{
		ptr:  ptr
		drop: drop
	}
}

// own_gc keeps a V allocation alive for as long as the instance holding it.
//
// `own` is for memory the collector does not manage. V state built with `&T{...}` -- a
// struct with maps, arrays, a mutex, a channel -- is the collector's, and a pointer to it
// kept only in an instance is a pointer the collector cannot see: the state block lives
// in CPython's memory, which it does not scan, so the struct would be freed while the
// instance still used it. `own_gc` registers the pointer as a collector root, and
// `release` (run by the generated `tp_dealloc`) drops the root again, after which the
// collector reclaims the struct like any other garbage.
//
// ```v
// @[vc_class]
// pub struct Server {
// mut:
// 	@[vc_handle]
// 	hub vcraft.Owned
// }
//
// pub fn new_server() &Server {
// 	return &Server{
// 		hub: vcraft.own_gc(&Hub{})
// 	}
// }
//
// fn (s &Server) state() &Hub {
// 	return unsafe { &Hub(s.hub.get()) }
// }
// ```
//
// Each instance owns its own state, so a process can hold any number of them, which a
// module-level global cannot give.
pub fn own_gc(ptr voidptr) Owned {
	return Owned{
		ptr:  ptr
		root: C.vpy_gc_pin(ptr)
	}
}

// release calls the drop function, once.
//
// Safe to call twice, and safe on the zero value of the struct: a field of a class that
// was never constructed holds no pointer, and `tp_dealloc` runs on such an instance every
// time a constructor raises. The pointer is cleared before the drop runs, so a drop that
// panics cannot leave a handle that would release the same address again.
pub fn (mut o Owned) release() {
	ptr := o.ptr
	if ptr == unsafe { nil } {
		return
	}
	o.ptr = unsafe { nil }
	if o.root != unsafe { nil } {
		root := o.root
		o.root = unsafe { nil }
		C.vpy_gc_unpin(root)
	}
	if o.drop != unsafe { nil } {
		o.drop(ptr)
	}
}

// get returns the pointer, for the code that knows what it is.
//
// V has no generic cast to a named type here, so a caller writes the cast itself:
// `unsafe { &net.TcpListener(handle.get()) }`.
pub fn (o Owned) get() voidptr {
	return o.ptr
}

// is_set reports whether the handle still owns something.
pub fn (o Owned) is_set() bool {
	return o.ptr != unsafe { nil }
}
