// The collector's start-up on macOS, done before V's own.
//
// Included into the C file V generates for the module, never compiled on its own: V's
// translation unit already has `gc.h`, which cannot be included twice, and only there
// does this constructor end up ahead of V's. Constructors in one translation unit run in
// the order they are defined, and V defines its `_vinit_caller` at the end of the file,
// after every include. The linker's `-init` would say the same thing more directly, but
// with a macOS 11 deployment target, which is what the wheel tag promises, the linker
// drops it without a word.
#ifndef VCRAFT_GC_PREINIT_H
#define VCRAFT_GC_PREINIT_H

#if defined(__APPLE__) && defined(GC_THREADS)
#include <dlfcn.h>
#include <mach-o/getsect.h>

// The heap growth divisor, overridable from `vcraft.toml` (`gc-free-space-divisor`)
// through `-DVCRAFT_GC_DIVISOR`. Boehm's default favours a small heap; V builds for
// throughput with 1.
#ifndef VCRAFT_GC_DIVISOR
#define VCRAFT_GC_DIVISOR 1
#endif

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

#endif // VCRAFT_GC_PREINIT_H
