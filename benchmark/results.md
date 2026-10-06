Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 222 KiB | 193 KiB | 187 KiB |
| extension (as built) | 552 KiB | 406 KiB | 484 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 401 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.6 s | 2.1 s | 8.7 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 28 ns (1.23×) | 23 ns **(best)** | 203 ns (8.90×) | 16 ns |
| fib(25) | pure compute, recursion | 121.7 µs (1.02×) | 119.9 µs **(best)** | 154.9 µs (1.29×) | 5.17 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.02 ms (1.39×) | 3.77 ms (2.60×) | 1.45 ms **(best)** | 42.30 ms |
| sum_floats(100k) | list[float] -> native | 455.8 µs (3.47×) | 131.3 µs **(best)** | 497.1 µs (3.78×) | 775.1 µs |
| make_range(100k) | native -> list[int] | 830.7 µs **(best)** | 999.9 µs (1.20×) | 842.1 µs (1.01×) | 776.2 µs |
| greet | str in, new str out | 54 ns (1.56×) | 35 ns **(best)** | 261 ns (7.55×) | 32 ns |
| checksum(100kB) | bytes -> native, no copy | 1.7 µs **(best)** | 4.8 µs (2.84×) | 25.6 µs (15.12×) | 984.3 µs |
| expect_positive(err) | raise + catch per call | 103 ns (1.09×) | 94 ns **(best)** | 279 ns (2.97×) | 124 ns |
| Counter() | object construction | 37 ns (1.08×) | 34 ns **(best)** | 199 ns (5.79×) | 38 ns |
| c.increment() | method call | 19 ns (1.22×) | 16 ns **(best)** | 195 ns (12.26×) | 25 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,136 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.53 ms | 0.62 ms | 0.58 ms | 0.07 ms |
| import time (first after install) | 165.74 ms | 245.43 ms | 114.92 ms | 0.87 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.5 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 32.0 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 34.0 MiB peak · 1.1 MiB kept · 0.0 MiB leak | 31.0 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.8 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 29.3 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 27.4 MiB peak · 0.3 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.6 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
