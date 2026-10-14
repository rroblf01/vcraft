Python 3.13.16 · x86_64 · Linux-6.18.56-1-lts-x86_64-with-glibc2.44

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 274 KiB | 289 KiB | 1,014 KiB |
| extension (as built) | 674 KiB | 549 KiB | 3,569 KiB |
| extension (strip -x) | 499 KiB | 485 KiB | 590 KiB |
| files in wheel | 6 | 5 | 4 |
| clean release build | 9.6 s | 11.4 s | 18.1 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 72 ns (1.04×) | 70 ns **(best)** | 89 ns (1.27×) | 36 ns |
| fib(25) | pure compute, recursion | 222.1 µs (2.04×) | 108.9 µs **(best)** | 383.5 µs (3.52×) | 9.11 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.80 ms **(best)** | 2.16 ms (1.20×) | 2.13 ms (1.19×) | 93.82 ms |
| sum_floats(100k) | list[float] -> native | 849.2 µs (3.56×) | 238.3 µs **(best)** | 1.19 ms (4.97×) | 1.58 ms |
| make_range(100k) | native -> list[int] | 2.21 ms (1.00×) | 2.40 ms (1.08×) | 2.21 ms **(best)** | 2.15 ms |
| greet | str in, new str out | 136 ns (1.18×) | 115 ns **(best)** | 221 ns (1.91×) | 69 ns |
| describe(3) | keyword/default binding | 167 ns (1.23×) | 206 ns (1.51×) | 136 ns **(best)** | 157 ns |
| maybe_double(21) | optional in/out | 65 ns (1.16×) | 56 ns **(best)** | 77 ns (1.36×) | 37 ns |
| histogram(10k) | list[str] -> dict | 797.3 µs (1.40×) | 569.3 µs **(best)** | 1.84 ms (3.24×) | 592.6 µs |
| minmax(100k) | list[int] -> tuple | 1.10 ms (1.69×) | 652.1 µs **(best)** | 1.29 ms (1.97×) | 1.90 ms |
| reverse3([1,2,3]) | fixed array in/out | 203 ns (1.14×) | 209 ns (1.17×) | 178 ns **(best)** | 123 ns |
| checksum(100kB) | bytes -> native, no copy | 13.4 µs **(best)** | 40.1 µs (2.99×) | 40.0 µs (2.98×) | 2.27 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.7 µs (1.96×) | 1.9 µs **(best)** | 1.9 µs (1.01×) | 2.0 µs |
| join_strings(10k) | list[str] -> native -> str | 491.8 µs (1.69×) | 290.6 µs **(best)** | 295.1 µs (1.02×) | 72.8 µs |
| expect_positive(err) | raise + catch per call | 219 ns **(best)** | 228 ns (1.04×) | 228 ns (1.04×) | 231 ns |
| Counter() | object construction | 102 ns (1.36×) | 105 ns (1.40×) | 75 ns **(best)** | 93 ns |
| c.increment() | method call | 47 ns **(best)** | 82 ns (1.76×) | 60 ns (1.29×) | 55 ns |
| c.add(1) | method call with an argument | 67 ns **(best)** | 101 ns (1.51×) | 74 ns (1.11×) | 54 ns |
| c.value | attribute read | 47 ns (1.45×) | 72 ns (2.23×) | 32 ns **(best)** | 12 ns |
| c.is_zero | property read | 35 ns **(best)** | 70 ns (1.98×) | 47 ns (1.31×) | 37 ns |
| c == c | rich comparison | 47 ns (1.24×) | 38 ns **(best)** | 49 ns (1.28×) | 71 ns |
| list(Countdown()) | construct and iterate | 345 ns (1.29×) | 638 ns (2.38×) | 268 ns **(best)** | 565 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 952 KiB | 868 KiB | 424 KiB | 24 KiB |
| import time (warm, median) | 0.54 ms | 0.71 ms | 0.22 ms | 0.14 ms |
| import time (first after install) | 0.72 ms | 0.71 ms | 0.24 ms | 2.01 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 31.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 31.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 32.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 31.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 36.6 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 39.8 MiB peak · 3.8 MiB kept · 0.5 MiB leak | 36.0 MiB peak · 1.5 MiB kept · 0.0 MiB leak | 35.1 MiB peak · 1.5 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 41.7 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 51.3 MiB peak · 9.6 MiB kept · 0.0 MiB leak | 41.3 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 40.5 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 32.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 32.9 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 32.3 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 31.7 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 32.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 32.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.3 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 32.2 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 32.2 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 31.5 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 31.7 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 31.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| histogram(new 1k words) x500 | 32.5 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 33.1 MiB peak · 1.1 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 31.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 32.5 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 31.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| expect_positive(-1) x500k | 31.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 31.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(wrong elem) x200k | 32.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 32.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 31.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 31.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
| 1 | 0.162 s (1.0×) | 0.160 s (1.0×) | 0.161 s (1.0×) | — |
| 2 | 0.186 s (1.7×) | 0.196 s (1.6×) | 0.191 s (1.7×) | — |
| 4 | 0.190 s (3.4×) | 0.202 s (3.2×) | 0.193 s (3.3×) | — |
| 8 | 0.229 s (5.6×) | 0.205 s (6.2×) | 0.203 s (6.3×) | — |

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
