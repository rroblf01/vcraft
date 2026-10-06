Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 189 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.3 s | 2.1 s | 8.5 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns (1.29×) | 22 ns **(best)** | 202 ns (9.05×) | 16 ns |
| fib(25) | pure compute, recursion | 122.0 µs (1.02×) | 119.2 µs **(best)** | 163.2 µs (1.37×) | 5.26 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.04 ms (1.41×) | 3.77 ms (2.61×) | 1.45 ms **(best)** | 42.02 ms |
| sum_floats(100k) | list[float] -> native | 451.6 µs **(best)** | 942.2 µs (2.09×) | 505.1 µs (1.12×) | 775.9 µs |
| make_range(100k) | native -> list[int] | 831.8 µs **(best)** | 1.10 ms (1.32×) | 842.3 µs (1.01×) | 782.9 µs |
| greet | str in, new str out | 60 ns (1.70×) | 35 ns **(best)** | 278 ns (7.86×) | 32 ns |
| Counter() | object construction | 36 ns (1.05×) | 35 ns **(best)** | 201 ns (5.78×) | 38 ns |
| c.increment() | method call | 19 ns **(best)** | 29 ns (1.52×) | 195 ns (10.09×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,104 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.53 ms | 3.48 ms | 0.58 ms | 0.06 ms |
| import time (first after install) | 166.18 ms | 123.98 ms | 124.97 ms | 0.08 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.9 MiB peak · 13.8 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.7 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 50.7 MiB peak · 17.8 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 42.6 MiB peak · 5.1 MiB kept · 0.0 MiB leak | 36.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.8 MiB peak · 12.9 MiB kept · 0.9 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
