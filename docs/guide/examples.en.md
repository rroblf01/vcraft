# Examples gallery

Five complete projects under [`examples/`](https://github.com/rroblf01/vcraft/tree/main/examples),
each with a `test_*.py` that CI runs (`tests/examples/test_examples.py`):

| Example | What it shows |
| --- | --- |
| `async_server` | `@[vc_async]` functions (iterated SHA-256, a prime sieve) behind an asyncio TCP server; the loop keeps serving while V computes off the GIL |
| `csv_parser` | A parser returning `list[list[str]]` and `list[dict]`, checked against `csv.reader` on random tables; unquoted fields are zero-copy views of the input |
| `numpy_kernel` | `vcraft.NdArray`/`NdOut`: a moving average, a stride-aware `matmul` that takes `b.T` without a copy, an in-place `normalize`; no NumPy dependency |
| `with_c` | A project with its own `c/fastc.c`, compiled in with `#flag @VMODROOT/c/fastc.c` and declared with `fn C.` |
| `fuzzy_match` | Levenshtein, Jaro-Winkler and a `rapidfuzz`-style `extract` over 20,000 words, about 50x faster than the same algorithm in pure Python, and checked against it |

Try one:

```console
$ cd examples/numpy_kernel
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop
$ python test_numpy_kernel.py
```

`examples/hello` is the code generator's test project and uses every annotation;
it is the place to look up a feature's exact syntax.
