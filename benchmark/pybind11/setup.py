# The extension is built by pybind11's own setuptools helper, the way its documentation
# sets a project up. `-O3` matches the release builds of the other projects; the helper
# already adds `-fvisibility=hidden` and the C++ standard, and `-DNDEBUG` turns off the
# asserts a release build drops.
from pybind11.setup_helpers import Pybind11Extension
from setuptools import setup

setup(
    ext_modules=[
        Pybind11Extension(
            "bench_pybind11",
            ["src/bench_pybind11.cpp"],
            cxx_std=17,
            extra_compile_args=["-O3", "-DNDEBUG"],
        )
    ],
)
