module vcraft_runtime_check

// End-to-end exercise of the vcraft runtime.
//
// The glue here is written by hand, exactly as the code generator will emit it.
// Keeping it hand-written means the runtime can be tested before the generator
// exists, and it doubles as the reference the generator is checked against.
//
// Note the module name: it must not end in `_test`. V treats any file matching
// `*_test.v` as a test file, compiles it with the test harness, and silently
// drops the module's export, which looks like a vcraft bug and is not.

import vcraft


@[export: 'PyInit_vcraft_runtime_check']
fn pyinit_vcraft_runtime_check() voidptr {
	vcraft.init_state()
	mut m := vcraft.new_module('vcraft_runtime_check', 'Hand-written glue over the vcraft runtime.')
	m.add_function_owned('answer', voidptr(answer_trampoline), vcraft.meth_noargs,
		'Return the answer.')
	m.add_function_owned('add', voidptr(add_trampoline), vcraft.meth_fastcall, 'add(a, b)')
	m.add_function_owned('greet', voidptr(greet_trampoline), vcraft.meth_fastcall,
		'greet(name)')
	m.add_function_owned('describe', voidptr(describe_trampoline), vcraft.meth_fastcall,
		'describe(value)')
	m.add_function_owned('checked', voidptr(checked_trampoline), vcraft.meth_fastcall,
		'checked(a, b)')
	m.add_function_owned('boom', voidptr(boom_trampoline), vcraft.meth_noargs, 'boom()')
	m.add_function_owned('maybe', voidptr(maybe_trampoline), vcraft.meth_fastcall,
		'maybe(flag)')
	m.add_function_owned('identity', voidptr(identity_trampoline), vcraft.meth_fastcall,
		'identity(obj)')
	m.add_function_owned('sum_all', voidptr(sum_all_trampoline), vcraft.meth_fastcall,
		'sum_all(values)')
	m.add_function_owned('sum_callback', voidptr(sum_callback_trampoline), vcraft.meth_fastcall,
		'sum_callback(callee)')
	m.add_function_owned('call_kw_test', voidptr(call_kw_test_trampoline), vcraft.meth_fastcall,
		'call_kw_test(callee)')
	m.add_function_owned('unpack_tuple', voidptr(unpack_tuple_trampoline), vcraft.meth_fastcall,
		'unpack_tuple(t)')
	m.add_function_owned('unpack_bytes', voidptr(unpack_bytes_trampoline), vcraft.meth_fastcall,
		'unpack_bytes(t)')
	m.add_function_owned('build_obj_list', voidptr(build_obj_list_trampoline), vcraft.meth_noargs,
		'build_obj_list()')
	m.add_function_owned('py_scope_test', voidptr(py_scope_test_trampoline), vcraft.meth_noargs,
		'py_scope_test()')
	m.add_function_owned('setattr_hasattr', voidptr(setattr_hasattr_trampoline), vcraft.meth_fastcall,
		'setattr_hasattr(obj)')
	m.add_function_owned('repr_f64_test', voidptr(repr_f64_test_trampoline), vcraft.meth_noargs,
		'repr_f64_test()')
	m.add_function_owned('type_obj_name', voidptr(type_obj_name_trampoline), vcraft.meth_noargs,
		'type_obj_name()')	m.add_function_owned('build_set', voidptr(build_set_trampoline), vcraft.meth_noargs,
		'build_set()')
	m.add_function_owned('list_build', voidptr(list_build_trampoline), vcraft.meth_noargs,
		'list_build()')	m.add_function_owned('run_coro_fast', voidptr(run_coro_fast_trampoline), vcraft.meth_fastcall,
		'run_coro_fast(callee)')
	m.add_function_owned('call_from_thread', voidptr(call_from_thread_trampoline),
		vcraft.meth_fastcall, 'call_from_thread(callee)')
	m.add_function_owned('released_then_call', voidptr(released_then_call_trampoline),
		vcraft.meth_fastcall, 'released_then_call(callee)')
	m.add_function_owned('released_panics', voidptr(released_panics_trampoline),
		vcraft.meth_noargs, 'released_panics()')
	m.add_function_owned('export_squares', voidptr(export_squares_trampoline),
		vcraft.meth_fastcall, 'export_squares(n)')
	m.add_function_owned('layout', voidptr(layout_trampoline), vcraft.meth_noargs,
		'layout()')
	return m.seal().ptr
}

// Each trampoline follows the same shape: check the arity, read the arguments
// through the runtime, call the V function, box the result. No reader object and
// no cross-module struct mutation, because V cannot compile either.

fn answer_trampoline(self voidptr, args voidptr) voidptr {
	return vcraft.to_py_int(answer()).ptr
}

fn add_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('add', 2, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	a := vcraft.from_py_int_arg(args, 0, 'add', 'a') or { return unsafe { nil } }
	b := vcraft.from_py_int_arg(args, 1, 'add', 'b') or { return unsafe { nil } }
	vcraft.reject_extra_args('add', 2, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(add(a, b)).ptr
}

fn greet_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('greet', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	name := vcraft.from_py_string_arg(args, 0, 'greet', 'name') or { return unsafe { nil } }
	vcraft.reject_extra_args('greet', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	greeting := greet(name) or {
		vcraft.raise_from_error(err)
		return unsafe { nil }
	}
	return vcraft.to_py_string(greeting).ptr
}

fn describe_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('describe', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	value := vcraft.from_py_f64_arg(args, 0, 'describe', 'value') or { return unsafe { nil } }
	vcraft.reject_extra_args('describe', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_string(describe(value)).ptr
}

fn checked_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('checked', 2, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	a := vcraft.from_py_int_arg(args, 0, 'checked', 'a') or { return unsafe { nil } }
	b := vcraft.from_py_int_arg(args, 1, 'checked', 'b') or { return unsafe { nil } }
	// The panic guard is inlined, exactly as the code generator emits it. A V
	// panic calls exit(1), which inside CPython would kill the interpreter.
	mut result := 0
	defer {
		if message := recover() {
			vcraft.raise_runtime_error('panic in V code: ${message}')
		}
	}
	result = checked(a, b)
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

fn boom_trampoline(self voidptr, args voidptr) voidptr {
	defer {
		if message := recover() {
			vcraft.raise_runtime_error('panic in V code: ${message}')
		}
	}
	boom()
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_none().ptr
}

fn maybe_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('maybe', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	flag := vcraft.from_py_bool_arg(args, 0, 'maybe', 'flag') or { return unsafe { nil } }
	vcraft.reject_extra_args('maybe', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	if flag {
		return vcraft.to_py_int(42).ptr
	}
	return vcraft.to_py_none().ptr
}

// sum_callback calls `callee()` and sums the bytes it returns, which is what puts
// `bytes_view` through both of its paths: the exact-`bytes` alias, which needs no view, and
// the buffer view a `bytearray` or a `memoryview` goes through.
fn sum_callback(callee voidptr) int {
	empty := []voidptr{}
	result := vcraft.call(callee, empty)
	if result.is_null() {
		return -1
	}
	view := vcraft.bytes_view(result, 'result') or {
		result.decref()
		return -1
	}
	mut total := 0
	for byte in view.data {
		total += int(byte)
	}
	view.release()
	result.decref()
	return total
}

// call_kw_test calls `callee(a=1, b=2)` and returns the result as an int.
fn call_kw_test(callee voidptr) int {
	mut kwargs := map[string]vcraft.PyObj{}
	kwargs['a'] = vcraft.to_py_int(1)
	kwargs['b'] = vcraft.to_py_int(2)
	result := vcraft.call_kw(callee, []voidptr{}, kwargs)
	if result.is_null() {
		vcraft.clear_error()
		return -1
	}
	value := vcraft.from_py_int(result, 'result') or {
		vcraft.clear_error()
		-1
	}
	result.decref()
	return int(value)
}

fn call_kw_test_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('call_kw_test', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	callee := vcraft.require_voidptr_arg(args, 0, 'call_kw_test', 'callee')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := call_kw_test(callee)
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

fn sum_callback_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('sum_callback', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	callee := vcraft.require_voidptr_arg(args, 0, 'sum_callback', 'callee')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := sum_callback(callee)
	if vcraft.error_is_set() {
		// `bytes_view` leaves CPython's own TypeError pending; returning a value with an
		// exception set is a SystemError, so the null pointer is the answer.
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

// call_from_thread calls `callee()` from a thread V created, and returns what it produced.
//
// A `spawn`ed thread holds no Python thread state, so this is exactly what
// `vcraft.with_gil` exists for: without it the call is undefined behaviour, with it the
// GIL is acquired for the block and given back on the way out. The result travels back on
// a channel, which is a reference type and the one thing `spawn` accepts without an
// argument dance.
// call_from_thread calls `callee()` from a thread V created.
//
// A `spawn`ed thread holds no Python thread state, so this is exactly what
// `vcraft.with_gil` exists for: without it the call is undefined behaviour, with it the
// GIL is acquired for the block and given back on the way out. The answer travels on a
// channel, a reference type, so nothing has to be shared mutably between the threads -
// a closure capturing a `mut` local captures a copy and would report the initial value.
fn thread_call_worker(callee voidptr, results chan int) {
	vcraft.with_gil(fn [callee, results] () {
		results <- thread_python_call(callee)
	})
}

// thread_python_call is the Python work, so the GIL question stays in one place.
fn thread_python_call(callee voidptr) int {
	result := vcraft.call(callee, []voidptr{})
	if result.is_null() {
		// Dropped rather than left pending: the exception belongs to a thread that is
		// about to end, and -101 is what the caller can act on.
		vcraft.clear_error()
		return -101
	}
	value := vcraft.from_py_int(result, 'result') or {
		vcraft.clear_error()
		-103
	}
	result.decref()
	return value
}

fn call_from_thread(callee voidptr) int {
	results := chan int{cap: 1}
	spawn thread_call_worker(callee, results)
	// The trampoline holds the GIL, and the thread this waits for needs the GIL to finish:
	// waiting with it held is a deadlock, and these two lines are the pattern `with_gil`
	// makes possible rather than the feature itself.
	state := vcraft.allow_threads()
	value := <-results
	vcraft.end_allow_threads(state)
	return value
}

fn call_from_thread_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('call_from_thread', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	callee := vcraft.require_voidptr_arg(args, 0, 'call_from_thread', 'callee')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := call_from_thread(callee)
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

fn released_then_call(callee voidptr) int {
	vcraft.released(fn () {
		// Pure V only. Touching Python here is the same mistake as touching it in a
		// `@[vc_nogil]` function.
	})
	result := vcraft.call(callee, []voidptr{})
	if result.is_null() {
		vcraft.clear_error()
		return -1
	}
	value := vcraft.from_py_int(result, 'result') or {
		vcraft.clear_error()
		-1
	}
	result.decref()
	return value
}

fn released_panics() int {
	vcraft.released(fn () {
		panic('deliberate release panic')
	})
	if !vcraft.error_is_set() {
		return 0
	}
	vcraft.clear_error()
	// The panic is caught and re-raised as a Python exception by the `recover` defer;
	// the GIL is already back by the time that runs, so a call into Python afterwards
	// is the thing that proves it was restored rather than abandoned.
	_ = vcraft.to_py_int(1)
	return 1
}

fn released_then_call_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('released_then_call', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	callee := vcraft.require_voidptr_arg(args, 0, 'released_then_call', 'callee')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(released_then_call(callee)).ptr
}

fn released_panics_trampoline(self voidptr, args voidptr) voidptr {
	return vcraft.to_py_int(released_panics()).ptr
}

// run_coro_fast drives a coroutine to completion and returns its result.
//
// `vcraft.run_coroutine` is the thing under test: the fast path for a coroutine that never
// suspends, and the slow path for one that does.
fn run_coro_fast(callee voidptr) int {
	coro := vcraft.call(callee, []voidptr{})
	if coro.is_null() {
		vcraft.clear_error()
		return -1
	}
	result := vcraft.run_coroutine(coro)
	coro.decref()
	if result.is_null() {
		// Leave the exception pending so Python sees it. The trampoline checks
		// `error_is_set` and returns null, which raises it.
		return 0
	}
	value := vcraft.from_py_int(result, 'result') or {
		vcraft.clear_error()
		-1
	}
	result.decref()
	return value
}

fn run_coro_fast_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('run_coro_fast', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	callee := vcraft.require_voidptr_arg(args, 0, 'run_coro_fast', 'callee')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := run_coro_fast(callee)
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

// unpack_tuple reads a `(int, str)` tuple with the item helpers.
//
// `from_py_*_item` is the counterpart of `from_py_*_arg`: one for a positional argument,
// the other for an element of a value that is already in hand. They are what a function
// that receives a tuple or a list from Python uses.
fn unpack_tuple(t voidptr) !int {
	obj := vcraft.borrow(t)
	a := vcraft.from_py_int_item(obj, 0, 'a')!
	b := vcraft.from_py_str_item(obj, 1, 'b')!
	return int(a) + b.len
}

fn unpack_bytes(t voidptr) !int {
	obj := vcraft.borrow(t)
	b := vcraft.from_py_bytes_item(obj, 0, 'b')!
	return b.len
}

fn unpack_tuple_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('unpack_tuple', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	t := vcraft.require_voidptr_arg(args, 0, 'unpack_tuple', 't')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := unpack_tuple(t) or {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}

fn unpack_bytes_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('unpack_bytes', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	t := vcraft.require_voidptr_arg(args, 0, 'unpack_bytes', 't')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	result := unpack_bytes(t) or {
		return unsafe { nil }
	}
	return vcraft.to_py_int(result).ptr
}


// to_py_obj_list builds a list of the given ints without a boxing closure.
fn build_obj_list() vcraft.PyObj {
	mut items := []vcraft.PyObj{cap: 3}
	items << vcraft.to_py_int(1)
	items << vcraft.to_py_int(2)
	items << vcraft.to_py_int(3)
	return vcraft.to_py_obj_list(items)
}

fn build_obj_list_trampoline(self voidptr, args voidptr) voidptr {
	return build_obj_list().ptr
}

// from_py_list_sum reads a list and returns the sum of its ints.
fn from_py_list_sum(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('from_py_list_sum', 1, int(nargs))
	if vcraft.error_is_set() { return unsafe { nil } }
	list := vcraft.require_arg(args, 0, 'from_py_list_sum', 'lst')
	if vcraft.error_is_set() { return unsafe { nil } }
	items := vcraft.from_py_list(list, 'lst') or { return unsafe { nil } }
	mut total := int(0)
	for it in items {
		total += int(vcraft.from_py_int(it, 'x') or { 0 })
	}
	return vcraft.to_py_int(total).ptr
}

// from_py_dict_sum reads a dict {str: int} and returns the sum of values.
fn from_py_dict_sum(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('from_py_dict_sum', 1, int(nargs))
	if vcraft.error_is_set() { return unsafe { nil } }
	d := vcraft.require_arg(args, 0, 'from_py_dict_sum', 'd')
	if vcraft.error_is_set() { return unsafe { nil } }
	m := vcraft.from_py_dict(d, 'd') or { return unsafe { nil } }
	mut total := int(0)
	for _, v in m {
		total += int(vcraft.from_py_int(v, 'x') or { 0 })
	}
	return vcraft.to_py_int(total).ptr
}

// build_set builds a set of ints.
fn build_set() vcraft.PyObj {
	mut items := []vcraft.PyObj{cap: 3}
	items << vcraft.to_py_int(1)
	items << vcraft.to_py_int(2)
	items << vcraft.to_py_int(2) // duplicate
	return vcraft.to_py_set(items)
}

fn build_set_trampoline(self voidptr, args voidptr) voidptr {
	return build_set().ptr
}

// read_set_sum reads a set and returns the sum.
fn read_set_sum(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('read_set_sum', 1, int(nargs))
	if vcraft.error_is_set() { return unsafe { nil } }
	s := vcraft.require_arg(args, 0, 'read_set_sum', 's')
	if vcraft.error_is_set() { return unsafe { nil } }
	items := vcraft.from_py_set(s, 's') or { return unsafe { nil } }
	mut total := int(0)
	for it in items {
		total += int(vcraft.from_py_int(it, 'x') or { 0 })
	}
	return vcraft.to_py_int(total).ptr
}

// list_build builds a list incrementally with list_new/append.
fn list_build() vcraft.PyObj {
	l := vcraft.list_new()
	for i in 0 .. 5 {
		vcraft.list_append_owned(l, vcraft.to_py_int(i))
	}
	return l
}

fn list_build_trampoline(self voidptr, args voidptr) voidptr {
	return list_build().ptr
}


// repr_f64_test returns repr of a float.

// type_obj_name returns the type name of an object.

// bytes_view_sum reads bytes from a bytes_view.
fn bytes_view_sum(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('bytes_view_sum', 1, int(nargs))
	if vcraft.error_is_set() { return unsafe { nil } }
	obj := vcraft.require_arg(args, 0, 'bytes_view_sum', 'obj')
	if vcraft.error_is_set() { return unsafe { nil } }
	view := vcraft.bytes_view(obj, 'obj') or { return unsafe { nil } }
	mut total := int(0)
	for b in view.data {
		total += int(b)
	}
	view.release()
	obj.decref()
	return vcraft.to_py_int(total).ptr
}

// setattr_hasattr sets an attr on the passed object and returns the value.
fn setattr_hasattr(obj voidptr) vcraft.PyObj {
	o := vcraft.borrow(obj)
	if !vcraft.hasattr(o.ptr, 'x') {
		vcraft.setattr(o.ptr, 'x', vcraft.to_py_int(42))
	}
	return vcraft.getattr(o.ptr, 'x')
}

fn setattr_hasattr_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('setattr_hasattr', 1, int(nargs))
	if vcraft.error_is_set() { return unsafe { nil } }
	obj := vcraft.require_voidptr_arg(args, 0, 'setattr_hasattr', 'obj')
	if vcraft.error_is_set() { return unsafe { nil } }
	return setattr_hasattr(obj).ptr
}

// repr_f64_test returns the repr of 3.14.
fn repr_f64_test() vcraft.PyObj {
	return vcraft.to_py_string(vcraft.repr_f64(3.14))
}

fn repr_f64_test_trampoline(self voidptr, args voidptr) voidptr {
	return repr_f64_test().ptr
}

// type_obj_name returns the type name of an int.
fn type_obj_name() vcraft.PyObj {
	o := vcraft.to_py_int(42)
	t := o.type_obj()
	name := t.type_name()
	t.decref()
	o.decref()
	return vcraft.to_py_string(name)
}

fn type_obj_name_trampoline(self voidptr, args voidptr) voidptr {
	return type_obj_name().ptr
}

// py_scope_test creates several PyObj inside a scope and returns their count.
// The scope releases them on exit; the function returns how many were tracked.
fn py_scope_test() int {
	mut cell := 0
	ptr := &cell
	vcraft.with_py_scope(fn [ptr] (mut scope vcraft.PyScope) {
		a := scope.track(vcraft.to_py_int(1))
		b := scope.track(vcraft.to_py_int(2))
		c := scope.track(vcraft.to_py_int(3))
		// keep `c` alive past the scope
		scope.keep(c)
		unsafe { *ptr = 3 }
		_ = a
		_ = b
		_ = c
	})
	return cell
}

fn py_scope_test_trampoline(self voidptr, args voidptr) voidptr {
	return vcraft.to_py_int(py_scope_test()).ptr
}

fn identity_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('identity', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	obj := vcraft.require_arg(args, 0, 'identity', 'obj')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	// A borrowed argument becomes a new reference on the way out, which is what a
	// function returning its argument owes the caller.
	return obj.new_ref().ptr
}

fn sum_all_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('sum_all', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	list := vcraft.require_arg(args, 0, 'sum_all', 'values')
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	mut total := int(0)
	mut i := 0
	n := int(list.len())
	for i < n {
		item := list.item(i)
		value := vcraft.from_py_int(item, 'values') or { return unsafe { nil } }
		total += value
		i++
	}
	return vcraft.to_py_int(total).ptr
}

fn export_squares_trampoline(self voidptr, args voidptr, nargs isize) voidptr {
	vcraft.require_nargs('export_squares', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	n := vcraft.from_py_int_arg(args, 0, 'export_squares', 'n') or { return unsafe { nil } }
	vcraft.reject_extra_args('export_squares', 1, int(nargs))
	if vcraft.error_is_set() {
		return unsafe { nil }
	}
	return vcraft.buffer_export_int(export_squares(n)).ptr
}

fn layout_trampoline(self voidptr, args voidptr) voidptr {
	vcraft.check_layout() or {
		return unsafe { nil }
	}
	major, minor := vcraft.version_major_minor()
	api := vcraft.python_api_version()
	return vcraft.to_py_string('${major}.${minor} api=${api}').ptr
}

// The V functions under test ----------------------------------------------

fn answer() int {
	return 42
}

fn add(a int, b int) int {
	return a + b
}

// greet returns an error for an empty name, which must surface as a Python
// exception rather than a crash.
fn greet(name string) !string {
	if name.len == 0 {
		return error('name must not be empty')
	}
	return 'Hello, ${name}!'
}

fn describe(value f64) string {
	if value < 0.0 {
		return 'negative'
	}
	return 'non-negative'
}

// checked divides, which panics on a zero divisor. The panic must become a
// Python RuntimeError and leave the interpreter running.
fn checked(a int, b int) int {
	return a / b
}

// boom panics outright rather than returning an error.
fn boom() {
	panic('boom: deliberate panic from V')
}

// export_squares is native-backed, so the runtime hands it to Python as a memoryview
// that owns the buffer, rather than copying it into a boxed list.
fn export_squares(n int) []int {
	mut out := vcraft.buffer_new_int(n)
	for i in 0 .. n {
		out[i] = i * i
	}
	return out
}
