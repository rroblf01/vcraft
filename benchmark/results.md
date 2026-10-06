Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 188 KiB | 186 KiB |
| extension (as built) | 550 KiB | 404 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.6 s | 2.1 s | 8.6 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns **(best)** | 40 ns (1.37×) | 202 ns (6.96×) | 15 ns |
| fib(25) | pure compute, recursion | 119.7 µs (1.01×) | 118.6 µs **(best)** | 160.9 µs (1.36×) | 5.25 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.99 ms (1.40×) | 3.76 ms (2.64×) | 1.42 ms **(best)** | 41.39 ms |
| sum_floats(100k) | list[float] -> native | 450.9 µs **(best)** | 969.6 µs (2.15×) | 496.5 µs (1.10×) | 776.9 µs |
| make_range(100k) | native -> list[int] | 826.6 µs **(best)** | 1.09 ms (1.31×) | 843.9 µs (1.02×) | 773.2 µs |
| greet | str in, new str out | 61 ns (1.58×) | 39 ns **(best)** | 278 ns (7.16×) | 32 ns |
| Counter() | object construction | 36 ns (1.06×) | 34 ns **(best)** | 199 ns (5.80×) | 38 ns |
| c.increment() | method call | 19 ns **(best)** | 29 ns (1.52×) | 195 ns (10.07×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,088 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.52 ms | 3.49 ms | 0.57 ms | 0.06 ms |
| import time (first after install) | 158.95 ms | 235.46 ms | 98.05 ms | 0.08 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.8 MiB peak · 13.8 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 51.5 MiB peak · 18.5 MiB kept · 0.0 MiB leak | 31.0 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 52.4 MiB peak · 14.7 MiB kept · 0.0 MiB leak | 36.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.6 MiB peak · 12.9 MiB kept · 0.9 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
