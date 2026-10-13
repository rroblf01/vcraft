use pyo3::prelude::*;

/// Benchmark workloads written in Rust.
///
/// The same thirteen workloads as the vcraft and zig-maturin projects, with the same
/// semantics and 64-bit integers throughout.
#[pymodule]
mod bench_pyo3 {
    use pyo3::prelude::*;

    /// Call overhead: two ints in, one int out.
    #[pyfunction]
    fn add(a: i64, b: i64) -> i64 {
        a + b
    }

    fn fib_inner(n: i64) -> i64 {
        if n < 2 {
            return n;
        }
        fib_inner(n - 1) + fib_inner(n - 2)
    }

    /// Pure compute: naive recursion.
    #[pyfunction]
    fn fib(n: i64) -> i64 {
        fib_inner(n)
    }

    /// Compute plus a native heap allocation of n + 1 bytes.
    #[pyfunction]
    fn count_primes(n: i64) -> i64 {
        if n < 2 {
            return 0;
        }
        let size = (n + 1) as usize;
        let mut composite = vec![false; size];
        let mut count = 0;
        for i in 2..size {
            if !composite[i] {
                count += 1;
                let mut j = i * i;
                while j < size {
                    composite[j] = true;
                    j += i;
                }
            }
        }
        count
    }

    /// Pure compute with the GIL released, for thread scaling.
    #[pyfunction]
    fn sum_squares(py: Python<'_>, n: i64) -> i64 {
        py.detach(|| (1..=n).map(|i| i * i).sum())
    }

    /// A serial integer loop with the GIL released: a dependency between iterations,
    /// so no compiler vectorises it or collapses it to a closed form.
    #[pyfunction]
    fn lcg(py: Python<'_>, n: i64) -> i64 {
        py.detach(|| {
            let mut x: i64 = 12345;
            for _ in 1..=n {
                x = (x * 1_103_515_245 + 12345) & 0x7fff_ffff;
            }
            x
        })
    }

    /// A Python list of floats converted into a native vector.
    #[pyfunction]
    fn sum_floats(xs: Vec<f64>) -> f64 {
        xs.iter().sum()
    }

    /// A native sequence returned as a Python list of ints.
    #[pyfunction]
    fn make_range(n: i64) -> Vec<i64> {
        (0..n).collect()
    }

    /// A str in, a freshly allocated str out.
    #[pyfunction]
    fn greet(name: &str) -> String {
        format!("Hello, {name}!")
    }

    /// A count formatted with a defaulted step and label: keywords and defaults.
    #[pyfunction]
    #[pyo3(signature = (count, step = 1, label = "item", unit = None))]
    fn describe(count: i64, step: i64, label: &str, unit: Option<&str>) -> String {
        format!("{label}: {}{}", count * step, unit.unwrap_or(""))
    }

    /// A value doubled, or None: an optional parameter and result.
    #[pyfunction]
    fn maybe_double(x: Option<i64>) -> Option<i64> {
        x.map(|v| v * 2)
    }

    /// How often each word appears: a dict result.
    #[pyfunction]
    fn histogram(words: Vec<String>) -> std::collections::HashMap<String, i64> {
        let mut counts = std::collections::HashMap::new();
        for word in words {
            *counts.entry(word).or_insert(0) += 1;
        }
        counts
    }

    /// The smallest and largest value: a multi-value (tuple) result.
    #[pyfunction]
    fn minmax(xs: Vec<i64>) -> PyResult<(i64, i64)> {
        if xs.is_empty() {
            return Err(pyo3::exceptions::PyValueError::new_err(
                "minmax() arg is an empty sequence",
            ));
        }
        Ok((*xs.iter().min().unwrap(), *xs.iter().max().unwrap()))
    }

    /// Three values reversed: a fixed-size array in and out.
    #[pyfunction]
    fn reverse3(a: [i64; 3]) -> [i64; 3] {
        [a[2], a[1], a[0]]
    }

    /// Bytes in without copying, one int out.
    #[pyfunction]
    fn checksum(data: &[u8]) -> u64 {
        data.iter().map(|b| *b as u64).sum()
    }

    /// The error path: a bad value raises instead of returning.
    #[pyfunction]
    fn expect_positive(n: i64) -> PyResult<i64> {
        if n < 0 {
            Err(pyo3::exceptions::PyValueError::new_err(
                "expect_positive() expected n >= 0",
            ))
        } else {
            Ok(n)
        }
    }

    /// A list of str in, one new str out.
    #[pyfunction]
    fn join_strings(parts: Vec<String>) -> String {
        parts.join(",")
    }

    /// Bytes in, a fresh copy out.
    #[pyfunction]
    fn echo_bytes(data: &[u8]) -> Vec<u8> {
        data.to_vec()
    }

    /// Method-call overhead on a native object, with a property, value equality and a
    /// hash, and a subclass below.
    #[pyclass(subclass)]
    struct Counter {
        #[pyo3(get, set)]
        value: i64,
    }

    #[pymethods]
    impl Counter {
        #[new]
        fn new() -> Self {
            Counter { value: 0 }
        }

        fn increment(&mut self) -> i64 {
            self.value += 1;
            self.value
        }

        fn add(&mut self, n: i64) -> i64 {
            self.value += n;
            self.value
        }

        #[getter]
        fn is_zero(&self) -> bool {
            self.value == 0
        }

        fn __eq__(&self, other: &Bound<'_, PyAny>) -> bool {
            other
                .extract::<PyRef<Counter>>()
                .map(|o| self.value == o.value)
                .unwrap_or(false)
        }

        fn __hash__(&self) -> u64 {
            self.value as u64
        }
    }

    /// Its own iterator: yields start, start-1, ... 1.
    #[pyclass]
    struct Countdown {
        #[pyo3(get, set)]
        current: i64,
        #[pyo3(get, set)]
        start: i64,
    }

    #[pymethods]
    impl Countdown {
        #[new]
        fn new() -> Self {
            Countdown { current: 3, start: 3 }
        }

        fn __iter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
            slf
        }

        fn __next__(mut slf: PyRefMut<'_, Self>) -> PyResult<i64> {
            if slf.current <= 0 {
                return Err(pyo3::exceptions::PyStopIteration::new_err(()));
            }
            slf.current -= 1;
            Ok(slf.current + 1)
        }
    }

    /// A Counter that refuses to pass a limit.
    #[pyclass(extends=Counter)]
    struct BoundedCounter {
        #[pyo3(get, set)]
        limit: i64,
    }

    #[pymethods]
    impl BoundedCounter {
        #[new]
        fn new() -> (Self, Counter) {
            (BoundedCounter { limit: 0 }, Counter { value: 0 })
        }

        fn bump(mut slf: PyRefMut<'_, Self>, by: i64) -> PyResult<i64> {
            let limit = slf.limit;
            let base = slf.as_super();
            if base.value + by > limit {
                return Err(pyo3::exceptions::PyValueError::new_err(
                    "the counter would pass its limit",
                ));
            }
            base.value += by;
            Ok(base.value)
        }
    }
}
