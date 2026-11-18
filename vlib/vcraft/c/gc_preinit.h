// The collector's start-up on macOS and Linux, done before V's own.
//
// Included into the C file V generates for the module, never compiled on its own: V's
// translation unit already has `gc.h`, which cannot be included twice, and only there
// does this constructor end up ahead of V's. Constructors in one translation unit run in
// the order they are defined, and V defines its `_vinit_caller` at the end of the file,
// after every include. The linker's `-init` would say the same thing more directly, but
// with a macOS 11 deployment target, which is what the wheel tag promises, the linker
// drops it without a word.
//
// On Linux the shape below is the macOS one translated to `dl_iterate_phdr`, measured
// with the collector's start-up at about half of an extension's import before the main
// stack bound was supplied (`vpy_gc_set_main_stackbottom`). If the own-object walk ever
// fails to locate the module, the constructor returns before touching anything and V
// starts the collector with its defaults, exactly as without this file.
#ifndef VCRAFT_GC_PREINIT_H
#define VCRAFT_GC_PREINIT_H

// glibc only declares `struct dl_phdr_info`, `dl_iterate_phdr` and `dladdr` with
// `_GNU_SOURCE`. `vcraft build` passes `-D_GNU_SOURCE` for Linux targets, which is
// what takes effect: by the time this header is included, the translation unit has
// already pulled in system headers and glibc has frozen its feature set. This
// fallback only helps something that includes this header first.
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#if (defined(__APPLE__) || defined(__linux__)) && defined(GC_THREADS)
#include <dlfcn.h>

// The heap growth divisor, overridable from `vcraft.toml` (`gc-free-space-divisor`)
// through `-DVCRAFT_GC_DIVISOR`. Boehm's default favours a small heap; V builds for
// throughput with 1, and vcraft ships 2: roughly half a MiB less resident for a few
// percent of allocation-heavy throughput (see benchmark/README.md).
#ifndef VCRAFT_GC_DIVISOR
#define VCRAFT_GC_DIVISOR 2
#endif

// The parallel marker's thread count, from `vcraft.toml` (`gc-markers`) through
// `-DVCRAFT_GC_MARKERS`. Left undefined, the collector picks one marker per core. It has
// to be set before `GC_INIT`, which is why it lives in the pre-initialiser.
static inline void vpy_gc_set_markers(void) {
#ifdef VCRAFT_GC_MARKERS
	GC_set_markers_count(VCRAFT_GC_MARKERS);
#endif
}

#endif

#if defined(__APPLE__) && defined(GC_THREADS)
#include <mach-o/getsect.h>

// vpy_gc_preinit starts V's collector so that it scans only this module.
//
// On macOS the collector registers the writable data of every image in the process as
// roots, through a dyld callback that runs once per image. A Python process has a few
// hundred images and none of them holds a pointer into V's heap: the registration took
// about 3 ms of every import, and every collection afterwards scanned all of that data.
//
// So the per-image registration is switched off before the collector starts, and this
// image's `__DATA` segment, where V keeps its globals, is registered by hand. V's runtime
// sees a collector that is already initialised and leaves it alone, so the settings it
// would have made are made here.
__attribute__((constructor)) static void vpy_gc_preinit(void) {
	if (GC_is_init_called()) {
		return;
	}
	GC_set_pages_executable(0);
	GC_set_all_interior_pointers(1);
	GC_set_free_space_divisor(VCRAFT_GC_DIVISOR);
	GC_set_no_dls(1);
	vpy_gc_set_markers();
	GC_INIT();
	Dl_info info;
	if (dladdr((void *)&vpy_gc_preinit, &info) == 0 || info.dli_fbase == NULL) {
		return;
	}
	const struct mach_header_64 *header = (const struct mach_header_64 *)info.dli_fbase;
	const char *segments[] = { "__DATA", "__DATA_DIRTY" };
	for (size_t i = 0; i < sizeof(segments) / sizeof(segments[0]); i++) {
		unsigned long size = 0;
		uint8_t *start = getsegmentdata(header, segments[i], &size);
		if (start != NULL && size > 0) {
			GC_add_roots(start, start + size);
		}
	}
}
#endif

#if defined(__linux__) && defined(GC_THREADS)
#include <link.h>

// vpy_gc_linux_layout is what the `dl_iterate_phdr` walk fills in: the writable
// segments of the object this constructor lives in.
typedef struct {
	const char *self;
	void *starts[16];
	void *ends[16];
	unsigned count;
} vpy_gc_linux_layout;

// vpy_gc_linux_visit finds our own object and records its writable segments.
//
// The constructor's own address falls inside one of the object's loaded segments,
// which identifies the object however it was mapped. What is registered is every
// writable `PT_LOAD`: V keeps its globals there, whatever the linker named them.
// Returning 1 stops the walk once the object is found.
static int vpy_gc_linux_visit(struct dl_phdr_info *info, size_t _size, void *data) {
	(void)_size;
	vpy_gc_linux_layout *out = (vpy_gc_linux_layout *)data;
	int holds_self = 0;
	for (int i = 0; i < info->dlpi_phnum; i++) {
		if (info->dlpi_phdr[i].p_type != PT_LOAD) {
			continue;
		}
		const char *start = (const char *)(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
		if (out->self >= start &&
			out->self < start + info->dlpi_phdr[i].p_memsz) {
			holds_self = 1;
			break;
		}
	}
	if (!holds_self) {
		return 0;
	}
	for (int i = 0; i < info->dlpi_phnum && out->count < 16; i++) {
		if (info->dlpi_phdr[i].p_type != PT_LOAD ||
			(info->dlpi_phdr[i].p_flags & PF_W) == 0) {
			continue;
		}
		void *start = (void *)(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
		void *end = (void *)((char *)start + info->dlpi_phdr[i].p_memsz);
		if (end == start) {
			continue;
		}
		out->starts[out->count] = start;
		out->ends[out->count] = end;
		out->count++;
	}
	return 1;
}

// vpy_gc_set_main_stackbottom hands the collector the main thread's stack base, so its
// start-up does not have to look it up.
//
// Left to itself, `GC_init` asks `pthread_getattr_np` for the initialising thread's
// stack, and for the main thread glibc answers that by reading `/proc/self/maps` line by
// line. A Python process has hundreds of mappings, and the read was half of the
// collector's start-up and a third of the whole import. `__libc_stack_end` is the same
// bound, published by the dynamic loader, and is what the collector itself uses when it
// is built without `pthread_getattr_np`; setting `GC_stackbottom` before `GC_init` is
// the documented way to supply it.
//
// Only for the main thread: an extension imported from another thread has its own stack,
// for which `pthread_getattr_np` is cheap and is left to run. On a libc without
// `__libc_stack_end` (musl) the weak reference is null and nothing changes.
#include <sys/syscall.h>
#include <unistd.h>
extern void *__libc_stack_end __attribute__((weak));

static void vpy_gc_set_main_stackbottom(void) {
	if (&__libc_stack_end == NULL || __libc_stack_end == NULL) {
		return;
	}
	if ((pid_t)syscall(SYS_gettid) != getpid()) {
		return;
	}
	GC_stackbottom = (char *)__libc_stack_end;
}

// vpy_gc_preinit_linux starts V's collector so that it scans only this module.
//
// The Linux shape of the macOS problem: left alone, the collector registers every
// loaded object and scans all of their data on each collection. What runs here is
// the same trade with ELF means -- no per-library registration, the module's own
// writable segments registered by hand. The main executable's own data stays
// registered, as it always is; a Python process keeps no V pointer there.
__attribute__((constructor)) static void vpy_gc_preinit_linux(void) {
	if (GC_is_init_called()) {
		return;
	}
	vpy_gc_linux_layout layout;
	layout.self = (const char *)&vpy_gc_preinit_linux;
	layout.count = 0;
	if (dl_iterate_phdr(vpy_gc_linux_visit, &layout) == 0 || layout.count == 0) {
		return;
	}
	GC_set_pages_executable(0);
	GC_set_all_interior_pointers(1);
	GC_set_free_space_divisor(VCRAFT_GC_DIVISOR);
	GC_set_no_dls(1);
	vpy_gc_set_markers();
	vpy_gc_set_main_stackbottom();
	GC_INIT();
	for (unsigned i = 0; i < layout.count; i++) {
		GC_add_roots(layout.starts[i], layout.ends[i]);
	}
}
#endif

// vpy_gc_enter registers the calling thread with V's collector, once per thread.
//
// Every trampoline in the generated glue calls it before running any V code. The
// collector only knows the thread that imported the module: any other thread that
// allocated and triggered a collection aborted the process with "Collecting from
// unknown thread", and with the GIL released or on a free-threaded interpreter the
// collector would neither stop such a thread nor scan its stack, and could free
// memory it was still using. A worker thread, a ThreadPoolExecutor or a threaded web
// server is enough to get there.
//
// After the first call a thread pays one thread-local load. Registration is undone
// when the thread exits, on the exiting thread itself as GC_unregister_my_thread
// requires: a thread left registered after it is gone would be signalled by the next
// collection. POSIX uses a pthread key destructor; Windows has no per-thread TLS
// destructor, so it uses a fiber-local slot's.
#if defined(GC_THREADS) && (defined(__APPLE__) || defined(__linux__))
#include <pthread.h>

static __thread int vpy_gc_thread_known = 0;
static pthread_key_t vpy_gc_thread_key;
static pthread_once_t vpy_gc_thread_key_once = PTHREAD_ONCE_INIT;

static void vpy_gc_thread_exit(void *unused) {
	(void)unused;
	GC_unregister_my_thread();
}

static void vpy_gc_thread_key_init(void) {
	pthread_key_create(&vpy_gc_thread_key, vpy_gc_thread_exit);
}

static inline void vpy_gc_enter(void) {
	if (vpy_gc_thread_known) {
		return;
	}
	vpy_gc_thread_known = 1;
	// The importing thread, and any thread V started itself, is already known.
	if (GC_thread_is_registered()) {
		return;
	}
	struct GC_stack_base base;
	if (GC_get_stack_base(&base) != GC_SUCCESS) {
		return;
	}
	pthread_once(&vpy_gc_thread_key_once, vpy_gc_thread_key_init);
	if (GC_register_my_thread(&base) == GC_SUCCESS) {
		pthread_setspecific(vpy_gc_thread_key, (void *)1);
	}
}
#elif defined(GC_THREADS) && defined(_WIN32)
#include <windows.h>

// The Windows shape of the same registration. The destructor is bound to a fiber-local
// slot rather than a pthread key, because Windows TLS has no destructor of its own; the
// slot is created once, through the run-once initialiser Windows has in place of
// `pthread_once`.
static __thread int vpy_gc_thread_known = 0;
static DWORD vpy_gc_thread_fls = FLS_OUT_OF_INDEXES;
static INIT_ONCE vpy_gc_thread_fls_once = INIT_ONCE_STATIC_INIT;

static void NTAPI vpy_gc_thread_exit(PVOID unused) {
	(void)unused;
	GC_unregister_my_thread();
}

static BOOL CALLBACK vpy_gc_thread_fls_init(PINIT_ONCE once, PVOID param, PVOID *ctx) {
	(void)once;
	(void)param;
	(void)ctx;
	vpy_gc_thread_fls = FlsAlloc(vpy_gc_thread_exit);
	return TRUE;
}

static inline void vpy_gc_enter(void) {
	if (vpy_gc_thread_known) {
		return;
	}
	vpy_gc_thread_known = 1;
	// The importing thread, and any thread V started itself, is already known.
	if (GC_thread_is_registered()) {
		return;
	}
	struct GC_stack_base base;
	if (GC_get_stack_base(&base) != GC_SUCCESS) {
		return;
	}
	InitOnceExecuteOnce(&vpy_gc_thread_fls_once, vpy_gc_thread_fls_init, NULL, NULL);
	if (GC_register_my_thread(&base) == GC_SUCCESS && vpy_gc_thread_fls != FLS_OUT_OF_INDEXES) {
		FlsSetValue(vpy_gc_thread_fls, (void *)1);
	}
}
#else
// Without a threaded collector (`gc = none`, or another platform) there is nothing
// to register.
static inline void vpy_gc_enter(void) {}
#endif

// V's collector follows Python's: a full Python collection runs a full V one.
//
// A V allocation is reclaimed only when the collector next runs, and the collector runs
// on allocation pressure alone, so the temporaries of the last calls -- a converted
// argument, a result already handed to Python as a list, a scratch buffer -- stay
// resident until the extension allocates enough again. Python code that wants memory
// back calls `gc.collect()`, and Python itself runs a full collection now and then; this
// hooks both. On the generation-2 `stop` callback the collector runs a full collection
// and returns the pages it freed to the system (`GC_gcollect_and_unmap`), so a process
// that collects sees the V heap shrink the way the Python one does.
//
// Generation 0 and 1 collections, which are frequent, cost the callback one string
// compare and nothing else. The hook is registered once per process by `init_state`;
// each extension links its own collector and so registers its own hook.
#ifdef GC_H
static PyObject *vpy_gc_on_python_gc(PyObject *self, PyObject *const *args, Py_ssize_t nargs) {
	(void)self;
	// `phase` is "start" or "stop"; only a finished generation-2 pass matters. The length
	// test first keeps the frequent young-generation calls to a couple of loads.
	if (nargs == 2 && PyUnicode_Check(args[0]) && PyUnicode_GetLength(args[0]) == 4
		&& PyUnicode_CompareWithASCIIString(args[0], "stop") == 0 && PyDict_Check(args[1])) {
		PyObject *generation = PyDict_GetItemString(args[1], "generation");
		if (generation != NULL && PyLong_Check(generation) && PyLong_AsLong(generation) == 2) {
			vpy_gc_enter();
			GC_gcollect_and_unmap();
		}
	}
	Py_INCREF(Py_None);
	return Py_None;
}

static PyMethodDef vpy_gc_hook_def = {"_vcraft_collect", (PyCFunction)(void (*)(void))vpy_gc_on_python_gc,
	METH_FASTCALL, NULL};
static int vpy_gc_hooked = 0;

// vpy_gc_hook_python appends the hook to `gc.callbacks`. A failure leaves the extension
// working exactly as without it, so it is cleared rather than reported.
static void vpy_gc_hook_python(void) {
	if (vpy_gc_hooked) {
		return;
	}
	vpy_gc_hooked = 1;
	PyObject *gc = PyImport_ImportModule("gc");
	if (gc == NULL) {
		PyErr_Clear();
		return;
	}
	PyObject *callbacks = PyObject_GetAttrString(gc, "callbacks");
	Py_DECREF(gc);
	if (callbacks == NULL) {
		PyErr_Clear();
		return;
	}
	PyObject *hook = PyCFunction_NewEx(&vpy_gc_hook_def, NULL, NULL);
	if (hook == NULL || PyList_Append(callbacks, hook) < 0) {
		PyErr_Clear();
	}
	Py_XDECREF(hook);
	Py_DECREF(callbacks);
}

// vpy_gc_pin makes `ptr` a collector root until `vpy_gc_unpin`: a one-word cell from the
// uncollectable heap, which the collector scans and never frees, holding the pointer.
static void *vpy_gc_pin(void *ptr) {
	void **cell = (void **)GC_MALLOC_UNCOLLECTABLE(sizeof(void *));
	if (cell != NULL) {
		*cell = ptr;
	}
	return cell;
}

static void vpy_gc_unpin(void *root) {
	if (root != NULL) {
		*(void **)root = NULL;
		GC_FREE(root);
	}
}
// vpy_gc_box allocates the state block of a class whose fields hold V-managed memory: a
// zeroed block the collector scans for pointers but never frees on its own, so a string
// stored in a field stays alive exactly as long as the instance. `vpy_gc_unbox` frees it.
static void *vpy_gc_box(size_t size) {
	return GC_MALLOC_UNCOLLECTABLE(size > 0 ? size : 1);
}

static void vpy_gc_unbox(void *block) {
	if (block != NULL) {
		GC_FREE(block);
	}
}
#else
static void *vpy_gc_box(size_t size) {
	return calloc(1, size > 0 ? size : 1);
}

static void vpy_gc_unbox(void *block) {
	free(block);
}

static void vpy_gc_hook_python(void) {}
static void *vpy_gc_pin(void *ptr) {
	(void)ptr;
	return NULL;
}
static void vpy_gc_unpin(void *root) {
	(void)root;
}
#endif

#endif // VCRAFT_GC_PREINIT_H
