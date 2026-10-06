Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 189 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.7 s | 2.1 s | 8.4 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns **(best)** | 41 ns (1.43×) | 206 ns (7.16×) | 16 ns |
| fib(25) | pure compute, recursion | 121.0 µs (1.03×) | 117.9 µs **(best)** | 163.6 µs (1.39×) | 5.20 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.00 ms (1.39×) | 3.76 ms (2.62×) | 1.43 ms **(best)** | 42.23 ms |
| sum_floats(100k) | list[float] -> native | 450.9 µs **(best)** | 968.4 µs (2.15×) | 496.4 µs (1.10×) | 775.1 µs |
| make_range(100k) | native -> list[int] | 833.1 µs **(best)** | 1.10 ms (1.32×) | 841.3 µs (1.01×) | 774.7 µs |
| greet | str in, new str out | 60 ns (1.56×) | 39 ns **(best)** | 275 ns (7.11×) | 33 ns |
| Counter() | object construction | 36 ns (1.04×) | 35 ns **(best)** | 200 ns (5.78×) | 39 ns |
| c.increment() | method call | 19 ns **(best)** | 29 ns (1.53×) | 194 ns (10.14×) | 27 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,088 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.51 ms | 3.50 ms | 0.57 ms | 0.06 ms |
| import time (first after install) | 48.61 ms | 239.68 ms | 101.89 ms | 0.94 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.8 MiB peak · 13.8 MiB kept · 0.0 MiB leak | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 1,594.2 MiB peak · 789.9 MiB kept · 771.8 MiB leak | 30.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 36.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 52.2 MiB peak · 14.7 MiB kept · 0.0 MiB leak | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.7 MiB peak · 12.9 MiB kept · 0.9 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
