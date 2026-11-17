# numpy_kernel

Numeric kernels over N-dimensional buffers with `vcraft.NdArray` and `vcraft.NdOut`:
`moving_average` (1-D, running sum), `matmul` (2-D, reads through strides, so `b.T` or a
slice needs no copy) and `normalize` (writes into the caller's array). The extension never
imports NumPy; it accepts any buffer (`array.array`, `memoryview`, NumPy arrays).

```console
$ vcraft develop
$ python test_numpy_kernel.py   # NumPy checks run when NumPy is installed
```

```python
>>> import numpy as np, ndkernel
>>> np.asarray(ndkernel.matmul(np.eye(2), np.arange(4.0).reshape(2, 2)))
array([[0., 1.],
       [2., 3.]])
```
