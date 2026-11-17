#include "fastc.h"

uint32_t fastc_fnv1a(const uint8_t *data, size_t len) {
	uint32_t hash = 2166136261u;
	for (size_t i = 0; i < len; i++) {
		hash ^= data[i];
		hash *= 16777619u;
	}
	return hash;
}

ptrdiff_t fastc_rle(const uint8_t *src, size_t len, uint8_t *dst, size_t dst_cap) {
	size_t out = 0;
	size_t i = 0;
	while (i < len) {
		uint8_t byte = src[i];
		size_t run = 1;
		while (i + run < len && src[i + run] == byte && run < 255) {
			run++;
		}
		if (out + 2 > dst_cap) {
			return -1;
		}
		dst[out++] = (uint8_t)run;
		dst[out++] = byte;
		i += run;
	}
	return (ptrdiff_t)out;
}
