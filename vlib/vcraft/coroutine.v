module vcraft

// Driving Python coroutines from V.
//
// Python's own way of doing this is `loop.run_until_complete`, which costs ~9.5 us a
// request: it wraps the coroutine in a Task and enters the loop twice, polling the
// selector with a zero timeout - a syscall - before the request is done. Almost every
// await in an extension is our own receive/send, which complete without suspending, so a
// single `send(None)` finishes the request in ~1.8 us. The loop is only entered when the
// coroutine really suspends on I/O.
//
// The GIL is held for the whole call, exactly as for `call`: V can release it with
// `released` if it has V-only work to do, but the coroutine itself is not paused while V
// works. It has already finished (fast path) or has suspended on a future that V cannot
// resume without re-entering the loop.
//
// `asyncio.events._set_running_loop` is a private name. It is the only way to make
// `asyncio.get_running_loop()` work while the coroutine is being stepped by hand, and
// everything that uses a running loop - `asyncio.sleep` with a positive delay, `anyio`, a
// database driver - needs it. vcraft is now the only place that depends on it: an
// extension that does not reimplement this function does not depend on it at all, and if a
// future CPython renames it, one function changes.

// run_coroutine drives a coroutine to completion on the current thread and returns its
// result, or the null object with a Python exception set.
pub fn run_coroutine(coro PyObj) PyObj {
	if coro.is_null() {
		return coro
	}
	asyncio := import_module('asyncio')
	events := import_module('asyncio.events')

	// The loop for this thread, created if it does not have one. `get_event_loop` raises
	// on a worker thread that never set one, and then we create and install it.
	mut loop := call_method(asyncio.ptr, 'get_event_loop', []voidptr{})
	if loop.is_null() {
		clear_error()
		loop = call_method(asyncio.ptr, 'new_event_loop', []voidptr{})
		if loop.is_null() {
			clear_error()
			return steal(unsafe { nil })
		}
		none_obj := py_none()
		mut set_args := []voidptr{cap: 1}
		set_args << loop.ptr
		_ = call_method(asyncio.ptr, 'set_event_loop', set_args)
		none_obj.decref()
	}

	// Save the running-loop marker so it can be restored on every path.
	mut previous := call_method(events.ptr, '_get_running_loop', []voidptr{})
	if previous.is_null() {
		clear_error()
		previous = steal(unsafe { nil })
	}

	// Mark the loop as running for the steps.
	none_obj := py_none()
	mut args0 := []voidptr{cap: 1}
	args0 << loop.ptr
	_ = call_method(events.ptr, '_set_running_loop', args0)
	none_obj.decref()

	none_for_defer := py_none()
	defer {
		none_for_defer.decref()
	}

	// Fast path: one send(None). A coroutine that finishes without suspending returns
	// StopIteration carrying its result; one that suspends returns the yielded value.
	mut send_arg := []voidptr{cap: 1}
	send_arg << none_obj.ptr
	yielded := call_method(coro.ptr, 'send', send_arg)
	if yielded.is_null() {
		if error_is_set() {
			t, v, tb := fetch_error()
			if !t.is_null() && v.type_name() == 'StopIteration' {
				value := if v.is_null() {
					py_none()
				} else {
					attr := getattr(v.ptr, 'value')
					if attr.is_null() {
						clear_error()
						py_none()
					} else {
						attr
					}
				}
				t.decref()
				v.decref()
				tb.decref()
				restore_marker(events, previous, loop)
				if !previous.is_null() {
					previous.decref()
				}
				loop.decref()
				return value
			}
			restore_marker(events, previous, loop)
			if !previous.is_null() {
				previous.decref()
			}
			loop.decref()
			C.PyErr_Restore(t.ptr, v.ptr, tb.ptr)
			return steal(unsafe { nil })
		}
		restore_marker(events, previous, loop)
		if !previous.is_null() {
			previous.decref()
		}
		loop.decref()
		return py_none()
	}

	// Slow path: the coroutine suspended. Drive it through the loop, re-stepping after
	// each future completes. The running-loop marker is cleared around run_until_complete,
	// which refuses to start while it is set.
	mut future := yielded
	for {
		none_obj2 := py_none()
		mut args1 := []voidptr{cap: 1}
		args1 << none_obj2.ptr
		_ = call_method(events.ptr, '_set_running_loop', args1)
		none_obj2.decref()

		if future.is_none() {
			// A bare yield: run one loop iteration so timers and callbacks progress.
			mut sleep_args := []voidptr{cap: 1}
		sleep_args << to_py_f64(0.0).ptr
		coro_sleep := call_method(asyncio.ptr, 'sleep', sleep_args)
			if !coro_sleep.is_null() {
				mut args2 := []voidptr{cap: 1}
				args2 << coro_sleep.ptr
				_ = call_method(loop.ptr, 'run_until_complete', args2)
				coro_sleep.decref()
			} else {
				clear_error()
			}
		} else {
			mut args3 := []voidptr{cap: 1}
			args3 << future.ptr
			_ = call_method(loop.ptr, 'run_until_complete', args3)
		}

		none_obj4 := py_none()
		mut args4 := []voidptr{cap: 1}
		args4 << loop.ptr
		_ = call_method(events.ptr, '_set_running_loop', args4)
		none_obj4.decref()

		mut send_value := py_none()
		mut send_exc := steal(unsafe { nil })
		if !future.is_none() {
			result := call_method(future.ptr, 'result', []voidptr{})
			if result.is_null() {
				if error_is_set() {
					t, v, tb := fetch_error()
					send_exc = v
					t.decref()
					tb.decref()
				}
			} else {
				send_value = result
			}
		}

		mut resume_args := []voidptr{cap: 1}
		mut yielded2 := PyObj{}
		if send_exc.ptr != nil {
			resume_args << send_exc.ptr
			yielded2 = call_method(coro.ptr, 'throw', resume_args)
		} else {
			resume_args << send_value.ptr
			yielded2 = call_method(coro.ptr, 'send', resume_args)
		}
		send_value.decref()
		if !send_exc.is_null() {
			send_exc.decref()
		}
		future.decref()

		if yielded2.is_null() {
			if error_is_set() {
				t, v, tb := fetch_error()
				if !t.is_null() && v.type_name() == 'StopIteration' {
					value := if v.is_null() {
						py_none()
					} else {
						attr := getattr(v.ptr, 'value')
						if attr.is_null() {
							clear_error()
							py_none()
						} else {
							attr
						}
					}
					t.decref()
					v.decref()
					tb.decref()
					restore_marker(events, previous, loop)
					if !previous.is_null() {
						previous.decref()
					}
					loop.decref()
					return value
				}
				// Not StopIteration: restore the exception so it propagates.
				restore_marker(events, previous, loop)
				if !previous.is_null() {
					previous.decref()
				}
				loop.decref()
				C.PyErr_Restore(t.ptr, v.ptr, tb.ptr)
				return steal(unsafe { nil })
			}
			restore_marker(events, previous, loop)
			if !previous.is_null() {
				previous.decref()
			}
			loop.decref()
			return py_none()
		}
		future = yielded2
	}

	// unreachable
}

// call_async calls `callee` with positional `args` and drives the coroutine it returns.
pub fn call_async(callee voidptr, args []voidptr) PyObj {
	coro := call(callee, args)
	if coro.is_null() {
		return coro
	}
	result := run_coroutine(coro)
	coro.decref()
	return result
}

// restore_marker puts the running-loop marker back where it was, without leaking it.
fn restore_marker(events PyObj, previous PyObj, loop PyObj) {
	none_obj := py_none()
	mut args := []voidptr{cap: 1}
	if previous.is_null() {
		args << none_obj.ptr
	} else {
		args << previous.ptr
	}
	_ = call_method(events.ptr, '_set_running_loop', args)
	none_obj.decref()
}
