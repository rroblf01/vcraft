# Array codegen costs a Python binding 2–3× on some loops

A report for the V project. Everything below is measured with V
`36be92642c49a8fe9213ea4b96c6bf56b67b668c` (reported as `V 0.5.2 36be926`), the commit
vcraft pins because the `-new-compiler` flag it needs postdates the last release. The
project is [vcraft](https://github.com/anomalyco/vcraft): CPython bindings written in V,
the same shape as PyO3. The benchmark compares it against PyO3, `zig-maturin` and a pure
Python reference on identical workloads, so a gap here is a gap between V's generated C
and LLVM's, not between two hand-written runtimes.

The binding itself is at or ahead of PyO3 on 17 of the 26 workloads (call overhead,
recursion, `list[float]` conversion, strings, dicts, tuples, class construction, method
and attribute access, iteration, the error path). The workloads V loses are the ones
whose hot loop is array indexing or appending, and every one of them is in the C codegen,
not in vcraft. This report is those four findings, with the generated C and the assembly.

## How to reproduce

```
cd benchmark
./run.sh              # builds all three projects, installs into benchmark/.venv, runs bench.py
```

`benchmark/vcraft/src/bench_vcraft_native.v` holds the V side. To see the generated C
without building the wheel:

```
cd benchmark/vcraft
v -new-compiler -enable-globals -shared -o /tmp/bench.c -path "$ROOT/vlib|@vlib" \
  -cflags "-I$(python3 -c 'import sysconfig;print(sysconfig.get_paths()["include"])') -D_GNU_SOURCE" \
  -prod .
```

The numbers quoted are from `benchmark/results-linux.md` (Linux x86_64, CPython 3.13.16,
gcc) unless a controlled A/B is noted.

## Finding A — `array.get` is a non-inline bounds-checked call

`vlib/builtin/array.v`:

```v
// we manually inline this for single operations for performance without -prod
@[inline; unsafe]
fn (a array) get_unsafe(i int) voidptr { ... }

// Private function. Used to implement array[] operator.
fn (a array) get(i int) voidptr {          // <- not @[inline]
	$if !no_bounds_checking {
		if i < 0 || i >= a.len {
			panic_n2('array.get: index out of range (i,a.len):', i, a.len)
		}
	}
	unsafe { return &u8(a.data) + u64(i) * u64(a.element_size) }
}
```

`for x in xs` and `xs[i]` both go through `get` (C name `array__get`). In this program's
generated C:

```c
// checksum(data []u8) u64  —  for b in data { total += u64(b) }
u64 bench_vcraft_native__checksum(Array data) {
	u64 total = (u64)(0);
	{
		i64 __for_idx_0 = 0;
		for (; __for_idx_0 < data.len; __for_idx_0++) {
			u8 b = *(u8*)(array_get(data, __for_idx_0));
			total += (u64)(b);
		}
	}
	return total;
}
```

The compiler emits `array_get` as a call, not an access. GCC inlines it at `-O3` here but
the `panic_n2` branch keeps it from vectorizing: the emitted loop is scalar, one
`movzbl`+`add` per byte:

```
8cc0: movzbl (%rdx),%esi
8cc3: add    $0x1,%rax
8cc7: add    $0x1,%rdx
8ccb: add    %rsi,%rcx
8cce: cmp    %rax,%rdi
8cd1: jne    8cc0
```

LLVM emits a single `psadbw`/`uaddlv` sequence for the identical Rust loop
(`data.iter().map(|b| *b as u64).sum()`). The result is a ~3× gap on `checksum(100 kB)`:
vcraft 43.3 µs against PyO3 14.4 µs.

**Proposal A1.** Mark `get` `@[inline]` like `get_unsafe`. The bounds check stays, but an
inlined `if (i < 0 || i >= len) panic();` inside a loop whose condition already proves
`0 <= i < len` is something the C optimizer can delete, and it is the branch that blocks
vectorization.

**Proposal A2.** In the C backend's loop and index lowering, use `get_unsafe` where the
bound is provable — `for x in xs`, `for i in 0 .. xs.len { xs[i] }`, `for i, x in xs` —
since `i < xs.len` is the loop condition. A check that is already guaranteed by the
enclosing loop is pure cost.

## Finding B — `for x in arr` ignores `@[direct_array_access]`

`vlib/v/gen/c/for.v`, the array branch of `gen_for_in`, emits `array_get` unconditionally:

```c
for (int i = 0; i < arr.len; i++) {
    T elem = *(T*)array_get(arr, i);     // no direct_array_access check
}
```

`@[direct_array_access]` is documented as "translate array operations directly into C array
operations - omitting bounds checking", and it *is* honored for `arr[i]` reads and stores
(only recently — the store case in `#29512`). It is not honored by `for x in arr`.

This is directly measurable. Marking the benchmark's `count_primes` with the attribute
takes it from 2.34 ms to **1.75 ms**, ahead of PyO3's 1.96 ms, because the attribute
removes the per-read check:

```v
@[direct_array_access]
@[vc_fn]
pub fn count_primes(n i64) i64 { ... }
```

The benchmark does *not* carry the attribute, on purpose: the workload exists to measure
what the codegen does on ordinary safe code, and one attribute should not be needed to
make a `for i in 2 .. size { if !composite[i] }` loop competitive.

**Proposal B.** Honor `@[direct_array_access]` in the `for in` element access (emit
`get_unsafe` / `arr.data[i]`), matching the index-expression case.

## Finding C — `<<` on a scalar slice does not take the fast path

`make_range` is `mut out := []i64{cap: int(n)}` then `for i in i64(0) .. n { out << i }`.
The generated C calls the generic push per element:

```c
Array bench_vcraft_native__make_range(i64 n) {
	Array out = __new_array_noscan(0, (i64)(n), sizeof(i64));
	{
		i64 i = (i64)(0);
		for (; i < n; i++) {
			i64 __arr_val_0 = i;
			array_push(&out, &__arr_val_0);
		}
	}
	return out;
}
```

`array_push` (`array.v:1288`) is `@[inline]`, but its body is the general one: a negative-len
check, a `max_int` check, a cap check, an `is_slice` check, a call to `copy_element_to`, and
the `len++`. The typed scalar fast path added in `#29736`
(`vlib/v/gen/c/array.v`, `gen_scalar_array_push_call_stmt`) does not fire for this shape —
it should, since the value is a plain `i64` and the receiver is a local `[]i64`.

PyO3's `(0..n).collect()` reserves and writes through a pointer with no per-element branch.
The result is `make_range(100k)` at 2.52 ms against PyO3's 2.26 ms.

**Proposal C.** Make the scalar-append fast path fire for `out << scalar` where `out` is a
local `[]T` of a scalar (it appears to be skipped here), or lower a loop whose body is only
`out << <scalar>` into a reserve-plus-direct-store form.

## Finding D — the byte-widening reduction is not vectorized

Same loop as Finding A. Even with `@[direct_array_access]` the checksum loop stays scalar
(43.3 → 41.0 µs, within noise), so the blocker is not only the bounds check: it is that the
loop is not recognised as a reducible byte-widening sum. LLVM does recognise it for Rust.

**Proposal D.** If A2 is done and the loop still does not vectorize, add a way to ask for it
(the reduction pattern is common enough in bindings — checksums, hashes, byte sums). A
`@[vectorize]` function attribute, or emitting the sum with a form the vectorizer
recognises, would close a 3× gap that no vcraft-side change can reach.

## Not a finding — the optimization level

V's `-prod` compiles a generated C unit of at least 8 MiB with `-O2` and a smaller one with
`-O3` (`vlib/v/driver/driver.v`, `v3_large_prod_c_unit_threshold`). This project's generated
unit is 644 KiB, so it is compiled at `-O3` and shared builds get no `-flto` (`is_shared`),
which matches Rust's default `opt-level=3`. The gap is not an optimization-level mismatch.

## Summary of asks

1. `array.get`: `@[inline]` (A1).
2. Loop/index lowering: use `get_unsafe` where the bound is provable (A2).
3. `for x in arr`: honor `@[direct_array_access]` (B).
4. Scalar `<<`: make the `#29736` fast path fire for a local scalar slice (C).
5. Byte-widening reductions: a vectorization lever (D).

Findings 1–2 also remove the `panic` branch from every hot read loop, which is what unlocks
the vectorizer in Finding 4; they are the highest-leverage of the five.
