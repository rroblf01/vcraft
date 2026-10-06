Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 188 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.7 s | 2.0 s | 8.6 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns (1.26×) | 23 ns **(best)** | 204 ns (8.88×) | 16 ns |
| fib(25) | pure compute, recursion | 121.9 µs (1.02×) | 119.0 µs **(best)** | 162.6 µs (1.37×) | 5.19 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.02 ms (1.37×) | 3.73 ms (2.53×) | 1.48 ms **(best)** | 42.72 ms |
| sum_floats(100k) | list[float] -> native | 452.1 µs (3.36×) | 134.6 µs **(best)** | 499.6 µs (3.71×) | 781.3 µs |
| make_range(100k) | native -> list[int] | 837.4 µs **(best)** | 1.00 ms (1.20×) | 843.8 µs (1.01×) | 782.6 µs |
| greet | str in, new str out | 54 ns (1.62×) | 34 ns **(best)** | 262 ns (7.80×) | 33 ns |
| Counter() | object construction | 36 ns (1.05×) | 34 ns **(best)** | 202 ns (5.86×) | 38 ns |
| c.increment() | method call | 20 ns (1.23×) | 16 ns **(best)** | 197 ns (12.25×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,104 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.54 ms | 0.63 ms | 0.61 ms | 0.07 ms |
| import time (first after install) | 162.48 ms | 213.69 ms | 123.85 ms | 0.33 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.2 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 26.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 34.3 MiB peak · 1.1 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.9 MiB peak · -0.4 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 36.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.8 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 29.5 MiB peak · 1.4 MiB kept · 0.0 MiB leak | 27.5 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 27.4 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.9 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
