# Galería de ejemplos

Cinco proyectos completos en [`examples/`](https://github.com/rroblf01/vcraft/tree/main/examples),
cada uno con un `test_*.py` que ejecuta la CI (`tests/examples/test_examples.py`):

| Ejemplo | Qué muestra |
| --- | --- |
| `async_server` | Funciones `@[vc_async]` (SHA-256 iterado, una criba de primos) detrás de un servidor TCP asyncio; el bucle sigue atendiendo mientras V calcula sin el GIL |
| `csv_parser` | Un parser que devuelve `list[list[str]]` y `list[dict]`, comprobado contra `csv.reader` con tablas aleatorias; los campos sin comillas son vistas sin copia de la entrada |
| `numpy_kernel` | `vcraft.NdArray`/`NdOut`: una media móvil, un `matmul` que respeta los strides y acepta `b.T` sin copia, un `normalize` in situ; sin depender de NumPy |
| `with_c` | Un proyecto con su propio `c/fastc.c`, compilado con `#flag @VMODROOT/c/fastc.c` y declarado con `fn C.` |
| `arrow_kernel` | Kernels de columnas sobre la Arrow C Data Interface: columnas de pyarrow y polars de entrada, columnas Arrow de salida, sin copias ni depender de pyarrow |
| `fuzzy_match` | Levenshtein, Jaro-Winkler y un `extract` al estilo de `rapidfuzz` sobre 20.000 palabras, unas 50× más rápido que el mismo algoritmo en Python puro, y comprobado contra él |

Para probar uno:

```console
$ cd examples/numpy_kernel
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop
$ python test_numpy_kernel.py
```

`examples/hello` es el proyecto de pruebas del generador y usa todas las anotaciones; es
el sitio donde consultar la sintaxis exacta de cada funcionalidad.
