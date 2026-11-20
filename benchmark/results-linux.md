Python 3.13.16 · x86_64 · Linux-6.18.64-1-lts-x86_64-with-glibc2.44

Toolchain: vcraft 1.8.0 · V 36be926 · PyO3 0.29.0 · maturin 1.15.0 · zig-maturin 1.0.1 · pybind11 3.1.0 · zig 0.17.1 · c++ c++ (GCC) 16.2.1 20260810

### Package size

| | pyo3 | vcraft | pybind11 |
|---|---|---|---|
| wheel | 279 KiB | 293 KiB | 155 KiB |
| extension (as built) | 688 KiB | 658 KiB | 411 KiB |
| extension (strip -x) | 508 KiB | 578 KiB | 328 KiB |
| files in wheel | 6 | 5 | 5 |
| clean release build | 9.1 s | 14.1 s | 10.2 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|---|
| add | call overhead | 73 ns (1.18×) | 62 ns **(best)** | 79 ns (1.27×) | 36 ns |
| fib(25) | pure compute, recursion | 221.3 µs (2.08×) | 106.2 µs **(best)** | 112.0 µs (1.05×) | 9.07 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.99 ms **(best)** | 2.12 ms (1.07×) | 2.31 ms (1.16×) | 94.44 ms |
| sum_floats(100k) | list[float] -> native | 842.1 µs (3.68×) | 228.8 µs **(best)** | 840.9 µs (3.68×) | 1.58 ms |
| make_range(100k) | native -> list[int] | 2.25 ms **(best)** | 2.28 ms (1.01×) | 2.98 ms (1.33×) | 2.15 ms |
| greet | str in, new str out | 135 ns (1.22×) | 111 ns **(best)** | 125 ns (1.12×) | 71 ns |
| describe(3) | keyword/default binding | 168 ns (1.34×) | 125 ns **(best)** | 225 ns (1.79×) | 159 ns |
| maybe_double(21) | optional in/out | 66 ns (1.43×) | 46 ns **(best)** | 65 ns (1.41×) | 37 ns |
| histogram(10k) | list[str] -> dict | 686.2 µs (1.81×) | 582.2 µs (1.54×) | 378.9 µs **(best)** | 618.5 µs |
| minmax(100k) | list[int] -> tuple | 1.08 ms (1.95×) | 550.7 µs **(best)** | 1.06 ms (1.92×) | 1.88 ms |
| reverse3([1,2,3]) | fixed array in/out | 197 ns (1.30×) | 152 ns **(best)** | 216 ns (1.42×) | 127 ns |
| checksum(100kB) | bytes -> native, no copy | 13.7 µs (1.09×) | 12.6 µs **(best)** | 12.8 µs (1.01×) | 2.19 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.5 µs (2.01×) | 1.7 µs **(best)** | 1.8 µs (1.03×) | 1.9 µs |
| join_strings(10k) | list[str] -> native -> str | 466.3 µs (1.82×) | 256.4 µs **(best)** | 279.0 µs (1.09×) | 71.0 µs |
| expect_positive(err) | raise + catch per call | 217 ns (1.02×) | 212 ns **(best)** | 3.1 µs (14.68×) | 223 ns |
| Counter() | object construction | 96 ns (1.54×) | 62 ns **(best)** | 249 ns (4.00×) | 103 ns |
| c.increment() | method call | 55 ns (1.31×) | 42 ns **(best)** | 136 ns (3.23×) | 52 ns |
| c.add(1) | method call with an argument | 65 ns (1.20×) | 54 ns **(best)** | 155 ns (2.90×) | 53 ns |
| c.value | attribute read | 46 ns (1.38×) | 33 ns **(best)** | 107 ns (3.26×) | 12 ns |
| c.is_zero | property read | 35 ns (1.07×) | 33 ns **(best)** | 78 ns (2.36×) | 37 ns |
| c == c | rich comparison | 48 ns (1.95×) | 24 ns **(best)** | 144 ns (5.89×) | 71 ns |
| list(Countdown()) | construct and iterate | 337 ns (1.41×) | 239 ns **(best)** | 4.3 µs (17.84×) | 584 ns |
| Vector(1000) | class with a native buffer | 226 ns (1.04×) | 217 ns **(best)** | 397 ns (1.83×) | 2.3 µs |
| vector.total() | native buffer sum in V | 763 ns **(best)** | 763 ns (1.00×) | 862 ns (1.13×) | 5.9 µs |
| complex_scale(1+2j, 3) | complex in and out | 93 ns (1.13×) | 82 ns **(best)** | 97 ns (1.19×) | 61 ns |
| Counter.zero() | static method | 58 ns **(best)** | 58 ns (1.01×) | 65 ns (1.13×) | 40 ns |

### Memory

| | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|
| RSS added by `import` | 864 KiB | 1,008 KiB | 2,672 KiB | 28 KiB |
| import time (warm, median) | 0.51 ms | 0.60 ms | 1.35 ms | 0.17 ms |
| import time (first after install) | 0.92 ms | 0.70 ms | 1.40 ms | 0.17 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|
| greet x2M | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 36.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 39.0 MiB peak · -0.1 MiB kept · 0.0 MiB leak | 42.4 MiB peak · 4.7 MiB kept · 0.0 MiB leak | 41.1 MiB peak · 0.9 MiB kept · 0.0 MiB leak | 37.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 43.9 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 73.0 MiB peak · 28.8 MiB kept · 0.2 MiB leak | 37.4 MiB peak · 1.2 MiB kept · 0.0 MiB leak | 42.9 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 34.7 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 35.4 MiB peak · 0.7 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 34.5 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.7 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 36.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 34.8 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 34.8 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 36.3 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 35.1 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 36.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| histogram(new 1k words) x500 | 34.9 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 35.3 MiB peak · 0.7 MiB kept · 0.0 MiB leak | 36.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Vector(1000) x500 | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 35.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| expect_positive(-1) x500k | 34.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.9 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 36.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(wrong elem) x200k | 34.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.7 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 35.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

### Reference retention

Each probe calls the same borrowed argument many times in one process and
reports the change in `sys.getrefcount` of the argument (or of an item it
was handed). **0 is correct**; a positive number is one leaked reference per
call, which a heap that has plateaued hides from the memory table.

| probe | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|
| sum_floats: borrowed list | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| sum_floats: borrowed elements | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed bytes | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed bytearray | unsupported | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| checksum: borrowed memoryview | unsupported | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| echo_bytes: borrowed argument | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |
| method: borrowed self | **0** (3→3) | **0** (3→3) | **0** (3→3) | **0** (3→3) |

### Thread scaling

Each thread runs `lcg(2_000_000)` 64 times; wall seconds, and
parallel speedup over one thread. A binding that releases the GIL scales close
to the core count. The pure-Python reference cannot release the GIL, so it is
not measured here.

| threads | pyo3 | vcraft | pybind11 | python |
|---|---|---|---|---|
| 1 | 0.169 s (1.0×) | 0.167 s (1.0×) | 0.168 s (1.0×) | — |
| 2 | 0.168 s (2.0×) | 0.169 s (2.0×) | 0.169 s (2.0×) | — |
| 4 | 0.172 s (3.9×) | 0.168 s (4.0×) | 0.168 s (4.0×) | — |
| 8 | 0.222 s (6.1×) | 0.174 s (7.6×) | 0.206 s (6.5×) | — |

### Correctness

| check | pyo3 | vcraft | pybind11 | python |
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
| add 2**63 overflows | ok | ok | `TypeError: add(): incompatible function arguments. The following argument types are supported:` | n/a |
| add 2**64-1 overflows | ok | ok | `TypeError: add(): incompatible function arguments. The following argument types are supported:` | n/a |
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
| make_range negative | ok | `RuntimeError: panic in V code: negative .cap:-1` | ok | ok |
| make_range float rejected | ok | ok | ok | ok |
| greet empty | ok | ok | ok | ok |
| greet unicode | ok | ok | ok | ok |
| greet emoji | ok | ok | ok | ok |
| greet embedded NUL | ok | ok | ok | ok |
| greet int rejected | ok | ok | ok | n/a |
| greet bytes rejected | ok | ok | `wrong: 'Hello, x!'` | n/a |
| describe defaults | ok | ok | ok | ok |
| describe all positional | ok | ok | ok | ok |
| describe keyword label | ok | ok | ok | ok |
| describe keyword unit | ok | ok | ok | ok |
| describe mixed kw and pos | ok | ok | ok | ok |
| describe missing required | ok | ok | ok | ok |
| describe unknown keyword | ok | ok | ok | ok |
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
| checksum memoryview | n/a | ok | ok | ok |
| checksum array | n/a | ok | ok | ok |
| checksum str rejected | ok | ok | ok | ok |
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
| complex round trip | ok | ok | ok | ok |
| complex real coerced | ok | ok | ok | ok |
| complex wrong type | ok | ok | ok | n/a |
| static method on the class | ok | ok | ok | ok |
| static method on an instance | ok | ok | ok | ok |
