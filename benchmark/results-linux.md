Python 3.13.13 · x86_64 · Linux-6.18.55-1-lts-x86_64-with-glibc2.44

### Package size

| | pyo3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 259 KiB | 268 KiB | 986 KiB |
| extension (as built) | 622 KiB | 508 KiB | 3,458 KiB |
| extension (strip -x) | 464 KiB | 448 KiB | 569 KiB |
| files in wheel | 6 | 4 | 4 |
| clean release build | 10.8 s | 12.0 s | 23.4 s |

### Speed (time per call, lower is better; best of repeats)

| workload | measures | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|---|
| add | call overhead | 73 ns (1.12×) | 65 ns **(best)** | 87 ns (1.34×) | 37 ns |
| fib(25) | pure compute, recursion | 202.6 µs (1.89×) | 107.2 µs **(best)** | 323.2 µs (3.01×) | 9.41 ms |
| count_primes(1e6) | compute + 1 MB native alloc | 1.95 ms (1.03×) | 2.37 ms (1.25×) | 1.89 ms **(best)** | 96.80 ms |
| sum_floats(100k) | list[float] -> native | 889.0 µs (3.84×) | 231.4 µs **(best)** | 1.13 ms (4.89×) | 1.53 ms |
| make_range(100k) | native -> list[int] | 2.33 ms (1.03×) | 2.75 ms (1.21×) | 2.28 ms **(best)** | 2.34 ms |
| greet | str in, new str out | 138 ns (1.07×) | 129 ns **(best)** | 224 ns (1.74×) | 75 ns |
| checksum(100kB) | bytes -> native, no copy | 13.6 µs **(best)** | 41.9 µs (3.08×) | 39.4 µs (2.89×) | 2.17 ms |
| echo_bytes(100kB) | bytes in, fresh copy out | 3.7 µs (2.09×) | 1.8 µs **(best)** | 1.8 µs (1.02×) | 2.0 µs |
| join_strings(10k) | list[str] -> native -> str | 536.3 µs (1.83×) | 304.7 µs (1.04×) | 292.8 µs **(best)** | 72.2 µs |
| expect_positive(err) | raise + catch per call | 221 ns **(best)** | 231 ns (1.05×) | 222 ns (1.01×) | 231 ns |
| Counter() | object construction | 96 ns (1.25×) | 93 ns (1.22×) | 77 ns **(best)** | 83 ns |
| c.increment() | method call | 52 ns (1.04×) | 49 ns **(best)** | 66 ns (1.33×) | 58 ns |
| c.add(1) | method call with an argument | 65 ns (1.05×) | 62 ns **(best)** | 87 ns (1.40×) | 63 ns |
| c.value | attribute read | 48 ns (1.52×) | 33 ns (1.05×) | 32 ns **(best)** | 12 ns |

### Memory

| | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| RSS added by `import` | 648 KiB | 684 KiB | 220 KiB | 4 KiB |
| import time (warm, median) | 0.48 ms | 0.81 ms | 0.23 ms | 0.11 ms |
| import time (first after install) | 1.10 ms | 0.72 ms | 0.23 ms | 1.76 ms |

Each scenario runs twice in a fresh process. *Peak* is the process's maximum
RSS; *kept* is what the first batch left resident after `gc.collect()`; *leak*
is what the identical second batch added on top, which is ~0 for a heap that
has plateaued.

| scenario | pyo3 | vcraft | zig-maturin | python |
|---|---|---|---|---|
| greet x2M | 27.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| make_range(100k) x200 | 31.9 MiB peak · 1.0 MiB kept · 0.0 MiB leak | 35.0 MiB peak · 3.9 MiB kept · 0.4 MiB leak | 31.3 MiB peak · 1.6 MiB kept · 0.0 MiB leak | 30.8 MiB peak · 1.6 MiB kept · -0.0 MiB leak |
| count_primes(10M) x5 | 37.0 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 56.4 MiB peak · 19.1 MiB kept · 0.0 MiB leak | 36.8 MiB peak · 9.5 MiB kept · 0.0 MiB leak | 36.5 MiB peak · 9.5 MiB kept · 0.0 MiB leak |
| sum_floats(new 10k list) x500 | 27.9 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 28.7 MiB peak · 1.1 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.4 MiB kept · 0.0 MiB leak |
| checksum(new 100kB) x500 | 27.5 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.5 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.8 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 26.5 MiB peak · 0.1 MiB kept · 0.0 MiB leak |
| echo_bytes(new 100kB) x500 | 27.8 MiB peak · 0.3 MiB kept · 0.0 MiB leak | 28.0 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.2 MiB kept · 0.0 MiB leak | 26.7 MiB peak · 0.2 MiB kept · 0.0 MiB leak |
| join_strings(new 1k strs) x500 | 27.1 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 28.1 MiB peak · 0.5 MiB kept · 0.0 MiB leak | 27.3 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak |
| Counter() x1M | 26.8 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.1 MiB kept · 0.0 MiB leak | 27.6 MiB peak · 0.0 MiB kept · 0.0 MiB leak | 26.7 MiB peak · 0.0 MiB kept · 0.0 MiB leak |

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
