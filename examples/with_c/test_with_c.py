"""Run with the built extension importable: `vcraft develop`, then `python test_with_c.py`."""

import fastc


def fnv1a(data: bytes) -> int:
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


for sample in (b"", b"a", b"hello world", bytes(range(256)) * 10):
    assert fastc.fnv1a(sample) == fnv1a(sample), sample[:20]
    assert fastc.unrle(fastc.rle(sample)) == sample

assert fastc.rle(b"aaab") == bytes([3, ord("a"), 1, ord("b")])
assert fastc.rle(b"z" * 300) == bytes([255, ord("z"), 45, ord("z")])
try:
    fastc.unrle(b"\x01")
except ValueError:
    pass
else:
    raise AssertionError("odd-length rle data was accepted")
print("ok with_c")
