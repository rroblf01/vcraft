# Benchmarks

Every number here can be reproduced from the repository: the harness, the three
equivalent projects (PyO3, vcraft, zig-maturin) and a pure-Python reference are in
[`benchmark/`](https://github.com/rroblf01/vcraft/tree/main/benchmark), and each stored
run records the toolchain that produced it.

## vcraft 1.8.0 against PyO3 0.29

Linux x86_64, CPython 3.13, release builds of both (`cargo --release`,
`vcraft build --release`), both keeping bounds checks. Measured with `benchmark/ab.py`,
five interleaved rounds, best figure per variant. Time per call, lower is better; the
last column below 1.00 means vcraft is faster.

| workload | PyO3 | vcraft | vcraft/PyO3 |
|---|---|---|---|
| add | 69 ns | 60 ns | 0.87× |
| fib(25) | 227.6 µs | 109.5 µs | 0.48× |
| count_primes(1e6) | 1.93 ms | 2.12 ms | 1.10× |
| sum_floats(100k) | 833.3 µs | 234.8 µs | 0.28× |
| make_range(100k) | 2.18 ms | 2.30 ms | 1.05× |
| greet | 131 ns | 108 ns | 0.83× |
| describe(3) | 165 ns | 121 ns | 0.73× |
| histogram(10k) | 718.4 µs | 570.9 µs | 0.79× |
| minmax(100k) | 1.09 ms | 555.9 µs | 0.51× |
| reverse3([1,2,3]) | 193 ns | 157 ns | 0.81× |
| checksum(100kB) | 13.5 µs | 12.7 µs | 0.94× |
| echo_bytes(100kB) | 3.6 µs | 1.8 µs | 0.49× |
| join_strings(10k) | 483.5 µs | 300.5 µs | 0.62× |
| expect_positive(err) | 218 ns | 209 ns | 0.96× |
| Counter() | 94 ns | 70 ns | 0.74× |
| c.increment() | 57 ns | 44 ns | 0.78× |
| c.add(1) | 62 ns | 57 ns | 0.92× |
| c.value | 46 ns | 41 ns | 0.89× |
| c.is_zero | 36 ns | 38 ns | 1.08× |
| c == c | 47 ns | 26 ns | 0.57× |
| list(Countdown()) | 348 ns | 237 ns | 0.68× |
| Vector(1000) | 221 ns | 221 ns | 1.00× |
| vector.total() | 786 ns | 792 ns | 1.01× |
| complex_scale(1+2j, 3) | 89 ns | 83 ns | 0.93× |
| Counter.zero() | 59 ns | 53 ns | 0.90× |
| import (median of 30) | 0.591 ms | 0.592 ms | 1.00× |

vcraft is faster on 20 of the 26 rows, level on three, and slower on three:
`count_primes` (10%, a tight sieve loop with a 1 MB allocation), `make_range` (5%, within
the noise of long loops) and the `c.is_zero` property read (2 ns). The large leads are on
the conversion paths (`sum_floats`, `minmax`, `echo_bytes`, `join_strings`) and on the
recursive `fib`.

## How to read a difference

Two builds of the same code differ by up to about 5% on short calls and about 10% on long
loops from one run to the next on the same machine. A single `run.sh` cannot resolve a
difference smaller than that, which is why comparisons are made with `ab.py`: it runs
every variant round after round, interleaved, and keeps each one's best time, so load or
frequency changes hit all variants alike.

## Reproducing

```console
$ cd benchmark
$ ./run.sh                    # builds all three, installs into benchmark/.venv, measures
$ ./run.sh --quick            # fewer repeats, to check the harness
$ python ab.py pyo3=.venv/bin/python:bench_pyo3 \
               vcraft=.venv/bin/python:bench_vcraft_native --rounds 5
```

`run.sh` needs `uv`, `cargo` and a `v` built at the pinned commit on `PATH` (zig 0.16 is
optional); it installs nothing outside `benchmark/.venv`. Besides speed it measures peak
and retained memory (each scenario twice, so a leak shows as growth), import time, wheel
and binary size, a correctness matrix of edge cases, reference retention, and GIL-free
scaling across threads.

The full tables, including memory, size and the history of every optimisation, are in
[`benchmark/results-linux.md`](https://github.com/rroblf01/vcraft/blob/main/benchmark/results-linux.md)
and [`benchmark/HISTORY.md`](https://github.com/rroblf01/vcraft/blob/main/benchmark/HISTORY.md).
