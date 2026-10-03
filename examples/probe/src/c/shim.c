// CPython exposes its builtin exception types and other singletons as data
// symbols, and V has no way to name a C global. A tiny accessor per symbol is
// the supported way to reach them from V.
//
// This file is compiled by V because probe.c.v references it with
// `#flag @VMODROOT/c/shim.c`.

#include <Python.h>

#include "shim.h"

void *vpyprobe_type_error(void) {
	return (void *)PyExc_TypeError;
}

void *vpyprobe_value_error(void) {
	return (void *)PyExc_ValueError;
}

void *vpyprobe_runtime_error(void) {
	return (void *)PyExc_RuntimeError;
}
