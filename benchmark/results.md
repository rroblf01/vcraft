Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 222 KiB | 192 KiB | 187 KiB |
| extension (as built) | 552 KiB | 406 KiB | 484 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 401 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.6 s | 2.1 s | 8.7 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 28 ns (1.24×) | 22 ns **(best)** | 204 ns (9.06×) | 16 ns |
| fib(25) | pure compute, recursion | 122.3 µs (1.02×) | 119.7 µs **(best)** | 155.1 µs (1.30×) | 5.50 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.02 ms (1.38×) | 3.78 ms (2.57×) | 1.47 ms **(best)** | 41.92 ms |
| sum_floats(100k) | list[float] -> native | 457.8 µs (3.54×) | 129.3 µs **(best)** | 496.9 µs (3.84×) | 780.9 µs |
| make_range(100k) | native -> list[int] | 828.9 µs **(best)** | 997.9 µs (1.20×) | 847.9 µs (1.02×) | 777.6 µs |
| greet | str in, new str out | 54 ns (1.57×) | 34 ns **(best)** | 262 ns (7.66×) | 32 ns |
| checksum(100kB) | bytes -> native, no copy | 1.7 µs **(best)** | 4.8 µs (2.85×) | 25.7 µs (15.20×) | 988.3 µs |
| expect_positive(err) | raise + catch per call | 112 ns (1.21×) | 93 ns **(best)** | 277 ns (3.00×) | 124 ns |
| Counter() | object construction | 37 ns (1.07×) | 35 ns **(best)** | 201 ns (5.82×) | 38 ns |
| c.increment() | method call | 19 ns (1.20×) | 16 ns **(best)** | 196 ns (12.29×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,136 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.52 ms | 0.62 ms | 0.58 ms | 0.07 ms |
| import time (first after install) | 168.58 ms | 96.81 ms | 124.53 ms | 0.86 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.3 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 34.9 MiB peak · 1.8 MiB kept · 0.0 MiB leak | 30.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.9 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 29.8 MiB peak · 1.4 MiB kept · 0.0 MiB leak | 27.7 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 27.5 MiB peak · 0.3 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 27.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.1 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

### Correctness

| check | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| add small | ok | ok | ok | ok |
| add 2**40 | ok | ok | ok | ok |
| fib(20) | ok | ok | ok | ok |
| count_primes(100) | ok | ok | ok | ok |
| sum_floats | ok | ok | ok | ok |
| make_range(3) | ok | ok | ok | ok |
| greet unicode | ok | ok | ok | ok |
| checksum 3 bytes | ok | ok | ok | ok |
| expect_positive ok | ok | ok | ok | ok |
| expect_positive raises | ok | ok | ok | ok |
| add 2**63 overflows | ok | ok | `TypeError: expected int, got int` | n/a |
