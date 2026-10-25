module async_callback_native

import vcraft

// run_async calls `coroutine` (a Python async function) and returns its result.
//
// `vcraft.call_async` is `vcraft.call` plus `vcraft.run_coroutine`: it calls the
// callable, gets the coroutine it returns, and drives it to completion on the
// current thread. The fast path is a single `send(None)`; the slow path enters the
// loop only when the coroutine suspends on real I/O.
//
// The GIL is held for the whole call. V can release it with `vcraft.released` if it
// has V-only work to do, but the coroutine itself is not paused while V works.
@[vc_fn]
pub fn run_async(coroutine voidptr, arg int) !int {
	mut args := []voidptr{cap: 1}
	args << vcraft.to_py_int(arg).ptr
	result := vcraft.call_async(coroutine, args)
	if result.is_null() {
		return vcraft.raise_domain(.runtime_error, 'async call failed')
	}
	value := vcraft.from_py_int(result, 'result') or {
		return vcraft.raise_domain(.runtime_error, 'async call failed')
	}
	result.decref()
	return value
}
