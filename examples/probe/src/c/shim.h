// Accessors for CPython data symbols.
//
// The V C backend does not emit prototypes for `fn C.` declarations, so a
// companion header is required for the generated C to see them. This is the
// same reason the module includes <Python.h> instead of relying on V.

#ifndef VCRAFT_PROBE_SHIM_H
#define VCRAFT_PROBE_SHIM_H

void *vpyprobe_type_error(void);
void *vpyprobe_value_error(void);
void *vpyprobe_runtime_error(void);

#endif // VCRAFT_PROBE_SHIM_H
