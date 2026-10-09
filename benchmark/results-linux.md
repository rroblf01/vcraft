Python 3.13.13 · x86_64 · Linux-6.18.55-1-lts-x86_64-with-glibc2.44

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 259 KiB | 259 KiB | 986 KiB |
| extension (as built) | 622 KiB | 489 KiB | 3,458 KiB |
| extension (strip -x) | 464 KiB | 433 KiB | 569 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 8.0 s | 5.3 s | 16.6 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 72 ns **(best)** | 73 ns (1.02×) | 85 ns (1.18×) | 35 ns |
| fib(25) | pure compute, recursion | 205.5 µs (2.01×) | 102.4 µs **(best)** | 316.6 µs (3.09×) | 9.28 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.91 ms (1.02×) | 2.14 ms (1.14×) | 1.87 ms **(best)** | 92.73 ms |
| sum_floats(100k) | list[float] -> native | 859.0 µs (3.47×) | 247.8 µs **(best)** | 1.09 ms (4.39×) | 1.53 ms |
| make_range(100k) | native -> list[int] | 2.18 ms **(best)** | 2.31 ms (1.06×) | 2.23 ms (1.02×) | 2.22 ms |
| greet | str in, new str out | 135 ns (1.18×) | 114 ns **(best)** | 210 ns (1.84×) | 78 ns |
| checksum(100kB) | bytes -> native, no copy | 13.4 µs **(best)** | 39.4 µs (2.95×) | 40.3 µs (3.01×) | 2.21 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.7 µs (2.13×) | 1.8 µs **(best)** | 1.8 µs (1.05×) | 2.1 µs |
| join_strings(10k) | list[str] -> native -> str | 510.2 µs (1.78×) | 321.4 µs (1.12×) | 286.3 µs **(best)** | 71.5 µs |
| expect_positive(err) | raise + catch per call | 212 ns **(best)** | 230 ns (1.09×) | 219 ns (1.03×) | 225 ns |
| Counter() | object construction | 90 ns (1.15×) | 103 ns (1.32×) | 78 ns **(best)** | 79 ns |
| c.increment() | method call | 51 ns (1.06×) | 48 ns **(best)** | 68 ns (1.41×) | 59 ns |
| c.add(1) | method call with an argument | 68 ns (1.02×) | 66 ns **(best)** | 87 ns (1.31×) | 63 ns |
| c.value | attribute read | 49 ns (1.53×) | 34 ns (1.05×) | 32 ns **(best)** | 12 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 532 KiB | 716 KiB | 180 KiB | 4 KiB |
| import time (warm, median) | 0.44 ms | 0.66 ms | 0.19 ms | 0.10 ms |
| import time (first after install) | 1.51 ms | 0.67 ms | 0.20 ms | 0.10 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 28.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.4 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 28.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 32.8 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 35.4 MiB peak · 3.9 MiB kept · 0.4 MiB leak | 32.0 MiB peak · 1.6 MiB kept · 0.0 MiB leak | 31.4 MiB peak · 1.6 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 37.2 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 56.9 MiB peak · 19.1 MiB kept · 0.0 MiB leak | 37.4 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 36.9 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 28.5 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 29.1 MiB peak · 0.8 MiB kept · 0.0 MiB leak | 28.4 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 28.0 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 28.3 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 28.3 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 28.3 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 28.2 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 27.4 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 27.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.6 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 28.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 28.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.2 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
| echo_bytes round trip | ok | ok | ok | ok |
| join_strings 3 items | ok | ok | ok | ok |
| counter starts at 0 | ok | ok | ok | ok |
| counter add and value | ok | ok | ok | ok |
| expect_positive ok | ok | ok | ok | ok |
| expect_positive raises | ok | ok | ok | ok |
| add 2**63 overflows | ok | ok | `TypeError: expected int, got int` | n/a |
