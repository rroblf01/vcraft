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
