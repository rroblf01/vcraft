module vcraft

// Running V code without the global interpreter lock.
//
// `@[vc_nogil]` marks a function as pure V with no Python interaction, and the generated
// wrapper releases the GIL around the call so long-running V code runs in parallel the
// way `py.allow_threads` does in PyO3. The wrapper looks like this:
//
// ```v
// mut saved := vcraft.allow_threads()
// defer {
// 	if message := recover() {
// 		vcraft.raise_runtime_error('panic in V code: ${message}')
// 	}
// }
// defer {
// 	if saved != unsafe { nil } {
// 		vcraft.end_allow_threads(saved)
// 	}
// }
// result = add(arg0, arg1)
// vcraft.end_allow_threads(saved)
// saved = unsafe { nil }
// return vcraft.to_py_int(result).ptr
// ```
//
// Three details are load-bearing and none of them is obvious:
//
//   - The release is paired in a `defer` rather than only on the fall-through path,
//     because a panic unwinds past the explicit release. The `saved != nil` guard is
//     what keeps that from double-restoring: the fall-through path restores and nulls
//     the handle, so the deferred restore on the way out finds nothing to do, while a
//     panic unwinds straight into a restore of the handle that is still set.
//   - The `recover` defer is registered *before* the restore defer. Defers run last in,
//     first out, so the restore runs first on a panic and the raise that follows it
//     already holds the GIL. Registered the other way round, the raise would run
//     without it.
//   - A `!T` call captures its error into V locals rather than raising in the `or`
//     block, because raising touches Python. The block restores, raises, re-releases
//     and returns, reassigning `saved` so the deferred restore still pairs exactly
//     once.
//
// The contract on the V side is absolute: no Python calls, no `raise_domain`, no
// touching a `PyObj`, while released. `raise_domain` sets a Python exception, which
// without the GIL corrupts the interpreter state rather than reporting anything. The
// generator cannot verify purity, so `@[vc_nogil]` on a `@[vc_raw]` function is refused:
// raw means the function handles `PyObject *` itself, which is the opposite of pure.

// allow_threads releases the GIL and returns the state to restore.
//
// The state is the thread's own, saved by CPython. It travels as an opaque pointer
// because restoring anything else corrupts the interpreter, and a void pointer gives
// the generated code nothing to mistake for something else.
pub fn allow_threads() voidptr {
	unsafe {
		return C.vpy_allow_threads()
	}
}

// end_allow_threads restores the state a matching `allow_threads` returned.
//
// Exactly once per release. The generated wrapper guards the deferred call with a nil
// check so a fall-through restore and a panic-unwind restore cannot both fire.
pub fn end_allow_threads(state voidptr) {
	unsafe {
		C.vpy_end_allow_threads(state)
	}
}

// gil_ensure acquires the GIL for a thread that does not hold it, and returns the state to
// give back with `gil_release`.
//
// The other direction from `allow_threads`, and the one that makes a V-owned thread
// possible. A thread V created with `spawn` holds no Python thread state: calling into
// Python from it - `vcraft.call`, `to_py_*`, a `PyObj` - needs the GIL, and nothing in V
// can hand it over. `PyGILState_Ensure` is a no-op when the calling thread already holds
// the GIL, so a function may call it defensively rather than asserting which thread it is
// on.
//
// The state is CPython's own enum and travels as an int, because V has no name for it and
// a `[faulty]` void pointer would invite someone to invent one.
pub fn gil_ensure() int {
	return C.vpy_gil_ensure()
}

// gil_release gives back the state `gil_ensure` returned. Exactly once per acquisition.
pub fn gil_release(state int) {
	C.vpy_gil_release(state)
}

// with_gil runs `f` holding the GIL, acquiring it for the duration when the calling thread
// does not already have it.
//
// This is the shape a V-created thread wants: everything Python-touching goes inside the
// block, and the defer gives the GIL back on the way out, panic included. It does not make
// `@[vc_nogil]` safe to call Python from - a released call still may not touch Python -
// it is the way back in.
pub fn with_gil(f fn ()) {
	state := gil_ensure()
	defer {
		gil_release(state)
	}
	f()
}

// released runs `f` with the GIL released, and re-acquires it on every path, panic included.
//
// The mirror image of `with_gil`: a function that is not `@[vc_nogil]` holds the GIL for its
// whole call, so a long V-only stretch - a poll, a parse, a compress, a syscall loop - blocks
// every other Python thread. `released` is the RAII version of the `allow_threads`/
// `end_allow_threads` pair the README describes, and it is the only way to get the pair
// balanced when the block can panic: the restore runs in a `defer` registered *after* the
// `recover` defer, so on a panic the restore fires first and the raise that follows it
// already holds the GIL. An unbalanced pair leaves the GIL count wrong and crashes the
// next thread switch inside CPython, which is how this was found.
//
// `f` runs released, so it may not touch Python, may not call `allow_threads` or
// `end_allow_threads`, and may not raise a V error: all three go through the interpreter.
// Anything that has to cross the boundary goes before `released` or after it.
pub fn released(f fn ()) {
	state := allow_threads()
	defer {
		if message := recover() {
			vcraft.raise_panic(message)
		}
	}
	defer {
		end_allow_threads(state)
	}
	f()
}
