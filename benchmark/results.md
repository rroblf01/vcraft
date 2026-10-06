Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 188 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.4 s | 2.1 s | 8.6 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns (1.28×) | 23 ns **(best)** | 203 ns (8.99×) | 15 ns |
| fib(25) | pure compute, recursion | 122.4 µs (1.02×) | 120.0 µs **(best)** | 159.0 µs (1.32×) | 5.15 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.03 ms (1.37×) | 3.78 ms (2.55×) | 1.48 ms **(best)** | 42.39 ms |
| sum_floats(100k) | list[float] -> native | 452.2 µs **(best)** | 961.4 µs (2.13×) | 496.2 µs (1.10×) | 777.6 µs |
| make_range(100k) | native -> list[int] | 825.8 µs **(best)** | 1.10 ms (1.33×) | 836.9 µs (1.01×) | 776.4 µs |
| greet | str in, new str out | 60 ns (1.73×) | 35 ns **(best)** | 279 ns (8.08×) | 33 ns |
| Counter() | object construction | 37 ns (1.07×) | 34 ns **(best)** | 202 ns (5.94×) | 37 ns |
| c.increment() | method call | 19 ns (1.22×) | 16 ns **(best)** | 197 ns (12.44×) | 25 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,104 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.52 ms | 3.48 ms | 0.58 ms | 0.06 ms |
| import time (first after install) | 159.39 ms | 119.15 ms | 80.93 ms | 0.08 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.7 MiB peak · 13.8 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.8 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 51.4 MiB peak · 18.5 MiB kept · 0.0 MiB leak | 31.0 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 52.6 MiB peak · 15.1 MiB kept · 0.0 MiB leak | 36.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.6 MiB peak · 12.9 MiB kept · 0.9 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
