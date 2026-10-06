Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | 189 KiB | 186 KiB |
| extension (as built) | 550 KiB | 405 KiB | 483 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 400 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.2 s | 2.1 s | 8.4 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 29 ns (1.28×) | 22 ns **(best)** | 203 ns (9.01×) | 16 ns |
| fib(25) | pure compute, recursion | 121.7 µs (1.02×) | 119.3 µs **(best)** | 164.7 µs (1.38×) | 5.20 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.03 ms (1.41×) | 3.78 ms (2.63×) | 1.44 ms **(best)** | 42.18 ms |
| sum_floats(100k) | list[float] -> native | 450.6 µs (2.95×) | 152.7 µs **(best)** | 495.3 µs (3.24×) | 776.6 µs |
| make_range(100k) | native -> list[int] | 824.1 µs **(best)** | 1.10 ms (1.33×) | 842.1 µs (1.02×) | 779.9 µs |
| greet | str in, new str out | 60 ns (1.75×) | 35 ns **(best)** | 277 ns (8.02×) | 33 ns |
| Counter() | object construction | 36 ns (1.06×) | 34 ns **(best)** | 199 ns (5.88×) | 39 ns |
| c.increment() | method call | 19 ns (1.20×) | 16 ns **(best)** | 195 ns (12.24×) | 26 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,120 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.51 ms | 3.48 ms | 0.58 ms | 0.07 ms |
| import time (first after install) | 160.91 ms | 119.04 ms | 108.16 ms | 0.07 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.7 MiB peak · 13.8 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.6 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 51.4 MiB peak · 18.5 MiB kept · 0.0 MiB leak | 30.8 MiB peak · -0.4 MiB kept · 0.0 MiB leak | 30.9 MiB peak · -0.4 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 36.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 42.6 MiB peak · 5.1 MiB kept · 0.0 MiB leak | 36.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 36.4 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.5 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 43.9 MiB peak · 15.7 MiB kept · 0.0 MiB leak | 27.5 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 27.3 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 41.7 MiB peak · 12.9 MiB kept · 0.9 MiB leak | 27.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
