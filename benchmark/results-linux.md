Python 3.13.16 · x86_64 · Linux-6.18.56-1-lts-x86_64-with-glibc2.44

Toolchain: vcraft 1.2.0 · V 36be926 · PyO3 0.29.0 · maturin 1.15.0 · zig-maturin 1.0.1 · zig 0.16.0

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 279 KiB | 302 KiB | 1,023 KiB |
| extension (as built) | 688 KiB | 576 KiB | 3,606 KiB |
| extension (strip -x) | 508 KiB | 509 KiB | 598 KiB |
| files in wheel | 6 | 5 | 4 |
| clean release build | 8.5 s | 7.1 s | 16.6 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 69 ns (1.04×) | 66 ns **(best)** | 79 ns (1.18×) | 36 ns |
| fib(25) | pure compute, recursion | 223.5 µs (1.98×) | 113.0 µs **(best)** | 345.2 µs (3.06×) | 9.36 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.99 ms (1.07×) | 2.28 ms (1.23×) | 1.86 ms **(best)** | 93.20 ms |
| sum_floats(100k) | list[float] -> native | 900.3 µs (3.64×) | 247.4 µs **(best)** | 1.27 ms (5.12×) | 1.57 ms |
| make_range(100k) | native -> list[int] | 2.20 ms (1.02×) | 2.37 ms (1.10×) | 2.15 ms **(best)** | 2.29 ms |
| greet | str in, new str out | 131 ns (1.10×) | 119 ns **(best)** | 220 ns (1.85×) | 69 ns |
| describe(3) | keyword/default binding | 173 ns (1.13×) | 261 ns (1.70×) | 154 ns **(best)** | 163 ns |
| maybe_double(21) | optional in/out | 66 ns (1.21×) | 55 ns **(best)** | 70 ns (1.27×) | 38 ns |
| histogram(10k) | list[str] -> dict | 710.0 µs (1.18×) | 604.1 µs **(best)** | 1.84 ms (3.05×) | 605.8 µs |
| minmax(100k) | list[int] -> tuple | 1.07 ms (1.77×) | 606.3 µs **(best)** | 1.41 ms (2.33×) | 1.91 ms |
| reverse3([1,2,3]) | fixed array in/out | 198 ns (1.07×) | 193 ns (1.04×) | 185 ns **(best)** | 124 ns |
| checksum(100kB) | bytes -> native, no copy | 13.3 µs **(best)** | 41.6 µs (3.11×) | 40.0 µs (3.00×) | 2.28 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.8 µs (2.00×) | 2.1 µs (1.11×) | 1.9 µs **(best)** | 1.9 µs |
| join_strings(10k) | list[str] -> native -> str | 477.8 µs (1.68×) | 328.6 µs (1.15×) | 285.0 µs **(best)** | 73.3 µs |
| expect_positive(err) | raise + catch per call | 215 ns **(best)** | 242 ns (1.13×) | 231 ns (1.07×) | 233 ns |
| Counter() | object construction | 95 ns (1.26×) | 107 ns (1.42×) | 76 ns **(best)** | 92 ns |
| c.increment() | method call | 56 ns **(best)** | 65 ns (1.16×) | 61 ns (1.08×) | 53 ns |
| c.add(1) | method call with an argument | 66 ns **(best)** | 79 ns (1.21×) | 89 ns (1.36×) | 55 ns |
| c.value | attribute read | 45 ns (1.41×) | 53 ns (1.66×) | 32 ns **(best)** | 12 ns |
| c.is_zero | property read | 35 ns **(best)** | 53 ns (1.51×) | 43 ns (1.20×) | 38 ns |
| c == c | rich comparison | 48 ns (1.29×) | 37 ns **(best)** | 51 ns (1.36×) | 72 ns |
| list(Countdown()) | construct and iterate | 343 ns (1.30×) | 542 ns (2.05×) | 265 ns **(best)** | 599 ns |
| Vector(1000) | class with a native buffer | 219 ns **(best)** | 342 ns (1.57×) | 4.2 µs (18.99×) | 2.5 µs |
| vector.total() | native buffer sum in V | 765 ns **(best)** | 793 ns (1.04×) | 789 ns (1.03×) | 6.1 µs |
| complex_scale(1+2j, 3) | complex in and out | 87 ns **(best)** | 149 ns (1.70×) | — | 62 ns |
| Counter.zero() | static method | 59 ns **(best)** | 59 ns (1.01×) | 71 ns (1.21×) | 41 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 840 KiB | 768 KiB | 356 KiB | 16 KiB |
| import time (warm, median) | 0.58 ms | 0.70 ms | 0.25 ms | 0.16 ms |
| import time (first after install) | 0.84 ms | 0.67 ms | 0.25 ms | 0.19 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 38.8 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 40.9 MiB peak · 3.8 MiB kept · 0.0 MiB leak | 37.8 MiB peak · 1.5 MiB kept · 0.0 MiB leak | 37.3 MiB peak · 1.5 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 43.7 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 72.0 MiB peak · 28.7 MiB kept · 0.1 MiB leak | 43.1 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 42.3 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 34.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 35.0 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 33.7 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 33.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.8 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 34.0 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 33.8 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| histogram(new 1k words) x500 | 34.2 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 35.2 MiB peak · 0.6 MiB kept · 0.4 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.7 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Vector(1000) x500 | 33.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.8 MiB peak · 0.0 MiB kept · 0.1 MiB leak | 33.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| expect_positive(-1) x500k | 33.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(wrong elem) x200k | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.7 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 33.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 33.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

### Reference retention

Each probe calls the same borrowed argument many times in one process and
reports the change in `sys.getrefcount` of the argument (or of an item it
was handed). **0 is correct**; a positive number is one leaked reference per
call, which a heap that has plateaued hides from the memory table.

| probe | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| sum_floats: borrowed list | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| sum_floats: borrowed elements | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed bytes | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed bytearray | unsupported | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed memoryview | unsupported | **0** (3→3) | unsupported | **0** (3→3) |
| echo_bytes: borrowed argument | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| method: borrowed self | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |

### Thread scaling

Each thread runs `lcg(2_000_000)` 64 times; wall seconds, and
parallel speedup over one thread. A binding that releases the GIL scales close
to the core count. The pure-Python reference cannot release the GIL, so it is
not measured here.

| threads | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| 1 | 0.166 s (1.0×) | 0.188 s (1.0×) | 0.191 s (1.0×) | — |
| 2 | 0.194 s (1.7×) | 0.169 s (2.2×) | 0.181 s (2.1×) | — |
| 4 | 0.199 s (3.3×) | 0.174 s (4.3×) | 0.178 s (4.3×) | — |
| 8 | 0.211 s (6.3×) | 0.177 s (8.5×) | 0.184 s (8.3×) | — |

### Correctness

| check | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| add small | ok | ok | ok | ok |
| add zero | ok | ok | ok | ok |
| add negative | ok | ok | ok | ok |
| add 2**40 | ok | ok | ok | ok |
| add i64 max | ok | ok | ok | ok |
| add i64 min | ok | ok | ok | ok |
| add bool | ok | ok | ok | ok |
| add float rejected | ok | ok | ok | n/a |
| add str rejected | ok | ok | ok | ok |
| add 2**63 overflows | ok | ok | `TypeError: expected int, got int` | n/a |
| add 2**64-1 overflows | ok | ok | `TypeError: expected int, got int` | n/a |
| fib(0) | ok | ok | ok | ok |
| fib(1) | ok | ok | ok | ok |
| fib(20) | ok | ok | ok | ok |
| fib(-1) | ok | ok | ok | ok |
| fib float rejected | ok | ok | ok | n/a |
| count_primes(0) | ok | ok | ok | ok |
| count_primes(1) | ok | ok | ok | ok |
| count_primes(10) | ok | ok | ok | ok |
| count_primes(100) | ok | ok | ok | ok |
| count_primes negative | ok | ok | ok | ok |
| sum_squares(0) | ok | ok | ok | ok |
| sum_squares(1) | ok | ok | ok | ok |
| sum_squares(10) | ok | ok | ok | ok |
| sum_squares float rejected | ok | ok | ok | n/a |
| lcg(10) | ok | ok | ok | ok |
| lcg(0) | ok | ok | ok | ok |
| sum_floats empty | ok | ok | ok | ok |
| sum_floats two | ok | ok | ok | ok |
| sum_floats negative | ok | ok | ok | ok |
| sum_floats ints | ok | ok | ok | ok |
| sum_floats nan | ok | ok | ok | ok |
| sum_floats inf | ok | ok | ok | ok |
| sum_floats str rejected | ok | ok | ok | ok |
| sum_floats mixed rejected | ok | ok | ok | ok |
| make_range(0) | ok | ok | ok | ok |
| make_range(1) | ok | ok | ok | ok |
| make_range(3) | ok | ok | ok | ok |
| make_range negative | ok | `RuntimeError: panic in V code: negative .cap:-1` | `SystemError: Objects/listobject.c:265: bad argument to internal function` | ok |
| make_range float rejected | ok | ok | ok | ok |
| greet empty | ok | ok | ok | ok |
| greet unicode | ok | ok | ok | ok |
| greet emoji | ok | ok | ok | ok |
| greet embedded NUL | ok | ok | `wrong: 'Hello, a!'` | ok |
| greet int rejected | ok | ok | ok | n/a |
| greet bytes rejected | ok | ok | `wrong: 'Hello, x!'` | n/a |
| describe defaults | ok | ok | ok | ok |
| describe all positional | ok | ok | ok | ok |
| describe keyword label | ok | ok | ok | ok |
| describe keyword unit | ok | ok | ok | ok |
| describe mixed kw and pos | ok | ok | ok | ok |
| describe missing required | ok | ok | ok | ok |
| describe unknown keyword | ok | ok | `wrong: 'item: 3'` | ok |
| describe too many positional | ok | ok | ok | ok |
| maybe_double some | ok | ok | ok | ok |
| maybe_double none | ok | ok | ok | ok |
| maybe_double wrong type | ok | ok | ok | n/a |
| histogram counts | ok | ok | ok | ok |
| histogram empty | ok | ok | ok | ok |
| histogram str rejected | ok | ok | ok | n/a |
| histogram ints rejected | ok | ok | ok | n/a |
| minmax | ok | ok | ok | ok |
| minmax single | ok | ok | ok | ok |
| minmax empty | ok | ok | ok | ok |
| minmax float rejected | ok | ok | ok | n/a |
| reverse3 | ok | ok | ok | ok |
| reverse3 wrong length | ok | ok | ok | ok |
| reverse3 float rejected | ok | ok | ok | n/a |
| checksum empty | ok | ok | ok | ok |
| checksum 3 bytes | ok | ok | ok | ok |
| checksum bytearray | n/a | ok | ok | ok |
| checksum memoryview | n/a | ok | `TypeError: expected str or bytes, got memoryview` | ok |
| checksum array | n/a | ok | `TypeError: expected str or bytes, got array.array` | ok |
| checksum str rejected | ok | ok | `wrong: 195` | ok |
| echo_bytes round trip | ok | ok | ok | ok |
| echo_bytes empty | ok | ok | ok | ok |
| echo_bytes from bytearray | n/a | ok | ok | ok |
| join_strings empty | ok | ok | ok | ok |
| join_strings single | ok | ok | ok | ok |
| join_strings 3 items | ok | ok | ok | ok |
| join_strings nonstr rejected | ok | ok | ok | ok |
| counter starts at 0 | ok | ok | ok | ok |
| counter increment twice | ok | ok | ok | ok |
| counter add and value | ok | ok | ok | ok |
| counter add negative | ok | ok | ok | ok |
| counter is_zero | ok | ok | ok | ok |
| counter not is_zero | ok | ok | ok | ok |
| counter equality | ok | ok | ok | ok |
| counter inequality | ok | ok | ok | ok |
| counter not equal to int | ok | ok | ok | ok |
| counter ne | ok | ok | ok | ok |
| counter hash collapses a set | ok | ok | ok | ok |
| countdown yields | ok | ok | ok | ok |
| countdown two steps | ok | ok | ok | ok |
| countdown raises StopIteration | ok | ok | ok | ok |
| bounded inherits value | ok | ok | ok | ok |
| bounded bump | ok | ok | ok | ok |
| bounded over limit | ok | ok | ok | ok |
| bounded base method | ok | ok | ok | ok |
| bounded is a Counter | ok | ok | ok | ok |
| counter is not bounded | ok | ok | ok | ok |
| expect_positive zero | ok | ok | ok | ok |
| expect_positive ok | ok | ok | ok | ok |
| expect_positive raises | ok | ok | ok | ok |
| expect_positive str rejected | ok | ok | ok | ok |
| vector total of zeros | ok | ok | ok | ok |
| vector set and total | ok | ok | ok | ok |
| vector get | ok | ok | ok | ok |
| vector out of range ignored | ok | ok | ok | ok |
| vector length rejected | ok | ok | ok | n/a |
| vector memoryview writes through | n/a | ok | ok | n/a |
| complex round trip | ok | ok | n/a | ok |
| complex real coerced | ok | ok | n/a | ok |
| complex wrong type | ok | ok | n/a | n/a |
| static method on the class | ok | ok | ok | ok |
| static method on an instance | ok | ok | ok | ok |
