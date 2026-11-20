// Benchmark workloads written in C++ with pybind11.
//
// The same workloads as the PyO3, vcraft and zig-maturin projects, with the same
// semantics and 64-bit integers throughout. Each binding is written the way pybind11's
// documentation writes it (STL containers through <pybind11/stl.h>, `py::buffer` for
// bytes-like input), so the numbers measure pybind11 as people use it.
#include <pybind11/complex.h>
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <algorithm>
#include <array>
#include <complex>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace py = pybind11;

namespace {

int64_t fib_inner(int64_t n) {
    if (n < 2) {
        return n;
    }
    return fib_inner(n - 1) + fib_inner(n - 2);
}

int64_t count_primes(int64_t n) {
    if (n < 2) {
        return 0;
    }
    const auto size = static_cast<size_t>(n + 1);
    std::vector<bool> composite(size, false);
    int64_t count = 0;
    for (size_t i = 2; i < size; ++i) {
        if (!composite[i]) {
            ++count;
            for (size_t j = i * i; j < size; j += i) {
                composite[j] = true;
            }
        }
    }
    return count;
}

// Method-call overhead on a native object, with a property, value equality and a
// hash, and a subclass below.
struct Counter {
    int64_t value = 0;
};

// Its own iterator: yields start, start-1, ... 1.
struct Countdown {
    int64_t current = 3;
    int64_t start = 3;
};

// A Counter that refuses to pass a limit.
struct BoundedCounter : Counter {
    int64_t limit = 0;
};

// A vector that owns a native buffer of doubles: a constructor that takes its length,
// element writes, and a native sum.
struct Vector {
    explicit Vector(size_t n) : data(n, 0.0) {}
    std::vector<double> data;
};

}  // namespace

PYBIND11_MODULE(bench_pybind11, m) {
    m.doc() = "Benchmark workloads written in C++ with pybind11.";

    m.def("complex_scale", [](std::complex<double> z, double k) { return z * k; },
          "A Python complex scaled by a real, in and out.");

    m.def("add", [](int64_t a, int64_t b) { return a + b; },
          "Call overhead: two ints in, one int out.");

    m.def("fib", &fib_inner, "Pure compute: naive recursion.");

    m.def("count_primes", &count_primes,
          "Compute plus a native heap allocation of n + 1 entries.");

    m.def("sum_squares", [](int64_t n) {
        py::gil_scoped_release release;
        int64_t total = 0;
        for (int64_t i = 1; i <= n; ++i) {
            total += i * i;
        }
        return total;
    }, "Pure compute with the GIL released, for thread scaling.");

    // A serial integer loop with the GIL released: a dependency between iterations, so
    // no compiler vectorises it or collapses it to a closed form.
    m.def("lcg", [](int64_t n) {
        py::gil_scoped_release release;
        int64_t x = 12345;
        for (int64_t i = 1; i <= n; ++i) {
            x = (x * 1103515245 + 12345) & 0x7fffffff;
        }
        return x;
    });

    m.def("sum_floats", [](const std::vector<double> &xs) {
        double total = 0.0;
        for (double x : xs) {
            total += x;
        }
        return total;
    }, "A Python list of floats converted into a native vector.");

    m.def("make_range", [](int64_t n) {
        std::vector<int64_t> out;
        if (n > 0) {
            out.reserve(static_cast<size_t>(n));
            for (int64_t i = 0; i < n; ++i) {
                out.push_back(i);
            }
        }
        return out;
    }, "A native sequence returned as a Python list of ints.");

    m.def("greet", [](const std::string &name) { return "Hello, " + name + "!"; },
          "A str in, a freshly allocated str out.");

    m.def("describe",
          [](int64_t count, int64_t step, const std::string &label,
             const std::optional<std::string> &unit) {
              return label + ": " + std::to_string(count * step) + unit.value_or("");
          },
          py::arg("count"), py::arg("step") = 1, py::arg("label") = "item",
          py::arg("unit") = py::none(),
          "A count formatted with a defaulted step and label: keywords and defaults.");

    m.def("maybe_double", [](std::optional<int64_t> x) -> std::optional<int64_t> {
        if (!x) {
            return std::nullopt;
        }
        return *x * 2;
    }, py::arg("x").none(true), "A value doubled, or None: an optional parameter and result.");

    m.def("histogram", [](const std::vector<std::string> &words) {
        std::unordered_map<std::string, int64_t> counts;
        for (const auto &word : words) {
            ++counts[word];
        }
        return counts;
    }, "How often each word appears: a dict result.");

    m.def("minmax", [](const std::vector<int64_t> &xs) {
        if (xs.empty()) {
            throw py::value_error("minmax() arg is an empty sequence");
        }
        const auto [lo, hi] = std::minmax_element(xs.begin(), xs.end());
        return std::make_pair(*lo, *hi);
    }, "The smallest and largest value: a multi-value (tuple) result.");

    m.def("reverse3", [](const std::array<int64_t, 3> &a) {
        return std::array<int64_t, 3>{a[2], a[1], a[0]};
    }, "Three values reversed: a fixed-size array in and out.");

    m.def("checksum", [](const py::buffer &data) {
        const py::buffer_info info = data.request();
        const auto *bytes = static_cast<const uint8_t *>(info.ptr);
        const auto len = static_cast<size_t>(info.size * info.itemsize);
        uint64_t total = 0;
        for (size_t i = 0; i < len; ++i) {
            total += bytes[i];
        }
        return total;
    }, "Bytes in without copying, one int out.");

    m.def("expect_positive", [](int64_t n) {
        if (n < 0) {
            throw py::value_error("expect_positive() expected n >= 0");
        }
        return n;
    }, "The error path: a bad value raises instead of returning.");

    m.def("join_strings", [](const std::vector<std::string> &parts) {
        std::string out;
        for (size_t i = 0; i < parts.size(); ++i) {
            if (i > 0) {
                out += ',';
            }
            out += parts[i];
        }
        return out;
    }, "A list of str in, one new str out.");

    m.def("echo_bytes", [](const py::buffer &data) {
        const py::buffer_info info = data.request();
        return py::bytes(static_cast<const char *>(info.ptr),
                         static_cast<size_t>(info.size * info.itemsize));
    }, "Bytes in, a fresh copy out.");

    py::class_<Counter>(m, "Counter")
        .def(py::init<>())
        .def_readwrite("value", &Counter::value)
        .def("increment", [](Counter &c) { return ++c.value; })
        .def("add", [](Counter &c, int64_t n) {
            c.value += n;
            return c.value;
        })
        .def_property_readonly("is_zero", [](const Counter &c) { return c.value == 0; })
        .def_static("zero", []() { return int64_t{0}; },
                    "A static method: it belongs to the class but takes no instance.")
        .def("__eq__", [](const Counter &self, const py::object &other) {
            return py::isinstance<Counter>(other) && self.value == other.cast<const Counter &>().value;
        })
        .def("__hash__", [](const Counter &c) { return static_cast<uint64_t>(c.value); });

    py::class_<Countdown>(m, "Countdown")
        .def(py::init<>())
        .def_readwrite("current", &Countdown::current)
        .def_readwrite("start", &Countdown::start)
        .def("__iter__", [](Countdown &self) -> Countdown & { return self; },
             py::return_value_policy::reference_internal)
        .def("__next__", [](Countdown &self) {
            if (self.current <= 0) {
                throw py::stop_iteration();
            }
            return self.current--;
        });

    py::class_<BoundedCounter, Counter>(m, "BoundedCounter")
        .def(py::init<>())
        .def_readwrite("limit", &BoundedCounter::limit)
        .def("bump", [](BoundedCounter &self, int64_t by) {
            if (self.value + by > self.limit) {
                throw py::value_error("the counter would pass its limit");
            }
            self.value += by;
            return self.value;
        });

    py::class_<Vector>(m, "Vector", py::buffer_protocol())
        .def(py::init<size_t>())
        .def("set", [](Vector &v, size_t i, double x) {
            if (i < v.data.size()) {
                v.data[i] = x;
            }
        })
        .def("get", [](const Vector &v, size_t i) {
            return i < v.data.size() ? v.data[i] : 0.0;
        })
        .def("total", [](const Vector &v) {
            double total = 0.0;
            for (double x : v.data) {
                total += x;
            }
            return total;
        })
        .def_buffer([](Vector &v) {
            return py::buffer_info(v.data.data(), static_cast<py::ssize_t>(v.data.size()));
        });
}
