# with_c

An extension that compiles a C file of its own: `c/fastc.c` (FNV-1a hash and run-length
encoding) is built into the module through `#flag @VMODROOT/c/fastc.c`, declared to V
with `fn C.` and wrapped by `@[vc_fn]` functions. The same shape wraps an existing C
library. `vcraft sdist` ships `c/`, so the sdist builds elsewhere too.

```console
$ vcraft develop
$ python test_with_c.py
```

Mind the widths: C's `int` is V's `i32`, `size_t` is `usize`, `uint32_t` is `u32`. The
generator warns on a `fn C.` that takes V's 64-bit `int` through a pointer.
