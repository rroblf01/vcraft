# arrow_kernel

Column kernels in V over the Arrow C Data Interface: `zscore`, `word_lengths` and
`initials` take a pyarrow array, a polars Series or a chunked array (`vcraft.ArrowArray`)
and return a column (`vcraft.ArrowOut`) that `pyarrow.array()` and `polars.Series()` adopt
without copying. The extension imports none of those libraries.

```console
$ vcraft develop
$ python test_arrow_kernel.py
```

```python
>>> import polars as pl, arrowk
>>> pl.Series(arrowk.zscore(pl.Series([10.0, 20.0, 30.0])))
shape: (3,)
Series: '' [f64]
[
	-1.224745
	0.0
	1.224745
]
```

A pyarrow array is read in place; a polars Series or a chunked array arrives as a stream,
which is copied once into one contiguous column. Strings in any of Arrow's three layouts
(`utf8`, `large_utf8`, `utf8_view`, polars' default) are read.
