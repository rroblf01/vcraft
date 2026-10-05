module vcraft

// Running V code without the global interpreter lock.
//
// `@[vc_gil]` marks a function as pure V with no Python interaction, and the generated
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
// generator cannot verify purity, so `@[vc_gil]` on a `@[vc_raw]` function is refused:
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
