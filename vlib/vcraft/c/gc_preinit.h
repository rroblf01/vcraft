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
// Not yet measured on Linux: the shape below is the macOS one translated to
// `dl_iterate_phdr`, and CI is where it gets exercised. If the own-object walk ever
// fails to locate the module, the constructor returns before touching anything and V
// starts the collector with its defaults, exactly as without this file.
#ifndef VCRAFT_GC_PREINIT_H
#define VCRAFT_GC_PREINIT_H

#if (defined(__APPLE__) || defined(__linux__)) && defined(GC_THREADS)
#include <dlfcn.h>

// The heap growth divisor, overridable from `vcraft.toml` (`gc-free-space-divisor`)
// through `-DVCRAFT_GC_DIVISOR`. Boehm's default favours a small heap; V builds for
// throughput with 1, and vcraft ships 2: roughly half a MiB less resident for a few
// percent of allocation-heavy throughput (see benchmark/README.md).
#ifndef VCRAFT_GC_DIVISOR
#define VCRAFT_GC_DIVISOR 2
#endif

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
	GC_INIT();
	for (unsigned i = 0; i < layout.count; i++) {
		GC_add_roots(layout.starts[i], layout.ends[i]);
	}
}
#endif

#endif // VCRAFT_GC_PREINIT_H
