Python 3.13.16 · x86_64 · Linux-6.18.56-1-lts-x86_64-with-glibc2.44

Toolchain: vcraft 1.2.0 · V 36be926 · PyO3 0.29.0 · maturin 1.15.0 · zig-maturin 1.0.1 · zig 0.16.0

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 279 KiB | 300 KiB | 1,023 KiB |
| extension (as built) | 688 KiB | 576 KiB | 3,606 KiB |
| extension (strip -x) | 508 KiB | 505 KiB | 598 KiB |
| files in wheel | 6 | 5 | 4 |
| clean release build | 8.2 s | 6.7 s | 15.9 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 70 ns **(best)** | 72 ns (1.02×) | 72 ns (1.03×) | 36 ns |
| fib(25) | pure compute, recursion | 226.5 µs (2.03×) | 111.7 µs **(best)** | 337.0 µs (3.02×) | 9.08 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.90 ms (1.04×) | 2.10 ms (1.16×) | 1.81 ms **(best)** | 92.30 ms |
| sum_floats(100k) | list[float] -> native | 816.6 µs (3.61×) | 226.3 µs **(best)** | 1.24 ms (5.46×) | 1.53 ms |
| make_range(100k) | native -> list[int] | 2.13 ms (1.01×) | 2.24 ms (1.06×) | 2.12 ms **(best)** | 2.10 ms |
| greet | str in, new str out | 130 ns (1.20×) | 108 ns **(best)** | 214 ns (1.98×) | 69 ns |
| describe(3) | keyword/default binding | 167 ns (1.34×) | 125 ns **(best)** | 156 ns (1.26×) | 158 ns |
| maybe_double(21) | optional in/out | 65 ns (1.15×) | 56 ns **(best)** | 68 ns (1.21×) | 38 ns |
| histogram(10k) | list[str] -> dict | 699.2 µs (1.30×) | 539.3 µs **(best)** | 1.89 ms (3.51×) | 588.8 µs |
| minmax(100k) | list[int] -> tuple | 1.09 ms (1.73×) | 631.5 µs **(best)** | 1.21 ms (1.92×) | 1.91 ms |
| reverse3([1,2,3]) | fixed array in/out | 189 ns (1.05×) | 188 ns (1.04×) | 181 ns **(best)** | 127 ns |
| checksum(100kB) | bytes -> native, no copy | 13.1 µs **(best)** | 40.1 µs (3.05×) | 41.8 µs (3.18×) | 2.18 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.8 µs (2.12×) | 2.1 µs (1.17×) | 1.8 µs **(best)** | 1.9 µs |
| join_strings(10k) | list[str] -> native -> str | 471.9 µs (1.72×) | 291.1 µs (1.06×) | 274.5 µs **(best)** | 72.7 µs |
| expect_positive(err) | raise + catch per call | 218 ns **(best)** | 237 ns (1.09×) | 227 ns (1.04×) | 235 ns |
| Counter() | object construction | 94 ns (1.22×) | 106 ns (1.38×) | 77 ns **(best)** | 91 ns |
| c.increment() | method call | 55 ns (1.09×) | 50 ns **(best)** | 64 ns (1.27×) | 52 ns |
| c.add(1) | method call with an argument | 68 ns **(best)** | 72 ns (1.06×) | 88 ns (1.30×) | 55 ns |
| c.value | attribute read | 46 ns (1.46×) | 34 ns (1.09×) | 32 ns **(best)** | 12 ns |
| c.is_zero | property read | 35 ns **(best)** | 36 ns (1.05×) | 43 ns (1.25×) | 38 ns |
| c == c | rich comparison | 46 ns (1.23×) | 38 ns **(best)** | 51 ns (1.35×) | 71 ns |
| list(Countdown()) | construct and iterate | 330 ns (1.25×) | 443 ns (1.68×) | 264 ns **(best)** | 565 ns |
| Vector(1000) | class with a native buffer | 223 ns **(best)** | 306 ns (1.37×) | 4.1 µs (18.56×) | 2.3 µs |
| vector.total() | native buffer sum in V | 784 ns (1.02×) | 767 ns **(best)** | 790 ns (1.03×) | 5.9 µs |
| complex_scale(1+2j, 3) | complex in and out | 85 ns **(best)** | 96 ns (1.13×) | — | 61 ns |
| Counter.zero() | static method | 57 ns **(best)** | 66 ns (1.15×) | 70 ns (1.23×) | 41 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 872 KiB | 764 KiB | 368 KiB | 16 KiB |
| import time (warm, median) | 0.51 ms | 0.73 ms | 0.24 ms | 0.17 ms |
| import time (first after install) | 0.68 ms | 0.77 ms | 0.25 ms | 0.19 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 38.4 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 41.5 MiB peak · 4.5 MiB kept · 0.0 MiB leak | 37.5 MiB peak · 1.5 MiB kept · 0.0 MiB leak | 37.0 MiB peak · 1.5 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 43.6 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 63.1 MiB peak · 19.6 MiB kept · 0.0 MiB leak | 43.5 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 42.6 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 34.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.7 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 34.6 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 34.3 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.5 MiB peak · 0.2 MiB kept · 0.2 MiB leak | 34.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| histogram(new 1k words) x500 | 34.3 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.8 MiB peak · 0.6 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Vector(1000) x500 | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.1 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| expect_positive(-1) x500k | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(wrong elem) x200k | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
| 1 | 0.167 s (1.0×) | 0.159 s (1.0×) | 0.172 s (1.0×) | — |
| 2 | 0.169 s (2.0×) | 0.178 s (1.8×) | 0.184 s (1.9×) | — |
| 4 | 0.175 s (3.8×) | 0.192 s (3.3×) | 0.194 s (3.6×) | — |
| 8 | 0.209 s (6.4×) | 0.232 s (5.5×) | 0.201 s (6.9×) | — |

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
