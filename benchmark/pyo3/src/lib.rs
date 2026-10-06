use pyo3::prelude::*;

/// Benchmark workloads written in Rust.
///
/// The same seven workloads as the vcraft and zig-maturin projects, with the same
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

    /// Method-call overhead on a native object.
    #[pyclass]
    struct Counter {
        #[pyo3(get)]
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
    }
}
