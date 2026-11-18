"""Run with the built extension importable: `vcraft develop`, then `python test_arrow_kernel.py`.

The module's own columns speak the Arrow PyCapsule protocol, so the round trip is checked
everywhere; with pyarrow and polars installed their columns are checked in and out too.
"""

import math

import arrowk

z = arrowk.values(arrowk.zscore(arrowk.column([1.0, 2.0, 3.0])))
assert math.isclose(z[0], -1.224744871391589) and math.isclose(z[1], 0.0, abs_tol=1e-12), z
assert len(arrowk.column([0.5] * 10)) == 10
try:
    arrowk.zscore([1.0, 2.0])
except TypeError as exc:
    assert "Arrow" in str(exc)
else:
    raise AssertionError("a plain list was taken as an Arrow column")

try:
    import pyarrow as pa
    import polars as pl
except ImportError:
    print("ok arrow_kernel (pyarrow/polars not installed: the module's own columns only)")
    raise SystemExit(0)

z = pa.array(arrowk.zscore(pa.array([1.0, 2.0, None, 3.0]))).to_pylist()
assert math.isclose(z[0], -1.224744871391589) and math.isnan(z[2]) and math.isclose(z[3], 1.224744871391589), z
s = pl.Series(arrowk.zscore(pl.Series([10.0, 20.0, 30.0])))
assert s.len() == 3 and math.isclose(s[1], 0.0, abs_tol=1e-12), s
words = pl.Series(["árbol", "río", "a much longer word than twelve bytes"])
assert pl.Series(arrowk.word_lengths(words)).to_list() == [5, 3, 36]
assert pa.array(arrowk.initials(pa.array(["vcraft", "ñu"], type=pa.large_string()))).to_pylist() == ["v", "ñ"]
big = pl.Series(range(1_000_000), dtype=pl.Float64)
assert pl.Series(arrowk.zscore(big)).len() == 1_000_000
print("ok arrow_kernel (pyarrow and polars columns in and out)")
