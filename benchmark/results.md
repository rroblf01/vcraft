Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 189 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.3 s | 2.0 s | 8.4 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns (1.29×) | 22 ns **(best)** | 202 ns (9.10×) | 16 ns |
| fib(25) | pure compute, recursion | 121.0 µs (1.02×) | 118.8 µs **(best)** | 159.3 µs (1.34×) | 5.20 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.02 ms (1.41×) | 3.70 ms (2.58×) | 1.43 ms **(best)** | 41.99 ms |
| sum_floats(100k) | list[float] -> native | 450.7 µs (3.38×) | 133.1 µs **(best)** | 515.3 µs (3.87×) | 779.3 µs |
| make_range(100k) | native -> list[int] | 828.9 µs **(best)** | 987.9 µs (1.19×) | 838.3 µs (1.01×) | 783.0 µs |
| greet | str in, new str out | 60 ns (1.78×) | 34 ns **(best)** | 277 ns (8.15×) | 32 ns |
| Counter() | object construction | 36 ns (1.04×) | 35 ns **(best)** | 199 ns (5.73×) | 39 ns |
| c.increment() | method call | 19 ns (1.21×) | 16 ns **(best)** | 194 ns (12.23×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,120 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.50 ms | 0.61 ms | 0.55 ms | 0.06 ms |
| import time (first after install) | 163.88 ms | 209.76 ms | 102.01 ms | 0.09 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.0 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 35.1 MiB peak · 1.8 MiB kept · 0.0 MiB leak | 30.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 37.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.7 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 29.6 MiB peak · 1.4 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 27.3 MiB peak · 0.3 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.9 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
| add 2**63 overflows | ok | ok | `TypeError: expected int, got int` | n/a |
