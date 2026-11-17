"""Run with the built extension importable: `vcraft develop`, then `python test_numpy_kernel.py`.

The kernels take any buffer; the NumPy checks run when NumPy is installed.
"""

import array
import math

import ndkernel

samples = array.array("d", [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
assert list(memoryview(ndkernel.moving_average(samples, 3))) == [2.0, 3.0, 4.0, 5.0]
for bad in (0, 7):
    try:
        ndkernel.moving_average(samples, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"window {bad} was accepted")

values = array.array("d", [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])
mean, std = ndkernel.normalize(values)
assert (mean, std) == (5.0, 2.0) and values[0] == -1.5, (mean, std, values)

try:
    import numpy as np
except ImportError:
    print("ok numpy_kernel (NumPy not installed: buffer checks only)")
    raise SystemExit(0)

rng = np.random.default_rng(1)
x = rng.random(10_000)
got = np.asarray(ndkernel.moving_average(x, 50))
assert np.allclose(got, np.convolve(x, np.ones(50) / 50, mode="valid"))

a = rng.random((40, 30))
b = rng.random((50, 30))
c = np.asarray(ndkernel.matmul(a, b.T))  # b.T is a strided view, not a copy
assert c.shape == (40, 50) and np.allclose(c, a @ b.T)
assert np.allclose(np.asarray(ndkernel.matmul(a[::2, ::3], b.T[::3, ::5])), a[::2, ::3] @ b.T[::3, ::5])
try:
    ndkernel.matmul(a, a)
except ValueError as exc:
    assert "do not align" in str(exc)
else:
    raise AssertionError("misaligned shapes were accepted")
try:
    ndkernel.matmul(a.astype(np.float32), b.T)
except TypeError:
    pass
else:
    raise AssertionError("float32 was accepted")

z = rng.normal(3.0, 2.0, 1000)
m, s = ndkernel.normalize(z)
assert math.isclose(m, 3.0, abs_tol=0.3) and abs(z.mean()) < 1e-12 and math.isclose(z.std(), 1.0)
frozen = np.arange(4.0)
frozen.flags.writeable = False
try:
    ndkernel.normalize(frozen)
except ValueError:
    pass
else:
    raise AssertionError("a read-only array was written")
print("ok numpy_kernel")
