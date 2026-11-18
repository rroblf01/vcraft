# Examples

| Example | Shows |
| --- | --- |
| [`hello`](hello) | Every annotation; the code generator's end-to-end test project |
| [`async_server`](async_server) | `@[vc_async]` functions serving an asyncio TCP server without blocking the loop |
| [`csv_parser`](csv_parser) | A parser returning lists and dicts, checked against Python's `csv` |
| [`numpy_kernel`](numpy_kernel) | `NdArray`/`NdOut` kernels on NumPy arrays, strided views, in-place writes |
| [`with_c`](with_c) | A project with its own C file compiled into the extension |
| [`arrow_kernel`](arrow_kernel) | Column kernels over Arrow: pyarrow and polars columns in and out, without copies |
| [`fuzzy_match`](fuzzy_match) | Levenshtein, Jaro-Winkler and best-match search, against pure Python |
| [`async_callback`](async_callback) | A project as `vcraft new` writes it, calling back into Python |
| [`probe`](probe) | The minimal "Gate 0" module the runtime is checked with |

Each gallery project builds with `vcraft develop` (or `vcraft build`) and carries a
`test_*.py`; `python3 tests/examples/test_examples.py` builds them all and runs them.
