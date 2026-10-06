Python 3.13.15 · arm64 · macOS-27.0-arm64-arm-64bit-Mach-O

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 225 KiB | 195 KiB | 188 KiB |
| extension (as built) | 554 KiB | 407 KiB | 485 KiB |
| extension (strip -x) | 414 KiB | 351 KiB | 401 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 5.2 s | 2.2 s | 8.5 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 28 ns (1.23×) | 23 ns **(best)** | 203 ns (9.01×) | 16 ns |
| fib(25) | pure compute, recursion | 120.2 µs (1.01×) | 119.4 µs **(best)** | 158.7 µs (1.33×) | 5.19 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 2.01 ms (1.39×) | 3.76 ms (2.61×) | 1.44 ms **(best)** | 41.60 ms |
| sum_floats(100k) | list[float] -> native | 456.6 µs (3.41×) | 133.9 µs **(best)** | 498.1 µs (3.72×) | 778.0 µs |
| make_range(100k) | native -> list[int] | 830.8 µs **(best)** | 997.5 µs (1.20×) | 840.7 µs (1.01×) | 783.8 µs |
| greet | str in, new str out | 54 ns (1.57×) | 34 ns **(best)** | 262 ns (7.68×) | 33 ns |
| checksum(100kB) | bytes -> native, no copy | 1.7 µs **(best)** | 4.8 µs (2.85×) | 25.5 µs (15.13×) | 980.3 µs |
| echo_bytes(100kB) | bytes in, fresh copy out | 4.2 µs (2.73×) | 1.5 µs **(best)** | 1.7 µs (1.14×) | 1.6 µs |
| join_strings(10k) | list[str] -> native -> str | 204.1 µs (1.60×) | 172.5 µs (1.35×) | 127.4 µs **(best)** | 45.2 µs |
| expect_positive(err) | raise + catch per call | 108 ns (1.16×) | 93 ns **(best)** | 277 ns (2.99×) | 124 ns |
| Counter() | object construction | 37 ns (1.08×) | 34 ns **(best)** | 200 ns (5.80×) | 38 ns |
| c.increment() | method call | 19 ns (1.22×) | 16 ns **(best)** | 195 ns (12.28×) | 26 ns |
| c.add(1) | method call with an argument | 28 ns (1.30×) | 22 ns **(best)** | 204 ns (9.41×) | 26 ns |
| c.value | attribute read | 21 ns (1.39×) | 15 ns **(best)** | 15 ns (1.02×) | 5 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 304 KiB | 1,120 KiB | 144 KiB | 0 KiB |
| import time (warm, median) | 0.53 ms | 0.61 ms | 0.58 ms | 0.07 ms |
| import time (first after install) | 50.81 ms | 161.70 ms | 120.20 ms | 0.90 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 28.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.2 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 32.6 MiB peak · 0.6 MiB kept · 0.0 MiB leak | 34.1 MiB peak · 1.4 MiB kept · 0.0 MiB leak | 31.8 MiB peak · 0.6 MiB kept · 0.0 MiB leak | 31.5 MiB peak · 0.6 MiB kept · 0.0 MiB leak |
| count_primes(10M) x5 | 37.5 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 38.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 37.2 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 28.5 MiB peak · 0.4 MiB kept · 0.0 MiB leak | 30.0 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 28.2 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.3 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 28.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 28.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.0 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.9 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 28.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 29.5 MiB peak · 0.8 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.9 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| Counter() x1M | 27.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 29.2 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
