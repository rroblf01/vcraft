// The Arrow C Data Interface, both ways, over the Arrow PyCapsule Interface: the
// protocol pyarrow, polars, pandas and DuckDB share for handing columns across without
// copying. https://arrow.apache.org/docs/format/CDataInterface.html
//
// In: `vpy_arrow_view` reads any object with `__arrow_c_array__` (pyarrow arrays) or
// `__arrow_c_stream__` (polars Series, chunked arrays) into a flat view of one column. An
// array is viewed in place, its buffers kept alive by its capsules for the call; a stream
// is copied once into one contiguous column, because its chunks are released with it.
//
// Out: `vpy_arrow_column` builds a small Python object that owns a column's buffers and
// implements `__arrow_c_array__` and `__arrow_c_schema__`, so `pyarrow.array(col)` or
// `polars.Series(col)` take it without a copy.
//
// Fixed-width numbers (int8..int64, uint8..uint64, float32, float64) and UTF-8 strings
// (`u`, 32-bit offsets) are handled; anything else is refused with its format string.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ArrowSchema {
	const char *format;
	const char *name;
	const char *metadata;
	int64_t flags;
	int64_t n_children;
	struct ArrowSchema **children;
	struct ArrowSchema *dictionary;
	void (*release)(struct ArrowSchema *);
	void *private_data;
};

struct ArrowArray {
	int64_t length;
	int64_t null_count;
	int64_t offset;
	int64_t n_buffers;
	int64_t n_children;
	const void **buffers;
	struct ArrowArray **children;
	struct ArrowArray *dictionary;
	void (*release)(struct ArrowArray *);
	void *private_data;
};

struct ArrowArrayStream {
	int (*get_schema)(struct ArrowArrayStream *, struct ArrowSchema *out);
	int (*get_next)(struct ArrowArrayStream *, struct ArrowArray *out);
	const char *(*get_last_error)(struct ArrowArrayStream *);
	void (*release)(struct ArrowArrayStream *);
	void *private_data;
};

// VArrowView is what V sees of a column: its format, length, nulls, and the buffers
// (validity, then values; for strings validity, offsets, bytes). The array's `offset` is
// reported, not applied: V indexes with it.
typedef struct {
	char format[8];
	int64_t length;
	int64_t null_count;
	int64_t offset;
	const uint8_t *validity;
	const void *values;
	const void *data;
	void *keep;  // PyObject* that keeps the buffers alive, or an owned copy (see owned)
	void *owned; // malloc'd block holding a concatenated copy, freed by vpy_arrow_view_free
} VArrowView;

static int vpy_arrow_width(const char *f) {
	if (f == NULL || f[0] == 0 || f[1] != 0) {
		return 0;
	}
	switch (f[0]) {
	case 'c': case 'C': return 1;
	case 's': case 'S': return 2;
	case 'i': case 'I': case 'f': return 4;
	case 'l': case 'L': case 'g': return 8;
	default: return 0;
	}
}

// Strings come in three layouts: `u` (32-bit offsets), `U` (64-bit offsets, pandas and
// polars' large strings) and `vu` (string views, polars' default). V sees `u` only: the
// other two are converted once, element by element.
static int vpy_arrow_is_string(const char *f) {
	return f != NULL && (strcmp(f, "u") == 0 || strcmp(f, "U") == 0 || strcmp(f, "vu") == 0);
}

static int vpy_arrow_supported(const char *f) {
	return vpy_arrow_width(f) > 0 || vpy_arrow_is_string(f);
}

// vpy_arrow_str_at is element `i` of a string array in any of the three layouts.
static void vpy_arrow_str_at(const char *f, const struct ArrowArray *a, int64_t i, const char **p,
	int64_t *n) {
	int64_t k = a->offset + i;
	if (strcmp(f, "u") == 0) {
		const int32_t *o = (const int32_t *)a->buffers[1];
		*p = (const char *)a->buffers[2] + o[k];
		*n = o[k + 1] - o[k];
	} else if (strcmp(f, "U") == 0) {
		const int64_t *o = (const int64_t *)a->buffers[1];
		*p = (const char *)a->buffers[2] + o[k];
		*n = o[k + 1] - o[k];
	} else {
		// A 16-byte view: the length, then either up to 12 bytes inline, or a 4-byte
		// prefix, the index of the data buffer and the offset in it.
		const uint8_t *v = (const uint8_t *)a->buffers[1] + 16 * k;
		int32_t len = 0;
		memcpy(&len, v, 4);
		if (len <= 12) {
			*p = (const char *)v + 4;
		} else {
			int32_t buffer = 0, offset = 0;
			memcpy(&buffer, v + 8, 4);
			memcpy(&offset, v + 12, 4);
			*p = (const char *)a->buffers[2 + buffer] + offset;
		}
		*n = len;
	}
}

// Fills `out` from one array, whose buffers stay valid while `keep` is alive.
static void vpy_arrow_fill(VArrowView *out, const struct ArrowSchema *s, const struct ArrowArray *a) {
	snprintf(out->format, sizeof(out->format), "%s", s->format);
	out->length = a->length;
	out->null_count = a->null_count;
	out->offset = a->offset;
	out->validity = a->n_buffers > 0 ? (const uint8_t *)a->buffers[0] : NULL;
	out->values = a->n_buffers > 1 ? a->buffers[1] : NULL;
	out->data = a->n_buffers > 2 ? a->buffers[2] : NULL;
}

static int vpy_arrow_refuse(const char *format) {
	PyErr_Format(PyExc_TypeError,
		"Arrow column of format '%s' is not supported (numbers and utf8 strings are)", format);
	return -1;
}

// A stream's chunks, released together with the stream.
typedef struct {
	struct ArrowArrayStream *stream;
	struct ArrowSchema schema;
	struct ArrowArray *chunks;
	int64_t n;
} VArrowChunks;

static void vpy_arrow_chunks_free(VArrowChunks *c) {
	for (int64_t i = 0; i < c->n; i++) {
		if (c->chunks[i].release) {
			c->chunks[i].release(&c->chunks[i]);
		}
	}
	free(c->chunks);
	if (c->schema.release) {
		c->schema.release(&c->schema);
	}
}

static int vpy_bit(const uint8_t *bits, int64_t i) {
	return bits == NULL || ((bits[i >> 3] >> (i & 7)) & 1);
}

// Concatenates arrays (a stream's chunks, or one array in a string layout V does not
// read directly) into one owned column; strings come out as `u`.
static int vpy_arrow_concat(VArrowView *out, const char *f, const struct ArrowArray *chunks, int64_t count) {
	int width = vpy_arrow_width(f);
	int64_t total = 0, nulls = 0, bytes = 0;
	for (int64_t i = 0; i < count; i++) {
		total += chunks[i].length;
		nulls += chunks[i].null_count;
		if (width == 0) {
			for (int64_t k = 0; k < chunks[i].length; k++) {
				const char *p;
				int64_t n;
				vpy_arrow_str_at(f, &chunks[i], k, &p, &n);
				bytes += n;
			}
		}
	}
	if (width == 0 && bytes > INT32_MAX) {
		PyErr_SetString(PyExc_OverflowError, "Arrow string column holds over 2 GiB of text");
		return -1;
	}
	size_t vbytes = (size_t)((total + 7) / 8);
	size_t values_bytes = width > 0 ? (size_t)total * width : (size_t)(total + 1) * 4;
	uint8_t *block = (uint8_t *)calloc(1, vbytes + values_bytes + (size_t)bytes + 8);
	if (block == NULL) {
		PyErr_NoMemory();
		return -1;
	}
	uint8_t *validity = block;
	uint8_t *values = block + vbytes;
	uint8_t *data = values + values_bytes;
	int64_t at = 0, byte_at = 0;
	for (int64_t i = 0; i < count; i++) {
		const struct ArrowArray *a = &chunks[i];
		const uint8_t *bits = a->n_buffers > 0 ? (const uint8_t *)a->buffers[0] : NULL;
		for (int64_t k = 0; k < a->length; k++) {
			if (vpy_bit(bits, a->offset + k)) {
				validity[(at + k) >> 3] |= (uint8_t)(1 << ((at + k) & 7));
			}
		}
		if (width > 0) {
			memcpy(values + at * width, (const uint8_t *)a->buffers[1] + a->offset * width,
				(size_t)a->length * width);
		} else {
			int32_t *dst = (int32_t *)values;
			for (int64_t k = 0; k < a->length; k++) {
				const char *p;
				int64_t n;
				vpy_arrow_str_at(f, a, k, &p, &n);
				dst[at + k] = (int32_t)byte_at;
				if (n > 0) {
					memcpy(data + byte_at, p, (size_t)n);
				}
				byte_at += n;
			}
		}
		at += a->length;
	}
	if (width == 0) {
		((int32_t *)values)[total] = (int32_t)byte_at;
	}
	snprintf(out->format, sizeof(out->format), "%s", width > 0 ? f : "u");
	out->length = total;
	out->null_count = nulls;
	out->offset = 0;
	out->validity = nulls > 0 ? validity : NULL;
	out->values = values;
	out->data = width > 0 ? NULL : data;
	out->owned = block;
	return 0;
}

static int vpy_arrow_from_stream(PyObject *obj, VArrowView *out) {
	PyObject *capsule = PyObject_CallMethod(obj, "__arrow_c_stream__", NULL);
	if (capsule == NULL) {
		return -1;
	}
	struct ArrowArrayStream *stream =
		(struct ArrowArrayStream *)PyCapsule_GetPointer(capsule, "arrow_array_stream");
	if (stream == NULL) {
		Py_DECREF(capsule);
		return -1;
	}
	VArrowChunks c;
	memset(&c, 0, sizeof(c));
	if (stream->get_schema(stream, &c.schema) != 0) {
		Py_DECREF(capsule);
		PyErr_SetString(PyExc_ValueError, "the Arrow stream has no schema");
		return -1;
	}
	if (!vpy_arrow_supported(c.schema.format)) {
		int rc = vpy_arrow_refuse(c.schema.format);
		vpy_arrow_chunks_free(&c);
		Py_DECREF(capsule);
		return rc;
	}
	int64_t cap = 4;
	c.chunks = (struct ArrowArray *)calloc((size_t)cap, sizeof(struct ArrowArray));
	for (;;) {
		struct ArrowArray next;
		memset(&next, 0, sizeof(next));
		if (stream->get_next(stream, &next) != 0) {
			vpy_arrow_chunks_free(&c);
			Py_DECREF(capsule);
			PyErr_SetString(PyExc_ValueError, "reading the Arrow stream failed");
			return -1;
		}
		if (next.release == NULL) {
			break;
		}
		if (c.n == cap) {
			cap *= 2;
			c.chunks = (struct ArrowArray *)realloc(c.chunks, (size_t)cap * sizeof(struct ArrowArray));
		}
		c.chunks[c.n++] = next;
	}
	int rc = 0;
	if (c.n == 0) {
		snprintf(out->format, sizeof(out->format), "%s", c.schema.format);
		out->length = 0;
		vpy_arrow_chunks_free(&c);
	} else {
		// One chunk or many, the column is copied out of the stream: the stream's chunks
		// belong to it and are released with it, so a view could not outlive this call.
		// A single chunk could be kept alive instead; the copy keeps one code path and is
		// one memcpy per buffer.
		rc = vpy_arrow_concat(out, c.schema.format, c.chunks, c.n);
		vpy_arrow_chunks_free(&c);
	}
	Py_DECREF(capsule);
	return rc;
}

// vpy_arrow_view reads an Arrow column from any object implementing the PyCapsule
// interface. 0 on success; -1 with an exception set. Free with `vpy_arrow_view_free`.
int vpy_arrow_view(PyObject *obj, VArrowView *out) {
	memset(out, 0, sizeof(*out));
	if (PyObject_HasAttrString(obj, "__arrow_c_array__")) {
		PyObject *pair = PyObject_CallMethod(obj, "__arrow_c_array__", NULL);
		if (pair == NULL) {
			return -1;
		}
		if (!PyTuple_Check(pair) || PyTuple_Size(pair) != 2) {
			Py_DECREF(pair);
			PyErr_SetString(PyExc_TypeError, "__arrow_c_array__ did not return a (schema, array) pair");
			return -1;
		}
		const struct ArrowSchema *s =
			(const struct ArrowSchema *)PyCapsule_GetPointer(PyTuple_GetItem(pair, 0), "arrow_schema");
		const struct ArrowArray *a =
			(const struct ArrowArray *)PyCapsule_GetPointer(PyTuple_GetItem(pair, 1), "arrow_array");
		if (s == NULL || a == NULL) {
			Py_DECREF(pair);
			return -1;
		}
		if (!vpy_arrow_supported(s->format)) {
			int rc = vpy_arrow_refuse(s->format);
			Py_DECREF(pair);
			return rc;
		}
		if (strcmp(s->format, "U") == 0 || strcmp(s->format, "vu") == 0) {
			int rc = vpy_arrow_concat(out, s->format, a, 1);
			Py_DECREF(pair);
			return rc;
		}
		// The capsules release the array when the pair is freed: kept until the view is.
		vpy_arrow_fill(out, s, a);
		out->keep = pair;
		return 0;
	}
	if (PyObject_HasAttrString(obj, "__arrow_c_stream__")) {
		return vpy_arrow_from_stream(obj, out);
	}
	PyErr_Format(PyExc_TypeError,
		"expected an Arrow array (an object with __arrow_c_array__ or __arrow_c_stream__), got %R",
		(PyObject *)Py_TYPE(obj));
	return -1;
}

void vpy_arrow_view_free(VArrowView *v) {
	Py_XDECREF((PyObject *)v->keep);
	free(v->owned);
	v->keep = NULL;
	v->owned = NULL;
}

// ---------------------------------------------------------------- out

// VArrowColumn is the exported object: one column whose buffers it owns.
typedef struct {
	PyObject_HEAD
	char format[4];
	int64_t length;
	int n_buffers;
	void *buffers[3];
} VArrowColumn;

static PyObject *vpy_arrow_column_type = NULL;

static void vpy_arrow_column_dealloc(PyObject *self) {
	VArrowColumn *c = (VArrowColumn *)self;
	for (int i = 0; i < 3; i++) {
		free(c->buffers[i]);
	}
	PyTypeObject *tp = Py_TYPE(self);
	freefunc tp_free = (freefunc)PyType_GetSlot(tp, Py_tp_free);
	tp_free(self);
	Py_DECREF(tp);
}

// The exported structs point into the column and keep it alive through private_data;
// their release callbacks may run on any thread, so they take the GIL to drop it.
static void vpy_release_owner(void *owner) {
	PyGILState_STATE g = PyGILState_Ensure();
	Py_XDECREF((PyObject *)owner);
	PyGILState_Release(g);
}

static void vpy_arrow_schema_release(struct ArrowSchema *s) {
	s->release = NULL;
}

static void vpy_arrow_array_release(struct ArrowArray *a) {
	free((void *)a->buffers);
	vpy_release_owner(a->private_data);
	a->release = NULL;
}

static void vpy_capsule_schema_free(PyObject *capsule) {
	struct ArrowSchema *s = (struct ArrowSchema *)PyCapsule_GetPointer(capsule, "arrow_schema");
	if (s != NULL) {
		if (s->release) {
			s->release(s);
		}
		free(s);
	}
}

static void vpy_capsule_array_free(PyObject *capsule) {
	struct ArrowArray *a = (struct ArrowArray *)PyCapsule_GetPointer(capsule, "arrow_array");
	if (a != NULL) {
		if (a->release) {
			a->release(a);
		}
		free(a);
	}
}

static PyObject *vpy_arrow_make_schema(VArrowColumn *c) {
	struct ArrowSchema *s = (struct ArrowSchema *)calloc(1, sizeof(struct ArrowSchema));
	if (s == NULL) {
		return PyErr_NoMemory();
	}
	s->format = c->format;
	s->name = "";
	s->flags = 2; // ARROW_FLAG_NULLABLE
	s->release = vpy_arrow_schema_release;
	return PyCapsule_New(s, "arrow_schema", vpy_capsule_schema_free);
}

static PyObject *vpy_arrow_column_schema(PyObject *self, PyObject *const *args, Py_ssize_t nargs) {
	(void)args;
	(void)nargs;
	return vpy_arrow_make_schema((VArrowColumn *)self);
}

static PyObject *vpy_arrow_column_array(PyObject *self, PyObject *const *args, Py_ssize_t nargs) {
	(void)args;
	(void)nargs;
	VArrowColumn *c = (VArrowColumn *)self;
	PyObject *schema = vpy_arrow_make_schema(c);
	if (schema == NULL) {
		return NULL;
	}
	struct ArrowArray *a = (struct ArrowArray *)calloc(1, sizeof(struct ArrowArray));
	const void **buffers = (const void **)calloc(3, sizeof(void *));
	if (a == NULL || buffers == NULL) {
		free(a);
		free(buffers);
		Py_DECREF(schema);
		return PyErr_NoMemory();
	}
	for (int i = 0; i < c->n_buffers; i++) {
		buffers[i] = c->buffers[i];
	}
	a->length = c->length;
	a->n_buffers = c->n_buffers;
	a->buffers = buffers;
	a->release = vpy_arrow_array_release;
	Py_INCREF(self);
	a->private_data = self;
	PyObject *array = PyCapsule_New(a, "arrow_array", vpy_capsule_array_free);
	if (array == NULL) {
		vpy_arrow_array_release(a);
		free(a);
		Py_DECREF(schema);
		return NULL;
	}
	PyObject *pair = PyTuple_Pack(2, schema, array);
	Py_DECREF(schema);
	Py_DECREF(array);
	return pair;
}

static Py_ssize_t vpy_arrow_column_len(PyObject *self) {
	return (Py_ssize_t)((VArrowColumn *)self)->length;
}

static PyMethodDef vpy_arrow_column_methods[] = {
	{"__arrow_c_array__", (PyCFunction)(void (*)(void))vpy_arrow_column_array, METH_FASTCALL,
		"__arrow_c_array__(requested_schema=None)\n--\n\nThe column as Arrow C Data Interface capsules."},
	{"__arrow_c_schema__", (PyCFunction)(void (*)(void))vpy_arrow_column_schema, METH_FASTCALL,
		"__arrow_c_schema__()\n--\n\nThe column's type as an Arrow schema capsule."},
	{NULL, NULL, 0, NULL},
};

static PyType_Slot vpy_arrow_column_slots[] = {
	{Py_tp_dealloc, (void *)vpy_arrow_column_dealloc},
	{Py_tp_methods, (void *)vpy_arrow_column_methods},
	{Py_sq_length, (void *)vpy_arrow_column_len},
	{Py_tp_doc, (void *)"An Arrow column made by a vcraft extension: pass it to pyarrow.array(), "
		"polars.Series() or anything that reads the Arrow PyCapsule interface."},
	{0, NULL},
};

static PyType_Spec vpy_arrow_column_spec = {
	"vcraft.ArrowColumn", sizeof(VArrowColumn), 0, Py_TPFLAGS_DEFAULT, vpy_arrow_column_slots,
};

// vpy_arrow_column makes a column that owns `buffers` (malloc'd, NULL for absent ones).
PyObject *vpy_arrow_column(const char *format, int64_t length, int n_buffers, void *b0, void *b1, void *b2) {
	if (vpy_arrow_column_type == NULL) {
		vpy_arrow_column_type = PyType_FromSpec(&vpy_arrow_column_spec);
		if (vpy_arrow_column_type == NULL) {
			free(b0); free(b1); free(b2);
			return NULL;
		}
	}
	allocfunc alloc = (allocfunc)PyType_GetSlot((PyTypeObject *)vpy_arrow_column_type, Py_tp_alloc);
	VArrowColumn *c = (VArrowColumn *)alloc((PyTypeObject *)vpy_arrow_column_type, 0);
	if (c == NULL) {
		free(b0); free(b1); free(b2);
		return NULL;
	}
	snprintf(c->format, sizeof(c->format), "%s", format);
	c->length = length;
	c->n_buffers = n_buffers;
	c->buffers[0] = b0;
	c->buffers[1] = b1;
	c->buffers[2] = b2;
	return (PyObject *)c;
}

void *vpy_arrow_malloc(size_t n) {
	return malloc(n > 0 ? n : 1);
}

// Accessors, so V holds an opaque pointer rather than mirroring the struct's layout.
VArrowView *vpy_arrow_view_new(void) {
	return (VArrowView *)calloc(1, sizeof(VArrowView));
}
void vpy_arrow_view_delete(VArrowView *v) {
	if (v != NULL) {
		vpy_arrow_view_free(v);
		free(v);
	}
}
const char *vpy_arrow_format(VArrowView *v) { return v->format; }
int64_t vpy_arrow_length(VArrowView *v) { return v->length; }
int64_t vpy_arrow_null_count(VArrowView *v) { return v->null_count; }
int64_t vpy_arrow_offset(VArrowView *v) { return v->offset; }
const void *vpy_arrow_validity(VArrowView *v) { return v->validity; }
const void *vpy_arrow_values(VArrowView *v) { return v->values; }
const void *vpy_arrow_data(VArrowView *v) { return v->data; }
