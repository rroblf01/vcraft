module vcraft

// V functions Python can await (`@[vc_async]`).
//
// The trampoline reads the arguments under the GIL like any other, copies whatever only
// borrows from a Python object (a `str`, `bytes`, the items of a `list[str]`), asks the
// running event loop for a future, and starts the V function on a thread of its own,
// without the GIL. When the function returns, that thread takes the GIL, boxes the result
// -- or turns its error, or its panic, into the exception -- and hands it to the loop with
// `call_soon_threadsafe`, which settles the future on the loop's own thread. A future
// cancelled in the meantime is left alone.
//
// No runtime crate and no executor: the loop is asyncio's, the thread is V's.

// AsyncCall is what the worker thread needs to settle one call: the loop and the future,
// each an owned reference that `async_settle` releases.
pub struct AsyncCall {
pub:
	loop   PyObj
	future PyObj
}

// async_begin returns the running event loop and a new future on it. Called on the
// calling thread, with the GIL; outside a running loop it raises RuntimeError, as
// `asyncio.get_running_loop()` does.
pub fn async_begin() !AsyncCall {
	loop := steal(C.vpy_running_loop())
	if loop.is_null() {
		return error('no running event loop')
	}
	future := call_method(loop.ptr, 'create_future', []voidptr{})
	if future.is_null() {
		loop.decref()
		return error('create_future failed')
	}
	return AsyncCall{
		loop:   loop
		future: future
	}
}

// async_succeed settles the call with `value`, whose reference it takes. The caller holds
// the GIL.
pub fn async_succeed(call AsyncCall, value PyObj) {
	if value.is_null() {
		// The value failed to box; its exception is pending and becomes the outcome.
		async_settle_pending(call)
		return
	}
	async_settle(call, true, value)
}

// async_fail settles the call with the exception `err` stands for, chosen the way a
// synchronous call's would be. Takes the GIL itself.
pub fn async_fail(call AsyncCall, err IError) {
	state := gil_ensure()
	raise_from_error(err)
	async_settle_pending(call)
	gil_release(state)
}

// async_panic settles the call with the RuntimeError a recovered panic becomes. Takes the
// GIL itself: the panic happened in V code running without it.
pub fn async_panic(call AsyncCall, message string) {
	state := gil_ensure()
	raise_panic(message)
	async_settle_pending(call)
	gil_release(state)
}

// async_settle_pending settles the call with the pending exception.
fn async_settle_pending(call AsyncCall) {
	t, v, tb := fetch_error()
	t.decref()
	tb.decref()
	if v.is_null() {
		async_settle(call, false, steal(C.vpy_new_runtime_error()))
		return
	}
	async_settle(call, false, v)
}

// async_settle schedules `future.set_result(value)` (or `set_exception`) on the loop's
// thread and releases the call's references and `value`. A loop that has closed since
// cannot take it, and then there is nobody left to tell.
fn async_settle(call AsyncCall, ok bool, value PyObj) {
	settle := C.vpy_async_settle_fn()
	flag := to_py_bool(ok)
	r := call_method(call.loop.ptr, 'call_soon_threadsafe', [settle, call.future.ptr, flag.ptr,
		value.ptr])
	if r.is_null() {
		clear_error()
	}
	r.decref()
	flag.decref()
	value.decref()
	call.future.decref()
	call.loop.decref()
}
