# vcraft_wheel

Writing wheels in V: DEFLATE, the ZIP container, and the metadata files.

## Why DEFLATE is implemented here

A wheel has to be a ZIP using method 8. Method 0, stored, is also a valid ZIP and
every tool reads it, and it needs no compressor at all — so storing would work, and it
is deliberately not what this does. An uncompressed `.so` is roughly twice the size,
and a packaging tool that doubles the download is a bug users notice.

zlib is not linked. It is present on most build hosts but not all, and linking it makes
the extension depend on a shared library that the manylinux and musllinux images have
to agree on. Vendoring zlib is worse. About 250 lines of fixed-Huffman DEFLATE is
cheaper than either, and the output is read by every unzip.

What is implemented: one fixed-Huffman block per 32 KiB of input, with a hash-chain
match finder. That is roughly 2.3x on a compiled extension, which is what a wheel
needs. Dynamic Huffman would do better and is not written.

## Two bit orders

DEFLATE packs most things least significant bit first, but Huffman codes most
significant bit first. `write_bits` and `write_code` are separate methods so that only
those two know it. The fixed codes from RFC 1951 section 3.2.6 are already in the order
a decoder reads them, so they are handed to `write_code` as they stand: reversing them
first and letting `write_code` reverse again cancels out and emits every code backwards,
which decodes to a different symbol rather than failing.

## The window is 32768, not 65536

`block_size` is 32768 because that is the furthest back DEFLATE can address: a distance
is 15 bits of extra value over a base of 24577. A larger block is not a choice, it is
unimplementable, and using 65536 produces a stream that decodes to garbage for any input
past the halfway point — the encoder finds a match it can describe and the decoder
cannot reach it. The symptom is a small file that round-trips and a large one that does
not, which is why the tests compress a real `.so` and not only strings.

Two separate limits apply to a match, and both are needed: the start of the current
block, because the decoder has only this block, and 32768, because the format caps it.

## Slices do not grow across module boundaries

Three signatures were tried for the byte writers and two fail in ways that do not
explain themselves.

- `&[]u8` never grows the caller's slice. V passes a slice header by value, so the
  callee appends to a copy of the header and the caller still sees the old length.
- `mut []u8` does grow it, but the call has to be written `mut out`. A caller that
  forgets compiles fine and silently appends to a copy.

Returning the slice as well makes the growth visible in both directions, so a mistake
is a type error rather than a truncated file. `put_u32` and friends are therefore
`fn put_u32(mut out []u8, v u32) []u8`.

`<< u32` is also wrong on its own: it appends in V's byte order, and it appends the
value at its declared width, so a `u16` field would take four bytes. ZIP is
little-endian throughout, which is what these functions are for.

## V 0.5.2 constraints hit here

- A descending range literal such as `count - 1 .. 0` is rejected as an empty range.
  Written as an explicit countdown instead. This one is nasty: `write_code` compiled,
  ran, and silently emitted no bits at all, so every output was a bare block header.
- A `while` loop needs `for cond {}`; V 0.5 has no `while` keyword.
- `[]u8` has no `chunks`. SHA-256 walks the message 64 bytes at a time by index.
- A slice literal ignores `cap`, so a capacity hint allocates nothing.
- `u(x)` is not a function. A shift count is `u32(x)`.
- `while`-style growth of a shared slice needs `unsafe`, which corrupts the header when
  the caller disagrees about capacity. The `mut []u8` return-value form avoids it.

## File names

Two rules that look identical and are not, and getting either wrong makes pip reject
the wheel before opening it:

- The distribution name is **escaped**: a run of `-_.` becomes a single `_`. So
  `vcraft-demo` and `zope.interface` become `vcraft_demo` and `zope_interface`.
- The version is **escaped too, but only its dashes**: `-` becomes `_` and `.` stays
  `.`. Writing the separator as `-` looks equivalent, because PEP 440 treats `0.1.0`
  and `0-1-0` as the same version — but the installer splits the file name on `-`, so
  `0-1-0` reads as three extra name parts and pip says "wrong number of parts".

The `.dist-info` directory is named after the *distribution*, never after the module.
pip checks that it starts with the distribution name from the file name and rejects the
wheel outright otherwise.

## The extension goes at the archive root

Not inside a directory named after the module. A directory with no `__init__.py` is a
namespace package, and Python resolves one without opening the files inside it:
`hello_native/hello_native.so` installs cleanly and then imports as an empty namespace
package with `__file__` of None. The symptom looks like a build that produced an empty
extension, and nothing in the wheel is malformed.

## Hashes

`RECORD` carries `sha256=<digest>`, and pip compares the string, so the encoding has to
be right: base64 with the URL-safe alphabet and the padding stripped, not hex. A hex
digest installs and fails verification on every file.

`crc32` and `sha256` are both checked against `zlib.crc32` and `hashlib.sha256` rather
than against themselves. CRC-32's table is built on first use instead of being written
out as 256 literals: it is 1 KiB of source for something derivable in four lines, and a
transcribed table eventually has a typo in it.

## Tests

```console
$ python3 tests/wheel/test_wheel.py
```

Every assertion is against a library that already exists and is already correct:
`zipfile` for the container, `hashlib` for the hashes, `zlib` for the DEFLATE stream, and
`pip` for the install. Nothing here re-implements the format, because a test that shares
its assumptions with the code proves nothing.

The install check is the one that matters. A wheel can satisfy every structural
assertion and still fail to install, and the reasons — a namespace package, a
dist-info name that does not match, a version separator pip cannot parse — are all
invisible to a reader of the archive.
