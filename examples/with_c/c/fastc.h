#ifndef FASTC_H
#define FASTC_H

#include <stddef.h>
#include <stdint.h>

/* FNV-1a, 32-bit: a small, well-known hash, here as the stand-in for any existing C. */
uint32_t fastc_fnv1a(const uint8_t *data, size_t len);

/* Run-length encodes `src` into `dst` as (count, byte) pairs, counts capped at 255.
   Returns the bytes written, or -1 when `dst_cap` is too small. */
ptrdiff_t fastc_rle(const uint8_t *src, size_t len, uint8_t *dst, size_t dst_cap);

#endif
