Python 3.13.16 · x86_64 · Linux-6.18.56-1-lts-x86_64-with-glibc2.44

Toolchain: vcraft 1.3.0 · V 36be926 · PyO3 0.29.0 · maturin 1.15.0 · zig-maturin 1.0.1 · zig 0.16.0

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 279 KiB | 299 KiB | 1,023 KiB |
| extension (as built) | 688 KiB | 576 KiB | 3,606 KiB |
| extension (strip -x) | 508 KiB | 505 KiB | 598 KiB |
| files in wheel | 6 | 5 | 4 |
| clean release build | 9.5 s | 7.2 s | 17.7 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 71 ns **(best)** | 73 ns (1.02×) | 77 ns (1.08×) | 37 ns |
| fib(25) | pure compute, recursion | 237.3 µs (2.12×) | 112.0 µs **(best)** | 359.9 µs (3.21×) | 9.36 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.00 ms **(best)** | 2.22 ms (1.11×) | 2.03 ms (1.02×) | 98.07 ms |
| sum_floats(100k) | list[float] -> native | 881.1 µs (3.95×) | 223.3 µs **(best)** | 1.37 ms (6.14×) | 1.59 ms |
| make_range(100k) | native -> list[int] | 2.29 ms **(best)** | 2.45 ms (1.07×) | 2.46 ms (1.08×) | 2.37 ms |
| greet | str in, new str out | 135 ns (1.13×) | 120 ns **(best)** | 235 ns (1.97×) | 73 ns |
| describe(3) | keyword/default binding | 174 ns (1.41×) | 123 ns **(best)** | 157 ns (1.28×) | 169 ns |
| maybe_double(21) | optional in/out | 68 ns (1.21×) | 56 ns **(best)** | 69 ns (1.24×) | 39 ns |
| histogram(10k) | list[str] -> dict | 733.5 µs (1.29×) | 567.7 µs **(best)** | 1.85 ms (3.27×) | 623.2 µs |
| minmax(100k) | list[int] -> tuple | 1.10 ms (1.61×) | 683.2 µs **(best)** | 1.26 ms (1.84×) | 1.98 ms |
| reverse3([1,2,3]) | fixed array in/out | 198 ns (1.08×) | 203 ns (1.11×) | 183 ns **(best)** | 128 ns |
| checksum(100kB) | bytes -> native, no copy | 14.9 µs **(best)** | 39.6 µs (2.66×) | 41.0 µs (2.76×) | 2.28 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.9 µs (2.13×) | 2.1 µs (1.16×) | 1.8 µs **(best)** | 1.9 µs |
| join_strings(10k) | list[str] -> native -> str | 506.4 µs (1.91×) | 266.0 µs (1.00×) | 265.1 µs **(best)** | 75.4 µs |
| expect_positive(err) | raise + catch per call | 237 ns (1.04×) | 237 ns (1.04×) | 228 ns **(best)** | 247 ns |
| Counter() | object construction | 96 ns (1.23×) | 92 ns (1.18×) | 78 ns **(best)** | 97 ns |
| c.increment() | method call | 58 ns (1.12×) | 52 ns **(best)** | 64 ns (1.22×) | 57 ns |
| c.add(1) | method call with an argument | 67 ns **(best)** | 68 ns (1.01×) | 90 ns (1.33×) | 59 ns |
| c.value | attribute read | 48 ns (1.48×) | 37 ns (1.16×) | 32 ns **(best)** | 13 ns |
| c.is_zero | property read | 37 ns **(best)** | 41 ns (1.13×) | 43 ns (1.17×) | 40 ns |
| c == c | rich comparison | 50 ns (1.30×) | 39 ns **(best)** | 51 ns (1.33×) | 75 ns |
| list(Countdown()) | construct and iterate | 365 ns (1.37×) | 465 ns (1.74×) | 267 ns **(best)** | 605 ns |
| Vector(1000) | class with a native buffer | 252 ns **(best)** | 310 ns (1.23×) | 4.2 µs (16.62×) | 2.4 µs |
| vector.total() | native buffer sum in V | 785 ns (1.01×) | 794 ns (1.02×) | 779 ns **(best)** | 6.1 µs |
| complex_scale(1+2j, 3) | complex in and out | 94 ns **(best)** | 97 ns (1.03×) | — | 65 ns |
| Counter.zero() | static method | 64 ns **(best)** | 65 ns (1.01×) | 71 ns (1.11×) | 43 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 788 KiB | 760 KiB | 384 KiB | 16 KiB |
| import time (warm, median) | 0.58 ms | 0.73 ms | 0.33 ms | 0.16 ms |
| import time (first after install) | 0.71 ms | 0.71 ms | 0.39 ms | 0.20 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 38.8 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 41.6 MiB peak · 4.6 MiB kept · 0.0 MiB leak | 37.5 MiB peak · 1.5 MiB kept · 0.0 MiB leak | 37.4 MiB peak · 1.5 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 43.2 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 73.0 MiB peak · 28.9 MiB kept · 0.5 MiB leak | 43.1 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 42.8 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 34.1 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.7 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 34.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 34.5 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 34.2 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 34.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.6 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| histogram(new 1k words) x500 | 34.6 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 35.2 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 34.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 33.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Vector(1000) x500 | 33.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.4 MiB peak · 0.0 MiB kept · 0.1 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| expect_positive(-1) x500k | 34.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(wrong elem) x200k | 33.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
| 1 | 0.176 s (1.0×) | 0.207 s (1.0×) | 0.167 s (1.0×) | — |
| 2 | 0.170 s (2.1×) | 0.186 s (2.2×) | 0.168 s (2.0×) | — |
| 4 | 0.197 s (3.6×) | 0.176 s (4.7×) | 0.168 s (4.0×) | — |
| 8 | 0.215 s (6.6×) | 0.202 s (8.2×) | 0.226 s (5.9×) | — |

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
